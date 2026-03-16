import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/utils/logger.dart';
import '../../../core/utils/secure_storage.dart';
import 'drift/app_database.dart';

// Export enums
export 'drift/app_database.dart' show PlaylistType, RecordingStatus, AccessLevel, VideoQuality;
// Export data classes
export 'drift/app_database.dart' show Playlist, Channel, EpgProgram, Favorite, Recording, UserProfile, AppSettingsTableData;
// Export companion classes for inserts
export 'drift/app_database.dart' show PlaylistsCompanion, ChannelsCompanion, EpgProgramsCompanion, FavoritesCompanion, RecordingsCompanion, UserProfilesCompanion, AppSettingsTableCompanion;

/// Database service using Drift
class DatabaseService {
  static AppDatabase? _database;

  static AppDatabase get instance {
    if (_database == null) {
      throw StateError('Database not initialized. Call DatabaseService.initialize() first.');
    }
    return _database!;
  }

  /// Initialize the database
  static Future<void> initialize() async {
    if (_database != null) return;

    try {
      _database = AppDatabase();
      AppLogger.info('Database initialized');

      // Migrate any legacy plaintext credentials from the database to SecureStorage
      await migrateCredentialsToSecureStorage();
    } catch (e, stack) {
      AppLogger.error('Failed to initialize database', e, stack);
      rethrow;
    }
  }

  /// Migrate legacy plaintext Xtream credentials from the Playlists table
  /// into SecureStorage, then NULL out the database columns.
  ///
  /// This is a one-time data migration for playlists that were created before
  /// SecureStorage was adopted. It is safe to run multiple times: credentials
  /// already present in SecureStorage are not overwritten.
  static Future<void> migrateCredentialsToSecureStorage() async {
    final db = instance;

    try {
      // Query all playlists that still have a non-empty username in the DB
      final playlistsWithCreds = await (db.select(db.playlists)
            ..where((t) =>
                t.username.isNotNull() & t.username.equals('').not()))
          .get();

      if (playlistsWithCreds.isEmpty) {
        return;
      }

      AppLogger.info(
        'Credential migration: found ${playlistsWithCreds.length} playlist(s) '
        'with legacy plaintext credentials',
      );

      int migrated = 0;

      for (final playlist in playlistsWithCreds) {
        final username = playlist.username;
        final password = playlist.password;

        if (username == null || username.isEmpty) continue;

        try {
          // Check if SecureStorage already has credentials for this playlist.
          // Do not overwrite existing secure credentials — they take precedence.
          final (existingUser, _) =
              await SecureStorage.getCredentials(playlist.id);

          if (existingUser == null || existingUser.isEmpty) {
            await SecureStorage.storeCredentials(
              playlist.id,
              username,
              password ?? '',
            );
            AppLogger.info(
              'Credential migration: stored credentials for playlist '
              '${playlist.id} ("${playlist.name}") in SecureStorage',
            );
          } else {
            AppLogger.info(
              'Credential migration: SecureStorage already has credentials '
              'for playlist ${playlist.id} ("${playlist.name}"), skipping write',
            );
          }

          // NULL out the plaintext columns in the database regardless,
          // since SecureStorage now holds the authoritative copy.
          await (db.update(db.playlists)
                ..where((t) => t.id.equals(playlist.id)))
              .write(const PlaylistsCompanion(
            username: Value(null),
            password: Value(null),
          ));

          migrated++;
        } catch (e, stack) {
          // Log but continue — don't let one playlist block the others
          AppLogger.error(
            'Credential migration: failed for playlist ${playlist.id} '
            '("${playlist.name}")',
            e,
            stack,
          );
        }
      }

      AppLogger.info(
        'Credential migration: completed. '
        '$migrated/${playlistsWithCreds.length} playlist(s) migrated.',
      );
    } catch (e, stack) {
      // Don't let a migration failure prevent the app from starting
      AppLogger.error('Credential migration failed', e, stack);
    }
  }

  /// Close the database
  static Future<void> close() async {
    await _database?.close();
    _database = null;
  }

  /// Clear all data (for testing or reset)
  /// Deletes in FK-safe order: children before parents.
  static Future<void> clearAll() async {
    if (_database == null) return;

    await _database!.transaction(() async {
      // Children first (reference channels / playlists)
      await _database!.delete(_database!.recordings).go();
      await _database!.delete(_database!.favorites).go();
      await _database!.delete(_database!.epgPrograms).go();
      // Then channels (references playlists)
      await _database!.delete(_database!.channels).go();
      // Then parents
      await _database!.delete(_database!.playlists).go();
      await _database!.delete(_database!.userProfiles).go();
      await _database!.delete(_database!.appSettingsTable).go();
    });
  }
}

// Helper to parse JSON lists
List<int> parseIntList(String json) {
  try {
    final list = jsonDecode(json) as List;
    return list.cast<int>();
  } catch (e) {
    AppLogger.warning('Failed to parse JSON int list: $e');
    return [];
  }
}

List<String> parseStringList(String json) {
  try {
    final list = jsonDecode(json) as List;
    return list.cast<String>();
  } catch (e) {
    AppLogger.warning('Failed to parse JSON string list: $e');
    return [];
  }
}

String encodeIntList(List<int> list) => jsonEncode(list);
String encodeStringList(List<String> list) => jsonEncode(list);
