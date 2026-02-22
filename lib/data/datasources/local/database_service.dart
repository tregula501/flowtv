import 'dart:convert';

import '../../../core/utils/logger.dart';
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
    } catch (e, stack) {
      AppLogger.error('Failed to initialize database', e, stack);
      rethrow;
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
