import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import '../../data/datasources/local/drift/app_database.dart' show Recording, Channel, RecordingStatus;
import '../../data/repositories/recording_repository.dart';
import '../../core/utils/logger.dart';

/// Recording repository provider
final recordingRepositoryProvider = Provider<RecordingRepository>((ref) {
  return RecordingRepository();
});

/// All recordings stream
final recordingsProvider = StreamProvider<List<Recording>>((ref) {
  final repo = ref.watch(recordingRepositoryProvider);
  return repo.watchRecordings();
});

/// Active recordings
final activeRecordingsProvider = Provider<List<Recording>>((ref) {
  final recordingsAsync = ref.watch(recordingsProvider);
  return recordingsAsync.whenOrNull(
        data: (recordings) =>
            recordings.where((r) => r.status == RecordingStatus.recording).toList(),
      ) ??
      [];
});

/// Scheduled recordings
final scheduledRecordingsProvider = Provider<List<Recording>>((ref) {
  final recordingsAsync = ref.watch(recordingsProvider);
  return recordingsAsync.whenOrNull(
        data: (recordings) =>
            recordings.where((r) => r.status == RecordingStatus.scheduled).toList(),
      ) ??
      [];
});

/// Completed recordings
final completedRecordingsProvider = Provider<List<Recording>>((ref) {
  final recordingsAsync = ref.watch(recordingsProvider);
  return recordingsAsync.whenOrNull(
        data: (recordings) =>
            recordings.where((r) => r.status == RecordingStatus.completed).toList(),
      ) ??
      [];
});

/// Recording manager provider
final recordingManagerProvider = Provider<RecordingManager>((ref) {
  return RecordingManager(ref);
});

/// Active recording state for a channel
class ActiveRecordingState {
  final int channelId;
  final Recording recording;
  final Player player;
  final IOSink? fileSink;
  final Timer? updateTimer;

  ActiveRecordingState({
    required this.channelId,
    required this.recording,
    required this.player,
    this.fileSink,
    this.updateTimer,
  });
}

class RecordingManager {
  final Ref _ref;
  final Map<int, ActiveRecordingState> _activeRecordings = {};
  Timer? _schedulerTimer;

  RecordingManager(this._ref) {
    _startScheduler();
  }

  /// Start the scheduler to check for recordings that need to start
  void _startScheduler() {
    _schedulerTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _checkScheduledRecordings(),
    );
  }

  /// Check and start any scheduled recordings that are due
  Future<void> _checkScheduledRecordings() async {
    final repo = _ref.read(recordingRepositoryProvider);
    final dueRecordings = await repo.getRecordingsDueToStart();

    for (final recording in dueRecordings) {
      // Get channel info
      AppLogger.info('Starting scheduled recording: ${recording.title}');
      // For scheduled recordings, we'd need to get the channel and start
      // This is a placeholder - full implementation would need channel lookup
    }
  }

  /// Check if a channel is currently being recorded
  bool isRecording(int channelId) {
    return _activeRecordings.containsKey(channelId);
  }

  /// Get active recording for a channel
  Recording? getActiveRecording(int channelId) {
    return _activeRecordings[channelId]?.recording;
  }

  /// Start instant recording for a channel
  Future<Recording?> startRecording(
    Channel channel, {
    Duration duration = const Duration(hours: 1),
  }) async {
    if (isRecording(channel.id)) {
      AppLogger.warning('Already recording channel: ${channel.name}');
      return _activeRecordings[channel.id]?.recording;
    }

    try {
      final repo = _ref.read(recordingRepositoryProvider);
      await repo.initialize();

      // Create recording entry
      final recording = await repo.startInstantRecording(
        channel: channel,
        duration: duration,
      );

      // Create player for recording
      final player = Player();

      // Update status to recording
      await repo.updateStatus(recording.id, RecordingStatus.recording);

      // Create file for writing
      final file = File(recording.filePath);
      final sink = file.openWrite();

      // Start periodic file size update
      final updateTimer = Timer.periodic(
        const Duration(seconds: 10),
        (_) => repo.updateFileSize(recording.id),
      );

      // Store active recording state
      _activeRecordings[channel.id] = ActiveRecordingState(
        channelId: channel.id,
        recording: recording,
        player: player,
        fileSink: sink,
        updateTimer: updateTimer,
      );

      // Start playback (this captures the stream)
      // Note: media_kit doesn't have direct stream recording capability
      // In a full implementation, we'd use FFmpeg for recording
      await player.open(Media(channel.streamUrl));

      AppLogger.info('Started recording: ${channel.name} to ${recording.filePath}');
      return recording;
    } catch (e) {
      AppLogger.error('Failed to start recording: $e');
      return null;
    }
  }

  /// Stop recording for a channel
  Future<void> stopRecording(int channelId) async {
    final state = _activeRecordings[channelId];
    if (state == null) {
      AppLogger.warning('No active recording for channel $channelId');
      return;
    }

    try {
      // Stop update timer
      state.updateTimer?.cancel();

      // Stop player
      await state.player.stop();
      await state.player.dispose();

      // Close file sink
      await state.fileSink?.close();

      // Update recording status
      final repo = _ref.read(recordingRepositoryProvider);
      await repo.updateStatus(state.recording.id, RecordingStatus.completed);
      await repo.updateFileSize(state.recording.id);

      // Remove from active recordings
      _activeRecordings.remove(channelId);

      AppLogger.info('Stopped recording: ${state.recording.title}');
    } catch (e) {
      AppLogger.error('Error stopping recording: $e');

      // Mark as failed
      final repo = _ref.read(recordingRepositoryProvider);
      await repo.updateStatus(
        state.recording.id,
        RecordingStatus.failed,
        errorMessage: e.toString(),
      );
    }
  }

  /// Delete a recording
  Future<void> deleteRecording(int recordingId) async {
    final repo = _ref.read(recordingRepositoryProvider);
    await repo.deleteRecording(recordingId);
  }

  /// Play a recorded file
  String? getRecordingPlaybackUrl(Recording recording) {
    final file = File(recording.filePath);
    if (file.existsSync()) {
      return recording.filePath;
    }
    return null;
  }

  void dispose() {
    _schedulerTimer?.cancel();
    for (final state in _activeRecordings.values) {
      state.updateTimer?.cancel();
      state.player.dispose();
      state.fileSink?.close();
    }
    _activeRecordings.clear();
  }
}
