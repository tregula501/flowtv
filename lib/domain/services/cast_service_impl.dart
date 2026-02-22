// Platform-specific implementation selector
// Uses Android/iOS implementation on mobile, stub on desktop

import 'dart:io';

import '../../core/utils/logger.dart';
import 'cast_types.dart';
import 'cast_service_android.dart' as android;
import 'cast_service_stub.dart' as stub;

// Re-export shared types for consumers
export 'cast_types.dart';

/// CastService factory that returns platform-specific implementation.
/// Both implementations use shared types from cast_types.dart,
/// so no type mapping or wrapper layer is needed.
class CastService implements ICastService {
  static CastService? _instance;

  static CastService get instance {
    if (_instance != null) return _instance!;

    if (Platform.isAndroid || Platform.isIOS) {
      _instance = _MobileCastService();
    } else {
      _instance = _DesktopCastService();
    }
    return _instance!;
  }

  /// Check if casting is supported on this platform
  static bool get isSupported => Platform.isAndroid || Platform.isIOS;

  @override
  Stream<List<CastDeviceInfo>> get devicesStream => throw UnimplementedError();
  @override
  List<CastDeviceInfo> get devices => throw UnimplementedError();
  @override
  Stream<CastSessionState> get sessionStream => throw UnimplementedError();
  @override
  CastSessionState get sessionState => throw UnimplementedError();
  @override
  Future<void> startDiscovery() async {}
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
  void dispose() {}
}

/// Direct delegation to Android CastService — no type mapping needed
class _MobileCastService extends CastService {
  final android.CastService _service = android.CastService.instance;

  @override
  Stream<List<CastDeviceInfo>> get devicesStream => _service.devicesStream;

  @override
  List<CastDeviceInfo> get devices => _service.devices;

  @override
  Stream<CastSessionState> get sessionStream => _service.sessionStream;

  @override
  CastSessionState get sessionState => _service.sessionState;

  @override
  Future<void> startDiscovery() => _service.startDiscovery();

  @override
  void stopDiscovery() => _service.stopDiscovery();

  @override
  Future<bool> connect(CastDeviceInfo device) async {
    // Find the matching device with native reference in the discovered list
    final devices = _service.devices;
    AppLogger.debug(
        'Cast connect: Looking for "${device.name}" in ${devices.length} devices',);

    CastDeviceInfo? matchedDevice;
    for (final d in devices) {
      if (d.id == device.id) {
        matchedDevice = d;
        break;
      }
    }

    if (matchedDevice == null) {
      AppLogger.debug('Cast connect: Device not found in discovered list');
      return false;
    }

    AppLogger.debug(
        'Cast connect: Found device, hasNativeRef=${matchedDevice.nativeDevice != null}',);
    return _service.connect(matchedDevice);
  }

  @override
  Future<void> disconnect() => _service.disconnect();

  @override
  Future<bool> castMedia(CastMediaInfo media) => _service.castMedia(media);

  @override
  Future<void> play() => _service.play();

  @override
  Future<void> pause() => _service.pause();

  @override
  Future<void> stop() => _service.stop();

  @override
  Future<void> seek(Duration position) => _service.seek(position);

  @override
  Future<void> setVolume(double volume) => _service.setVolume(volume);

  @override
  Future<void> toggleMute() => _service.toggleMute();

  @override
  void dispose() => _service.dispose();
}

/// Direct delegation to stub CastService
class _DesktopCastService extends CastService {
  final stub.CastService _service = stub.CastService.instance;

  @override
  Stream<List<CastDeviceInfo>> get devicesStream => _service.devicesStream;

  @override
  List<CastDeviceInfo> get devices => _service.devices;

  @override
  Stream<CastSessionState> get sessionStream => _service.sessionStream;

  @override
  CastSessionState get sessionState => _service.sessionState;

  @override
  Future<void> startDiscovery() => _service.startDiscovery();

  @override
  void stopDiscovery() => _service.stopDiscovery();

  @override
  Future<bool> connect(CastDeviceInfo device) => _service.connect(device);

  @override
  Future<void> disconnect() => _service.disconnect();

  @override
  Future<bool> castMedia(CastMediaInfo media) => _service.castMedia(media);

  @override
  Future<void> play() => _service.play();

  @override
  Future<void> pause() => _service.pause();

  @override
  Future<void> stop() => _service.stop();

  @override
  Future<void> seek(Duration position) => _service.seek(position);

  @override
  Future<void> setVolume(double volume) => _service.setVolume(volume);

  @override
  Future<void> toggleMute() => _service.toggleMute();

  @override
  void dispose() => _service.dispose();
}
