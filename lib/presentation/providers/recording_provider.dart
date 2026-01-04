import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/datasources/local/drift/app_database.dart'
    show Recording, Channel, RecordingStatus;
import '../../data/repositories/recording_repository.dart';
import '../../domain/services/ffmpeg_service.dart';
import '../../core/utils/logger.dart';

/// Recording repository provider
final recordingRepositoryProvider = Provider<RecordingRepository>((ref) {
  return RecordingRepository();
});

/// FFmpeg service provider
final ffmpegServiceProvider = Provider<FFmpegService>((ref) {
  return FFmpegService.instance;
});

/// FFmpeg availability provider
final ffmpegAvailableProvider = FutureProvider<bool>((ref) async {
  final service = ref.watch(ffmpegServiceProvider);
  return service.initialize();
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
  final Timer? updateTimer;

  ActiveRecordingState({
    required this.channelId,
    required this.recording,
    this.updateTimer,
  });
}

class RecordingManager {
  final Ref _ref;
  final Map<int, ActiveRecordingState> _activeRecordings = {};
  Timer? _schedulerTimer;

  RecordingManager(this._ref) {
    _startScheduler();
    _initializeFFmpeg();
  }

  /// Initialize FFmpeg service
  Future<void> _initializeFFmpeg() async {
    final ffmpeg = _ref.read(ffmpegServiceProvider);
    final available = await ffmpeg.initialize();
    if (!available) {
      AppLogger.warning(
        'FFmpeg not found. Recording requires FFmpeg to be installed. '
        'Download from https://ffmpeg.org/download.html',
      );
    }
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

  /// Check if FFmpeg is available for recording
  bool get isFFmpegAvailable {
    final ffmpeg = _ref.read(ffmpegServiceProvider);
    return ffmpeg.isAvailable;
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

    final ffmpeg = _ref.read(ffmpegServiceProvider);

    // Check FFmpeg availability
    if (!ffmpeg.isAvailable) {
      await ffmpeg.initialize();
      if (!ffmpeg.isAvailable) {
        AppLogger.error(
          'Cannot start recording: FFmpeg not available. '
          'Please install FFmpeg and ensure it is in your PATH.',
        );
        return null;
      }
    }

    try {
      final repo = _ref.read(recordingRepositoryProvider);
      await repo.initialize();

      // Create recording entry in database
      final recording = await repo.startInstantRecording(
        channel: channel,
        duration: duration,
      );

      // Start FFmpeg recording
      final success = await ffmpeg.startRecording(
        recordingId: recording.id,
        streamUrl: channel.streamUrl,
        outputPath: recording.filePath,
        maxDuration: duration,
      );

      if (!success) {
        AppLogger.error('FFmpeg failed to start recording');
        await repo.updateStatus(
          recording.id,
          RecordingStatus.failed,
          errorMessage: 'FFmpeg failed to start',
        );
        return null;
      }

      // Update status to recording
      await repo.updateStatus(recording.id, RecordingStatus.recording);

      // Start periodic file size update
      final updateTimer = Timer.periodic(
        const Duration(seconds: 10),
        (_) async {
          final size = await ffmpeg.getFileSize(recording.filePath);
          if (size > 0) {
            await repo.updateFileSize(recording.id);
          }

          // Check if recording should auto-stop
          final elapsed = ffmpeg.getRecordingDuration(recording.id);
          if (elapsed != null && elapsed >= duration) {
            AppLogger.info('Recording duration reached, stopping: ${channel.name}');
            stopRecording(channel.id);
          }
        },
      );

      // Store active recording state
      _activeRecordings[channel.id] = ActiveRecordingState(
        channelId: channel.id,
        recording: recording,
        updateTimer: updateTimer,
      );

      AppLogger.info('Started recording: ${channel.name} to ${recording.filePath}');
      return recording;
    } catch (e, st) {
      AppLogger.error('Failed to start recording', e, st);
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

      // Stop FFmpeg recording
      final ffmpeg = _ref.read(ffmpegServiceProvider);
      await ffmpeg.stopRecording(state.recording.id);

      // Update recording status
      final repo = _ref.read(recordingRepositoryProvider);
      await repo.updateStatus(state.recording.id, RecordingStatus.completed);
      await repo.updateFileSize(state.recording.id);

      // Remove from active recordings
      _activeRecordings.remove(channelId);

      AppLogger.info('Stopped recording: ${state.recording.title}');
    } catch (e, st) {
      AppLogger.error('Error stopping recording', e, st);

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

  /// Play a recorded file - returns file path if exists
  String? getRecordingPlaybackUrl(Recording recording) {
    final file = File(recording.filePath);
    if (file.existsSync()) {
      return recording.filePath;
    }
    return null;
  }

  /// Get recording duration for active recording
  Duration? getRecordingDuration(int channelId) {
    final state = _activeRecordings[channelId];
    if (state == null) return null;

    final ffmpeg = _ref.read(ffmpegServiceProvider);
    return ffmpeg.getRecordingDuration(state.recording.id);
  }

  void dispose() {
    _schedulerTimer?.cancel();
    for (final state in _activeRecordings.values) {
      state.updateTimer?.cancel();
    }
    _activeRecordings.clear();
  }
}
