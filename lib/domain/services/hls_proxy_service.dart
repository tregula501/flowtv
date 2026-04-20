import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../../core/utils/logger.dart';
import 'audio_transcode_service.dart';

/// A local HTTP server that reads a remote MPEG-TS stream and serves it as
/// live HLS for Chromecast. Segments are split at keyframe (RAI) boundaries.
///
/// Audio handling:
/// - If MediaCodec AC-3 transcoding is available: AC-3 → AAC in real-time
/// - Otherwise: silent AAC placeholder (video-only casting)
class HlsProxyService {
  static HlsProxyService? _instance;
  static HlsProxyService get instance => _instance ??= HlsProxyService._();
  HlsProxyService._();

  static const _targetSegmentSecs = 6;
  static const _maxSegments = 8; // Chromecast needs ≥6 for stable seek window
  static const _initialSegments = 2;
  static const _tsPacketSize = 188;
  static const _minSegmentBytes = 512 * 1024;
  static const _maxSegmentBytes = 10 * 1024 * 1024; // 10MB cap
  static const _silentAudioPid = 258; // PID for our synthetic silent AAC

  // Silent AAC-LC frame: ADTS header (7 bytes) + silent 1024-sample frame
  // Profile: AAC-LC, Sample rate: 44100Hz, Channels: 2 (stereo)
  // Raw AAC data: CPE (channel pair element) with zero spectral data + END
  // Total frame_length = 13 (7 header + 6 raw data)
  static final _silentAacFrame = Uint8List.fromList([
    // ADTS header: syncword=0xFFF, id=0(MPEG4), layer=0, protection=1(no CRC),
    // profile=1(AAC-LC), sampling_freq_index=4(44100), channel_config=2(stereo),
    // frame_length=13, buffer_fullness=0x7FF(VBR), num_raw_blocks=0
    0xFF, 0xF1, 0x50, 0x80, 0x01, 0xBF, 0xFC,
    // CPE with zero spectral data (silent stereo 1024 samples)
    0x21, 0x10, 0x04, 0x60, 0x8C, 0x1C,
  ]);

  // Audio PTS increment per AAC frame: 1024 samples at 90kHz clock
  // = 1024 / 44100 * 90000 = 2089.795... ≈ 2090 ticks
  static const _audioPtsIncrement = 2090;

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

  // AC-3 → AAC transcoding
  bool _transcodeAvailable = false;
  final _ac3Buffer = BytesBuilder(copy: false); // AC-3 PES payloads per segment

  // PTS remapping: subtract _ptsOffset from all PTS values so they
  // start near zero. Huge PTS values (5+ billion from long-running
  // live streams) can cause 32-bit overflow in some Cast player internals.
  int _ptsOffset = -1; // -1 = not yet captured
  int _segmentIndex = 0; // for EXT-X-PROGRAM-DATE-TIME

  int _totalBytesReceived = 0;
  int _totalVideoBytes = 0; // bytes after filtering (video only)
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

      // AC-3 → AAC transcoding via MediaCodec.
      // TODO: Enable once AAC output is validated. Currently disabled
      // because the transcoded AAC frames cause Chromecast playback errors.
      // The infrastructure is in place (AudioTranscoder.kt + AudioTranscodeService.dart).
      _transcodeAvailable = false;
      AppLogger.info('HLS proxy: Audio transcode disabled (using silent AAC)');

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
    _totalVideoBytes = 0;
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
    _ptsOffset = -1;
    _segmentIndex = 0;
    _transcodeAvailable = false;
    _ac3Buffer.clear();
    AudioTranscodeService.instance.stop();
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
            onDone: () async {
              AppLogger.info('HLS proxy: Upstream closed');
              await _flushSegment();
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
      // Use video-only bytes for bitrate estimation since we filter out
      // audio. Using total bytes would overestimate, causing EXTINF
      // durations to be 3-5x too long (Chromecast freezes on playback).
      if (elapsed >= 3000 && _totalVideoBytes > 0) {
        _estimatedBytesPerSec = _totalVideoBytes * 1000.0 / elapsed;
        _bitrateEstimated = true;
        AppLogger.info(
          'HLS proxy: Estimated video bitrate '
          '${(_estimatedBytesPerSec * 8 / 1000000).toStringAsFixed(1)} Mbps '
          '(total stream: ${(_totalBytesReceived * 8000.0 / elapsed / 1000000).toStringAsFixed(1)} Mbps)',
        );
      }
    }

    _processPackets();
  }

  // ---------------------------------------------------------------------------
  // TS packet processing
  // ---------------------------------------------------------------------------

  Future<void> _processPackets() async {
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

      // Collect AC-3 audio PES payloads for transcoding
      if (_audioPids.contains(pid)) {
        if (_transcodeAvailable) {
          _collectAc3Payload(packet);
        }
        continue; // don't include AC-3 packets in segment
      }

      // Only keep video PID — drop everything else (SDT, etc.)
      if (_videoPid > 0 && pid != _videoPid) continue;

      final hasKeyframe = _isRandomAccessPoint(packet);

      if ((hasKeyframe && _segmentBytes >= _minSegmentBytes && _shouldSplit()) ||
          _segmentBytes >= _maxSegmentBytes) {
        await _flushSegment();
      }

      _segmentBuffer.add(packet);
      _segmentBytes += _tsPacketSize;
      _totalVideoBytes += _tsPacketSize;
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

  /// Remap PTS/DTS values in a PES header by subtracting _ptsOffset.
  void _remapPesTimestamps(Uint8List data, int tsOffset) {
    var ps = tsOffset + 4;
    final af = (data[tsOffset + 3] >> 4) & 0x03;
    if (af >= 2) ps += 1 + data[tsOffset + 4];
    if (ps + 9 >= data.length) return;

    if (data[ps] != 0x00 || data[ps + 1] != 0x00 || data[ps + 2] != 0x01) {
      return; // not a PES header
    }

    final flags = data[ps + 7];
    final hasPts = (flags & 0x80) != 0;
    final hasDts = (flags & 0x40) != 0;

    if (hasPts && ps + 14 <= data.length) {
      final pts = _readPts(data, ps + 9);
      final remapped = (pts - _ptsOffset).clamp(0, (1 << 33) - 1);
      _writePts(data, ps + 9, remapped, hasDts ? 0x03 : 0x02);

      if (hasDts && ps + 19 <= data.length) {
        final dts = _readPts(data, ps + 14);
        final remappedDts = (dts - _ptsOffset).clamp(0, (1 << 33) - 1);
        _writePts(data, ps + 14, remappedDts, 0x01);
      }
    }
  }

  /// Read a 33-bit PTS/DTS value from 5 bytes.
  static int _readPts(Uint8List data, int off) {
    return ((data[off] & 0x0E) << 29) |
        (data[off + 1] << 22) |
        ((data[off + 2] & 0xFE) << 14) |
        (data[off + 3] << 7) |
        (data[off + 4] >> 1);
  }

  /// Write a 33-bit PTS/DTS value into 5 bytes.
  static void _writePts(Uint8List data, int off, int pts, int marker) {
    data[off] = (marker << 4) | ((pts >> 29) & 0x0E) | 0x01;
    data[off + 1] = (pts >> 22) & 0xFF;
    data[off + 2] = ((pts >> 14) & 0xFE) | 0x01;
    data[off + 3] = (pts >> 7) & 0xFF;
    data[off + 4] = ((pts << 1) & 0xFE) | 0x01;
  }

  /// Extract AC-3 PES payload from a TS packet and add to buffer.
  void _collectAc3Payload(Uint8List packet) {
    var ps = 4;
    final af = (packet[3] >> 4) & 0x03;
    if (af >= 2) ps += 1 + packet[4];
    if (ps >= _tsPacketSize) return;

    final pusi = (packet[1] & 0x40) != 0;
    if (pusi) {
      // PES header — skip it, extract raw audio data after header
      if (ps + 9 < _tsPacketSize &&
          packet[ps] == 0x00 && packet[ps + 1] == 0x00 && packet[ps + 2] == 0x01) {
        final headerLen = packet[ps + 8];
        final dataStart = ps + 9 + headerLen;
        if (dataStart < _tsPacketSize) {
          _ac3Buffer.add(packet.sublist(dataStart));
        }
      }
    } else {
      // Continuation packet — all payload is audio data
      _ac3Buffer.add(packet.sublist(ps));
    }
  }

  /// Extract the last PTS from video PES packets in segment data.
  int _extractLastPts(Uint8List data) {
    int lastPts = 0;
    for (var i = 0; i + _tsPacketSize <= data.length; i += _tsPacketSize) {
      if (data[i] != 0x47) continue;
      final pusi = (data[i + 1] & 0x40) != 0;
      if (!pusi) continue;

      var ps = i + 4;
      final af = (data[i + 3] >> 4) & 0x03;
      if (af >= 2) ps += 1 + data[i + 4];
      if (ps + 13 >= data.length) continue;

      if (data[ps] == 0x00 && data[ps + 1] == 0x00 && data[ps + 2] == 0x01) {
        final flags = data[ps + 7];
        if ((flags & 0x80) != 0) {
          lastPts = _readPts(data, ps + 9);
        }
      }
    }
    return lastPts;
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

  /// Build TS packets from real transcoded AAC ADTS frames.
  Uint8List _buildAacAudioPackets(List<Uint8List> aacFrames, {int pts = 0}) {
    final allPackets = BytesBuilder();
    var audioCC = 0;
    var currentPts = pts;

    for (final frame in aacFrames) {
      // Each ADTS frame gets its own PES
      final pesLen = 3 + 5 + frame.length;
      final pesPacket = BytesBuilder();
      pesPacket.add([0x00, 0x00, 0x01]); // PES start code
      pesPacket.add([0xC0]); // audio stream 0
      pesPacket.add([(pesLen >> 8) & 0xFF, pesLen & 0xFF]);
      pesPacket.add([0x80, 0x80, 0x05]); // PTS only
      pesPacket.add(_encodePts(currentPts, 0x02));
      pesPacket.add(frame);

      final fullPayload = pesPacket.takeBytes();

      // Pack into TS packets
      var offset = 0;
      var first = true;
      while (offset < fullPayload.length) {
        final pkt = Uint8List(_tsPacketSize);
        pkt[0] = 0x47;
        pkt[1] = (first ? 0x40 : 0x00) | ((_silentAudioPid >> 8) & 0x1F);
        pkt[2] = _silentAudioPid & 0xFF;
        pkt[3] = 0x10 | (audioCC & 0x0F);
        audioCC++;
        first = false;

        const payloadSpace = _tsPacketSize - 4;
        final remaining = fullPayload.length - offset;
        final toCopy = remaining < payloadSpace ? remaining : payloadSpace;

        if (toCopy < payloadSpace) {
          final stuffLen = payloadSpace - toCopy - 1;
          pkt[3] |= 0x20;
          pkt[4] = stuffLen > 0 ? stuffLen : 0;
          if (stuffLen > 0) {
            pkt[5] = 0x00;
            for (var i = 6; i < 5 + stuffLen; i++) {
              pkt[i] = 0xFF;
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
        allPackets.add(pkt);
      }

      currentPts += _audioPtsIncrement;
    }

    return Uint8List.fromList(allPackets.takeBytes());
  }

  /// Build TS packets containing silent AAC audio frames, each in its own PES
  /// packet with an incrementing PTS. Chromecast requires per-frame PTS to
  /// maintain A/V sync; a single PES with all frames causes audio timeline
  /// confusion and playback cuts after ~3 segments.
  Uint8List _buildSilentAudioPackets(int numFrames, {int pts = 0}) {
    final allPackets = BytesBuilder();
    var audioCC = 0;
    var currentPts = pts;

    for (var frame = 0; frame < numFrames; frame++) {
      // Build a PES packet for this single ADTS frame
      final aacPayload = _silentAacFrame;
      final pesLen = 3 + 5 + aacPayload.length; // flags(3) + PTS(5) + data

      final pesPacket = BytesBuilder();
      pesPacket.add([0x00, 0x00, 0x01]); // PES start code
      pesPacket.add([0xC0]); // Stream ID: audio stream 0
      pesPacket.add([(pesLen >> 8) & 0xFF, pesLen & 0xFF]);
      pesPacket.add([0x80, 0x80, 0x05]); // PTS only
      pesPacket.add(_encodePts(currentPts, 0x02));
      pesPacket.add(aacPayload);

      final fullPayload = pesPacket.takeBytes();

      // Pack this single-frame PES into TS packets
      var offset = 0;
      var first = true;

      while (offset < fullPayload.length) {
        final pkt = Uint8List(_tsPacketSize);
        pkt[0] = 0x47; // sync
        pkt[1] = (first ? 0x40 : 0x00) | ((_silentAudioPid >> 8) & 0x1F);
        pkt[2] = _silentAudioPid & 0xFF;
        pkt[3] = 0x10 | (audioCC & 0x0F); // payload only, CC
        audioCC++;
        first = false;

        const payloadSpace = _tsPacketSize - 4;
        final remaining = fullPayload.length - offset;
        final toCopy = remaining < payloadSpace ? remaining : payloadSpace;

        // If payload doesn't fill the TS packet, add adaptation field stuffing
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
        allPackets.add(pkt);
      }

      // Advance PTS for next frame: 1024 samples at 90kHz
      currentPts += _audioPtsIncrement;
    }

    return Uint8List.fromList(allPackets.takeBytes());
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

  Future<void> _flushSegment() async {
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

    // Renumber CCs and remap PTS values to start near zero.
    // Large PTS (5+ billion from long-running live streams) can cause
    // 32-bit overflow in the Chromecast's internal player (Shaka).
    final videoBytes = contentBytes is Uint8List
        ? contentBytes
        : Uint8List.fromList(contentBytes);

    // Capture PTS offset from the very first segment
    if (_ptsOffset < 0) {
      final firstPts = _extractFirstPts(videoBytes);
      // Start at 90000 (1 second) to give some headroom
      _ptsOffset = firstPts > 90000 ? firstPts - 90000 : 0;
      AppLogger.info('HLS proxy: PTS offset set to $_ptsOffset '
          '(original PTS=${firstPts}, remapped to ${firstPts - _ptsOffset})');
    }

    // Remap all PTS/DTS in video PES headers and renumber CCs
    var cc = 0;
    for (var i = 0; i + _tsPacketSize <= videoBytes.length; i += _tsPacketSize) {
      if (videoBytes[i] != 0x47) continue;
      final hasPayload = (videoBytes[i + 3] & 0x10) != 0;
      if (hasPayload) {
        videoBytes[i + 3] = (videoBytes[i + 3] & 0xF0) | (cc & 0x0F);
        cc++;
      }

      // Remap PTS/DTS in PES headers
      final pusi = (videoBytes[i + 1] & 0x40) != 0;
      if (pusi && hasPayload) {
        _remapPesTimestamps(videoBytes, i);
      }
    }
    header.add(videoBytes);

    // Audio: try real AC-3 → AAC transcoding, fall back to silent AAC
    final firstVideoPts = _extractFirstPts(videoBytes);
    final lastVideoPts = _extractLastPts(videoBytes);
    final videoPtsDuration = lastVideoPts > firstVideoPts
        ? lastVideoPts - firstVideoPts
        : (_targetSegmentSecs * 90000);
    final audioDurationTicks = videoPtsDuration + 3000;
    final numSilentFrames = (audioDurationTicks / _audioPtsIncrement).ceil();

    Uint8List audioPackets;
    if (_transcodeAvailable && _ac3Buffer.length > 0) {
      // Transcode collected AC-3 data to real AAC
      final ac3Data = Uint8List.fromList(_ac3Buffer.takeBytes());
      final aacFrames = await AudioTranscodeService.instance.transcode(ac3Data);
      if (aacFrames.isNotEmpty) {
        audioPackets = _buildAacAudioPackets(aacFrames, pts: firstVideoPts);
        AppLogger.debug(
          'HLS proxy: Transcoded ${ac3Data.length} AC-3 bytes → '
          '${aacFrames.length} AAC frames',
        );
      } else {
        // Transcoding returned nothing — use silent fallback
        audioPackets = _buildSilentAudioPackets(numSilentFrames, pts: firstVideoPts);
      }
    } else {
      _ac3Buffer.clear(); // discard if not transcoding
      audioPackets = _buildSilentAudioPackets(numSilentFrames, pts: firstVideoPts);
    }
    header.add(audioPackets);

    _segmentIndex++;

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
      ..writeln('#EXT-X-MEDIA-SEQUENCE:$mediaSequence')
      ..writeln('#EXT-X-INDEPENDENT-SEGMENTS');

    for (var i = 0; i < sortedKeys.length; i++) {
      final seq = sortedKeys[i];
      final dur = _estimatedBytesPerSec > 0
          ? (_segments[seq]!.length / _estimatedBytesPerSec)
              .clamp(1.0, 30.0)
          : _targetSegmentSecs.toDouble();
      // Mark each segment as a discontinuity — our PTS values restart
      // per segment and may have small gaps at boundaries.
      if (i > 0) sb.writeln('#EXT-X-DISCONTINUITY');
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
