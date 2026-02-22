// Stub implementation for platforms that don't support casting (Windows, macOS, Linux)
// This provides the same interface but all methods are no-ops

import 'dart:async';

import '../../core/utils/logger.dart';
import 'cast_types.dart';

// Re-export shared types so consumers can import from this file
export 'cast_types.dart';

/// Stub Chromecast service - no-op on unsupported platforms
class CastService implements ICastService {
  static CastService? _instance;
  static CastService get instance => _instance ??= CastService._();

  CastService._();

  /// Casting is NOT supported on this platform
  static bool get isSupported => false;

  // Discovery state - always empty
  final _devicesController = StreamController<List<CastDeviceInfo>>.broadcast();
  @override
  Stream<List<CastDeviceInfo>> get devicesStream => _devicesController.stream;
  @override
  List<CastDeviceInfo> get devices => const [];

  // Session state - always disconnected
  final _sessionController = StreamController<CastSessionState>.broadcast();
  @override
  Stream<CastSessionState> get sessionStream => _sessionController.stream;
  @override
  CastSessionState get sessionState => const CastSessionState();

  @override
  Future<void> startDiscovery() async {
    AppLogger.debug('Cast: Not supported on this platform');
  }

  @override
  void stopDiscovery() {}

  @override
  Future<bool> connect(CastDeviceInfo device) async => false;

  @override
  Future<void> disconnect() async {}

  @override
  Future<bool> castMedia(CastMediaInfo media) async => false;

  @override
  Future<void> play() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> toggleMute() async {}

  @override
  void dispose() {
    _devicesController.close();
    _sessionController.close();
  }
}
