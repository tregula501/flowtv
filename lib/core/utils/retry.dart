import 'dart:async';
import 'dart:math';

import 'logger.dart';

/// Retry a function with exponential backoff and jitter.
/// Retries on any exception up to [maxAttempts] times.
/// Jitter spreads retries ±10% to avoid thundering-herd effects.
Future<T> withRetry<T>(
  Future<T> Function() fn, {
  int maxAttempts = 3,
  Duration initialDelay = const Duration(seconds: 1),
  String? label,
}) async {
  final random = Random();
  for (int attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      return await fn();
    } catch (e) {
      if (attempt == maxAttempts) rethrow;

      final baseDelay = initialDelay * pow(2, attempt - 1);
      // Add ±10% random jitter to avoid synchronized retries
      final jitter = baseDelay.inMilliseconds * 0.1 * (2 * random.nextDouble() - 1);
      final delay = Duration(
        milliseconds: baseDelay.inMilliseconds + jitter.toInt(),
      );
      final tag = label != null ? ' ($label)' : '';
      AppLogger.warning(
        'Attempt $attempt/$maxAttempts failed$tag: $e — retrying in ${delay.inMilliseconds}ms',
      );
      await Future.delayed(delay);
    }
  }
  // Unreachable, but satisfies the type system
  throw StateError('withRetry: unreachable');
}
