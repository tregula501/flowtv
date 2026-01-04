import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';

import '../../models/playlist.dart';
import '../../models/channel.dart';
import '../../models/epg_program.dart';
import '../../models/favorite.dart';
import '../../models/recording.dart';
import '../../models/user_profile.dart';
import '../../models/app_settings.dart';
import '../../../core/utils/logger.dart';

/// Database service using Isar
class DatabaseService {
  static Isar? _isar;

  static Isar get instance {
    if (_isar == null) {
      throw StateError('Database not initialized. Call DatabaseService.initialize() first.');
    }
    return _isar!;
  }

  /// Initialize the database
  static Future<void> initialize() async {
    if (_isar != null) return;

    try {
      final dir = await getApplicationDocumentsDirectory();
      final dbPath = '${dir.path}/flowtv';

      _isar = await Isar.open(
        [
          PlaylistSchema,
          ChannelSchema,
          EpgProgramSchema,
          FavoriteSchema,
          RecordingSchema,
          UserProfileSchema,
          AppSettingsSchema,
        ],
        directory: dbPath,
        name: 'flowtv',
      );

      // Ensure default settings exist
      await _ensureDefaults();

      AppLogger.info('Database initialized at: $dbPath');
    } catch (e, stack) {
      AppLogger.error('Failed to initialize database', e, stack);
      rethrow;
    }
  }

  /// Ensure default records exist
  static Future<void> _ensureDefaults() async {
    final settings = await _isar!.appSettings.get(1);
    if (settings == null) {
      await _isar!.writeTxn(() async {
        await _isar!.appSettings.put(AppSettings.defaults());
      });
    }

    // Ensure master profile exists
    final profiles = await _isar!.userProfiles.where().findAll();
    if (profiles.isEmpty) {
      await _isar!.writeTxn(() async {
        await _isar!.userProfiles.put(UserProfile.master());
      });
    }
  }

  /// Close the database
  static Future<void> close() async {
    await _isar?.close();
    _isar = null;
  }

  /// Clear all data (for testing or reset)
  static Future<void> clearAll() async {
    await _isar?.writeTxn(() async {
      await _isar!.clear();
      await _ensureDefaults();
    });
  }
}
