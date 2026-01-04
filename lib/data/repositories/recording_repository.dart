import 'dart:io';

import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import '../models/recording.dart';
import '../models/channel.dart';
import '../datasources/local/database_service.dart';
import '../../core/utils/logger.dart';

class RecordingRepository {
  late String _recordingsDir;
  bool _initialized = false;

  /// Initialize recordings directory
  Future<void> initialize() async {
    if (_initialized) return;

    final appDir = await getApplicationDocumentsDirectory();
    _recordingsDir = p.join(appDir.path, 'FlowTV', 'Recordings');

    final dir = Directory(_recordingsDir);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    _initialized = true;
    AppLogger.info('Recordings directory: $_recordingsDir');
  }

  String get recordingsDir => _recordingsDir;

  /// Generate a unique file path for a new recording
  String generateFilePath(String title, DateTime startTime) {
    // Sanitize title for filename
    final sanitized = title
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
        .replaceAll(RegExp(r'\s+'), '_');

    final timestamp = startTime.toIso8601String().replaceAll(':', '-');
    final filename = '${sanitized}_$timestamp.ts';

    return p.join(_recordingsDir, filename);
  }

  /// Create a new recording entry
  Future<Recording> createRecording({
    required int channelId,
    required String title,
    required DateTime scheduledStart,
    required DateTime scheduledEnd,
    int? epgProgramId,
  }) async {
    await initialize();

    final filePath = generateFilePath(title, scheduledStart);

    final recording = Recording.create(
      channelId: channelId,
      title: title,
      filePath: filePath,
      scheduledStart: scheduledStart,
      scheduledEnd: scheduledEnd,
      epgProgramId: epgProgramId,
    );

    final isar = DatabaseService.instance;
    await isar.writeTxn(() async {
      await isar.recordings.put(recording);
    });

    AppLogger.info('Created recording: ${recording.title}');
    return recording;
  }

  /// Start an instant recording
  Future<Recording> startInstantRecording({
    required Channel channel,
    Duration duration = const Duration(hours: 1),
  }) async {
    final now = DateTime.now();
    return createRecording(
      channelId: channel.id,
      title: '${channel.name} - ${now.toString().substring(0, 16)}',
      scheduledStart: now,
      scheduledEnd: now.add(duration),
    );
  }

  /// Update recording status
  Future<void> updateStatus(int recordingId, RecordingStatus status,
      {String? errorMessage}) async {
    final isar = DatabaseService.instance;

    await isar.writeTxn(() async {
      final recording = await isar.recordings.get(recordingId);
      if (recording != null) {
        recording.status = status;
        if (errorMessage != null) {
          recording.errorMessage = errorMessage;
        }
        if (status == RecordingStatus.recording) {
          recording.actualStart = DateTime.now();
        }
        if (status == RecordingStatus.completed ||
            status == RecordingStatus.failed) {
          recording.actualEnd = DateTime.now();
        }
        await isar.recordings.put(recording);
      }
    });
  }

  /// Update recording file size
  Future<void> updateFileSize(int recordingId) async {
    final isar = DatabaseService.instance;

    await isar.writeTxn(() async {
      final recording = await isar.recordings.get(recordingId);
      if (recording != null) {
        final file = File(recording.filePath);
        if (await file.exists()) {
          recording.fileSize = await file.length();

          if (recording.actualStart != null) {
            recording.durationSeconds =
                DateTime.now().difference(recording.actualStart!).inSeconds;
          }
        }
        await isar.recordings.put(recording);
      }
    });
  }

  /// Get all recordings
  Future<List<Recording>> getAllRecordings() async {
    final isar = DatabaseService.instance;
    return isar.recordings.where().sortByScheduledStartDesc().findAll();
  }

  /// Get recordings by status
  Future<List<Recording>> getRecordingsByStatus(RecordingStatus status) async {
    final isar = DatabaseService.instance;
    return isar.recordings
        .filter()
        .statusEqualTo(status)
        .sortByScheduledStartDesc()
        .findAll();
  }

  /// Get active recordings
  Future<List<Recording>> getActiveRecordings() async {
    return getRecordingsByStatus(RecordingStatus.recording);
  }

  /// Get scheduled recordings
  Future<List<Recording>> getScheduledRecordings() async {
    return getRecordingsByStatus(RecordingStatus.scheduled);
  }

  /// Get completed recordings
  Future<List<Recording>> getCompletedRecordings() async {
    return getRecordingsByStatus(RecordingStatus.completed);
  }

  /// Watch all recordings stream
  Stream<List<Recording>> watchRecordings() {
    final isar = DatabaseService.instance;
    return isar.recordings
        .where()
        .sortByScheduledStartDesc()
        .watch(fireImmediately: true);
  }

  /// Delete a recording
  Future<void> deleteRecording(int recordingId) async {
    final isar = DatabaseService.instance;

    final recording = await isar.recordings.get(recordingId);
    if (recording != null) {
      // Delete the file if it exists
      final file = File(recording.filePath);
      if (await file.exists()) {
        await file.delete();
        AppLogger.info('Deleted recording file: ${recording.filePath}');
      }

      // Delete from database
      await isar.writeTxn(() async {
        await isar.recordings.delete(recordingId);
      });

      AppLogger.info('Deleted recording: ${recording.title}');
    }
  }

  /// Get recording by ID
  Future<Recording?> getRecording(int id) async {
    final isar = DatabaseService.instance;
    return isar.recordings.get(id);
  }

  /// Check for recordings that should start now
  Future<List<Recording>> getRecordingsDueToStart() async {
    final now = DateTime.now();
    final isar = DatabaseService.instance;

    return isar.recordings
        .filter()
        .statusEqualTo(RecordingStatus.scheduled)
        .scheduledStartLessThan(now)
        .findAll();
  }
}
