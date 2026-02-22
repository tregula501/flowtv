import 'package:flutter/foundation.dart';

/// Log severity levels, ordered from most to least verbose.
enum LogLevel { debug, info, warning, error }

/// Simple logger utility for FlowTV
class AppLogger {
  static bool _initialized = false;
  static LogLevel _minLevel = LogLevel.debug;

  // Patterns that match credentials in Xtream-style URLs:
  //   http://host:port/<username>/<password>/...
  //   http://host:port/movie/<username>/<password>/...
  //   http://host:port/series/<username>/<password>/...
  //   http://host:port/player_api.php?username=X&password=Y
  static final _credentialPathPattern = RegExp(
    r'(https?://[^/]+/)(?:movie/|series/)?[^/]+/[^/]+(/)',
  );
  static final _credentialQueryPattern = RegExp(
    r'((?:username|password|token|api_key)=)[^&\s]+',
    caseSensitive: false,
  );

  static void init() {
    _initialized = true;
  }

  /// Set the minimum log level. Messages below this level are suppressed.
  static void setLevel(LogLevel level) {
    _minLevel = level;
  }

  /// Strip credentials from URLs and common secret patterns before logging.
  static String redactUrl(String message) {
    var redacted = message.replaceAll(_credentialPathPattern, r'$1***/***/');
    redacted = redacted.replaceAll(_credentialQueryPattern, r'$1***');
    return redacted;
  }

  static void _log(
    LogLevel level,
    String message, [
    Object? error,
    StackTrace? stackTrace,
  ]) {
    if (!_initialized) return;
    if (level.index < _minLevel.index) return;

    final timestamp = DateTime.now().toIso8601String();
    final redacted = redactUrl(message);
    final logMessage = '[$timestamp] [${level.name.toUpperCase()}] $redacted';

    if (kDebugMode) {
      // ignore: avoid_print
      print(logMessage);
      if (error != null) {
        // ignore: avoid_print
        print('Error: ${redactUrl(error.toString())}');
      }
      if (stackTrace != null) {
        // ignore: avoid_print
        print('StackTrace: ${redactUrl(stackTrace.toString())}');
      }
    }
  }

  static void debug(String message) => _log(LogLevel.debug, message);
  static void info(String message) => _log(LogLevel.info, message);
  static void warning(String message) => _log(LogLevel.warning, message);
  static void error(String message, [Object? error, StackTrace? stackTrace]) {
    _log(LogLevel.error, message, error, stackTrace);
  }
}
