import 'package:drift/drift.dart';

import '../datasources/local/database_service.dart';
import '../datasources/local/drift/app_database.dart';
import '../datasources/remote/xmltv_parser.dart';
import '../../core/utils/logger.dart';

/// Repository for EPG data operations
class EpgRepository {
  final XmltvParser _parser = XmltvParser();

  AppDatabase get _db => DatabaseService.instance;

  /// Fetch and store EPG from URL
  Future<int> fetchAndStoreEpg(String url) async {
    final result = await _parser.parseFromUrl(url);

    // Clear old EPG data
    await _db.delete(_db.epgPrograms).go();

    // Store new programs
    for (final program in result.programs) {
      await _db.into(_db.epgPrograms).insert(
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

    AppLogger.info('Stored ${result.programCount} EPG programs');
    return result.programCount;
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
              t.endTime.isSmallerThanValue(endTime))
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
              t.endTime.isBiggerThanValue(now)))
        .getSingleOrNull();
  }

  /// Get next program for a channel
  Future<EpgProgram?> getNextProgram(String channelId) async {
    final now = DateTime.now();

    return (_db.select(_db.epgPrograms)
          ..where((t) =>
              t.channelId.equals(channelId) &
              t.startTime.isBiggerThanValue(now))
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
              t.endTime.isBiggerThanValue(from))
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
