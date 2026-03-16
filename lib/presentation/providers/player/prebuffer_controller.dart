import 'dart:async';

import '../../../core/utils/logger.dart';

/// Controls prebuffering logic: waits for a specified duration before starting
/// playback, reporting progress via callbacks.
class PrebufferController {
  bool isPrebuffering = false;
  DateTime? startTime;
  Timer? _progressTimer;
  Timer? _completeTimer;

  /// Start prebuffering for [bufferSeconds].
  ///
  /// [onComplete] is called when the prebuffer duration elapses.
  /// [onProgress] is called every 100ms with the elapsed time so far.
  void startPrebuffering(
    int bufferSeconds, {
    required VoidCallback onComplete,
    required void Function(Duration elapsed) onProgress,
  }) {
    isPrebuffering = true;
    startTime = DateTime.now();

    // Periodic progress updates
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(
      const Duration(milliseconds: 100),
      (_) {
        if (!isPrebuffering || startTime == null) {
          _progressTimer?.cancel();
          _progressTimer = null;
          return;
        }
        final elapsed = DateTime.now().difference(startTime!);
        onProgress(elapsed);
      },
    );

    // Schedule completion
    AppLogger.info('Prebuffering for ${bufferSeconds}s...');
    _completeTimer = Timer(Duration(seconds: bufferSeconds), () {
      completePrebuffering(onComplete: onComplete);
    });
  }

  /// Complete prebuffering and invoke the completion callback.
  void completePrebuffering({required VoidCallback onComplete}) {
    if (!isPrebuffering) return;

    isPrebuffering = false;
    startTime = null;
    _progressTimer?.cancel();
    _progressTimer = null;
    _completeTimer = null;
    onComplete();
    AppLogger.info('Prebuffer complete, starting playback');
  }

  /// Cancel prebuffering without triggering the completion callback.
  void cancelPrebuffering() {
    isPrebuffering = false;
    startTime = null;
    _progressTimer?.cancel();
    _progressTimer = null;
    _completeTimer?.cancel();
    _completeTimer = null;
  }

  /// Release all timers.
  void dispose() {
    _progressTimer?.cancel();
    _completeTimer?.cancel();
  }
}

/// Matches [dart:ui] VoidCallback without importing Flutter.
typedef VoidCallback = void Function();
