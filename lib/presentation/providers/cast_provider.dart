import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/logger.dart';
import '../../domain/services/cast_service.dart';

/// Cast state for the provider
class CastState {
  final bool isSupported;
  final bool isDiscovering;
  final List<CastDeviceInfo> devices;
  final CastSessionState sessionState;

  const CastState({
    this.isSupported = false,
    this.isDiscovering = false,
    this.devices = const [],
    this.sessionState = const CastSessionState(),
  });

  bool get isConnected => sessionState.isConnected;
  CastDeviceInfo? get connectedDevice => sessionState.connectedDevice;
  CastPlaybackState get playbackState => sessionState.playbackState;

  CastState copyWith({
    bool? isSupported,
    bool? isDiscovering,
    List<CastDeviceInfo>? devices,
    CastSessionState? sessionState,
  }) {
    return CastState(
      isSupported: isSupported ?? this.isSupported,
      isDiscovering: isDiscovering ?? this.isDiscovering,
      devices: devices ?? this.devices,
      sessionState: sessionState ?? this.sessionState,
    );
  }
}

/// Cast controller notifier - Riverpod 3.x Notifier
class CastControllerNotifier extends Notifier<CastState> {
  StreamSubscription<List<CastDeviceInfo>>? _devicesSubscription;
  StreamSubscription<CastSessionState>? _sessionSubscription;

  @override
  CastState build() {
    // Clean up from any prior build() call (Notifier.build() re-runs on invalidation)
    _devicesSubscription?.cancel();
    _sessionSubscription?.cancel();

    // Check platform support
    final isSupported = CastService.isSupported;

    if (isSupported) {
      // Subscribe to device updates
      _devicesSubscription = CastService.instance.devicesStream.listen((devices) {
        state = state.copyWith(devices: devices);
      });

      // Subscribe to session updates
      _sessionSubscription = CastService.instance.sessionStream.listen((session) {
        state = state.copyWith(sessionState: session);
      });
    }

    // Register disposal callback
    ref.onDispose(() {
      _devicesSubscription?.cancel();
      _sessionSubscription?.cancel();
    });

    return CastState(isSupported: isSupported);
  }

  /// Start discovering Cast devices
  Future<void> startDiscovery() async {
    if (!state.isSupported || state.isDiscovering) return;

    state = state.copyWith(isDiscovering: true);

    try {
      await CastService.instance.startDiscovery();
    } finally {
      state = state.copyWith(isDiscovering: false);
    }
  }

  /// Stop device discovery
  void stopDiscovery() {
    if (!state.isSupported) return;
    CastService.instance.stopDiscovery();
    state = state.copyWith(isDiscovering: false);
  }

  /// Connect to a Cast device
  Future<bool> connect(CastDeviceInfo device) async {
    if (!state.isSupported) return false;
    return CastService.instance.connect(device);
  }

  /// Disconnect from current device
  Future<void> disconnect() async {
    if (!state.isSupported) return;
    await CastService.instance.disconnect();
  }

  /// Cast media to connected device
  Future<bool> castMedia({
    required String url,
    required String title,
    String? subtitle,
    String? imageUrl,
    String contentType = 'application/x-mpegurl',
  }) async {
    if (!state.isSupported || !state.isConnected) {
      AppLogger.error(
        'Cast: castMedia precondition failed — '
        'supported=${state.isSupported}, connected=${state.isConnected}',
      );
      return false;
    }

    return CastService.instance.castMedia(CastMediaInfo(
      url: url,
      title: title,
      subtitle: subtitle,
      imageUrl: imageUrl,
      contentType: contentType,
    ),);
  }

  /// Play/resume playback
  Future<void> play() async {
    if (!state.isSupported) return;
    await CastService.instance.play();
  }

  /// Pause playback
  Future<void> pause() async {
    if (!state.isSupported) return;
    await CastService.instance.pause();
  }

  /// Stop playback
  Future<void> stop() async {
    if (!state.isSupported) return;
    await CastService.instance.stop();
  }

  /// Seek to position
  Future<void> seek(Duration position) async {
    if (!state.isSupported) return;
    await CastService.instance.seek(position);
  }

  /// Set volume (0.0 to 1.0)
  Future<void> setVolume(double volume) async {
    if (!state.isSupported) return;
    await CastService.instance.setVolume(volume);
  }

  /// Toggle mute
  Future<void> toggleMute() async {
    if (!state.isSupported) return;
    await CastService.instance.toggleMute();
  }
}

/// Cast controller provider
final castControllerProvider =
    NotifierProvider<CastControllerNotifier, CastState>(
  CastControllerNotifier.new,
);

/// Convenience provider for checking if casting is supported
final castSupportedProvider = Provider<bool>((ref) {
  return ref.watch(castControllerProvider.select((s) => s.isSupported));
});

/// Convenience provider for checking if connected to a Cast device
final castConnectedProvider = Provider<bool>((ref) {
  return ref.watch(castControllerProvider.select((s) => s.isConnected));
});

/// Convenience provider for available Cast devices
final castDevicesProvider = Provider<List<CastDeviceInfo>>((ref) {
  return ref.watch(castControllerProvider.select((s) => s.devices));
});
