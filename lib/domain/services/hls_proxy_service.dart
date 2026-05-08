import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:meta/meta.dart';

import '../../core/utils/logger.dart';
import 'audio_transcode_service.dart';
import 'ffmpeg_transcode_service.dart';

/// Lightweight view of a network interface for IP picking. Used so the
/// picker logic can be unit-tested without depending on `dart:io`'s
/// `NetworkInterface`.
typedef NetworkInterfaceView = ({String name, List<String> ipv4Addresses});

/// Result of [pickWifiInterface]: the chosen interface plus a list of
/// per-interface scores, suitable for diagnostic logging.
typedef WifiPickResult = ({
  NetworkInterfaceView? chosen,
  List<({NetworkInterfaceView iface, int score, bool rejected})> scored,
});

// Negative-name patterns: interfaces whose names start with any of these
// are rejected outright (cellular, virtual, tunnel, etc).
const _kRejectedNamePrefixes = <String>[
  'lo',
  'docker',
  'veth',
  'rmnet',
  'dummy',
  'ifb',
  'tun',
  'ppp',
  'bond',
];

// Positive-name patterns: strong indicator that an interface is the
// physical Wi-Fi or Ethernet adapter we want.
const _kPositiveNamePrefixes = <String>[
  'wlan',
  'wlp',
  'en',
  'eth',
  'wifi',
];

bool _isRejectedName(String name) {
  final lower = name.toLowerCase();
  for (final prefix in _kRejectedNamePrefixes) {
    if (lower.startsWith(prefix)) return true;
  }
  return false;
}

bool _isPositiveName(String name) {
  final lower = name.toLowerCase();
  for (final prefix in _kPositiveNamePrefixes) {
    if (lower.startsWith(prefix)) return true;
  }
  return false;
}

bool _isRfc1918(String ip) {
  final parts = ip.split('.');
  if (parts.length != 4) return false;
  final o1 = int.tryParse(parts[0]);
  final o2 = int.tryParse(parts[1]);
  if (o1 == null || o2 == null) return false;
  if (o1 == 10) return true;
  if (o1 == 172 && o2 >= 16 && o2 <= 31) return true;
  if (o1 == 192 && o2 == 168) return true;
  return false;
}

/// Pick the interface most likely to be the LAN Wi-Fi/Ethernet adapter.
///
/// Scoring (only applied to non-rejected interfaces):
/// - +100 if the name starts with `wlan`/`wlp`/`en`/`eth`/`wifi`.
/// - +50 if the interface has at least one RFC1918 IPv4 address.
///
/// Rejected by name prefix (case-insensitive): `lo`, `docker`, `veth`,
/// `rmnet`, `dummy`, `ifb`, `tun`, `ppp`, `bond`.
///
/// Returns the highest-scoring interface. Ties are broken by preferring
/// an interface that has an RFC1918 address; remaining ties resolve by
/// lexicographic name order. Returns `null` if no interface scores > 0
/// (caller may fall back to a different strategy).
@visibleForTesting
WifiPickResult pickWifiInterface(List<NetworkInterfaceView> interfaces) {
  final scored = <({NetworkInterfaceView iface, int score, bool rejected})>[];

  for (final iface in interfaces) {
    if (_isRejectedName(iface.name)) {
      scored.add((iface: iface, score: 0, rejected: true));
      continue;
    }
    var score = 0;
    if (_isPositiveName(iface.name)) score += 100;
    if (iface.ipv4Addresses.any(_isRfc1918)) score += 50;
    scored.add((iface: iface, score: score, rejected: false));
  }

  final candidates =
      scored.where((s) => !s.rejected && s.score > 0).toList();
  if (candidates.isEmpty) {
    return (chosen: null, scored: scored);
  }

  candidates.sort((a, b) {
    // Primary: higher score wins.
    final byScore = b.score.compareTo(a.score);
    if (byScore != 0) return byScore;
    // Secondary: prefer the one with an RFC1918 address.
    final aPrivate = a.iface.ipv4Addresses.any(_isRfc1918);
    final bPrivate = b.iface.ipv4Addresses.any(_isRfc1918);
    if (aPrivate != bPrivate) return bPrivate ? 1 : -1;
    // Tertiary: lexicographic name order for determinism.
    return a.iface.name.compareTo(b.iface.name);
  });

  return (chosen: candidates.first.iface, scored: scored);
}

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
  static const _maxSegments = 6; // Enough runway to survive slow segment downloads without eviction
  static const _initialSegments = 2;
  static const _tsPacketSize = 188;
  static const _minSegmentBytes = 512 * 1024;
  static const _maxSegmentBytes = 10 * 1024 * 1024; // 10MB cap
  static const _silentAudioPid = 258; // PID for our synthetic silent AAC

  // Silent AAC-LC frame: ADTS header (7 bytes) + silent 1024-sample frame
  // Profile: AAC-LC, Sample rate: 48000Hz, Channels: 2 (stereo)
  // Raw AAC data: CPE (channel pair element) with zero spectral data + END
  // Total frame_length = 13 (7 header + 6 raw data)
  static final _silentAacFrame = Uint8List.fromList([
    // ADTS header: syncword=0xFFF, id=0(MPEG4), layer=0, protection=1(no CRC),
    // profile=1(AAC-LC), sampling_freq_index=3(48000), channel_config=2(stereo),
    // frame_length=13, buffer_fullness=0x7FF(VBR), num_raw_blocks=0
    0xFF, 0xF1, 0x4C, 0x80, 0x01, 0xBF, 0xFC,
    // CPE with zero spectral data (silent stereo 1024 samples)
    0x21, 0x10, 0x04, 0x60, 0x8C, 0x1C,
  ]);

  // Audio PTS increment per AAC frame: 1024 samples at 90kHz clock
  // = 1024 / 48000 * 90000 = 1920 ticks
  static const _audioPtsIncrement = 1920;

  HttpServer? _server;
  HttpClient? _httpClient;
  StreamSubscription<List<int>>? _fetchSub;
  String? _activeUrl;
  String? _wifiIp;

  final _segments = <int, Uint8List>{};
  final _segmentDurations = <int, double>{}; // sequence → PTS duration in seconds
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

  // AC-3 → AAC transcoding (incremental — transcode as data arrives)
  bool _transcodeAvailable = false;
  final _ac3Buffer = BytesBuilder(copy: false); // AC-3 PES payloads per segment
  final _transcodedAacFrames = <Uint8List>[]; // AAC frames ready for current segment

  // PTS remapping: subtract _ptsOffset from all PTS values so they
  // start near zero. Huge PTS values (5+ billion from long-running
  // live streams) can cause 32-bit overflow in some Cast player internals.
  int _ptsOffset = -1; // -1 = not yet captured
  int _segmentIndex = 0; // for EXT-X-PROGRAM-DATE-TIME

  // Set the first time _remapPcr sees a PCR base that is smaller than
  // _ptsOffset (so the subtraction would wrap into 33-bit space and emit
  // a nonsense PCR). Used to rate-limit the warning log to once per cast
  // session. Reset by stop().
  bool _pcrUnderflowWarned = false;

  int _totalBytesReceived = 0;
  int _totalVideoBytes = 0; // bytes after filtering (video only)
  Stopwatch? _stopwatch;

  // PTS-based segment duration tracking.
  int _segmentFirstPts = -1; // first video PTS in current segment
  int _segmentLastPts = -1; // last video PTS seen in current segment

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

      // AC-3 → AAC transcoding via FFmpeg subprocess.
      // Processes 8 seconds of audio in <500ms (50x+ realtime).
      // Called synchronously at segment flush — fast enough to not block.
      _transcodeAvailable = await FfmpegTranscodeService.instance.init();
      if (_transcodeAvailable) {
        AppLogger.info('HLS proxy: AC-3 → AAC transcoding enabled (ffmpeg)');
      }

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
    _segmentDurations.clear();
    _nextSequence = 0;
    _totalBytesReceived = 0;
    _totalVideoBytes = 0;
    _stopwatch = null;
    _segmentFirstPts = -1;
    _segmentLastPts = -1;
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
    _pcrUnderflowWarned = false;
    _transcodeAvailable = false;
    _ac3Buffer.clear();
    _transcodedAacFrames.clear();
    AudioTranscodeService.instance.stop();
    FfmpegTranscodeService.instance.stopProcess();
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

      // Collect audio TS packets for transcoding
      if (_audioPids.contains(pid)) {
        if (_transcodeAvailable) {
          _ac3Buffer.add(packet); // keep raw TS packets for FFmpeg
        }
        continue; // don't include AC-3 packets in segment
      }

      // Only keep video PID — drop everything else (SDT, etc.)
      if (_videoPid > 0 && pid != _videoPid) continue;

      final hasKeyframe = _isRandomAccessPoint(packet);

      if ((hasKeyframe && _segmentBytes >= _minSegmentBytes && _shouldSplit()) ||
          _segmentBytes >= _maxSegmentBytes) {
        _flushSegment();
      }

      // Track PTS for duration-based segmentation
      final pusi = (packet[1] & 0x40) != 0;
      if (pusi) {
        final pts = _extractPtsFromPacket(packet);
        if (pts > 0) {
          if (_segmentFirstPts < 0) _segmentFirstPts = pts;
          _segmentLastPts = pts;
        }
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
  /// Remap PCR in a TS packet's adaptation field by subtracting _ptsOffset.
  /// PCR is the master clock Cast uses — must match remapped PTS/DTS.
  void _remapPcr(Uint8List data, int i) {
    final afLen = data[i + 4];
    if (afLen < 7) return; // need at least flags + 6 bytes for PCR
    final afFlags = data[i + 5];
    if ((afFlags & 0x10) == 0) return; // PCR_flag not set

    // PCR is 6 bytes starting at i+6:
    // [0..4] = PCR base (33 bits) + marker + PCR ext (9 bits)
    // PCR base bits: b[0]<<25 | b[1]<<17 | b[2]<<9 | b[3]<<1 | b[4]>>7
    final b = data;
    final pcrBase = ((b[i + 6] & 0xFF) << 25) |
        ((b[i + 7] & 0xFF) << 17) |
        ((b[i + 8] & 0xFF) << 9) |
        ((b[i + 9] & 0xFF) << 1) |
        ((b[i + 10] >> 7) & 0x01);
    final pcrExt = ((b[i + 10] & 0x01) << 8) | (b[i + 11] & 0xFF);

    // Defensive: if PCR base sits before the captured PTS offset,
    // subtracting would wrap into a bogus 33-bit value and confuse Cast's
    // clock. Leave the PCR un-remapped for that packet — better a small
    // local clock discontinuity than a deliberately wrong PCR.
    if (_ptsOffset >= 0 && pcrBase < _ptsOffset) {
      if (!_pcrUnderflowWarned) {
        _pcrUnderflowWarned = true;
        AppLogger.warning(
          'HLS proxy: PCR underflow vs PTS offset; leaving PCR un-remapped.',
        );
      }
      return;
    }

    final remapped = (pcrBase - _ptsOffset) & 0x1FFFFFFFF; // 33-bit wraparound

    // Write remapped PCR back
    b[i + 6] = (remapped >> 25) & 0xFF;
    b[i + 7] = (remapped >> 17) & 0xFF;
    b[i + 8] = (remapped >> 9) & 0xFF;
    b[i + 9] = (remapped >> 1) & 0xFF;
    b[i + 10] = (((remapped & 0x01) << 7) | 0x7E | ((pcrExt >> 8) & 0x01));
    b[i + 11] = pcrExt & 0xFF;
  }

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
      // New PES — just collect data (sent as one batch at segment flush)

      // Extract raw audio data after PES header
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

  /// Parse a raw ADTS byte stream into individual ADTS frames.
  List<Uint8List> _parseAdtsFrames(Uint8List adtsStream) {
    final frames = <Uint8List>[];
    var offset = 0;
    while (offset + 7 <= adtsStream.length) {
      // ADTS sync word: 0xFFF
      if (adtsStream[offset] != 0xFF || (adtsStream[offset + 1] & 0xF0) != 0xF0) {
        offset++;
        continue;
      }
      // Frame length from ADTS header (13 bits across bytes 3-5)
      final frameLength = ((adtsStream[offset + 3] & 0x03) << 11) |
          (adtsStream[offset + 4] << 3) |
          ((adtsStream[offset + 5] >> 5) & 0x07);
      if (frameLength < 7 || offset + frameLength > adtsStream.length) break;
      frames.add(adtsStream.sublist(offset, offset + frameLength));
      offset += frameLength;
    }
    return frames;
  }

  /// Build TS packets from real transcoded AAC ADTS frames.
  Uint8List _buildAacAudioPackets(
    List<Uint8List> aacFrames, {
    int pts = 0,
    int totalFramesNeeded = 0,
  }) {
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

    // Pad with silent AAC frames to cover the full video duration.
    // Without this, audio PTS gaps cause Chromecast to stall after ~3 segments.
    final silentFramesToAdd = totalFramesNeeded > aacFrames.length
        ? totalFramesNeeded - aacFrames.length
        : 0;
    for (var i = 0; i < silentFramesToAdd; i++) {
      final aacPayload = _silentAacFrame;
      final pesLen = 3 + 5 + aacPayload.length;
      final pesPacket = BytesBuilder();
      pesPacket.add([0x00, 0x00, 0x01]);
      pesPacket.add([0xC0]);
      pesPacket.add([(pesLen >> 8) & 0xFF, pesLen & 0xFF]);
      pesPacket.add([0x80, 0x80, 0x05]);
      pesPacket.add(_encodePts(currentPts, 0x02));
      pesPacket.add(aacPayload);

      final fullPayload = pesPacket.takeBytes();
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
            for (var j = 6; j < 5 + stuffLen; j++) {
              pkt[j] = 0xFF;
            }
          }
          final dataStart = 5 + (stuffLen > 0 ? stuffLen : 0);
          for (var j = 0; j < toCopy; j++) {
            pkt[dataStart + j] = fullPayload[offset + j];
          }
        } else {
          for (var j = 0; j < toCopy; j++) {
            pkt[4 + j] = fullPayload[offset + j];
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
    // PTS-based duration — always accurate regardless of burst/bitrate.
    if (_segmentFirstPts >= 0 && _segmentLastPts > _segmentFirstPts) {
      final ptsDuration = (_segmentLastPts - _segmentFirstPts) / 90000.0;
      return ptsDuration >= _targetSegmentSecs;
    }
    // Fallback before first PTS is seen
    return _segmentBytes >= 3 * 1024 * 1024;
  }

  /// Extract PTS from a single TS packet with PUSI set.
  int _extractPtsFromPacket(Uint8List packet) {
    var ps = 4;
    final af = (packet[3] >> 4) & 0x03;
    if (af >= 2) ps += 1 + packet[4];
    if (ps + 13 >= packet.length) return 0;
    if (packet[ps] == 0x00 && packet[ps + 1] == 0x00 && packet[ps + 2] == 0x01) {
      final flags = packet[ps + 7];
      if ((flags & 0x80) != 0 && ps + 13 < packet.length) {
        return _readPts(packet, ps + 9);
      }
    }
    return 0;
  }

  void _flushSegment() async {
    if (_segmentBytes == 0) return;

    // Capture PTS duration before resetting
    double segDuration = _targetSegmentSecs.toDouble();
    if (_segmentFirstPts >= 0 && _segmentLastPts > _segmentFirstPts) {
      segDuration = ((_segmentLastPts - _segmentFirstPts) / 90000.0)
          .clamp(1.0, 30.0);
    }
    _segmentFirstPts = -1;
    _segmentLastPts = -1;

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

    // Remap all PTS/DTS/PCR in video packets and renumber CCs.
    // PCR must also be remapped — Cast uses PCR as the master clock.
    // If PCR is billions of ticks ahead of remapped PTS, Cast stalls.
    var cc = 0;
    for (var i = 0; i + _tsPacketSize <= videoBytes.length; i += _tsPacketSize) {
      if (videoBytes[i] != 0x47) continue;
      final hasAdaptation = (videoBytes[i + 3] & 0x20) != 0;
      final hasPayload = (videoBytes[i + 3] & 0x10) != 0;
      if (hasPayload) {
        videoBytes[i + 3] = (videoBytes[i + 3] & 0xF0) | (cc & 0x0F);
        cc++;
      }

      // Remap PCR in adaptation field
      if (hasAdaptation && _ptsOffset > 0) {
        _remapPcr(videoBytes, i);
      }

      // Remap PTS/DTS in PES headers
      final pusi = (videoBytes[i + 1] & 0x40) != 0;
      if (pusi && hasPayload) {
        _remapPesTimestamps(videoBytes, i);
      }
    }
    // Audio: try real AC-3 → AAC transcoding, fall back to silent AAC.
    // Audio packets go BEFORE video so the Cast device encounters them
    // early in the segment (some players only scan the beginning for streams).
    final firstVideoPts = _extractFirstPts(videoBytes);
    final lastVideoPts = _extractLastPts(videoBytes);
    final videoPtsDuration = lastVideoPts > firstVideoPts
        ? lastVideoPts - firstVideoPts
        : (_targetSegmentSecs * 90000);
    final audioDurationTicks = videoPtsDuration + 3000;
    final numSilentFrames = (audioDurationTicks / _audioPtsIncrement).ceil();

    Uint8List audioPackets;
    if (_transcodeAvailable && _ac3Buffer.length > 0) {
      final ffmpegStart = DateTime.now();
      final tsBuilder = BytesBuilder();
      if (_lastPat != null) tsBuilder.add(_lastPat!);
      if (_lastPmt != null) tsBuilder.add(_lastPmt!);
      tsBuilder.add(_ac3Buffer.takeBytes());
      final ac3TsData = Uint8List.fromList(tsBuilder.takeBytes());
      final aacAdts = await FfmpegTranscodeService.instance.transcode(ac3TsData);
      final ffmpegMs = DateTime.now().difference(ffmpegStart).inMilliseconds;

      if (aacAdts.isNotEmpty) {
        final frames = _parseAdtsFrames(aacAdts);
        audioPackets = _buildAacAudioPackets(
          frames,
          pts: firstVideoPts,
          totalFramesNeeded: numSilentFrames,
        );
        AppLogger.debug(
          'HLS proxy: FFmpeg ${ffmpegMs}ms → ${frames.length}/$numSilentFrames AAC frames '
          '(${(ac3TsData.length / 1024).toStringAsFixed(0)}KB in)',
        );
      } else {
        audioPackets = _buildSilentAudioPackets(numSilentFrames, pts: firstVideoPts);
        AppLogger.debug('HLS proxy: FFmpeg returned no data, using silent AAC');
      }
    } else {
      // Silent AAC fallback
      _ac3Buffer.clear();
      audioPackets = _buildSilentAudioPackets(numSilentFrames, pts: firstVideoPts);
    }
    // Audio before video so Cast's demuxer encounters audio early in the segment
    header.add(audioPackets);
    header.add(videoBytes);

    _segmentIndex++;

    final segment = Uint8List.fromList(header.takeBytes());

    final seq = _nextSequence++;
    _segments[seq] = segment;
    _segmentDurations[seq] = segDuration;

    while (_segments.length > _maxSegments) {
      final oldest = _segments.keys.reduce((a, b) => a < b ? a : b);
      _segments.remove(oldest);
      _segmentDurations.remove(oldest);
    }

    AppLogger.debug(
      'HLS proxy: Segment $seq — '
      '${(segment.length / 1024).toStringAsFixed(0)} KB, '
      '${segDuration.toStringAsFixed(1)}s '
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
    final sortedSegs = _segments.keys.toList()..sort();
    AppLogger.debug(
      'HLS proxy: Manifest request — segs=${sortedSegs.join(",")}, '
      'durations=${sortedSegs.map((s) => _segmentDurations[s]?.toStringAsFixed(1) ?? "?").join(",")}',
    );
    if (_segments.isEmpty) {
      request.response
        ..statusCode = HttpStatus.serviceUnavailable
        ..write('No segments available yet')
        ..close();
      return;
    }

    final sortedKeys = _segments.keys.toList()..sort();
    final mediaSequence = sortedKeys.first;

    // Accurate EXTINF from PTS duration. Combined with maxSegments=4,
    // the seek window is small enough (~24-32s) that the Cast starts
    // from the beginning rather than jumping to a non-IDR live edge.
    double maxDuration = _targetSegmentSecs.toDouble();
    for (final seq in sortedKeys) {
      final dur = _segmentDurations[seq] ?? _targetSegmentSecs.toDouble();
      if (dur > maxDuration) maxDuration = dur;
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
      final dur = _segmentDurations[seq] ?? _targetSegmentSecs.toDouble();
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

      // Adapt to the testable view used by [pickWifiInterface].
      final views = <NetworkInterfaceView>[
        for (final iface in interfaces)
          (
            name: iface.name,
            ipv4Addresses: [
              for (final a in iface.addresses)
                if (!a.isLoopback) a.address,
            ],
          ),
      ];

      final result = pickWifiInterface(views);

      // Diagnostic: log every interface, its score, and whether it was
      // rejected by name. Helps debug remote reports from users on
      // unusual carriers / VPNs / split-tunnel setups.
      final summary = result.scored
          .map(
            (s) => '${s.iface.name}'
                '${s.iface.ipv4Addresses.isEmpty ? "" : "=${s.iface.ipv4Addresses.join(",")}"}'
                '${s.rejected ? "[rejected]" : "[score=${s.score}]"}',
          )
          .join('; ');

      if (result.chosen != null && result.chosen!.ipv4Addresses.isNotEmpty) {
        final addr = result.chosen!.ipv4Addresses.first;
        AppLogger.info(
          'HLS proxy: Using IP $addr (${result.chosen!.name}). '
          'Interfaces: $summary',
        );
        return addr;
      }

      // Nothing scored > 0. Fall back to the prior behavior so we don't
      // regress users on home networks with unusual interface naming:
      // first non-loopback IPv4 from any interface that isn't `lo`,
      // `docker`, or `veth`.
      AppLogger.error(
        'HLS proxy: No interface scored as Wi-Fi/Ethernet. '
        'Falling back to first non-loopback IPv4. Interfaces: $summary',
      );
      for (final iface in interfaces) {
        final name = iface.name.toLowerCase();
        if (name.contains('lo') && !name.contains('wl')) continue;
        if (name.contains('docker') || name.contains('veth')) continue;
        for (final addr in iface.addresses) {
          if (!addr.isLoopback) {
            AppLogger.warning(
              'HLS proxy: Fallback IP ${addr.address} (${iface.name})',
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
