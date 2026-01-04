import 'package:flutter/foundation.dart';

/// Simple logger utility for FlowTV
class AppLogger {
  static bool _initialized = false;

  static void init() {
    _initialized = true;
  }

  static void _log(String level, String message, [Object? error, StackTrace? stackTrace]) {
    if (!_initialized) return;

    final timestamp = DateTime.now().toIso8601String();
    final logMessage = '[$timestamp] [$level] $message';

    if (kDebugMode) {
      // ignore: avoid_print
      print(logMessage);
      if (error != null) {
        // ignore: avoid_print
        print('Error: $error');
      }
      if (stackTrace != null) {
        // ignore: avoid_print
        print('StackTrace: $stackTrace');
      }
    }
  }

  static void debug(String message) => _log('DEBUG', message);
  static void info(String message) => _log('INFO', message);
  static void warning(String message) => _log('WARN', message);
  static void error(String message, [Object? error, StackTrace? stackTrace]) {
    _log('ERROR', message, error, stackTrace);
  }
}
