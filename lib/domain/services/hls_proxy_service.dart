import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/utils/logger.dart';

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

/// A local HTTP server that turns a remote MPEG-TS live stream into
/// Chromecast-compatible HLS.
///
/// Pipeline (all heavy lifting done by the bundled ffmpeg subprocess, off
/// the Dart event loop):
///
///   upstream HTTPS TS  ──Dart HttpClient──▶  ffmpeg stdin
///   ffmpeg  ─(-c:v copy, AC-3→AAC)─▶  live HLS files on disk
///   Dart HTTP server   ──serves m3u8 + segments──▶  Chromecast
///
/// Why a subprocess instead of hand-rolled Dart TS munging:
/// - ffmpeg produces standards-correct HLS (PCR/PTS/keyframe segmentation,
///   accurate EXTINF), which the Cast receiver's player handles natively.
/// - AC-3 is transcoded to AAC, so audio actually plays (Cast's Default
///   Media Receiver cannot decode AC-3).
/// - Running in a separate OS process means muxing/transcoding never blocks
///   the HTTP server that feeds the Chromecast — eliminating the segment-fetch
///   stalls that caused constant stuttering.
/// - Dart owns the upstream socket, so it transparently follows the provider's
///   HTTPS→HTTP signed redirect and reconnects when the provider drops the
///   connection (the main cause of casts dying after a while).
class HlsProxyService {
  static HlsProxyService? _instance;
  static HlsProxyService get instance => _instance ??= HlsProxyService._();
  HlsProxyService._();

  static const _packageName = 'io.github.tregula501.flowtv';

  // HLS shape. A deliberately SHORT window: 2s segments × 5 = ~10s. The
  // "Stream TV" receiver over-buffers and renders audio far behind video (a
  // constant ~30s offset, larger than our old 24s window). Bounding the window
  // to ~10s caps the worst-case A/V offset and keeps the receiver near the live
  // edge. Requires the 2s GOP that the transcode path produces (-g 60 @ 30fps).
  static const _segmentSeconds = 2;
  static const _listSize = 5;
  static const _readyTimeout = Duration(seconds: 25);

  // Upstream providers commonly reject empty/unknown User-Agents.
  static const _userAgent = 'VLC/3.0.20 LibVLC/3.0.20';

  static final _segmentPattern = RegExp(r'^/seg_\d+\.ts$');

  /// When true, re-encode video to 1080p30 Baseline H.264 via the hardware
  /// encoder instead of copying it.
  ///
  /// Enabled because it gives a controlled 2s GOP (`-g 60` @ 30fps), which lets
  /// us emit 2s segments and run the tight ~10s live window above. Copying the
  /// source instead would tie segment size to the broadcast's GOP (~4s),
  /// forcing a larger window. The re-encode also yields a clean, correctly
  /// labeled bitstream and stays A/V-synced (~2.6x realtime on the Fire HD 10).
  bool transcodeVideo = true;

  HttpServer? _server;
  String? _wifiIp;
  String? _activeUrl;
  String? _ffmpegPath;
  Directory? _hlsDir;

  Process? _ffmpeg;
  StreamSubscription<String>? _ffmpegStderrSub;
  int _ffmpegRestarts = 0;

  HttpClient? _upstreamClient;
  int _reconnects = 0;

  bool _stopping = false;
  bool _stopped = true;

  bool get isRunning => _server != null && !_stopped;

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  Future<String?> start(String tsStreamUrl) async {
    if (isRunning && _activeUrl == tsStreamUrl && _wifiIp != null) {
      return 'http://$_wifiIp:${_server!.port}/live.m3u8';
    }

    await stop();
    _stopping = false;
    _stopped = false;
    _reconnects = 0;
    _ffmpegRestarts = 0;

    final ip = await _getWifiIp();
    if (ip == null) {
      AppLogger.error('HLS proxy: Could not determine WiFi IP');
      await stop();
      return null;
    }
    _wifiIp = ip;

    _ffmpegPath = await _resolveFfmpegPath();
    if (_ffmpegPath == null) {
      AppLogger.error('HLS proxy: ffmpeg binary not found — cannot cast');
      await stop();
      return null;
    }

    try {
      final base = await getTemporaryDirectory();
      final dir = Directory('${base.path}/cast_hls');
      if (await dir.exists()) await dir.delete(recursive: true);
      await dir.create(recursive: true);
      _hlsDir = dir;

      _server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
      final port = _server!.port;
      AppLogger.info('HLS proxy: Listening on 0.0.0.0:$port (WiFi IP: $ip)');
      _server!.listen(_handleRequest);

      if (!await _startFfmpeg()) {
        AppLogger.error('HLS proxy: Failed to launch ffmpeg');
        await stop();
        return null;
      }

      _activeUrl = tsStreamUrl;
      unawaited(_fetchLoop(tsStreamUrl));

      final ready = await _waitForManifest();
      if (!ready) {
        AppLogger.error('HLS proxy: ffmpeg did not produce a playable manifest');
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
    _stopping = true;

    // Closing the upstream client aborts any in-flight addStream() pumping
    // the response into ffmpeg's stdin, which lets _fetchLoop exit.
    _upstreamClient?.close(force: true);
    _upstreamClient = null;

    await _ffmpegStderrSub?.cancel();
    _ffmpegStderrSub = null;

    final ff = _ffmpeg;
    _ffmpeg = null;
    if (ff != null) {
      try {
        await ff.stdin.close();
      } catch (_) {}
      ff.kill(ProcessSignal.sigkill);
    }

    await _server?.close(force: true);
    _server = null;

    final dir = _hlsDir;
    _hlsDir = null;
    if (dir != null) {
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    }

    _wifiIp = null;
    _activeUrl = null;
    _reconnects = 0;
    _ffmpegRestarts = 0;
    _stopped = true;
    AppLogger.info('HLS proxy: Stopped');
  }

  // ---------------------------------------------------------------------------
  // ffmpeg
  // ---------------------------------------------------------------------------

  /// Locate the bundled ffmpeg binary (shipped as `libffmpeg.so` in the
  /// app's native library directory so Android allows executing it).
  Future<String?> _resolveFfmpegPath() async {
    if (!Platform.isAndroid) return null;
    try {
      final pm = await Process.run('pm', ['path', _packageName]);
      if (pm.exitCode != 0) {
        AppLogger.error('HLS proxy: `pm path` failed (${pm.exitCode})');
        return null;
      }
      final firstLine = (pm.stdout as String)
          .split('\n')
          .map((l) => l.trim())
          .firstWhere((l) => l.startsWith('package:'), orElse: () => '');
      final apkPath = firstLine.replaceFirst('package:', '');
      if (apkPath.isEmpty) return null;
      final libDir = apkPath.replaceFirst('/base.apk', '/lib/arm64');
      final ffmpeg = File('$libDir/libffmpeg.so');
      if (await ffmpeg.exists()) return ffmpeg.path;
      AppLogger.error('HLS proxy: libffmpeg.so not found at ${ffmpeg.path}');
    } catch (e) {
      AppLogger.error('HLS proxy: ffmpeg path resolution failed — $e');
    }
    return null;
  }

  List<String> _videoArgs() {
    if (transcodeVideo) {
      // Hardware H.264 encode, capped at 30fps. Keeps full resolution but
      // halves the receiver's decode rate.
      return [
        '-c:v', 'h264_mediacodec',
        '-vf', 'fps=30',
        '-b:v', '6M',
        '-g', '60',
      ];
    }
    return ['-c:v', 'copy'];
  }

  Future<bool> _startFfmpeg() async {
    final dir = _hlsDir;
    final ffmpeg = _ffmpegPath;
    if (dir == null || ffmpeg == null) return false;

    final args = <String>[
      '-hide_banner',
      '-loglevel', 'warning',
      '-fflags', '+genpts',
      '-analyzeduration', '3000000',
      '-probesize', '3000000',
      '-f', 'mpegts',
      '-i', 'pipe:0',
      '-map', '0:v:0',
      '-map', '0:a:0?',
      ..._videoArgs(),
      '-c:a', 'aac',
      '-b:a', '160k',
      '-ac', '2',
      '-ar', '48000',
      '-max_muxing_queue_size', '1024',
      '-f', 'hls',
      '-hls_time', '$_segmentSeconds',
      '-hls_list_size', '$_listSize',
      // MPEG-TS segments. fMP4 was tried but the "Stream TV" Default Media
      // Receiver refuses to render it (loads init + a few fragments then
      // black-screens, regardless of codec/profile). TS is the only format
      // this receiver actually plays. program_date_time gives absolute time
      // anchors to help its demuxer align audio/video.
      '-hls_flags',
      'delete_segments+omit_endlist+independent_segments+program_date_time',
      '-hls_segment_type', 'mpegts',
      '-hls_allow_cache', '0',
      '-hls_delete_threshold', '1',
      '-hls_segment_filename', 'seg_%d.ts',
      'live.m3u8',
    ];

    try {
      // Run with the HLS dir as cwd so ffmpeg writes init.mp4 / segments /
      // playlist there and emits bare (relative) URIs in the manifest.
      final proc = await Process.start(ffmpeg, args, workingDirectory: dir.path);
      _ffmpeg = proc;
      AppLogger.info(
        'HLS proxy: ffmpeg started (video=${transcodeVideo ? "30fps h264_mediacodec" : "copy"})',
      );

      // HLS muxer writes to files; stdout is unused but must be drained so
      // the process never blocks on a full pipe.
      unawaited(proc.stdout.drain<void>().catchError((_) {}));

      _ffmpegStderrSub = proc.stderr
          .transform(const SystemEncoding().decoder)
          .transform(const LineSplitter())
          .listen((line) {
        if (line.trim().isNotEmpty) {
          AppLogger.info('HLS proxy: ffmpeg: ${line.trim()}');
        }
      });

      unawaited(proc.exitCode.then((code) {
        if (_stopping || !identical(_ffmpeg, proc)) return;
        AppLogger.warning('HLS proxy: ffmpeg exited (code=$code)');
        unawaited(_restartFfmpeg());
      }));

      return true;
    } catch (e) {
      AppLogger.error('HLS proxy: ffmpeg launch failed — $e');
      _ffmpeg = null;
      return false;
    }
  }

  Future<void> _restartFfmpeg() async {
    if (_stopping) return;
    if (_ffmpegRestarts >= 3) {
      AppLogger.error('HLS proxy: ffmpeg restarted too many times, giving up');
      await stop();
      return;
    }
    _ffmpegRestarts++;
    AppLogger.info('HLS proxy: Restarting ffmpeg (attempt $_ffmpegRestarts)');
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (_stopping) return;
    await _startFfmpeg();
  }

  // ---------------------------------------------------------------------------
  // Upstream fetch (Dart owns the socket: TLS, redirects, reconnect)
  // ---------------------------------------------------------------------------

  Future<void> _fetchLoop(String url) async {
    _upstreamClient = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);

    while (!_stopping) {
      final ff = _ffmpeg;
      if (ff == null) {
        // ffmpeg is (re)starting — wait briefly and retry.
        await Future<void>.delayed(const Duration(milliseconds: 300));
        continue;
      }

      try {
        final request = await _upstreamClient!.getUrl(Uri.parse(url));
        request.followRedirects = true;
        request.maxRedirects = 5;
        request.headers.set(HttpHeaders.userAgentHeader, _userAgent);
        final response = await request.close();

        if (response.statusCode < 200 || response.statusCode >= 300) {
          AppLogger.error('HLS proxy: Upstream ${response.statusCode}');
          await response.drain<void>().catchError((_) {});
          await _backoff();
          continue;
        }

        AppLogger.info(
          'HLS proxy: Upstream connected (${response.statusCode})'
          '${_reconnects > 0 ? " [reconnect #$_reconnects]" : ""}',
        );

        // Pump the response into ffmpeg's stdin. addStream() honors
        // backpressure and — crucially — does NOT close the sink when the
        // response ends, so the same ffmpeg process survives reconnects.
        await ff.stdin.addStream(response);

        if (_stopping) break;
        AppLogger.warning('HLS proxy: Upstream ended — reconnecting');
        _reconnects++;
        await _backoff(short: true);
      } catch (e) {
        if (_stopping) break;
        AppLogger.error('HLS proxy: Upstream/pipe error — $e; reconnecting');
        _reconnects++;
        await _backoff();
      }
    }
  }

  Future<void> _backoff({bool short = false}) async {
    if (short) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      return;
    }
    final secs = (_reconnects.clamp(1, 5));
    await Future<void>.delayed(Duration(seconds: secs));
  }

  // ---------------------------------------------------------------------------
  // Readiness
  // ---------------------------------------------------------------------------

  Future<bool> _waitForManifest() async {
    final dir = _hlsDir;
    if (dir == null) return false;
    final manifest = File('${dir.path}/live.m3u8');
    final deadline = DateTime.now().add(_readyTimeout);

    while (DateTime.now().isBefore(deadline) && !_stopping) {
      if (await manifest.exists()) {
        try {
          final text = await manifest.readAsString();
          final segCount = _segmentRefPattern.allMatches(text).length;
          if (segCount >= 2) return true;
        } catch (_) {
          // manifest mid-write; retry
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    return false;
  }

  static final _segmentRefPattern = RegExp(r'seg_\d+\.ts');

  // ---------------------------------------------------------------------------
  // HTTP serving
  // ---------------------------------------------------------------------------

  void _addCorsHeaders(HttpResponse response) {
    response.headers
      ..set('Access-Control-Allow-Origin', '*')
      ..set('Access-Control-Allow-Methods', 'GET, OPTIONS')
      ..set('Access-Control-Allow-Headers',
          'Content-Type, Range, User-Agent, X-Requested-With, '
          'If-Modified-Since, Cache-Control')
      ..set('Access-Control-Expose-Headers', 'Content-Length, Content-Range');
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final path = request.uri.path;

    if (request.method == 'OPTIONS') {
      _addCorsHeaders(request.response);
      request.response
        ..statusCode = HttpStatus.noContent
        ..close();
      return;
    }

    final from = request.connectionInfo?.remoteAddress.address ?? '?';
    AppLogger.debug('HLS proxy: ${request.method} $path from $from');

    if (path == '/live.m3u8') {
      await _serveFile(
        request,
        'live.m3u8',
        ContentType('application', 'x-mpegurl'),
        cacheControl: 'no-cache, no-store',
      );
    } else if (_segmentPattern.hasMatch(path)) {
      await _serveFile(
        request,
        path.substring(1), // strip leading '/'
        ContentType('video', 'mp2t'),
        cacheControl: 'no-cache',
      );
    } else {
      request.response
        ..statusCode = HttpStatus.notFound
        ..close();
    }
  }

  Future<void> _serveFile(
    HttpRequest request,
    String name,
    ContentType contentType, {
    required String cacheControl,
  }) async {
    final dir = _hlsDir;
    if (dir == null) {
      request.response
        ..statusCode = HttpStatus.serviceUnavailable
        ..close();
      return;
    }

    final file = File('${dir.path}/$name');
    Uint8List bytes;
    try {
      if (!await file.exists()) {
        request.response
          ..statusCode = HttpStatus.notFound
          ..close();
        return;
      }
      bytes = await file.readAsBytes();
    } catch (_) {
      try {
        request.response
          ..statusCode = HttpStatus.notFound
          ..close();
      } catch (_) {}
      return;
    }

    try {
      _addCorsHeaders(request.response);
      request.response
        ..headers.contentType = contentType
        ..headers.set('Cache-Control', cacheControl)
        ..headers.contentLength = bytes.length
        ..add(bytes);
      await request.response.close();
    } catch (_) {
      // Receiver aborted the download — normal during channel switches.
    }
  }

  // ---------------------------------------------------------------------------
  // Network
  // ---------------------------------------------------------------------------

  Future<String?> _getWifiIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      );

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
