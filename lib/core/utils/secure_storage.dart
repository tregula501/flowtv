import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Secure credential storage wrapper for sensitive data like Xtream API passwords.
/// Uses platform-specific encrypted storage (Keychain on iOS, EncryptedSharedPreferences on Android).
class SecureStorage {
  static const _storage = FlutterSecureStorage();

  static const _usernamePrefix = 'xtream_username_';
  static const _passwordPrefix = 'xtream_password_';

  /// Store Xtream credentials for a playlist.
  static Future<void> storeCredentials(
    int playlistId,
    String username,
    String password,
  ) async {
    await _storage.write(key: '$_usernamePrefix$playlistId', value: username);
    await _storage.write(key: '$_passwordPrefix$playlistId', value: password);
  }

  /// Retrieve Xtream credentials for a playlist.
  /// Returns (username, password) or (null, null) if not found.
  static Future<(String?, String?)> getCredentials(int playlistId) async {
    final username = await _storage.read(key: '$_usernamePrefix$playlistId');
    final password = await _storage.read(key: '$_passwordPrefix$playlistId');
    return (username, password);
  }

  /// Delete stored credentials for a playlist.
  static Future<void> deleteCredentials(int playlistId) async {
    await _storage.delete(key: '$_usernamePrefix$playlistId');
    await _storage.delete(key: '$_passwordPrefix$playlistId');
  }
}
