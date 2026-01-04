import 'package:isar/isar.dart';

import '../models/epg_program.dart';
import '../datasources/local/database_service.dart';
import '../datasources/remote/xmltv_parser.dart';
import '../../core/utils/logger.dart';

/// Repository for EPG data operations
class EpgRepository {
  final XmltvParser _parser = XmltvParser();

  Isar get _isar => DatabaseService.instance;

  /// Fetch and store EPG from URL
  Future<int> fetchAndStoreEpg(String url) async {
    final result = await _parser.parseFromUrl(url);

    await _isar.writeTxn(() async {
      // Clear old EPG data
      await _isar.epgPrograms.clear();

      // Store new programs
      await _isar.epgPrograms.putAll(result.programs);
    });

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

    return _isar.epgPrograms
        .filter()
        .channelIdEqualTo(channelId)
        .startTimeGreaterThan(startTime)
        .endTimeLessThan(endTime)
        .sortByStartTime()
        .findAll();
  }

  /// Get current program for a channel
  Future<EpgProgram?> getCurrentProgram(String channelId) async {
    final now = DateTime.now();

    return _isar.epgPrograms
        .filter()
        .channelIdEqualTo(channelId)
        .startTimeLessThan(now)
        .endTimeGreaterThan(now)
        .findFirst();
  }

  /// Get next program for a channel
  Future<EpgProgram?> getNextProgram(String channelId) async {
    final now = DateTime.now();

    return _isar.epgPrograms
        .filter()
        .channelIdEqualTo(channelId)
        .startTimeGreaterThan(now)
        .sortByStartTime()
        .findFirst();
  }

  /// Get all programs for a time range (for EPG grid)
  Future<Map<String, List<EpgProgram>>> getProgramsForTimeRange(
    DateTime from,
    DateTime to,
  ) async {
    final programs = await _isar.epgPrograms
        .filter()
        .startTimeLessThan(to)
        .endTimeGreaterThan(from)
        .sortByChannelId()
        .thenByStartTime()
        .findAll();

    final grouped = <String, List<EpgProgram>>{};
    for (final program in programs) {
      grouped.putIfAbsent(program.channelId, () => []).add(program);
    }

    return grouped;
  }

  /// Clear all EPG data
  Future<void> clearEpg() async {
    await _isar.writeTxn(() async {
      await _isar.epgPrograms.clear();
    });
  }

  /// Get EPG program count
  Future<int> getProgramCount() async {
    return _isar.epgPrograms.count();
  }
}
