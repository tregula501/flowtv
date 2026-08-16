import 'dart:isolate';

import 'package:drift/drift.dart';

import '../datasources/local/database_service.dart';
import '../datasources/local/drift/app_database.dart';
import '../datasources/remote/xmltv_parser.dart';
import '../../core/utils/logger.dart';

/// Progress callback for tracking import progress
/// [current] is the number of items processed so far
/// [total] is the total number of items to process
/// [phase] describes what phase we're in (e.g., "Downloading", "Parsing", "Storing")
typedef ProgressCallback = void Function(int current, int total, String phase);

/// Repository for EPG data operations
class EpgRepository {
  AppDatabase get _db => DatabaseService.instance;

  /// Fetch and store EPG from URL with optional progress callback.
  ///
  /// The whole pipeline (download, XMLTV parse, batch upsert) runs in a
  /// worker isolate via [computeWithDatabase] — building companions and batch
  /// payloads for 100k+ programs on the main isolate janks the UI for the
  /// entire store phase, even though statement execution is already
  /// backgrounded. Stream queries on the main connection still get update
  /// notifications, so open guide views refresh as usual.
  Future<int> fetchAndStoreEpg(
    String url, {
    ProgressCallback? onProgress,
  }) async {
    final progressPort = ReceivePort();
    final subscription = progressPort.listen((message) {
      if (message is List && message.length == 3) {
        onProgress?.call(
            message[0] as int, message[1] as int, message[2] as String);
      }
    });

    try {
      return await _db.computeWithDatabase(
        connect: AppDatabase.fromConnection,
        computation: _makeComputation(url, progressPort.sendPort),
      );
    } finally {
      await subscription.cancel();
      progressPort.close();
    }
  }

  /// Builds the isolate computation in a scope that holds ONLY sendable
  /// values. Creating this closure inline in [fetchAndStoreEpg] drags the
  /// whole enclosing context across the isolate boundary — including the
  /// caller's [onProgress] callback and everything it captures (timers,
  /// providers) — which fails with "object is unsendable".
  static Future<int> Function(AppDatabase) _makeComputation(
    String url,
    SendPort progress,
  ) {
    return (db) => _downloadParseAndStore(db, url, progress);
  }

  /// Runs inside the worker isolate — must not touch main-isolate state.
  static Future<int> _downloadParseAndStore(
    AppDatabase db,
    String url,
    SendPort progress,
  ) async {
    // Statics are per-isolate — without this the worker's logs are dropped.
    AppLogger.init();
    progress.send([0, 100, 'Downloading EPG...']);

    final parser = XmltvParser();
    final List<XmltvProgram> programs;
    try {
      final result = await parser.parseFromUrl(url);
      programs = result.programs;
    } finally {
      parser.close();
    }
    final total = programs.length;

    AppLogger.info('Parsed $total EPG programs, starting differential upsert...');
    progress.send([0, total, 'Updating programs...']);

    // Differential upsert — INSERT OR REPLACE keyed on (channel_id, start_time).
    // Unchanged rows get replaced in-place; new rows are inserted; stale rows cleaned up after.
    const batchSize = 1000;
    int processed = 0;

    for (int i = 0; i < programs.length; i += batchSize) {
      final end = (i + batchSize > programs.length) ? programs.length : i + batchSize;
      final chunk = programs.sublist(i, end);

      await db.batch((batch) {
        for (final program in chunk) {
          final companion = EpgProgramsCompanion.insert(
              channelId: program.channelId,
              title: program.title,
              startTime: program.startTime,
              endTime: program.endTime,
              description: Value(program.description),
              category: Value(program.category),
              episode: Value(program.episode),
              iconUrl: Value(program.iconUrl),
          );
          batch.insert(
            db.epgPrograms,
            companion,
            onConflict: DoUpdate(
              (old) => EpgProgramsCompanion.custom(
                title: Variable(program.title),
                endTime: Variable(program.endTime),
                description: Variable(program.description),
                category: Variable(program.category),
                episode: Variable(program.episode),
                iconUrl: Variable(program.iconUrl),
              ),
              target: [db.epgPrograms.channelId, db.epgPrograms.startTime],
            ),
          );
        }
      });

      processed = end;
      progress.send([processed, total, 'Updating programs...']);
    }

    // Clean up stale programs that ended more than 6 hours ago
    final staleThreshold = DateTime.now().subtract(const Duration(hours: 6));
    final deleted = await (db.delete(db.epgPrograms)
          ..where((t) => t.endTime.isSmallerThanValue(staleThreshold)))
        .go();
    if (deleted > 0) {
      AppLogger.info('EPG: Cleaned up $deleted stale programs');
    }

    AppLogger.info('EPG: Upserted $total programs');
    return total;
  }

  /// Get programs for a channel
  Future<List<EpgProgram>> getProgramsForChannel(
    String channelId, {
    DateTime? from,
    DateTime? to,
  }) async {
    final now = DateTime.now();
    final startTime = from ?? now.subtract(const Duration(hours: 2));
    final endTime = to ?? now.add(const Duration(hours: 24));

    return (_db.select(_db.epgPrograms)
          ..where((t) =>
              t.channelId.equals(channelId) &
              t.startTime.isBiggerThanValue(startTime) &
              t.endTime.isSmallerThanValue(endTime),)
          ..orderBy([(t) => OrderingTerm.asc(t.startTime)]))
        .get();
  }

  /// Get current program for a channel
  Future<EpgProgram?> getCurrentProgram(String channelId) async {
    final now = DateTime.now();

    return (_db.select(_db.epgPrograms)
          ..where((t) =>
              t.channelId.equals(channelId) &
              t.startTime.isSmallerThanValue(now) &
              t.endTime.isBiggerThanValue(now),))
        .getSingleOrNull();
  }

  /// Get next program for a channel
  Future<EpgProgram?> getNextProgram(String channelId) async {
    final now = DateTime.now();

    return (_db.select(_db.epgPrograms)
          ..where((t) =>
              t.channelId.equals(channelId) &
              t.startTime.isBiggerThanValue(now),)
          ..orderBy([(t) => OrderingTerm.asc(t.startTime)])
          ..limit(1))
        .getSingleOrNull();
  }

  /// Get all programs for a time range (for EPG grid)
  Future<Map<String, List<EpgProgram>>> getProgramsForTimeRange(
    DateTime from,
    DateTime to,
  ) async {
    final programs = await (_db.select(_db.epgPrograms)
          ..where((t) =>
              t.startTime.isSmallerThanValue(to) &
              t.endTime.isBiggerThanValue(from),)
          ..orderBy([
            (t) => OrderingTerm.asc(t.channelId),
            (t) => OrderingTerm.asc(t.startTime),
          ]))
        .get();

    final grouped = <String, List<EpgProgram>>{};
    for (final program in programs) {
      grouped.putIfAbsent(program.channelId, () => []).add(program);
    }

    return grouped;
  }

  /// Clear all EPG data
  Future<void> clearEpg() async {
    await _db.delete(_db.epgPrograms).go();
  }

  /// Get EPG program count
  Future<int> getProgramCount() async {
    final count = await _db.epgPrograms.count().getSingle();
    return count;
  }
}
