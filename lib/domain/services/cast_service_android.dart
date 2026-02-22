// Android/iOS implementation using flutter_chrome_cast
import 'dart:async';
import 'dart:io';

import 'package:flutter_chrome_cast/flutter_chrome_cast.dart';

import '../../core/utils/logger.dart';

/// Cast device wrapper for UI display
class CastDeviceInfo {
  final String id;
  final String name;
  final String? modelName;
  final GoogleCastDevice? _device;

  CastDeviceInfo({
    required this.id,
    required this.name,
    this.modelName,
    GoogleCastDevice? device,
  }) : _device = device;

  GoogleCastDevice? get device => _device;

  /// Check if this device supports video (has a screen)
  /// Only excludes known audio-only devices, includes everything else
  bool get isVideoCapable {
    if (modelName == null) return true; // Allow if unknown
    final model = modelName!.toLowerCase();

    // Exclude known audio-only devices
    if (model.contains('google home')) return false;
    if (model.contains('nest mini')) return false;
    if (model.contains('nest audio')) return false;
    if (model.contains('home mini')) return false;
    if (model.contains('home max')) return false;

    // Include everything else
    return true;
  }
}

/// Cast media info for casting
class CastMediaInfo {
  final String url;
  final String title;
  final String? subtitle;
  final String? imageUrl;
  final String contentType;

  const CastMediaInfo({
    required this.url,
    required this.title,
    this.subtitle,
    this.imageUrl,
    this.contentType = 'video/mp4',
  });
}

/// Cast playback state
enum CastPlaybackState {
  idle,
  loading,
  buffering,
  playing,
  paused,
  stopped,
}

/// Cast session state
class CastSessionState {
  final bool isConnected;
  final CastDeviceInfo? connectedDevice;
  final CastPlaybackState playbackState;
  final Duration? currentPosition;
  final Duration? duration;
  final double volume;
  final bool isMuted;

  const CastSessionState({
    this.isConnected = false,
    this.connectedDevice,
    this.playbackState = CastPlaybackState.idle,
    this.currentPosition,
    this.duration,
    this.volume = 1.0,
    this.isMuted = false,
  });

  CastSessionState copyWith({
    bool? isConnected,
    CastDeviceInfo? connectedDevice,
    CastPlaybackState? playbackState,
    Duration? currentPosition,
    Duration? duration,
    double? volume,
    bool? isMuted,
    bool clearDevice = false,
  }) {
    return CastSessionState(
      isConnected: isConnected ?? this.isConnected,
      connectedDevice:
          clearDevice ? null : (connectedDevice ?? this.connectedDevice),
      playbackState: playbackState ?? this.playbackState,
      currentPosition: currentPosition ?? this.currentPosition,
      duration: duration ?? this.duration,
      volume: volume ?? this.volume,
      isMuted: isMuted ?? this.isMuted,
    );
  }
}

/// Android/iOS Chromecast service using flutter_chrome_cast
class CastService {
  static CastService? _instance;
  static CastService get instance => _instance ??= CastService._();

  CastService._() {
    _init();
  }

  bool _initialized = false;

  /// Casting is supported on Android and iOS
  static bool get isSupported => Platform.isAndroid || Platform.isIOS;

  // Discovery state
  final _devicesController = StreamController<List<CastDeviceInfo>>.broadcast();
  Stream<List<CastDeviceInfo>> get devicesStream => _devicesController.stream;
  List<CastDeviceInfo> _devices = [];
  List<CastDeviceInfo> get devices => _devices;

  // Session state
  final _sessionController = StreamController<CastSessionState>.broadcast();
  Stream<CastSessionState> get sessionStream => _sessionController.stream;
  CastSessionState _sessionState = const CastSessionState();
  CastSessionState get sessionState => _sessionState;

  StreamSubscription? _deviceSubscription;
  StreamSubscription? _sessionSubscription;
  StreamSubscription? _mediaStatusSubscription;
  StreamSubscription? _positionSubscription;

  Future<void> _init() async {
    if (_initialized) return;
    _initialized = true;

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

      // Listen to device discovery
      _deviceSubscription =
          GoogleCastDiscoveryManager.instance.devicesStream.listen(
        (devices) {
          // Map devices and filter to video-capable only
          final allDevices = devices
              .map((d) => CastDeviceInfo(
                    id: d.deviceID,
                    name: d.friendlyName,
                    modelName: d.modelName,
                    device: d,
                  ),)
              .toList();

          // Filter to only video-capable devices
          _devices = allDevices.where((d) => d.isVideoCapable).toList();
          _devicesController.add(_devices);

          AppLogger.info(
              'Cast: Found ${allDevices.length} devices, ${_devices.length} video-capable',);
          for (final d in allDevices) {
            AppLogger.info(
                'Cast device: ${d.name} (${d.modelName}) - video=${d.isVideoCapable}',);
          }
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
                    device: device,
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
            case CastMediaPlayerState.paused:
              playbackState = CastPlaybackState.paused;
            case CastMediaPlayerState.buffering:
              playbackState = CastPlaybackState.buffering;
            case CastMediaPlayerState.loading:
              playbackState = CastPlaybackState.loading;
            case CastMediaPlayerState.idle:
            case CastMediaPlayerState.unknown:
              playbackState = CastPlaybackState.idle;
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
    }
  }

  /// Start discovering Cast devices
  Future<void> startDiscovery() async {
    try {
      AppLogger.info('Cast: Starting discovery');
      await GoogleCastDiscoveryManager.instance.startDiscovery();
    } catch (e) {
      AppLogger.error('Cast: Discovery start failed - $e');
    }
  }

  /// Stop device discovery
  void stopDiscovery() {
    try {
      GoogleCastDiscoveryManager.instance.stopDiscovery();
      AppLogger.info('Cast: Discovery stopped');
    } catch (e) {
      AppLogger.error('Cast: Discovery stop failed - $e');
    }
  }

  /// Connect to a Cast device with automatic retry
  Future<bool> connect(CastDeviceInfo deviceInfo) async {
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
      final device = deviceInfo.device;
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

      // Wait for connection via session stream instead of polling
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

  /// Disconnect from current device
  Future<void> disconnect() async {
    try {
      await GoogleCastSessionManager.instance.endSessionAndStopCasting();
      _sessionState = const CastSessionState();
      _sessionController.add(_sessionState);
      AppLogger.info('Cast: Disconnected');
    } catch (e) {
      AppLogger.error('Cast: Disconnect failed - $e');
    }
  }

  /// Prepare a stream URL for Chromecast playback.
  /// Xtream Codes URLs serve raw MPEG-TS by default, but the Default Media
  /// Receiver needs an HLS manifest. Appending .m3u8 tells the server to
  /// return HLS format instead.
  /// Also downgrades HTTPS to HTTP for IPTV streams because many servers
  /// redirect HLS segments from HTTPS to plain HTTP (different IP), which
  /// causes mixed-content blocking in the Chromecast's Chrome-based receiver.
  String _prepareCastUrl(String url) {
    var castUrl = url;

    // Already has a streaming extension - skip format conversion
    final lowerUrl = castUrl.toLowerCase();
    final needsM3u8 = !lowerUrl.contains('.m3u8') &&
        !lowerUrl.contains('.mpd') &&
        !lowerUrl.endsWith('.mp4') &&
        !lowerUrl.endsWith('.ts');

    if (needsM3u8) {
      // Xtream Codes pattern: /username/password/stream_id
      final xtreamPattern = RegExp(r'/[^/]+/[^/]+/\d+$');
      if (xtreamPattern.hasMatch(castUrl) || RegExp(r'/\d+$').hasMatch(castUrl)) {
        AppLogger.info('Cast: Appending .m3u8 for HLS format');
        castUrl = '$castUrl.m3u8';
      }
    }

    // Downgrade HTTPS to HTTP for IPTV streams to avoid mixed-content issues.
    // IPTV servers often redirect HLS segment requests from HTTPS to HTTP
    // (different backend IP), which the Chromecast receiver blocks.
    if (castUrl.startsWith('https://')) {
      castUrl = castUrl.replaceFirst('https://', 'http://');
      AppLogger.info('Cast: Using HTTP to avoid mixed-content redirect issues');
    }

    return castUrl;
  }

  /// Detect content type from URL patterns
  /// IPTV streams are typically HLS, so we default to that for ambiguous URLs
  String _detectContentType(String url, String defaultType) {
    final lowerUrl = url.toLowerCase();

    // Explicit HLS indicators
    if (lowerUrl.contains('.m3u8') || lowerUrl.contains('m3u8')) {
      return 'application/x-mpegurl';
    }

    // Explicit DASH indicators
    if (lowerUrl.contains('.mpd')) {
      return 'application/dash+xml';
    }

    // Explicit video file extensions - use MP4
    if (lowerUrl.endsWith('.mp4') ||
        lowerUrl.endsWith('.mkv') ||
        lowerUrl.endsWith('.avi') ||
        lowerUrl.endsWith('.mov')) {
      return 'video/mp4';
    }

    // Xtream Codes URL pattern: server/username/password/stream_id
    // These typically end with a numeric ID and serve HLS by default
    final xtreamPattern = RegExp(r'/[^/]+/[^/]+/\d+$');
    if (xtreamPattern.hasMatch(url)) {
      AppLogger.info('Cast: Detected Xtream Codes URL pattern, using HLS');
      return 'application/x-mpegurl';
    }

    // URLs ending with just a number (common IPTV pattern) - default to HLS
    if (RegExp(r'/\d+$').hasMatch(url)) {
      AppLogger.info('Cast: URL ends with stream ID, defaulting to HLS');
      return 'application/x-mpegurl';
    }

    // For IPTV, HLS is far more common than MP4, so default to HLS
    // unless explicitly set otherwise
    if (defaultType == 'video/mp4') {
      AppLogger.info('Cast: IPTV stream, defaulting to HLS instead of MP4');
      return 'application/x-mpegurl';
    }

    return defaultType;
  }

  /// Cast media to connected device
  Future<bool> castMedia(CastMediaInfo media) async {
    if (!_sessionState.isConnected) {
      AppLogger.error('Cast: Not connected to any device');
      return false;
    }

    try {
      // Prepare the URL for Chromecast compatibility
      final castUrl = _prepareCastUrl(media.url);
      final contentType = _detectContentType(castUrl, media.contentType);

      AppLogger.info('Cast: Loading media:');
      AppLogger.info('  Title: ${media.title}');
      AppLogger.info('  Original URL: ${media.url}');
      AppLogger.info('  Cast URL: $castUrl');
      AppLogger.info('  ContentType: $contentType');
      AppLogger.info('  Connected device: ${_sessionState.connectedDevice?.name}');

      final mediaInfo = GoogleCastMediaInformation(
        contentId: castUrl,
        contentUrl: Uri.parse(castUrl),
        contentType: contentType,
        streamType: CastMediaStreamType.live, // IPTV is typically live
        // Use GenericMediaMetadata instead of MovieMediaMetadata because
        // MovieMediaMetadata.toMap() doesn't filter null values, causing a
        // kotlin.Long cast crash in the native code when releaseDate is null.
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

      AppLogger.info('Cast: Media load request sent successfully');
      return true;
    } catch (e, stackTrace) {
      AppLogger.error('Cast: Load media failed - $e');
      AppLogger.error('Cast: Stack trace - $stackTrace');
      return false;
    }
  }

  /// Play/resume playback
  Future<void> play() async {
    try {
      await GoogleCastRemoteMediaClient.instance.play();
    } catch (e) {
      AppLogger.error('Cast: Play failed - $e');
    }
  }

  /// Pause playback
  Future<void> pause() async {
    try {
      await GoogleCastRemoteMediaClient.instance.pause();
    } catch (e) {
      AppLogger.error('Cast: Pause failed - $e');
    }
  }

  /// Stop playback
  Future<void> stop() async {
    try {
      await GoogleCastRemoteMediaClient.instance.stop();
    } catch (e) {
      AppLogger.error('Cast: Stop failed - $e');
    }
  }

  /// Seek to position
  Future<void> seek(Duration position) async {
    try {
      await GoogleCastRemoteMediaClient.instance.seek(
        GoogleCastMediaSeekOption(position: position),
      );
    } catch (e) {
      AppLogger.error('Cast: Seek failed - $e');
    }
  }

  /// Set volume (0.0 to 1.0)
  Future<void> setVolume(double volume) async {
    try {
      GoogleCastSessionManager.instance.setDeviceVolume(volume);
    } catch (e) {
      AppLogger.error('Cast: Set volume failed - $e');
    }
  }

  /// Toggle mute
  Future<void> toggleMute() async {
    // Note: flutter_chrome_cast doesn't have a direct mute toggle
    // We'll implement it by setting volume to 0 or restoring
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

  /// Dispose of the service
  void dispose() {
    _deviceSubscription?.cancel();
    _sessionSubscription?.cancel();
    _mediaStatusSubscription?.cancel();
    _positionSubscription?.cancel();
    _devicesController.close();
    _sessionController.close();
  }
}
