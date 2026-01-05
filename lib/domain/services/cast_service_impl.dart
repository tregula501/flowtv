// Platform-specific implementation selector
// Uses Android/iOS implementation on mobile, stub on desktop

import 'dart:io';

// Re-export shared types from stub (they're identical)
export 'cast_service_stub.dart'
    show CastDeviceInfo, CastMediaInfo, CastPlaybackState, CastSessionState;

// Import both implementations
import 'cast_service_stub.dart' as stub;
import 'cast_service_android.dart' as android;

/// CastService factory that returns platform-specific implementation
class CastService {
  static CastService? _instance;

  static CastService get instance {
    if (_instance != null) return _instance!;

    if (Platform.isAndroid || Platform.isIOS) {
      _instance = _AndroidCastServiceWrapper();
    } else {
      _instance = _StubCastServiceWrapper();
    }
    return _instance!;
  }

  /// Check if casting is supported on this platform
  static bool get isSupported => Platform.isAndroid || Platform.isIOS;

  // These methods will be overridden by the wrapper classes
  Stream<List<stub.CastDeviceInfo>> get devicesStream =>
      throw UnimplementedError();
  List<stub.CastDeviceInfo> get devices => throw UnimplementedError();
  Stream<stub.CastSessionState> get sessionStream => throw UnimplementedError();
  stub.CastSessionState get sessionState => throw UnimplementedError();

  Future<void> startDiscovery() async {}
  void stopDiscovery() {}
  Future<bool> connect(stub.CastDeviceInfo device) async => false;
  Future<void> disconnect() async {}
  Future<bool> castMedia(stub.CastMediaInfo media) async => false;
  Future<void> play() async {}
  Future<void> pause() async {}
  Future<void> stop() async {}
  Future<void> seek(Duration position) async {}
  Future<void> setVolume(double volume) async {}
  Future<void> toggleMute() async {}
  void dispose() {}
}

/// Wrapper for Android implementation
class _AndroidCastServiceWrapper extends CastService {
  final android.CastService _service = android.CastService.instance;

  @override
  Stream<List<stub.CastDeviceInfo>> get devicesStream =>
      _service.devicesStream.map((devices) => devices
          .map((d) => stub.CastDeviceInfo(id: d.id, name: d.name, modelName: d.modelName),)
          .toList(),);

  @override
  List<stub.CastDeviceInfo> get devices =>
      _service.devices.map((d) => stub.CastDeviceInfo(id: d.id, name: d.name, modelName: d.modelName)).toList();

  @override
  Stream<stub.CastSessionState> get sessionStream =>
      _service.sessionStream.map((s) => stub.CastSessionState(
            isConnected: s.isConnected,
            connectedDevice: s.connectedDevice != null
                ? stub.CastDeviceInfo(
                    id: s.connectedDevice!.id,
                    name: s.connectedDevice!.name,
                    modelName: s.connectedDevice!.modelName,
                  )
                : null,
            playbackState: _mapPlaybackState(s.playbackState),
            currentPosition: s.currentPosition,
            duration: s.duration,
            volume: s.volume,
            isMuted: s.isMuted,
          ),);

  @override
  stub.CastSessionState get sessionState {
    final s = _service.sessionState;
    return stub.CastSessionState(
      isConnected: s.isConnected,
      connectedDevice: s.connectedDevice != null
          ? stub.CastDeviceInfo(
              id: s.connectedDevice!.id,
              name: s.connectedDevice!.name,
              modelName: s.connectedDevice!.modelName,
            )
          : null,
      playbackState: _mapPlaybackState(s.playbackState),
      currentPosition: s.currentPosition,
      duration: s.duration,
      volume: s.volume,
      isMuted: s.isMuted,
    );
  }

  stub.CastPlaybackState _mapPlaybackState(android.CastPlaybackState state) {
    switch (state) {
      case android.CastPlaybackState.idle:
        return stub.CastPlaybackState.idle;
      case android.CastPlaybackState.loading:
        return stub.CastPlaybackState.loading;
      case android.CastPlaybackState.buffering:
        return stub.CastPlaybackState.buffering;
      case android.CastPlaybackState.playing:
        return stub.CastPlaybackState.playing;
      case android.CastPlaybackState.paused:
        return stub.CastPlaybackState.paused;
      case android.CastPlaybackState.stopped:
        return stub.CastPlaybackState.stopped;
    }
  }

  @override
  Future<void> startDiscovery() => _service.startDiscovery();

  @override
  void stopDiscovery() => _service.stopDiscovery();

  @override
  Future<bool> connect(stub.CastDeviceInfo device) async {
    // Find the matching Android device with the GoogleCastDevice reference
    final devices = _service.devices;

    print('Cast connect: Looking for device "${device.name}" (id=${device.id})');
    print('Cast connect: Available devices count: ${devices.length}');

    android.CastDeviceInfo? androidDevice;

    for (final d in devices) {
      print('Cast connect: Checking device "${d.name}" (id=${d.id}) hasRef=${d.device != null}');
      if (d.id == device.id) {
        androidDevice = d;
        print('Cast connect: Found matching device!');
        break;
      }
    }

    if (androidDevice == null) {
      // Device not found in current list - this can happen if discovery
      // stopped or the device went away. Log for debugging.
      print('Cast connect: ERROR - Device not found in discovered list');
      return false;
    }

    print('Cast connect: Proceeding to connect with device ref=${androidDevice.device != null}');
    return _service.connect(androidDevice);
  }

  @override
  Future<void> disconnect() => _service.disconnect();

  @override
  Future<bool> castMedia(stub.CastMediaInfo media) {
    return _service.castMedia(android.CastMediaInfo(
      url: media.url,
      title: media.title,
      subtitle: media.subtitle,
      imageUrl: media.imageUrl,
      contentType: media.contentType,
    ),);
  }

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

/// Wrapper for stub implementation (desktop platforms)
class _StubCastServiceWrapper extends CastService {
  final stub.CastService _service = stub.CastService.instance;

  @override
  Stream<List<stub.CastDeviceInfo>> get devicesStream => _service.devicesStream;

  @override
  List<stub.CastDeviceInfo> get devices => _service.devices;

  @override
  Stream<stub.CastSessionState> get sessionStream => _service.sessionStream;

  @override
  stub.CastSessionState get sessionState => _service.sessionState;

  @override
  Future<void> startDiscovery() => _service.startDiscovery();

  @override
  void stopDiscovery() => _service.stopDiscovery();

  @override
  Future<bool> connect(stub.CastDeviceInfo device) => _service.connect(device);

  @override
  Future<void> disconnect() => _service.disconnect();

  @override
  Future<bool> castMedia(stub.CastMediaInfo media) => _service.castMedia(media);

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
