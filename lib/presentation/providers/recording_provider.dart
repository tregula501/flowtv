import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/datasources/local/database_service.dart';
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
  final manager = RecordingManager(ref);
  ref.onDispose(() => manager.dispose());
  return manager;
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

  /// Initialize FFmpeg service (desktop only)
  Future<void> _initializeFFmpeg() async {
    // Skip FFmpeg initialization on mobile — recording is desktop-only
    if (Platform.isAndroid || Platform.isIOS) return;

    final ffmpeg = _ref.read(ffmpegServiceProvider);
    final available = await ffmpeg.initialize();
    if (!available) {
      AppLogger.warning(
        'FFmpeg not found. Recording requires FFmpeg to be installed. '
        'Download from https://ffmpeg.org/download.html',
      );
    }
  }

  /// Start the scheduler to check for recordings that need to start (desktop only)
  void _startScheduler() {
    // Don't run the periodic scheduler on mobile — recording is not supported
    if (Platform.isAndroid || Platform.isIOS) return;

    _schedulerTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _checkScheduledRecordings(),
    );
  }

  /// Check and start any scheduled recordings that are due
  Future<void> _checkScheduledRecordings() async {
    // Scheduled recordings are not supported on mobile (no FFmpeg)
    if (Platform.isAndroid || Platform.isIOS) return;

    final repo = _ref.read(recordingRepositoryProvider);
    final dueRecordings = await repo.getRecordingsDueToStart();

    for (final recording in dueRecordings) {
      // Skip if already being recorded
      if (isRecording(recording.channelId)) continue;

      AppLogger.info('Starting scheduled recording: ${recording.title}');

      try {
        // Look up the channel
        final db = DatabaseService.instance;
        final channel = await (db.select(db.channels)
              ..where((t) => t.id.equals(recording.channelId)))
            .getSingleOrNull();

        if (channel == null) {
          AppLogger.warning('Channel ${recording.channelId} not found for scheduled recording');
          await repo.updateStatus(
            recording.id,
            RecordingStatus.failed,
            errorMessage: 'Channel not found',
          );
          continue;
        }

        // Calculate remaining duration
        final now = DateTime.now();
        final remainingDuration = recording.scheduledEnd.difference(now);

        if (remainingDuration.isNegative) {
          AppLogger.warning('Scheduled recording ${recording.title} end time has passed');
          await repo.updateStatus(
            recording.id,
            RecordingStatus.failed,
            errorMessage: 'Recording end time has passed',
          );
          continue;
        }

        // Start FFmpeg recording
        final ffmpeg = _ref.read(ffmpegServiceProvider);
        if (!ffmpeg.isAvailable) {
          await repo.updateStatus(
            recording.id,
            RecordingStatus.failed,
            errorMessage: 'FFmpeg not available',
          );
          continue;
        }

        final success = await ffmpeg.startRecording(
          recordingId: recording.id,
          streamUrl: channel.streamUrl,
          outputPath: recording.filePath,
          maxDuration: remainingDuration,
        );

        if (!success) {
          await repo.updateStatus(
            recording.id,
            RecordingStatus.failed,
            errorMessage: 'FFmpeg failed to start',
          );
          continue;
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
            final elapsed = ffmpeg.getRecordingDuration(recording.id);
            if (elapsed != null && elapsed >= remainingDuration) {
              AppLogger.info('Scheduled recording duration reached: ${recording.title}');
              await stopRecording(recording.channelId);
            }
          },
        );

        _activeRecordings[recording.channelId] = ActiveRecordingState(
          channelId: recording.channelId,
          recording: recording,
          updateTimer: updateTimer,
        );

        AppLogger.info('Started scheduled recording: ${recording.title}');
      } catch (e, st) {
        AppLogger.error('Failed to start scheduled recording: ${recording.title}', e, st);
        await repo.updateStatus(
          recording.id,
          RecordingStatus.failed,
          errorMessage: e.toString(),
        );
      }
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
    // Recording requires FFmpeg via Process.start(), which is only available on desktop
    if (Platform.isAndroid || Platform.isIOS) {
      AppLogger.warning('Recording is not supported on mobile platforms');
      return null;
    }

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
            await stopRecording(channel.id);
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
    // Stop all active FFmpeg recordings before clearing
    final ffmpeg = _ref.read(ffmpegServiceProvider);
    for (final entry in _activeRecordings.entries) {
      entry.value.updateTimer?.cancel();
      try {
        ffmpeg.stopRecording(entry.value.recording.id);
      } catch (e) {
        AppLogger.warning('Failed to stop recording ${entry.key} during dispose: $e');
      }
    }
    _activeRecordings.clear();
  }
}
