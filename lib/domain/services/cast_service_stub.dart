// Stub implementation for platforms that don't support casting (Windows, macOS, Linux)
// This provides the same interface but all methods are no-ops

import 'dart:async';

import '../../core/utils/logger.dart';

/// Cast device wrapper for UI display
class CastDeviceInfo {
  final String id;
  final String name;
  final String? modelName;

  CastDeviceInfo({
    required this.id,
    required this.name,
    this.modelName,
  });

  /// Check if this device supports video (has a screen)
  bool get isVideoCapable => true; // Stub always returns true
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

/// Stub Chromecast service - no-op on unsupported platforms
class CastService {
  static CastService? _instance;
  static CastService get instance => _instance ??= CastService._();

  CastService._();

  /// Casting is NOT supported on this platform
  static bool get isSupported => false;

  // Discovery state - always empty
  final _devicesController = StreamController<List<CastDeviceInfo>>.broadcast();
  Stream<List<CastDeviceInfo>> get devicesStream => _devicesController.stream;
  List<CastDeviceInfo> get devices => const [];

  // Session state - always disconnected
  final _sessionController = StreamController<CastSessionState>.broadcast();
  Stream<CastSessionState> get sessionStream => _sessionController.stream;
  CastSessionState get sessionState => const CastSessionState();

  /// No-op on unsupported platforms
  Future<void> startDiscovery() async {
    AppLogger.debug('Cast: Not supported on this platform');
  }

  /// No-op on unsupported platforms
  void stopDiscovery() {}

  /// Always returns false on unsupported platforms
  Future<bool> connect(CastDeviceInfo device) async => false;

  /// No-op on unsupported platforms
  Future<void> disconnect() async {}

  /// Always returns false on unsupported platforms
  Future<bool> castMedia(CastMediaInfo media) async => false;

  /// No-op on unsupported platforms
  Future<void> play() async {}

  /// No-op on unsupported platforms
  Future<void> pause() async {}

  /// No-op on unsupported platforms
  Future<void> stop() async {}

  /// No-op on unsupported platforms
  Future<void> seek(Duration position) async {}

  /// No-op on unsupported platforms
  Future<void> setVolume(double volume) async {}

  /// No-op on unsupported platforms
  Future<void> toggleMute() async {}

  /// Dispose of the service
  void dispose() {
    _devicesController.close();
    _sessionController.close();
  }
}
