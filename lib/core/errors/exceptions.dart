/// Base exception class for FlowTV
class AppException implements Exception {
  final String message;
  final String? code;
  final dynamic originalError;

  const AppException(this.message, {this.code, this.originalError});

  @override
  String toString() => 'AppException: $message${code != null ? ' (code: $code)' : ''}';
}

/// Exception for network-related errors
class NetworkException extends AppException {
  const NetworkException(super.message, {super.code, super.originalError});
}

/// Exception for playlist parsing errors
class PlaylistParseException extends AppException {
  const PlaylistParseException(super.message, {super.code, super.originalError});
}

/// Exception for EPG parsing errors
class EpgParseException extends AppException {
  const EpgParseException(super.message, {super.code, super.originalError});
}

/// Exception for database errors
class DatabaseException extends AppException {
  const DatabaseException(super.message, {super.code, super.originalError});
}

/// Exception for playback errors
class PlaybackException extends AppException {
  const PlaybackException(super.message, {super.code, super.originalError});
}

/// Exception for file operations
class FileException extends AppException {
  const FileException(super.message, {super.code, super.originalError});
}

/// Exception for authentication/API errors
class ApiException extends AppException {
  final int? statusCode;

  const ApiException(
    super.message, {
    this.statusCode,
    super.code,
    super.originalError,
  });
}
