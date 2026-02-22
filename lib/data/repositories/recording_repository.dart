import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import '../datasources/local/database_service.dart';
import '../datasources/local/drift/app_database.dart';
import '../../core/utils/logger.dart';

class RecordingRepository {
  late String _recordingsDir;
  bool _initialized = false;

  AppDatabase get _db => DatabaseService.instance;

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

  String get recordingsDir {
    if (!_initialized) {
      throw StateError('RecordingRepository not initialized. Call initialize() first.');
    }
    return _recordingsDir;
  }

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

    final id = await _db.into(_db.recordings).insert(
      RecordingsCompanion.insert(
        channelId: channelId,
        title: title,
        filePath: filePath,
        scheduledStart: scheduledStart,
        scheduledEnd: scheduledEnd,
        status: RecordingStatus.scheduled,
        createdAt: DateTime.now(),
        epgProgramId: Value(epgProgramId),
      ),
    );

    final recording = await (_db.select(_db.recordings)..where((t) => t.id.equals(id))).getSingle();
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
  Future<void> updateStatus(
    int recordingId,
    RecordingStatus status, {
    String? errorMessage,
  }) async {
    final now = DateTime.now();

    await (_db.update(_db.recordings)..where((t) => t.id.equals(recordingId)))
        .write(RecordingsCompanion(
      status: Value(status),
      errorMessage: errorMessage != null ? Value(errorMessage) : const Value.absent(),
      actualStart: status == RecordingStatus.recording ? Value(now) : const Value.absent(),
      actualEnd: (status == RecordingStatus.completed || status == RecordingStatus.failed)
          ? Value(now)
          : const Value.absent(),
    ),);
  }

  /// Update recording file size
  Future<void> updateFileSize(int recordingId) async {
    final recording = await (_db.select(_db.recordings)..where((t) => t.id.equals(recordingId))).getSingleOrNull();
    if (recording == null) return;

    try {
      final file = File(recording.filePath);
      if (await file.exists()) {
        final fileSize = await file.length();
        final durationSeconds = recording.actualStart != null
            ? (recording.actualEnd ?? DateTime.now()).difference(recording.actualStart!).inSeconds
            : 0;

        await (_db.update(_db.recordings)..where((t) => t.id.equals(recordingId)))
            .write(RecordingsCompanion(
          fileSize: Value(fileSize),
          durationSeconds: Value(durationSeconds),
        ),);
      }
    } catch (e) {
      AppLogger.warning('Could not update file size for recording $recordingId: $e');
    }
  }

  /// Get all recordings
  Future<List<Recording>> getAllRecordings() async {
    return (_db.select(_db.recordings)
          ..orderBy([(t) => OrderingTerm.desc(t.scheduledStart)]))
        .get();
  }

  /// Get recordings by status
  Future<List<Recording>> getRecordingsByStatus(RecordingStatus status) async {
    return (_db.select(_db.recordings)
          ..where((t) => t.status.equals(status.name))
          ..orderBy([(t) => OrderingTerm.desc(t.scheduledStart)]))
        .get();
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
    return (_db.select(_db.recordings)
          ..orderBy([(t) => OrderingTerm.desc(t.scheduledStart)]))
        .watch();
  }

  /// Delete a recording
  Future<void> deleteRecording(int recordingId) async {
    final recording = await (_db.select(_db.recordings)..where((t) => t.id.equals(recordingId))).getSingleOrNull();
    if (recording != null) {
      // Delete the file if it exists (don't let file errors block DB cleanup)
      try {
        final file = File(recording.filePath);
        if (await file.exists()) {
          await file.delete();
          AppLogger.info('Deleted recording file: ${recording.filePath}');
        }
      } catch (e) {
        AppLogger.warning('Could not delete recording file: ${recording.filePath}: $e');
      }

      // Delete from database
      await (_db.delete(_db.recordings)..where((t) => t.id.equals(recordingId))).go();
      AppLogger.info('Deleted recording: ${recording.title}');
    }
  }

  /// Get recording by ID
  Future<Recording?> getRecording(int id) async {
    return (_db.select(_db.recordings)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  /// Check for recordings that should start now
  Future<List<Recording>> getRecordingsDueToStart() async {
    final now = DateTime.now();
    return (_db.select(_db.recordings)
          ..where((t) => t.status.equals(RecordingStatus.scheduled.name) & t.scheduledStart.isSmallerThanValue(now)))
        .get();
  }
}
