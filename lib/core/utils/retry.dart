import 'dart:async';
import 'dart:math';

import 'logger.dart';

/// Retry a function with exponential backoff.
/// Retries on any exception up to [maxAttempts] times.
Future<T> withRetry<T>(
  Future<T> Function() fn, {
  int maxAttempts = 3,
  Duration initialDelay = const Duration(seconds: 1),
  String? label,
}) async {
  for (int attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      return await fn();
    } catch (e) {
      if (attempt == maxAttempts) rethrow;

      final delay = initialDelay * pow(2, attempt - 1);
      final tag = label != null ? ' ($label)' : '';
      AppLogger.warning(
        'Attempt $attempt/$maxAttempts failed$tag: $e — retrying in ${delay.inSeconds}s',
      );
      await Future.delayed(delay);
    }
  }
  // Unreachable, but satisfies the type system
  throw StateError('withRetry: unreachable');
}
