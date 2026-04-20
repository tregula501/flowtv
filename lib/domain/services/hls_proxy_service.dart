import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../../core/utils/logger.dart';

/// A local HTTP server that reads a remote MPEG-TS stream and serves it as
/// live HLS for Chromecast. Segments are split at keyframe (RAI) boundaries.
///
/// Audio handling:
/// - AAC audio: included as-is (Chromecast-compatible)
/// - AC-3/other audio: included as-is (Chromecast may play video-only)
///
/// No transcoding is performed — this is a pure Dart repackaging proxy.
class HlsProxyService {
  static HlsProxyService? _instance;
  static HlsProxyService get instance => _instance ??= HlsProxyService._();
  HlsProxyService._();

  static const _targetSegmentSecs = 6;
  static const _maxSegments = 6; // balance memory vs Chromecast buffer needs
  static const _initialSegments = 2;
  static const _tsPacketSize = 188;
  static const _minSegmentBytes = 512 * 1024;
  static const _maxSegmentBytes = 10 * 1024 * 1024; // 10MB cap
  static const _silentAudioPid = 258; // PID for our synthetic silent AAC

  // Silent AAC-LC frame: ADTS header (7 bytes) + silent 1024-sample frame
  // Profile: AAC-LC, Sample rate: 44100Hz, Channels: 2 (stereo)
  static final _silentAacFrame = Uint8List.fromList([
    // ADTS header: syncword=0xFFF, id=0(MPEG4), layer=0, protection=1(no CRC),
    // profile=1(AAC-LC), sampling_freq=4(44100), private=0, channels=2,
    // frame_length=14 (7 header + 7 data)
    0xFF, 0xF1, 0x50, 0x80, 0x03, 0x80, 0xFC,
    // Minimal silent AAC frame data (SCE + END)
    0x21, 0x10, 0x04, 0x60, 0x8C, 0x1C, 0x00,
  ]);

  HttpServer? _server;
  HttpClient? _httpClient;
  StreamSubscription<List<int>>? _fetchSub;
  String? _activeUrl;
  String? _wifiIp;

  final _segments = <int, Uint8List>{};
  int _nextSequence = 0;
  Completer<void>? _readyCompleter;

  final _packetBuffer = BytesBuilder(copy: false);
  final _segmentBuffer = BytesBuilder(copy: false);
  int _segmentBytes = 0;

  // Cache the most recent PAT and PMT packets so every segment starts
  // with them. Chromecast requires PAT+PMT at the beginning of each
  // HLS segment to identify the streams.
  Uint8List? _lastPat;
  Uint8List? _lastPmt;
  int _pmtPid = -1; // PMT PID discovered from PAT
  final _audioPids = <int>{}; // audio PIDs to filter out
  int _videoPid = -1; // video PID to keep

  int _totalBytesReceived = 0;
  Stopwatch? _stopwatch;
  double _estimatedBytesPerSec = 0;
  bool _bitrateEstimated = false;

  bool get isRunning => _server != null;

  Future<String?> start(String tsStreamUrl) async {
    if (_server != null &&
        _activeUrl == tsStreamUrl &&
        _wifiIp != null &&
        _segments.isNotEmpty) {
      return 'http://$_wifiIp:${_server!.port}/live.m3u8';
    }

    await stop();

    final ip = await _getWifiIp();
    if (ip == null) {
      AppLogger.error('HLS proxy: Could not determine WiFi IP');
      return null;
    }
    _wifiIp = ip;

    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
      final port = _server!.port;
      AppLogger.info('HLS proxy: Listening on 0.0.0.0:$port (WiFi IP: $ip)');
      _server!.listen(_handleRequest);

      _readyCompleter = Completer<void>();
      _startFetching(tsStreamUrl);
      _activeUrl = tsStreamUrl;

      await _readyCompleter!.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          AppLogger.warning(
            'HLS proxy: Timed out waiting for initial segments '
            '(have ${_segments.length}/$_initialSegments)',
          );
          if (_segments.isNotEmpty && !_readyCompleter!.isCompleted) {
            _readyCompleter!.complete();
          }
        },
      );

      if (_segments.isEmpty) {
        AppLogger.error('HLS proxy: No segments produced');
        await stop();
        return null;
      }

      final hlsUrl = 'http://$ip:$port/live.m3u8';
      AppLogger.info('HLS proxy: Ready — $hlsUrl');
      return hlsUrl;
    } catch (e) {
      AppLogger.error('HLS proxy: Failed to start — $e');
      await stop();
      return null;
    }
  }

  Future<void> stop() async {
    _fetchSub?.cancel();
    _fetchSub = null;
    _httpClient?.close(force: true);
    _httpClient = null;
    await _server?.close(force: true);
    _server = null;
    _activeUrl = null;
    _wifiIp = null;
    _segments.clear();
    _nextSequence = 0;
    _totalBytesReceived = 0;
    _estimatedBytesPerSec = 0;
    _bitrateEstimated = false;
    _stopwatch = null;
    _packetBuffer.clear();
    _segmentBuffer.clear();
    _segmentBytes = 0;
    _readyCompleter = null;
    _lastPat = null;
    _lastPmt = null;
    _pmtPid = -1;
    _audioPids.clear();
    _videoPid = -1;
    AppLogger.info('HLS proxy: Stopped');
  }

  // ---------------------------------------------------------------------------
  // Stream fetching
  // ---------------------------------------------------------------------------

  void _startFetching(String url) {
    _stopwatch = Stopwatch()..start();
    _httpClient = HttpClient()..connectionTimeout = const Duration(seconds: 10);

    () async {
      for (var attempt = 1; attempt <= 5; attempt++) {
        try {
          final request = await _httpClient!.getUrl(Uri.parse(url));
          final response = await request.close();

          if (response.statusCode < 200 || response.statusCode >= 300) {
            AppLogger.error(
              'HLS proxy: Upstream returned ${response.statusCode} '
              '(attempt $attempt/5)',
            );
            await response.drain<void>();
            if (attempt < 5) {
              await Future.delayed(Duration(seconds: attempt * 2));
              continue;
            }
            return;
          }

          AppLogger.info(
            'HLS proxy: Connected to upstream (${response.statusCode})',
          );

          _fetchSub = response.listen(
            _onData,
            onError: (Object e) =>
                AppLogger.error('HLS proxy: Upstream error — $e'),
            onDone: () {
              AppLogger.info('HLS proxy: Upstream closed');
              _flushSegment();
            },
          );
          return;
        } catch (e) {
          AppLogger.error(
            'HLS proxy: Connection failed (attempt $attempt/5) — $e',
          );
          if (attempt < 5) {
            await Future.delayed(Duration(seconds: attempt * 2));
          }
        }
      }
    }();
  }

  void _onData(List<int> chunk) {
    _totalBytesReceived += chunk.length;
    _packetBuffer.add(chunk);

    if (!_bitrateEstimated) {
      final elapsed = _stopwatch!.elapsedMilliseconds;
      if (elapsed >= 3000 && _totalBytesReceived > 0) {
        _estimatedBytesPerSec = _totalBytesReceived * 1000.0 / elapsed;
        _bitrateEstimated = true;
        AppLogger.info(
          'HLS proxy: Estimated bitrate '
          '${(_estimatedBytesPerSec * 8 / 1000000).toStringAsFixed(1)} Mbps',
        );
      }
    }

    _processPackets();
  }

  // ---------------------------------------------------------------------------
  // TS packet processing
  // ---------------------------------------------------------------------------

  void _processPackets() {
    final data = _packetBuffer.takeBytes();
    var offset = 0;

    while (offset < data.length && data[offset] != 0x47) {
      offset++;
    }

    while (offset + _tsPacketSize <= data.length) {
      if (data[offset] != 0x47) {
        offset++;
        while (offset < data.length && data[offset] != 0x47) {
          offset++;
        }
        continue;
      }

      final packet = Uint8List.fromList(
        data.sublist(offset, offset + _tsPacketSize),
      );
      offset += _tsPacketSize;

      final pid = ((packet[1] & 0x1F) << 8) | packet[2];

      // Cache PAT and PMT packets for segment headers
      if (pid == 0) {
        _lastPat = packet;
        _extractPmtPid(packet);
        continue; // don't include in segment — we prepend rewritten ones
      } else if (pid == _pmtPid && _pmtPid > 0) {
        _lastPmt = packet;
        _extractAudioPids(packet);
        continue; // don't include in segment
      }

      // Only keep video PID — drop everything else (audio, SDT, etc.)
      if (_videoPid > 0 && pid != _videoPid) continue;

      final hasKeyframe = _isRandomAccessPoint(packet);

      if ((hasKeyframe && _segmentBytes >= _minSegmentBytes && _shouldSplit()) ||
          _segmentBytes >= _maxSegmentBytes) {
        _flushSegment();
      }

      _segmentBuffer.add(packet);
      _segmentBytes += _tsPacketSize;
    }

    if (offset < data.length) {
      _packetBuffer.add(data.sublist(offset));
    }
  }

  /// Extract audio PIDs from a PMT packet (to filter them out).
  void _extractAudioPids(Uint8List packet) {
    final pusi = (packet[1] & 0x40) != 0;
    if (!pusi) return;

    var ps = 4;
    final af = (packet[3] >> 4) & 0x03;
    if (af >= 2) ps += 1 + packet[4];
    if (ps >= _tsPacketSize) return;

    final pointer = packet[ps];
    var off = ps + 1 + pointer;
    if (off >= _tsPacketSize || packet[off] != 0x02) return;

    final sectionLen = ((packet[off + 1] & 0x0F) << 8) | packet[off + 2];
    final progInfoLen = ((packet[off + 10] & 0x0F) << 8) | packet[off + 11];
    off += 12 + progInfoLen;
    final end = off + sectionLen - 13 - progInfoLen;

    while (off + 5 <= end && off < _tsPacketSize) {
      final streamType = packet[off];
      final elemPid = ((packet[off + 1] & 0x1F) << 8) | packet[off + 2];
      final esInfoLen = ((packet[off + 3] & 0x0F) << 8) | packet[off + 4];

      // Video stream types
      if (streamType == 0x1B || streamType == 0x24 || streamType == 0x02) {
        if (_videoPid != elemPid) {
          _videoPid = elemPid;
          AppLogger.info('HLS proxy: Video PID=$elemPid (type=0x${streamType.toRadixString(16)})');
        }
      }
      // Audio stream types
      if (streamType == 0x81 || streamType == 0x87 || // AC-3, E-AC-3
          streamType == 0x0F || streamType == 0x03 || // AAC, MPEG-1 Audio
          streamType == 0x04 || streamType == 0x06) { // MPEG-2 Audio, PES private
        if (_audioPids.add(elemPid)) {
          AppLogger.info('HLS proxy: Audio PID=$elemPid (type=0x${streamType.toRadixString(16)})');
        }
      }
      off += 5 + esInfoLen;
    }
  }

  /// Extract PMT PID from a PAT packet.
  void _extractPmtPid(Uint8List packet) {
    final pusi = (packet[1] & 0x40) != 0;
    if (!pusi) return;

    var ps = 4;
    final af = (packet[3] >> 4) & 0x03;
    if (af >= 2) ps += 1 + packet[4];
    if (ps >= _tsPacketSize) return;

    final pointer = packet[ps];
    var off = ps + 1 + pointer;
    if (off >= _tsPacketSize || packet[off] != 0x00) return; // table_id 0 = PAT

    final sectionLen = ((packet[off + 1] & 0x0F) << 8) | packet[off + 2];
    off += 8; // skip to program entries
    final end = off + sectionLen - 9;
    while (off + 4 <= end && off < _tsPacketSize) {
      final prog = (packet[off] << 8) | packet[off + 1];
      final pmtPid = ((packet[off + 2] & 0x1F) << 8) | packet[off + 3];
      if (prog > 0 && _pmtPid != pmtPid) {
        _pmtPid = pmtPid;
        AppLogger.info('HLS proxy: PAT → PMT PID=$pmtPid');
      }
      off += 4;
    }
  }

  /// Build a video-only PMT packet from the cached PMT, stripping audio
  /// streams that the Chromecast Default Media Receiver can't handle.
  Uint8List? _buildVideoOnlyPmt() {
    if (_lastPmt == null) return _lastPmt;

    final pmt = Uint8List.fromList(_lastPmt!);
    final pusi = (pmt[1] & 0x40) != 0;
    if (!pusi) return pmt;

    var ps = 4;
    final af = (pmt[3] >> 4) & 0x03;
    if (af >= 2) ps += 1 + pmt[4];
    if (ps >= _tsPacketSize) return pmt;

    final pointer = pmt[ps];
    final tableStart = ps + 1 + pointer;
    if (tableStart >= _tsPacketSize || pmt[tableStart] != 0x02) return pmt;

    final sectionLenOff = tableStart + 1;
    final origSectionLen =
        ((pmt[sectionLenOff] & 0x0F) << 8) | pmt[sectionLenOff + 1];
    final progInfoLen =
        ((pmt[tableStart + 10] & 0x0F) << 8) | pmt[tableStart + 11];

    // Build new section with only video streams (type 0x1B=H.264, 0x24=H.265, 0x02=MPEG2)
    final headerEnd = tableStart + 12 + progInfoLen;
    var readOff = headerEnd;
    final sectionEnd = tableStart + 3 + origSectionLen - 4; // exclude CRC
    final kept = <int>[];

    while (readOff + 5 <= sectionEnd) {
      final streamType = pmt[readOff];
      final esInfoLen =
          ((pmt[readOff + 3] & 0x0F) << 8) | pmt[readOff + 4];
      final entryLen = 5 + esInfoLen;

      // Keep only video streams (we add silent AAC separately)
      if (streamType == 0x1B || streamType == 0x24 || streamType == 0x02) {
        for (var i = 0; i < entryLen && readOff + i < _tsPacketSize; i++) {
          kept.add(pmt[readOff + i]);
        }
      }
      readOff += entryLen;
    }

    // Rebuild the PMT packet
    final newPmt = Uint8List(_tsPacketSize);
    // Copy TS header + pointer + PMT header up to stream entries
    for (var i = 0; i < headerEnd && i < _tsPacketSize; i++) {
      newPmt[i] = pmt[i];
    }

    // Write kept video stream entries
    var writeOff = headerEnd;
    for (var i = 0; i < kept.length && writeOff < _tsPacketSize - 4; i++) {
      newPmt[writeOff++] = kept[i];
    }

    // Add silent AAC audio stream entry: type=0x0F(AAC), PID=258, es_info_len=0
    if (writeOff + 5 < _tsPacketSize - 4) {
      newPmt[writeOff++] = 0x0F; // stream type: AAC
      newPmt[writeOff++] = (_silentAudioPid >> 8) & 0x1F; // PID high
      newPmt[writeOff++] = _silentAudioPid & 0xFF; // PID low
      newPmt[writeOff++] = 0x00; // ES info length high
      newPmt[writeOff++] = 0x00; // ES info length low
    }

    // Update section length: header(9) + progInfoLen + kept entries + AAC entry(5) + CRC(4)
    final newSectionLen = 9 + progInfoLen + kept.length + 5 + 4;
    newPmt[sectionLenOff] =
        (pmt[sectionLenOff] & 0xF0) | ((newSectionLen >> 8) & 0x0F);
    newPmt[sectionLenOff + 1] = newSectionLen & 0xFF;

    // Calculate CRC32 over the section (from table_id to just before CRC)
    final crcStart = tableStart;
    final crcEnd = writeOff;
    final crc = _crc32Mpeg(newPmt, crcStart, crcEnd);
    newPmt[writeOff] = (crc >> 24) & 0xFF;
    newPmt[writeOff + 1] = (crc >> 16) & 0xFF;
    newPmt[writeOff + 2] = (crc >> 8) & 0xFF;
    newPmt[writeOff + 3] = crc & 0xFF;

    // Fill rest with 0xFF (stuffing)
    for (var i = writeOff + 4; i < _tsPacketSize; i++) {
      newPmt[i] = 0xFF;
    }

    return newPmt;
  }

  /// MPEG-2 CRC32 (used in PAT/PMT).
  static int _crc32Mpeg(Uint8List data, int start, int end) {
    int crc = 0xFFFFFFFF;
    for (var i = start; i < end; i++) {
      crc ^= (data[i] << 24);
      for (var j = 0; j < 8; j++) {
        if ((crc & 0x80000000) != 0) {
          crc = ((crc << 1) ^ 0x04C11DB7) & 0xFFFFFFFF;
        } else {
          crc = (crc << 1) & 0xFFFFFFFF;
        }
      }
    }
    return crc;
  }

  /// Extract the first PTS from video PES packets in segment data.
  int _extractFirstPts(Uint8List data) {
    for (var i = 0; i + _tsPacketSize <= data.length; i += _tsPacketSize) {
      if (data[i] != 0x47) continue;
      final pusi = (data[i + 1] & 0x40) != 0;
      if (!pusi) continue;

      var ps = i + 4;
      final af = (data[i + 3] >> 4) & 0x03;
      if (af >= 2) ps += 1 + data[i + 4];
      if (ps + 13 >= data.length) continue;

      // Check PES start code
      if (data[ps] == 0x00 && data[ps + 1] == 0x00 && data[ps + 2] == 0x01) {
        final flags = data[ps + 7];
        if ((flags & 0x80) != 0) {
          // PTS present
          final b = data.sublist(ps + 9, ps + 14);
          final pts = ((b[0] & 0x0E) << 29) |
              (b[1] << 22) |
              ((b[2] & 0xFE) << 14) |
              (b[3] << 7) |
              (b[4] >> 1);
          return pts;
        }
      }
    }
    return 0;
  }

  /// Encode a PTS value into the 5-byte PES timestamp format.
  List<int> _encodePts(int pts, int marker) {
    return [
      (marker << 4) | ((pts >> 29) & 0x0E) | 0x01,
      (pts >> 22) & 0xFF,
      ((pts >> 14) & 0xFE) | 0x01,
      (pts >> 7) & 0xFF,
      ((pts << 1) & 0xFE) | 0x01,
    ];
  }

  /// Build TS packets containing silent AAC audio frames wrapped in PES.
  Uint8List _buildSilentAudioPackets(int numFrames, {int pts = 0}) {
    // Build PES payload: multiple ADTS frames
    final aacData = BytesBuilder();
    for (var i = 0; i < numFrames; i++) {
      aacData.add(_silentAacFrame);
    }
    final aacPayload = aacData.takeBytes();

    // PES header: start code (3) + stream_id (1) + length (2) + flags (3)
    final pesHeaderLen = 9 + 5; // 9 base + 5 for PTS
    final pesPayload = BytesBuilder();
    // PES start code
    pesPayload.add([0x00, 0x00, 0x01]);
    // Stream ID: 0xC0 (audio stream 0)
    pesPayload.add([0xC0]);
    // PES packet length (0 = unbounded for video, but for audio set it)
    final pesLen = 3 + 5 + aacPayload.length; // flags(3) + PTS(5) + data
    pesPayload.add([(pesLen >> 8) & 0xFF, pesLen & 0xFF]);
    // PES flags: marker(10) + PTS_DTS_flags(10=PTS only) + rest zeros
    pesPayload.add([0x80, 0x80, 0x05]);
    // PTS matching the video stream's PTS for A/V sync
    pesPayload.add(_encodePts(pts, 0x02));
    pesPayload.add(aacPayload);

    final fullPayload = pesPayload.takeBytes();

    // Pack into 188-byte TS packets
    final packets = BytesBuilder();
    var offset = 0;
    var audioCC = 0;
    var first = true;

    while (offset < fullPayload.length) {
      final pkt = Uint8List(_tsPacketSize);
      pkt[0] = 0x47; // sync
      pkt[1] = (first ? 0x40 : 0x00) | ((_silentAudioPid >> 8) & 0x1F);
      pkt[2] = _silentAudioPid & 0xFF;
      pkt[3] = 0x10 | (audioCC & 0x0F); // payload only, CC
      audioCC++;
      first = false;

      final payloadSpace = _tsPacketSize - 4;
      final remaining = fullPayload.length - offset;
      final toCopy = remaining < payloadSpace ? remaining : payloadSpace;

      // If this is the last packet and there's leftover space, add adaptation field
      if (toCopy < payloadSpace) {
        final stuffLen = payloadSpace - toCopy - 1;
        pkt[3] |= 0x20; // adaptation field + payload
        pkt[4] = stuffLen > 0 ? stuffLen : 0;
        if (stuffLen > 0) {
          pkt[5] = 0x00; // adaptation flags
          for (var i = 6; i < 5 + stuffLen; i++) {
            pkt[i] = 0xFF; // stuffing
          }
        }
        final dataStart = 5 + (stuffLen > 0 ? stuffLen : 0);
        for (var i = 0; i < toCopy; i++) {
          pkt[dataStart + i] = fullPayload[offset + i];
        }
      } else {
        for (var i = 0; i < toCopy; i++) {
          pkt[4 + i] = fullPayload[offset + i];
        }
      }

      offset += toCopy;
      packets.add(pkt);
    }

    return Uint8List.fromList(packets.takeBytes());
  }

  bool _isRandomAccessPoint(List<int> packet) {
    final adaptationFieldControl = (packet[3] >> 4) & 0x03;
    if (adaptationFieldControl < 2) return false;
    final adaptationFieldLength = packet[4];
    if (adaptationFieldLength == 0) return false;
    return (packet[5] & 0x40) != 0;
  }

  bool _shouldSplit() {
    if (_estimatedBytesPerSec <= 0) {
      return _segmentBytes >= 3 * 1024 * 1024;
    }
    final estimatedSecs = _segmentBytes / _estimatedBytesPerSec;
    return estimatedSecs >= _targetSegmentSecs;
  }

  void _flushSegment() {
    if (_segmentBytes == 0) return;

    final contentBytes = _segmentBuffer.takeBytes();
    _segmentBytes = 0;

    // Build segment: PAT(CC=0) + video-only PMT(CC=0) + video packets(CC=0,1,2...)
    final header = BytesBuilder(copy: false);

    // PAT with CC=0
    if (_lastPat != null) {
      final pat = Uint8List.fromList(_lastPat!);
      pat[3] = (pat[3] & 0xF0) | 0; // CC = 0
      header.add(pat);
    }

    // Video-only PMT with CC=0
    final videoOnlyPmt = _buildVideoOnlyPmt();
    if (videoOnlyPmt != null) {
      videoOnlyPmt[3] = (videoOnlyPmt[3] & 0xF0) | 0; // CC = 0
      header.add(videoOnlyPmt);
    }

    // Renumber video packet CCs starting from 0
    final videoBytes = contentBytes is Uint8List
        ? contentBytes
        : Uint8List.fromList(contentBytes);
    var cc = 0;
    for (var i = 0; i + _tsPacketSize <= videoBytes.length; i += _tsPacketSize) {
      if (videoBytes[i] != 0x47) continue;
      final hasPayload = (videoBytes[i + 3] & 0x10) != 0;
      if (hasPayload) {
        videoBytes[i + 3] = (videoBytes[i + 3] & 0xF0) | (cc & 0x0F);
        cc++;
      }
    }
    header.add(videoBytes);

    // Add silent AAC audio packets synced to video PTS
    final videoPts = _extractFirstPts(videoBytes);
    final estimatedDuration = _estimatedBytesPerSec > 0
        ? videoBytes.length / _estimatedBytesPerSec
        : _targetSegmentSecs.toDouble();
    final numAudioFrames = (estimatedDuration * 44100 / 1024).ceil();
    final audioPackets = _buildSilentAudioPackets(numAudioFrames, pts: videoPts);
    header.add(audioPackets);

    final segment = Uint8List.fromList(header.takeBytes());

    final seq = _nextSequence++;
    _segments[seq] = segment;

    while (_segments.length > _maxSegments) {
      final oldest = _segments.keys.reduce((a, b) => a < b ? a : b);
      _segments.remove(oldest);
    }

    AppLogger.debug(
      'HLS proxy: Segment $seq — '
      '${(segment.length / 1024).toStringAsFixed(0)} KB '
      '(${_segments.length} in buffer)',
    );

    if (_segments.length >= _initialSegments &&
        _readyCompleter != null &&
        !_readyCompleter!.isCompleted) {
      _readyCompleter!.complete();
    }
  }

  // ---------------------------------------------------------------------------
  // HTTP serving
  // ---------------------------------------------------------------------------

  /// Add required CORS headers for Chromecast compatibility.
  void _addCorsHeaders(HttpResponse response) {
    response.headers
      ..set('Access-Control-Allow-Origin', '*')
      ..set('Access-Control-Allow-Methods', 'GET, OPTIONS')
      ..set('Access-Control-Allow-Headers',
          'Content-Type, Range, User-Agent, X-Requested-With, '
          'If-Modified-Since, Cache-Control')
      ..set('Access-Control-Expose-Headers', 'Content-Length, Content-Range');
  }

  void _handleRequest(HttpRequest request) {
    final path = request.uri.path;
    final from = request.connectionInfo?.remoteAddress.address ?? '?';
    AppLogger.info('HLS proxy: ${request.method} $path from $from');

    // Handle CORS preflight — Chromecast sends OPTIONS before GET
    if (request.method == 'OPTIONS') {
      _addCorsHeaders(request.response);
      request.response
        ..statusCode = HttpStatus.noContent
        ..close();
      return;
    }

    if (path == '/live.m3u8') {
      _serveManifest(request);
    } else if (path.startsWith('/seg_') && path.endsWith('.ts')) {
      _serveSegment(request);
    } else {
      request.response
        ..statusCode = HttpStatus.notFound
        ..close();
    }
  }

  void _serveManifest(HttpRequest request) {
    if (_segments.isEmpty) {
      request.response
        ..statusCode = HttpStatus.serviceUnavailable
        ..write('No segments available yet')
        ..close();
      return;
    }

    final sortedKeys = _segments.keys.toList()..sort();
    final mediaSequence = sortedKeys.first;

    // TARGETDURATION must be >= longest segment
    double maxDuration = _targetSegmentSecs.toDouble();
    if (_estimatedBytesPerSec > 0) {
      for (final seg in _segments.values) {
        final dur = (seg.length / _estimatedBytesPerSec).clamp(1.0, 30.0);
        if (dur > maxDuration) maxDuration = dur;
      }
    }
    final targetDuration = maxDuration.ceil();

    final sb = StringBuffer()
      ..writeln('#EXTM3U')
      ..writeln('#EXT-X-VERSION:3')
      ..writeln('#EXT-X-TARGETDURATION:$targetDuration')
      ..writeln('#EXT-X-MEDIA-SEQUENCE:$mediaSequence');

    for (final seq in sortedKeys) {
      final dur = _estimatedBytesPerSec > 0
          ? (_segments[seq]!.length / _estimatedBytesPerSec)
              .clamp(1.0, 30.0)
          : _targetSegmentSecs.toDouble();
      sb
        ..writeln('#EXTINF:${dur.toStringAsFixed(3)},')
        ..writeln('seg_$seq.ts');
    }

    _addCorsHeaders(request.response);
    request.response
      ..headers.contentType = ContentType('application', 'x-mpegurl')
      ..headers.set('Cache-Control', 'no-cache, no-store')
      ..write(sb.toString())
      ..close();
  }

  void _serveSegment(HttpRequest request) {
    final filename = request.uri.pathSegments.last;
    final seqStr = filename.replaceAll('seg_', '').replaceAll('.ts', '');
    final seq = int.tryParse(seqStr);

    if (seq == null || !_segments.containsKey(seq)) {
      request.response
        ..statusCode = HttpStatus.notFound
        ..close();
      return;
    }

    final data = _segments[seq]!;
    _addCorsHeaders(request.response);
    request.response
      ..headers.contentType = ContentType('video', 'mp2t')
      ..headers.set('Cache-Control', 'no-cache')
      ..headers.contentLength = data.length
      ..add(data)
      ..close();
  }

  // ---------------------------------------------------------------------------
  // Network
  // ---------------------------------------------------------------------------

  Future<String?> _getWifiIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      );
      for (final iface in interfaces) {
        final name = iface.name.toLowerCase();
        if (name.contains('lo') && !name.contains('wl')) continue;
        if (name.contains('docker') || name.contains('veth')) continue;

        for (final addr in iface.addresses) {
          if (!addr.isLoopback) {
            AppLogger.info(
              'HLS proxy: Using IP ${addr.address} (${iface.name})',
            );
            return addr.address;
          }
        }
      }
    } catch (e) {
      AppLogger.error('HLS proxy: Failed to get WiFi IP — $e');
    }
    return null;
  }
}
