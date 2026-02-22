// Android/iOS implementation using flutter_chrome_cast
import 'dart:async';
import 'dart:io';

import 'package:flutter_chrome_cast/flutter_chrome_cast.dart';

import '../../core/utils/logger.dart';
import 'cast_types.dart';

// Re-export shared types so consumers can import from this file
export 'cast_types.dart';

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

      // Listen to device discovery
      _deviceSubscription =
          GoogleCastDiscoveryManager.instance.devicesStream.listen(
        (devices) {
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
      await GoogleCastSessionManager.instance.endSessionAndStopCasting();
      _sessionState = const CastSessionState();
      _sessionController.add(_sessionState);
      AppLogger.info('Cast: Disconnected');
    } catch (e) {
      AppLogger.error('Cast: Disconnect failed - $e');
    }
  }

  /// Prepare a stream URL for Chromecast playback.
  String _prepareCastUrl(String url) {
    var castUrl = url;

    final lowerUrl = castUrl.toLowerCase();
    final needsM3u8 = !lowerUrl.contains('.m3u8') &&
        !lowerUrl.contains('.mpd') &&
        !lowerUrl.endsWith('.mp4') &&
        !lowerUrl.endsWith('.ts');

    if (needsM3u8) {
      if (_xtreamPattern.hasMatch(castUrl) || _streamIdPattern.hasMatch(castUrl)) {
        AppLogger.info('Cast: Appending .m3u8 for HLS format');
        castUrl = '$castUrl.m3u8';
      }
    }

    if (castUrl.startsWith('https://')) {
      castUrl = castUrl.replaceFirst('https://', 'http://');
      AppLogger.info('Cast: Using HTTP to avoid mixed-content redirect issues');
    }

    return castUrl;
  }

  /// Detect content type from URL patterns.
  String _detectContentType(String url, String defaultType) {
    final lowerUrl = url.toLowerCase();

    if (lowerUrl.contains('.m3u8') || lowerUrl.contains('m3u8')) {
      return 'application/x-mpegurl';
    }
    if (lowerUrl.contains('.mpd')) {
      return 'application/dash+xml';
    }
    if (lowerUrl.endsWith('.mp4') ||
        lowerUrl.endsWith('.mkv') ||
        lowerUrl.endsWith('.avi') ||
        lowerUrl.endsWith('.mov')) {
      return 'video/mp4';
    }
    if (_xtreamPattern.hasMatch(url)) {
      AppLogger.info('Cast: Detected Xtream Codes URL pattern, using HLS');
      return 'application/x-mpegurl';
    }
    if (_streamIdPattern.hasMatch(url)) {
      AppLogger.info('Cast: URL ends with stream ID, defaulting to HLS');
      return 'application/x-mpegurl';
    }
    if (defaultType == 'video/mp4') {
      AppLogger.info('Cast: IPTV stream, defaulting to HLS instead of MP4');
      return 'application/x-mpegurl';
    }

    return defaultType;
  }

  @override
  Future<bool> castMedia(CastMediaInfo media) async {
    await _initCompleter.future;
    if (!_sessionState.isConnected) {
      AppLogger.error('Cast: Not connected to any device');
      return false;
    }

    try {
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

      AppLogger.info('Cast: Media load request sent successfully');
      return true;
    } catch (e, stackTrace) {
      AppLogger.error('Cast: Load media failed - $e');
      AppLogger.error('Cast: Stack trace - $stackTrace');
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
    _deviceSubscription?.cancel();
    _sessionSubscription?.cancel();
    _mediaStatusSubscription?.cancel();
    _positionSubscription?.cancel();
    _devicesController.close();
    _sessionController.close();
  }
}
