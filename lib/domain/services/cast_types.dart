/// Shared types for the Cast service, used by both Android and stub implementations.
library;

/// Cast device wrapper for UI display.
class CastDeviceInfo {
  final String id;
  final String name;
  final String? modelName;

  /// Native device reference (e.g., GoogleCastDevice on Android).
  /// Stored as dynamic to avoid platform-specific imports in shared code.
  final dynamic nativeDevice;

  CastDeviceInfo({
    required this.id,
    required this.name,
    this.modelName,
    this.nativeDevice,
  });

  /// Check if this device supports video (has a screen).
  /// Only excludes known audio-only devices, includes everything else.
  bool get isVideoCapable {
    if (modelName == null) return true;
    final model = modelName!.toLowerCase();
    if (model.contains('google home')) return false;
    if (model.contains('nest mini')) return false;
    if (model.contains('nest audio')) return false;
    if (model.contains('home mini')) return false;
    if (model.contains('home max')) return false;
    return true;
  }
}

/// Cast media info for casting.
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

/// Cast playback state.
enum CastPlaybackState {
  idle,
  loading,
  buffering,
  playing,
  paused,
  stopped,
}

/// Cast session state.
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

/// Abstract interface for Cast service implementations.
abstract class ICastService {
  Stream<List<CastDeviceInfo>> get devicesStream;
  List<CastDeviceInfo> get devices;
  Stream<CastSessionState> get sessionStream;
  CastSessionState get sessionState;
  static bool get isSupported => false;

  Future<void> startDiscovery();
  void stopDiscovery();
  Future<bool> connect(CastDeviceInfo device);
  Future<void> disconnect();
  Future<bool> castMedia(CastMediaInfo media);
  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<void> seek(Duration position);
  Future<void> setVolume(double volume);
  Future<void> toggleMute();
  void dispose();
}
