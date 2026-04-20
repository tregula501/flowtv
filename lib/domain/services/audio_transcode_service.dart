import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';

import '../../core/utils/logger.dart';

/// Platform channel wrapper for Android MediaCodec AC-3 → AAC transcoding.
/// Falls back gracefully on unsupported platforms/devices.
class AudioTranscodeService {
  static const _channel = MethodChannel(
    'io.github.tregula501.flowtv/audio_transcode',
  );

  static AudioTranscodeService? _instance;
  static AudioTranscodeService get instance =>
      _instance ??= AudioTranscodeService._();
  AudioTranscodeService._();

  bool _started = false;
  bool _supported = false;

  /// Whether AC-3 transcoding is available on this device.
  bool get isSupported => _supported;

  /// Whether the transcoder is currently running.
  bool get isStarted => _started;

  /// Check if AC-3 decoding is supported on this device.
  Future<bool> checkSupport() async {
    if (!Platform.isAndroid) {
      _supported = false;
      return false;
    }
    try {
      _supported = await _channel.invokeMethod<bool>('isSupported') ?? false;
      AppLogger.info('AudioTranscode: AC-3 supported = $_supported');
      return _supported;
    } catch (e) {
      AppLogger.error('AudioTranscode: checkSupport failed — $e');
      _supported = false;
      return false;
    }
  }

  /// Start the transcode pipeline. Returns false if not supported.
  Future<bool> start() async {
    if (!Platform.isAndroid) return false;
    try {
      _started = await _channel.invokeMethod<bool>('start') ?? false;
      AppLogger.info('AudioTranscode: started = $_started');
      return _started;
    } catch (e) {
      AppLogger.error('AudioTranscode: start failed — $e');
      _started = false;
      return false;
    }
  }

  /// Transcode AC-3 data to AAC ADTS frames.
  /// Returns a list of complete ADTS frames, or empty if no output.
  Future<List<Uint8List>> transcode(Uint8List ac3Data) async {
    if (!_started) return [];
    try {
      final result = await _channel.invokeMethod<List<dynamic>>(
        'transcode',
        {'data': ac3Data},
      );
      if (result == null) return [];
      return result
          .whereType<Uint8List>()
          .toList();
    } catch (e) {
      AppLogger.error('AudioTranscode: transcode failed — $e');
      return [];
    }
  }

  /// Stop the transcode pipeline and release resources.
  Future<void> stop() async {
    if (!_started) return;
    try {
      await _channel.invokeMethod<void>('stop');
    } catch (e) {
      AppLogger.error('AudioTranscode: stop failed — $e');
    }
    _started = false;
    AppLogger.info('AudioTranscode: stopped');
  }
}
