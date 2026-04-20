// Android/iOS implementation using flutter_chrome_cast
import 'dart:async';
import 'dart:io';

import 'package:flutter_chrome_cast/flutter_chrome_cast.dart';

import '../../core/utils/logger.dart';
import 'cast_types.dart';
import 'hls_proxy_service.dart';

// Re-export shared types so consumers can import from this file
export 'cast_types.dart';

/// Result of probing a stream URL to determine its type.
class _StreamProbe {
  final String url;
  final String contentType;
  const _StreamProbe(this.url, this.contentType);
}

/// Android/iOS Chromecast service using flutter_chrome_cast
class CastService implements ICastService {
  static CastService? _syncInstance;
  static CastService get instance => _syncInstance ??= CastService._();

  CastService._() {
    _init();
  }

  final Completer<void> _initCompleter = Completer<void>();

  /// Casting is supported on Android and iOS
  static bool get isSupported => Platform.isAndroid || Platform.isIOS;

  // URL pattern constants — compiled once, reused
  static final _xtreamPattern = RegExp(r'/[^/]+/[^/]+/\d+$');
  static final _streamIdPattern = RegExp(r'/\d+$');

  // Discovery state
  final _devicesController = StreamController<List<CastDeviceInfo>>.broadcast();
  @override
  Stream<List<CastDeviceInfo>> get devicesStream => _devicesController.stream;
  List<CastDeviceInfo> _devices = [];
  @override
  List<CastDeviceInfo> get devices => _devices;
  Timer? _discoveryDebounce;
  Set<String> _lastDeviceKeys = {};

  // Auto-retry state for stream errors
  CastMediaInfo? _lastMedia;
  int _retryCount = 0;
  static const _maxRetries = 3;
  Timer? _retryTimer;
  bool _hasEverPlayed = false; // Guard: only auto-retry after playback started

  // Session state
  final _sessionController = StreamController<CastSessionState>.broadcast();
  @override
  Stream<CastSessionState> get sessionStream => _sessionController.stream;
  CastSessionState _sessionState = const CastSessionState();
  @override
  CastSessionState get sessionState => _sessionState;

  StreamSubscription? _deviceSubscription;
  StreamSubscription? _sessionSubscription;
  StreamSubscription? _mediaStatusSubscription;
  StreamSubscription? _positionSubscription;

  Future<void> _init() async {
    try {
      // Initialize with the Default Media Receiver app ID
      // The base GoogleCastOptions class does NOT include appId in toMap(),
      // which causes a TypeCastException in the native Kotlin code.
      // GoogleCastOptionsAndroid includes appId and is required for sessions to work.
      final initResult =
          await GoogleCastContext.instance.setSharedInstanceWithOptions(
        GoogleCastOptionsAndroid(
          appId: GoogleCastDiscoveryCriteria.kDefaultApplicationId,
        ),
      );
      AppLogger.info('Cast: Context initialized, result=$initResult');

      // Listen to device discovery (debounced to avoid noisy repeated callbacks)
      _deviceSubscription =
          GoogleCastDiscoveryManager.instance.devicesStream.listen(
        (devices) {
          _discoveryDebounce?.cancel();
          _discoveryDebounce = Timer(const Duration(milliseconds: 300), () {
            final allDevices = devices
                .map((d) => CastDeviceInfo(
                      id: d.deviceID,
                      name: d.friendlyName,
                      modelName: d.modelName,
                      nativeDevice: d,
                    ),)
                .toList();

            _devices = allDevices.where((d) => d.isVideoCapable).toList();
            _devicesController.add(_devices);

            // Only log when device list actually changes
            final currentKeys = allDevices.map((d) => '${d.name}_${d.modelName}').toSet();
            if (currentKeys.length != _lastDeviceKeys.length ||
                !currentKeys.containsAll(_lastDeviceKeys)) {
              _lastDeviceKeys = currentKeys;
              AppLogger.info(
                  'Cast: Found ${allDevices.length} devices, ${_devices.length} video-capable',);
              for (final d in allDevices) {
                AppLogger.info(
                    'Cast device: ${d.name} (${d.modelName}) - video=${d.isVideoCapable}',);
              }
            }
          });
        },
        onError: (e) {
          AppLogger.error('Cast discovery error: $e');
        },
      );

      // Listen to session state changes
      _sessionSubscription =
          GoogleCastSessionManager.instance.currentSessionStream.listen(
        (session) {
          final connectionState =
              GoogleCastSessionManager.instance.connectionState;
          final isConnected = session != null &&
              connectionState == GoogleCastConnectState.connected;
          final device = session?.device;

          AppLogger.info(
            'Cast session event: session=${session != null}, '
            'connectionState=$connectionState, '
            'isConnected=$isConnected, '
            'device=${device?.friendlyName}, '
            'sessionId=${session?.sessionID}',
          );

          _sessionState = _sessionState.copyWith(
            isConnected: isConnected,
            connectedDevice: device != null
                ? CastDeviceInfo(
                    id: device.deviceID,
                    name: device.friendlyName,
                    modelName: device.modelName,
                    nativeDevice: device,
                  )
                : null,
            clearDevice: device == null,
          );
          _sessionController.add(_sessionState);
        },
        onError: (e) {
          AppLogger.error('Cast session error: $e');
        },
      );

      // Listen to media status changes
      _mediaStatusSubscription =
          GoogleCastRemoteMediaClient.instance.mediaStatusStream.listen(
        (status) {
          if (status == null) return;

          CastPlaybackState playbackState;
          switch (status.playerState) {
            case CastMediaPlayerState.playing:
              playbackState = CastPlaybackState.playing;
              // Stream is playing — reset retry counter and mark as started
              _retryCount = 0;
              _hasEverPlayed = true;
            case CastMediaPlayerState.paused:
              playbackState = CastPlaybackState.paused;
            case CastMediaPlayerState.buffering:
              playbackState = CastPlaybackState.buffering;
            case CastMediaPlayerState.loading:
              playbackState = CastPlaybackState.loading;
            case CastMediaPlayerState.idle:
            case CastMediaPlayerState.unknown:
              playbackState = CastPlaybackState.idle;
              AppLogger.info(
                'Cast: Idle state — idleReason=${status.idleReason}, '
                'hasEverPlayed=$_hasEverPlayed, '
                'lastMedia=${_lastMedia?.title}, '
                'retryCount=$_retryCount',
              );
              // Auto-retry on stream error, but only if playback previously
              // started. Without this guard, the initial idle→loading
              // transition can trigger spurious retries that exhaust attempts
              // before the stream has a chance to play.
              if (status.idleReason == GoogleCastMediaIdleReason.error &&
                  _lastMedia != null &&
                  _sessionState.isConnected &&
                  _hasEverPlayed) {
                _scheduleRetry();
              }
          }

          _sessionState = _sessionState.copyWith(
            playbackState: playbackState,
            duration: status.mediaInformation?.duration,
            volume: status.volume.toDouble(),
            isMuted: status.isMuted,
          );
          _sessionController.add(_sessionState);
        },
        onError: (e) {
          AppLogger.error('Cast media status error: $e');
        },
      );

      // Listen to player position changes
      _positionSubscription =
          GoogleCastRemoteMediaClient.instance.playerPositionStream.listen(
        (position) {
          _sessionState = _sessionState.copyWith(currentPosition: position);
          _sessionController.add(_sessionState);
        },
        onError: (e) {
          AppLogger.error('Cast position error: $e');
        },
      );

      AppLogger.info('Cast: Service initialized');
    } catch (e) {
      AppLogger.error('Cast: Failed to initialize - $e');
      // Clean up any subscriptions created before the error
      _deviceSubscription?.cancel();
      _sessionSubscription?.cancel();
      _mediaStatusSubscription?.cancel();
      _positionSubscription?.cancel();
    } finally {
      _initCompleter.complete();
    }
  }

  @override
  Future<void> startDiscovery() async {
    await _initCompleter.future;
    try {
      AppLogger.info('Cast: Starting discovery');
      await GoogleCastDiscoveryManager.instance.startDiscovery();
    } catch (e) {
      AppLogger.error('Cast: Discovery start failed - $e');
    }
  }

  @override
  void stopDiscovery() {
    try {
      GoogleCastDiscoveryManager.instance.stopDiscovery();
      AppLogger.info('Cast: Discovery stopped');
    } catch (e) {
      AppLogger.error('Cast: Discovery stop failed - $e');
    }
  }

  /// Connect to a Cast device with automatic retry
  @override
  Future<bool> connect(CastDeviceInfo deviceInfo) async {
    await _initCompleter.future;
    for (int attempt = 1; attempt <= 2; attempt++) {
      final result = await _tryConnect(deviceInfo, attempt);
      if (result) return true;
      if (attempt < 2) {
        AppLogger.info('Cast: Retrying connection (attempt ${attempt + 1})...');
        await Future.delayed(const Duration(seconds: 1));
      }
    }
    return false;
  }

  Future<bool> _tryConnect(CastDeviceInfo deviceInfo, int attempt) async {
    try {
      final device = deviceInfo.nativeDevice as GoogleCastDevice?;
      if (device == null) {
        AppLogger.error('Cast: No device reference for ${deviceInfo.name}');
        return false;
      }

      AppLogger.info(
          'Cast: Connecting to ${device.friendlyName} (attempt $attempt)',);
      AppLogger.info(
          'Cast: connectionState before start: '
          '${GoogleCastSessionManager.instance.connectionState}');

      final started = await GoogleCastSessionManager.instance
          .startSessionWithDevice(device);

      AppLogger.info('Cast: startSessionWithDevice returned: $started');
      AppLogger.info(
          'Cast: connectionState after start: '
          '${GoogleCastSessionManager.instance.connectionState}');

      if (!started) {
        AppLogger.error('Cast: Failed to start session (attempt $attempt)');
        return false;
      }

      AppLogger.info('Cast: Session started, waiting for connection...');

      try {
        await sessionStream
            .where((state) => state.isConnected)
            .first
            .timeout(const Duration(seconds: 15));
        AppLogger.info('Cast: Connected successfully');
        return true;
      } on TimeoutException {
        AppLogger.error('Cast: Connection timeout (attempt $attempt)');
        return false;
      }
    } catch (e) {
      AppLogger.error('Cast: Connection failed (attempt $attempt) - $e');
      return false;
    }
  }

  @override
  Future<void> disconnect() async {
    try {
      _retryTimer?.cancel();
      _lastMedia = null;
      _retryCount = 0;
      _hasEverPlayed = false;
      await HlsProxyService.instance.stop();
      await GoogleCastSessionManager.instance.endSessionAndStopCasting();
      _sessionState = const CastSessionState();
      _sessionController.add(_sessionState);
      AppLogger.info('Cast: Disconnected');
    } catch (e) {
      AppLogger.error('Cast: Disconnect failed - $e');
    }
  }

  /// Detect content type from a URL's extension (no network).
  String? _contentTypeFromUrl(String url) {
    final lower = url.toLowerCase();
    if (lower.contains('.m3u8')) return 'application/x-mpegurl';
    if (lower.contains('.mpd')) return 'application/dash+xml';
    if (lower.endsWith('.mp4') || lower.endsWith('.mov')) return 'video/mp4';
    if (lower.endsWith('.ts')) return 'video/mp2t';
    return null;
  }

  /// Map an HTTP Content-Type header to a Cast-friendly MIME type.
  String? _contentTypeFromHeader(String? header) {
    if (header == null) return null;
    final lower = header.toLowerCase();
    if (lower.contains('mpegurl') || lower.contains('x-mpegurl')) {
      return 'application/x-mpegurl';
    }
    if (lower.contains('dash') || lower.contains('mpd')) {
      return 'application/dash+xml';
    }
    if (lower.contains('mp2t') || lower.contains('mpeg')) {
      return 'video/mp2t';
    }
    if (lower.contains('mp4')) return 'video/mp4';
    if (lower.contains('octet-stream')) return null; // ambiguous
    if (lower.contains('video/')) return lower.split(';').first.trim();
    return null;
  }

  /// Probe a URL with a HEAD request, returning the HTTP status and
  /// Content-Type header. Returns null on network error.
  Future<(int, String?)?> _headProbe(String url) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client.headUrl(Uri.parse(url));
      request.followRedirects = true;
      final response = await request.close().timeout(
            const Duration(seconds: 5),
          );
      await response.drain<void>();
      return (response.statusCode, response.headers.contentType?.toString());
    } catch (e) {
      AppLogger.info('Cast: HEAD probe failed for ${AppLogger.redactUrl(url)}: $e');
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// Determine stream URL and content type using heuristic detection only.
  /// No HEAD probes — they waste the IPTV server's single connection slot.
  _StreamProbe _detectStreamType(String url, String fallbackType) {
    // If the URL already has a known media extension, use it as-is.
    final knownType = _contentTypeFromUrl(url);
    if (knownType != null) {
      AppLogger.info('Cast: URL has known extension, type=$knownType');
      return _StreamProbe(url, knownType);
    }

    // Bare Xtream/stream-ID URLs are almost always MPEG-TS.
    // The HLS proxy will handle repackaging for Chromecast.
    if (_xtreamPattern.hasMatch(url) || _streamIdPattern.hasMatch(url)) {
      AppLogger.info('Cast: Detected stream ID URL, assuming video/mp2t');
      return _StreamProbe(url, 'video/mp2t');
    }

    AppLogger.info('Cast: Using fallback type=$fallbackType');
    return _StreamProbe(url, fallbackType);
  }

  /// Schedule an auto-retry after a stream error.
  /// Guards against duplicate callbacks from the native Cast SDK,
  /// which fires idleReason:ERROR twice in rapid succession.
  void _scheduleRetry() {
    // Already have a retry scheduled — ignore duplicate callback
    if (_retryTimer?.isActive ?? false) return;

    if (_retryCount >= _maxRetries) {
      AppLogger.error(
        'Cast: Stream error — max retries ($_maxRetries) reached, giving up',
      );
      _lastMedia = null;
      _retryCount = 0;
      return;
    }

    _retryCount++;
    final delay = Duration(seconds: 2 * _retryCount); // 2s, 4s, 6s backoff
    AppLogger.info(
      'Cast: Stream error — retrying in ${delay.inSeconds}s '
      '(attempt $_retryCount/$_maxRetries)',
    );

    _retryTimer = Timer(delay, () async {
      final media = _lastMedia;
      if (media == null || !_sessionState.isConnected) return;
      AppLogger.info('Cast: Auto-retrying "${media.title}"...');
      await castMedia(media);
    });
  }

  @override
  Future<bool> castMedia(CastMediaInfo media) async {
    await _initCompleter.future;
    if (!_sessionState.isConnected) {
      AppLogger.error('Cast: Not connected to any device');
      return false;
    }

    // Cancel any pending retry for previous media
    _retryTimer?.cancel();
    _hasEverPlayed = false; // Reset — must reach playing state before retries

    try {
      final probe = _detectStreamType(media.url, media.contentType);
      var castUrl = probe.url;
      var contentType = probe.contentType;

      // If the stream is MPEG-TS, Chromecast can't play it directly.
      // Start a local HLS proxy that repackages the TS into HLS segments.
      if (contentType == 'video/mp2t') {
        AppLogger.info('Cast: TS stream detected — starting HLS proxy');
        final hlsUrl = await HlsProxyService.instance.start(castUrl);
        if (hlsUrl != null) {
          castUrl = hlsUrl;
          contentType = 'application/x-mpegurl';
          AppLogger.info('Cast: Using local HLS proxy: $castUrl');
        } else {
          AppLogger.error('Cast: HLS proxy failed to start, trying raw URL');
        }
      } else {
        // Not using the proxy — make sure it's stopped
        if (HlsProxyService.instance.isRunning) {
          await HlsProxyService.instance.stop();
        }
      }

      AppLogger.info('Cast: Loading media:');
      AppLogger.info('  Title: ${media.title}');
      AppLogger.info('  Original URL: ${AppLogger.redactUrl(media.url)}');
      AppLogger.info('  Cast URL: ${AppLogger.redactUrl(castUrl)}');
      AppLogger.info('  ContentType: $contentType');
      AppLogger.info('  Connected device: ${_sessionState.connectedDevice?.name}');

      final mediaInfo = GoogleCastMediaInformation(
        contentId: castUrl,
        contentUrl: Uri.parse(castUrl),
        contentType: contentType,
        streamType: CastMediaStreamType.live,
        metadata: GoogleCastGenericMediaMetadata(
          title: media.title,
          subtitle: media.subtitle,
          images: media.imageUrl != null
              ? [GoogleCastImage(url: Uri.parse(media.imageUrl!))]
              : null,
        ),
      );

      AppLogger.info('Cast: Calling loadMedia...');
      await GoogleCastRemoteMediaClient.instance.loadMedia(
        mediaInfo,
        autoPlay: true,
      );

      // Store for auto-retry only after successful load request
      _lastMedia = media;
      _retryCount = 0;

      AppLogger.info('Cast: Media load request sent successfully');
      return true;
    } catch (e, stackTrace) {
      AppLogger.error('Cast: Load media failed - $e');
      AppLogger.error('Cast: Stack trace - $stackTrace');
      _lastMedia = null;
      return false;
    }
  }

  @override
  Future<void> play() async {
    try {
      await GoogleCastRemoteMediaClient.instance.play();
    } catch (e) {
      AppLogger.error('Cast: Play failed - $e');
    }
  }

  @override
  Future<void> pause() async {
    try {
      await GoogleCastRemoteMediaClient.instance.pause();
    } catch (e) {
      AppLogger.error('Cast: Pause failed - $e');
    }
  }

  @override
  Future<void> stop() async {
    try {
      await GoogleCastRemoteMediaClient.instance.stop();
    } catch (e) {
      AppLogger.error('Cast: Stop failed - $e');
    }
  }

  @override
  Future<void> seek(Duration position) async {
    try {
      await GoogleCastRemoteMediaClient.instance.seek(
        GoogleCastMediaSeekOption(position: position),
      );
    } catch (e) {
      AppLogger.error('Cast: Seek failed - $e');
    }
  }

  @override
  Future<void> setVolume(double volume) async {
    try {
      GoogleCastSessionManager.instance.setDeviceVolume(volume);
    } catch (e) {
      AppLogger.error('Cast: Set volume failed - $e');
    }
  }

  @override
  Future<void> toggleMute() async {
    try {
      if (_sessionState.isMuted) {
        await setVolume(_sessionState.volume > 0 ? _sessionState.volume : 1.0);
      } else {
        await setVolume(0.0);
      }
    } catch (e) {
      AppLogger.error('Cast: Toggle mute failed - $e');
    }
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    _lastMedia = null;
    _retryCount = 0;
    _hasEverPlayed = false;
    HlsProxyService.instance.stop();
    _discoveryDebounce?.cancel();
    _deviceSubscription?.cancel();
    _sessionSubscription?.cancel();
    _mediaStatusSubscription?.cancel();
    _positionSubscription?.cancel();
    _devicesController.close();
    _sessionController.close();
    _syncInstance = null;
  }
}
