import 'dart:async';
import 'dart:math';

import '../errors/exceptions.dart';
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
      // Don't retry non-transient HTTP errors (auth failures, not found, etc.)
      if (e is ApiException && e.statusCode != null) {
        final code = e.statusCode!;
        if (code == 401 || code == 403 || code == 404) rethrow;
      }
      if (attempt == maxAttempts) rethrow;

      // Cap the exponent to prevent overflow with large maxAttempts
      final exponent = min(attempt - 1, 10);
      final baseDelay = initialDelay * pow(2, exponent);
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
