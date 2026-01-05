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

  void _init() {
    if (_initialized) return;
    _initialized = true;

    try {
      // Initialize with default options
      GoogleCastContext.instance.setSharedInstanceWithOptions(
        GoogleCastOptions(
          physicalVolumeButtonsWillControlDeviceVolume: true,
          disableDiscoveryAutostart: false,
        ),
      );

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
          final isConnected = session != null &&
              GoogleCastSessionManager.instance.connectionState ==
                  GoogleCastConnectState.connected;
          final device = session?.device;

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

          AppLogger.info(
              'Cast session: connected=$isConnected, device=${device?.friendlyName}',);
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

  /// Connect to a Cast device
  Future<bool> connect(CastDeviceInfo deviceInfo) async {
    try {
      final device = deviceInfo.device;
      if (device == null) {
        AppLogger.error('Cast: No device reference for ${deviceInfo.name}');
        return false;
      }

      AppLogger.info('Cast: Connecting to ${device.friendlyName}');
      final started = await GoogleCastSessionManager.instance
          .startSessionWithDevice(device);

      if (!started) {
        AppLogger.error('Cast: Failed to start session');
        return false;
      }

      // Wait for the connection to actually be established
      // The session stream will update _sessionState.isConnected
      AppLogger.info('Cast: Session started, waiting for connection...');

      // Wait up to 10 seconds for connection
      for (int i = 0; i < 100; i++) {
        await Future.delayed(const Duration(milliseconds: 100));
        if (_sessionState.isConnected) {
          AppLogger.info('Cast: Connected successfully');
          return true;
        }
      }

      AppLogger.error('Cast: Connection timeout');
      return false;
    } catch (e) {
      AppLogger.error('Cast: Connection failed - $e');
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
      // Determine content type based on URL
      final contentType = _detectContentType(media.url, media.contentType);

      AppLogger.info('Cast: Loading media:');
      AppLogger.info('  Title: ${media.title}');
      AppLogger.info('  URL: ${media.url}');
      AppLogger.info('  ContentType: $contentType');
      AppLogger.info('  Connected device: ${_sessionState.connectedDevice?.name}');

      final mediaInfo = GoogleCastMediaInformation(
        contentId: media.url,
        contentUrl: Uri.parse(media.url),
        contentType: contentType,
        streamType: CastMediaStreamType.live, // IPTV is typically live
        metadata: GoogleCastMovieMediaMetadata(
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
