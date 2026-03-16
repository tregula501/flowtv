import 'dart:async';
import 'dart:math';

import 'package:media_kit/media_kit.dart' hide PlayerState;

import '../../../core/utils/logger.dart';
import '../../../data/datasources/local/database_service.dart';
import '../player_provider.dart' show PlayerState;

/// Manages auto-retry / reconnection logic when a stream errors out.
class RetryController {
  int retryAttempt = 0;
  static const int maxRetries = 3;
  bool isRetrying = false;
  Timer? _retryTimer;
  bool autoRetryEnabled = true;

  /// Handle a stream error, possibly scheduling a retry.
  ///
  /// [updateState] is a callback that applies a transformation to the current
  /// [PlayerState].
  void handleStreamError(
    String error, {
    required Player? player,
    required Channel? channel,
    required void Function(PlayerState Function(PlayerState)) updateState,
  }) {
    if (!autoRetryEnabled || channel == null || isRetrying) return;

    // Check if we've exceeded max retries
    if (retryAttempt >= maxRetries) {
      AppLogger.error('Max retry attempts reached ($maxRetries), giving up');
      updateState((s) => s.copyWith(
            error: 'Connection lost after $maxRetries retry attempts: $error',
            isReconnecting: false,
            retryAttempt: 0,
          ));
      resetRetryState();
      return;
    }

    // Calculate delay with exponential backoff + jitter: ~1s, ~2s, ~4s
    final baseDelayMs = (1 << retryAttempt) * 1000;
    final jitter = (baseDelayMs * 0.25 * (2 * Random().nextDouble() - 1)).toInt();
    final delayMs = baseDelayMs + jitter;
    retryAttempt++;

    AppLogger.info(
        'Stream error, retry attempt $retryAttempt/$maxRetries in ${delayMs}ms');

    updateState((s) => s.copyWith(
          isReconnecting: true,
          retryAttempt: retryAttempt,
          clearError: true,
        ));

    _retryTimer?.cancel();
    _retryTimer = Timer(Duration(milliseconds: delayMs), () {
      attemptReconnect(
        player: player,
        channel: channel,
        updateState: updateState,
      );
    });
  }

  /// Try to reconnect to [channel].
  Future<void> attemptReconnect({
    required Player? player,
    required Channel? channel,
    required void Function(PlayerState Function(PlayerState)) updateState,
  }) async {
    if (channel == null) return;

    isRetrying = true;
    AppLogger.info('Attempting reconnect to ${channel.name}...');

    try {
      await player?.stop();
      await Future.delayed(const Duration(milliseconds: 500));

      // Re-open the stream without resetting retry state yet
      await player?.open(Media(channel.streamUrl), play: true);

      // Wait a moment to see if playback starts successfully
      await Future.delayed(const Duration(seconds: 2));

      // Check if we're actually playing
      if (player?.state.playing ?? false) {
        AppLogger.info('Reconnect successful!');
        resetRetryState();
        updateState((s) => s.copyWith(
              isReconnecting: false,
              retryAttempt: 0,
              clearError: true,
            ));
      } else {
        // Still not playing, trigger another retry
        isRetrying = false;
        handleStreamError(
          'Reconnect failed - not playing',
          player: player,
          channel: channel,
          updateState: updateState,
        );
      }
    } catch (e) {
      AppLogger.error('Reconnect attempt failed: $e');
      isRetrying = false;
      handleStreamError(
        e.toString(),
        player: player,
        channel: channel,
        updateState: updateState,
      );
    }
  }

  /// Reset all retry state.
  void resetRetryState() {
    retryAttempt = 0;
    isRetrying = false;
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  /// Cancel any pending retry and clear reconnecting flags via [updateState].
  void cancelRetry(
      void Function(PlayerState Function(PlayerState)) updateState) {
    resetRetryState();
    updateState((s) =>
        s.copyWith(isReconnecting: false, retryAttempt: 0, clearError: true));
  }

  /// Release timers.
  void dispose() {
    _retryTimer?.cancel();
  }
}
