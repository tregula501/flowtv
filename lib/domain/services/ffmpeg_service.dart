import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/utils/logger.dart';

/// FFmpeg recording session
class RecordingSession {
  final int id;
  final String streamUrl;
  final String outputPath;
  final DateTime startTime;
  Process? _process;
  bool _isStopped = false;

  RecordingSession({
    required this.id,
    required this.streamUrl,
    required this.outputPath,
    required this.startTime,
  });

  bool get isActive => _process != null && !_isStopped;
}

/// FFmpeg service for stream recording
/// Uses Process on desktop, ffmpeg_kit on mobile
class FFmpegService {
  static FFmpegService? _instance;
  static FFmpegService get instance => _instance ??= FFmpegService._();

  FFmpegService._();

  final Map<int, RecordingSession> _sessions = {};
  String? _ffmpegPath;
  bool _initialized = false;

  /// Initialize the service and find FFmpeg
  Future<bool> initialize() async {
    if (_initialized) return _ffmpegPath != null;

    _ffmpegPath = await _findFFmpeg();
    _initialized = true;

    if (_ffmpegPath != null) {
      AppLogger.info('FFmpeg found at: $_ffmpegPath');
      return true;
    } else {
      AppLogger.warning('FFmpeg not found. Recording will not work.');
      return false;
    }
  }

  /// Check if FFmpeg is available
  bool get isAvailable => _ffmpegPath != null;

  /// Find FFmpeg executable
  Future<String?> _findFFmpeg() async {
    // Check common locations
    final possiblePaths = <String>[];

    if (Platform.isWindows) {
      // Check app directory first
      final appDir = File(Platform.resolvedExecutable).parent.path;
      possiblePaths.addAll([
        p.join(appDir, 'ffmpeg.exe'),
        p.join(appDir, 'ffmpeg', 'ffmpeg.exe'),
        p.join(appDir, 'bin', 'ffmpeg.exe'),
        'ffmpeg.exe', // System PATH
        r'C:\ffmpeg\bin\ffmpeg.exe',
        r'C:\Program Files\ffmpeg\bin\ffmpeg.exe',
        r'C:\Program Files (x86)\ffmpeg\bin\ffmpeg.exe',
      ]);
    } else if (Platform.isMacOS || Platform.isLinux) {
      possiblePaths.addAll([
        '/usr/local/bin/ffmpeg',
        '/usr/bin/ffmpeg',
        '/opt/homebrew/bin/ffmpeg',
        'ffmpeg', // System PATH
      ]);
    }

    // Try each path
    for (final path in possiblePaths) {
      try {
        final result = await Process.run(
          path,
          ['-version'],
          runInShell: true,
        );
        if (result.exitCode == 0) {
          return path;
        }
      } catch (_) {
        // Try next path
      }
    }

    // Try system PATH
    try {
      final result = await Process.run(
        'ffmpeg',
        ['-version'],
        runInShell: Platform.isWindows,
      );
      if (result.exitCode == 0) {
        return 'ffmpeg';
      }
    } catch (_) {
      // FFmpeg not found
    }

    return null;
  }

  /// Start recording a stream
  Future<bool> startRecording({
    required int recordingId,
    required String streamUrl,
    required String outputPath,
    Duration? maxDuration,
  }) async {
    if (!_initialized) {
      await initialize();
    }

    if (_ffmpegPath == null) {
      AppLogger.error('FFmpeg not available for recording');
      return false;
    }

    // Check if already recording this ID
    if (_sessions.containsKey(recordingId)) {
      AppLogger.warning('Recording $recordingId already in progress');
      return false;
    }

    try {
      // Ensure output directory exists
      final outputDir = Directory(p.dirname(outputPath));
      if (!await outputDir.exists()) {
        await outputDir.create(recursive: true);
      }

      // Build FFmpeg arguments
      final args = <String>[
        '-y', // Overwrite output file
        '-i', streamUrl, // Input stream
        '-c', 'copy', // Copy codec (no re-encoding for speed)
        '-bsf:a', 'aac_adtstoasc', // Fix AAC in TS container
      ];

      // Add duration limit if specified
      if (maxDuration != null) {
        args.addAll(['-t', maxDuration.inSeconds.toString()]);
      }

      // Add output file
      args.add(outputPath);

      AppLogger.info('Starting FFmpeg recording: $_ffmpegPath ${args.join(' ')}');

      // Start FFmpeg process
      final process = await Process.start(
        _ffmpegPath!,
        args,
        runInShell: Platform.isWindows,
      );

      // Create session
      final session = RecordingSession(
        id: recordingId,
        streamUrl: streamUrl,
        outputPath: outputPath,
        startTime: DateTime.now(),
      );
      session._process = process;
      _sessions[recordingId] = session;

      // Log FFmpeg output
      process.stderr.transform(const SystemEncoding().decoder).listen((data) {
        // FFmpeg outputs to stderr even for normal operation
        if (data.contains('Error') || data.contains('error')) {
          AppLogger.error('FFmpeg error: $data');
        } else {
          AppLogger.debug('FFmpeg: $data');
        }
      });

      // Handle process exit
      process.exitCode.then((exitCode) {
        AppLogger.info('FFmpeg recording $recordingId ended with code $exitCode');
        _sessions.remove(recordingId);
      });

      AppLogger.info('Recording started: $outputPath');
      return true;
    } catch (e, st) {
      AppLogger.error('Failed to start recording', e, st);
      return false;
    }
  }

  /// Stop a recording
  Future<bool> stopRecording(int recordingId) async {
    final session = _sessions[recordingId];
    if (session == null) {
      AppLogger.warning('No recording session found for ID $recordingId');
      return false;
    }

    try {
      session._isStopped = true;

      // Send 'q' to FFmpeg to gracefully stop
      if (session._process != null) {
        if (Platform.isWindows) {
          // On Windows, kill the process (graceful stop is harder)
          session._process!.kill(ProcessSignal.sigint);
        } else {
          // On Unix, send 'q' to stdin for graceful stop
          session._process!.stdin.write('q');
          await session._process!.stdin.flush();
        }

        // Wait for process to exit (with timeout)
        try {
          await session._process!.exitCode.timeout(
            const Duration(seconds: 5),
            onTimeout: () {
              session._process!.kill();
              return -1;
            },
          );
        } catch (_) {
          session._process!.kill();
        }
      }

      _sessions.remove(recordingId);
      AppLogger.info('Recording stopped: ${session.outputPath}');
      return true;
    } catch (e, st) {
      AppLogger.error('Failed to stop recording', e, st);
      return false;
    }
  }

  /// Check if a recording is active
  bool isRecording(int recordingId) {
    return _sessions[recordingId]?.isActive ?? false;
  }

  /// Get recording duration
  Duration? getRecordingDuration(int recordingId) {
    final session = _sessions[recordingId];
    if (session == null) return null;
    return DateTime.now().difference(session.startTime);
  }

  /// Stop all recordings
  Future<void> stopAllRecordings() async {
    final ids = _sessions.keys.toList();
    for (final id in ids) {
      await stopRecording(id);
    }
  }

  /// Get output file size
  Future<int> getFileSize(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        return await file.length();
      }
    } catch (_) {}
    return 0;
  }
}
