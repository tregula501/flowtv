import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

part 'app_database.g.dart';

// Enums stored as text
enum PlaylistType { m3u, xtream, file }
enum RecordingStatus { scheduled, recording, completed, failed, cancelled }
enum AccessLevel { full, restricted, kids }
enum VideoQuality { auto, low, medium, high, ultra }

// Table definitions
class Playlists extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get url => text()();
  TextColumn get username => text().nullable()();
  TextColumn get password => text().nullable()();
  TextColumn get epgUrl => text().nullable()();
  TextColumn get type => textEnum<PlaylistType>()();
  DateTimeColumn get lastRefresh => dateTime().nullable()();
  IntColumn get channelCount => integer().withDefault(const Constant(0))();
  BoolColumn get isActive => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
}

class Channels extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get playlistId => integer().references(Playlists, #id)();
  TextColumn get name => text()();
  TextColumn get streamUrl => text()();
  TextColumn get logoUrl => text().nullable()();
  TextColumn get epgId => text().nullable()();
  TextColumn get group => text().nullable()();
  IntColumn get channelNumber => integer().nullable()();
  BoolColumn get isFavorite => boolean().withDefault(const Constant(false))();
  BoolColumn get isLocked => boolean().withDefault(const Constant(false))();
  DateTimeColumn get lastWatched => dateTime().nullable()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  BoolColumn get isVod => boolean().withDefault(const Constant(false))();
  TextColumn get language => text().nullable()();
  TextColumn get country => text().nullable()();
}

class EpgPrograms extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get channelId => text()();
  TextColumn get title => text()();
  TextColumn get description => text().nullable()();
  DateTimeColumn get startTime => dateTime()();
  DateTimeColumn get endTime => dateTime()();
  TextColumn get category => text().nullable()();
  TextColumn get episode => text().nullable()();
  TextColumn get iconUrl => text().nullable()();
}

class Favorites extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get channelId => integer().references(Channels, #id)();
  IntColumn get playlistId => integer().references(Playlists, #id)();
  DateTimeColumn get addedAt => dateTime()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
}

class Recordings extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get channelId => integer().references(Channels, #id)();
  TextColumn get title => text()();
  TextColumn get filePath => text()();
  DateTimeColumn get scheduledStart => dateTime()();
  DateTimeColumn get scheduledEnd => dateTime()();
  DateTimeColumn get actualStart => dateTime().nullable()();
  DateTimeColumn get actualEnd => dateTime().nullable()();
  TextColumn get status => textEnum<RecordingStatus>()();
  IntColumn get fileSize => integer().withDefault(const Constant(0))();
  IntColumn get durationSeconds => integer().withDefault(const Constant(0))();
  IntColumn get epgProgramId => integer().nullable()();
  TextColumn get errorMessage => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
}

class UserProfiles extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get avatarId => text().nullable()();
  TextColumn get pinHash => text().nullable()();
  BoolColumn get isMaster => boolean().withDefault(const Constant(false))();
  TextColumn get accessLevel => textEnum<AccessLevel>()();
  // Store lists as JSON text
  TextColumn get lockedChannels => text().withDefault(const Constant('[]'))();
  TextColumn get lockedCategories => text().withDefault(const Constant('[]'))();
  IntColumn get dailyTimeLimitMinutes => integer().withDefault(const Constant(0))();
  IntColumn get allowedHoursStart => integer().nullable()();
  IntColumn get allowedHoursEnd => integer().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
}

class AppSettingsTable extends Table {
  @override
  String get tableName => 'app_settings';

  IntColumn get id => integer().autoIncrement()();
  IntColumn get themeMode => integer().withDefault(const Constant(2))(); // 0=system, 1=light, 2=dark
  TextColumn get languageCode => text().withDefault(const Constant('en'))();
  RealColumn get volume => real().withDefault(const Constant(1.0))();
  BoolColumn get isMuted => boolean().withDefault(const Constant(false))();
  BoolColumn get autoPlay => boolean().withDefault(const Constant(true))();
  BoolColumn get hardwareAcceleration => boolean().withDefault(const Constant(true))();
  TextColumn get defaultQuality => textEnum<VideoQuality>().withDefault(Constant(VideoQuality.auto.name))();
  IntColumn get epgRefreshHours => integer().withDefault(const Constant(6))();
  IntColumn get playlistRefreshHours => integer().withDefault(const Constant(24))();
  IntColumn get bufferSeconds => integer().withDefault(const Constant(30))();
  BoolColumn get showChannelNumbers => boolean().withDefault(const Constant(true))();
  BoolColumn get showEpgPreview => boolean().withDefault(const Constant(true))();
  BoolColumn get rememberLastChannel => boolean().withDefault(const Constant(true))();
  IntColumn get lastPlaylistId => integer().nullable()();
  IntColumn get lastChannelId => integer().nullable()();
  RealColumn get windowWidth => real().nullable()();
  RealColumn get windowHeight => real().nullable()();
  RealColumn get windowX => real().nullable()();
  RealColumn get windowY => real().nullable()();
  BoolColumn get windowMaximized => boolean().withDefault(const Constant(false))();
}

@DriftDatabase(tables: [
  Playlists,
  Channels,
  EpgPrograms,
  Favorites,
  Recordings,
  UserProfiles,
  AppSettingsTable,
],)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  // Bump this when you change the schema. Add a migration step below.
  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (Migrator m) async {
        await m.createAll();
        // Unique index enables differential upsert and fast EPG lookups
        await customStatement(
          'CREATE UNIQUE INDEX IF NOT EXISTS idx_epg_channel_start '
          'ON epg_programs (channel_id, start_time)',
        );
        // Index on channels.playlistId for fast playlist-scoped queries
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_channels_playlist '
          'ON channels (playlist_id)',
        );
        // Index on channels.epgId for fast EPG lookups
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_channels_epg_id '
          'ON channels (epg_id)',
        );
        // Create default settings
        await into(appSettingsTable).insert(
          AppSettingsTableCompanion.insert(),
        );
        // Create master profile
        await into(userProfiles).insert(
          UserProfilesCompanion.insert(
            name: 'Admin',
            accessLevel: AccessLevel.full,
            isMaster: const Value(true),
            isActive: const Value(true),
            createdAt: DateTime.now(),
          ),
        );
      },
      onUpgrade: (Migrator m, int from, int to) async {
        // Migration pattern: use sequential if-checks so each step runs in order.
        // Example:
        //   if (from < 3) { await m.addColumn(channels, channels.newCol); }
        //   if (from < 4) { ... }
        if (from < 2) {
          // v1 -> v2: Add index on EPG programs for faster channel lookups.
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_epg_channel_start '
            'ON epg_programs (channel_id, start_time)',
          );
        }
        if (from < 3) {
          // v2 -> v3: Upgrade to UNIQUE index for differential upsert support.
          await customStatement('DROP INDEX IF EXISTS idx_epg_channel_start');
          await customStatement(
            'CREATE UNIQUE INDEX IF NOT EXISTS idx_epg_channel_start '
            'ON epg_programs (channel_id, start_time)',
          );
        }
        if (from < 4) {
          // v3 -> v4: Add indexes on channels for faster queries.
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_channels_playlist '
            'ON channels (playlist_id)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_channels_epg_id '
            'ON channels (epg_id)',
          );
        }
      },
    );
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'flowtv', 'flowtv.db'));

    // Ensure directory exists
    await file.parent.create(recursive: true);

    return NativeDatabase.createInBackground(
      file,
      setup: (db) {
        // Enable foreign key enforcement
        db.execute('PRAGMA foreign_keys = ON');
      },
    );
  });
}
