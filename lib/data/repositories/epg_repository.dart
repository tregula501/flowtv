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
  final XmltvParser _parser = XmltvParser();

  AppDatabase get _db => DatabaseService.instance;

  /// Fetch and store EPG from URL with optional progress callback
  Future<int> fetchAndStoreEpg(
    String url, {
    ProgressCallback? onProgress,
  }) async {
    // Phase 1: Download and parse
    onProgress?.call(0, 100, 'Downloading EPG...');

    final result = await _parser.parseFromUrl(url);
    final programs = result.programs;
    final total = programs.length;

    AppLogger.info('Parsed $total EPG programs, starting database insert...');
    onProgress?.call(0, total, 'Clearing old data...');

    // Phase 2: Clear old EPG data
    // TODO: Replace full-table DELETE with differential upsert to avoid
    // data loss during refresh and reduce I/O on large EPG datasets.
    await _db.delete(_db.epgPrograms).go();

    // Phase 3: Batch insert new programs in chunks for progress tracking
    const batchSize = 1000;
    int processed = 0;

    for (int i = 0; i < programs.length; i += batchSize) {
      final end = (i + batchSize > programs.length) ? programs.length : i + batchSize;
      final chunk = programs.sublist(i, end);

      // Use Drift batch for efficient bulk insert
      await _db.batch((batch) {
        for (final program in chunk) {
          batch.insert(
            _db.epgPrograms,
            EpgProgramsCompanion.insert(
              channelId: program.channelId,
              title: program.title,
              startTime: program.startTime,
              endTime: program.endTime,
              description: Value(program.description),
              category: Value(program.category),
              episode: Value(program.episode),
              iconUrl: Value(program.iconUrl),
            ),
          );
        }
      });

      processed = end;
      onProgress?.call(processed, total, 'Storing programs...');
    }

    AppLogger.info('Stored $total EPG programs using batch inserts');
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
