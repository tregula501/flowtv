import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/services.dart';

import '../../core/utils/logger.dart';

/// Isolate-based AC-3 → AAC transcoding using Android MediaCodec.
///
/// Runs the platform channel calls on a background isolate so the main
/// isolate's event loop (HTTP serving, TS packet processing) is never blocked.
///
/// Usage:
///   1. `checkSupport()` — verify device has AC-3 decoder (main isolate, fast)
///   2. `start()` — spawn background isolate, initialize MediaCodec pipeline
///   3. `transcode(ac3Data)` — fire-and-forget send to background isolate
///   4. AAC frames arrive via `onAacFrames` callback asynchronously
///   5. `stop()` — tear down isolate and release MediaCodec resources
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

  Isolate? _isolate;
  SendPort? _bgSendPort;
  ReceivePort? _mainReceivePort;

  /// Callback invoked on the main isolate when AAC frames are ready.
  /// The HLS proxy wires this up to collect frames for segment building.
  void Function(List<Uint8List> aacFrames)? onAacFrames;

  /// Whether AC-3 transcoding is available on this device.
  bool get isSupported => _supported;

  /// Whether the transcoder isolate is running.
  bool get isStarted => _started;

  /// Check if AC-3 decoding is supported on this device.
  /// This is a lightweight call that runs on the main isolate.
  Future<bool> checkSupport() async {
    if (!_isAndroid) {
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

  /// Start the transcoding pipeline on a background isolate.
  Future<bool> start() async {
    if (!_isAndroid || !_supported) return false;
    if (_started) return true;

    try {
      final rootToken = RootIsolateToken.instance;
      if (rootToken == null) {
        AppLogger.error('AudioTranscode: No RootIsolateToken available');
        return false;
      }

      _mainReceivePort = ReceivePort();
      final setupMsg = _IsolateSetup(
        rootIsolateToken: rootToken,
        mainSendPort: _mainReceivePort!.sendPort,
      );

      _isolate = await Isolate.spawn(_backgroundEntry, setupMsg);

      // Wait for handshake (background sends its SendPort)
      final handshakeCompleter = Completer<bool>();

      _mainReceivePort!.listen((message) {
        if (message is SendPort) {
          _bgSendPort = message;
          // Send start command
          _bgSendPort!.send('start');
        } else if (message is Map) {
          final type = message['type'] as String?;
          if (type == 'started') {
            final success = message['success'] as bool? ?? false;
            _started = success;
            if (!handshakeCompleter.isCompleted) {
              handshakeCompleter.complete(success);
            }
            if (success) {
              AppLogger.info('AudioTranscode: Background isolate started');
            } else {
              AppLogger.error('AudioTranscode: Background isolate failed to start pipeline');
            }
          } else if (type == 'aac') {
            final frames = message['frames'] as List<Uint8List>?;
            if (frames != null && frames.isNotEmpty) {
              onAacFrames?.call(frames);
            }
          } else if (type == 'error') {
            AppLogger.error('AudioTranscode: Background error — ${message['message']}');
          } else if (type == 'stopped') {
            _started = false;
          }
        }
      });

      // Wait up to 5 seconds for the pipeline to start
      final success = await handshakeCompleter.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          AppLogger.error('AudioTranscode: Timeout waiting for background isolate');
          return false;
        },
      );

      if (!success) {
        await _cleanup();
      }
      return success;
    } catch (e) {
      AppLogger.error('AudioTranscode: start failed — $e');
      await _cleanup();
      return false;
    }
  }

  /// Send AC-3 data to the background isolate for transcoding.
  /// This is fire-and-forget — results arrive via [onAacFrames] callback.
  void transcode(Uint8List ac3Data) {
    if (!_started || _bgSendPort == null) return;
    _bgSendPort!.send(ac3Data);
  }

  /// Transcode AC-3 data and WAIT for all results (up to timeout).
  /// Sends the entire buffer in one call and collects all AAC frames.
  /// Used at segment boundaries to get complete audio for the segment.
  Future<List<Uint8List>> transcodeAndWait(
    Uint8List ac3Data, {
    Duration timeout = const Duration(seconds: 3),
  }) async {
    if (!_started || _bgSendPort == null) return [];

    final frames = <Uint8List>[];
    final completer = Completer<List<Uint8List>>();

    // Temporarily capture frames from this specific call
    final originalCallback = onAacFrames;
    onAacFrames = (aacFrames) {
      frames.addAll(aacFrames);
      // Complete after receiving frames (background sends one batch per call)
      if (!completer.isCompleted) {
        completer.complete(frames);
      }
    };

    _bgSendPort!.send(ac3Data);

    try {
      final result = await completer.future.timeout(timeout, onTimeout: () => frames);
      return result;
    } finally {
      onAacFrames = originalCallback;
    }
  }

  /// Stop the transcoding pipeline and tear down the background isolate.
  Future<void> stop() async {
    if (!_started && _isolate == null) return;

    try {
      if (_bgSendPort != null) {
        _bgSendPort!.send('stop');
        // Give it a moment to clean up
        await Future.delayed(const Duration(milliseconds: 200));
      }
    } catch (_) {}

    await _cleanup();
    AppLogger.info('AudioTranscode: Stopped');
  }

  Future<void> _cleanup() async {
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _mainReceivePort?.close();
    _mainReceivePort = null;
    _bgSendPort = null;
    _started = false;
  }

  bool get _isAndroid => Platform.isAndroid;

  // ---------------------------------------------------------------------------
  // Background isolate entry point
  // ---------------------------------------------------------------------------

  static Future<void> _backgroundEntry(_IsolateSetup setup) async {
    // Initialize platform channel access for this background isolate
    BackgroundIsolateBinaryMessenger.ensureInitialized(
      setup.rootIsolateToken,
    );

    final channel = MethodChannel(
      'io.github.tregula501.flowtv/audio_transcode',
    );

    final receivePort = ReceivePort();
    // Send our SendPort back to main isolate (handshake)
    setup.mainSendPort.send(receivePort.sendPort);

    bool started = false;

    receivePort.listen((message) async {
      if (message == 'start') {
        try {
          started = await channel.invokeMethod<bool>('start') ?? false;
          setup.mainSendPort.send({'type': 'started', 'success': started});
        } catch (e) {
          setup.mainSendPort.send({'type': 'started', 'success': false});
          setup.mainSendPort.send({'type': 'error', 'message': e.toString()});
        }
      } else if (message == 'stop') {
        try {
          if (started) {
            await channel.invokeMethod<void>('stop');
          }
        } catch (_) {}
        started = false;
        setup.mainSendPort.send({'type': 'stopped'});
        receivePort.close();
      } else if (message is Uint8List && started) {
        try {
          final result = await channel.invokeMethod<List<dynamic>>(
            'transcode',
            {'data': message},
          );
          if (result != null && result.isNotEmpty) {
            final frames = result.whereType<Uint8List>().toList();
            if (frames.isNotEmpty) {
              setup.mainSendPort.send({'type': 'aac', 'frames': frames});
            }
          }
        } catch (e) {
          setup.mainSendPort.send({'type': 'error', 'message': e.toString()});
        }
      }
    });
  }
}

/// Setup message passed to the background isolate.
class _IsolateSetup {
  final RootIsolateToken rootIsolateToken;
  final SendPort mainSendPort;

  _IsolateSetup({required this.rootIsolateToken, required this.mainSendPort});
}
