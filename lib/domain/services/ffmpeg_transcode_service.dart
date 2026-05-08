import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../../core/utils/logger.dart';

/// FFmpeg subprocess-based AC-3 → AAC transcoder.
///
/// Keeps a persistent FFmpeg process running with stdin/stdout pipes.
/// Audio data is written to stdin continuously; AAC ADTS frames are read
/// from stdout. Eliminates ~500ms process startup overhead per segment.
class FfmpegTranscodeService {
  static FfmpegTranscodeService? _instance;
  static FfmpegTranscodeService get instance =>
      _instance ??= FfmpegTranscodeService._();
  FfmpegTranscodeService._();

  String? _ffmpegPath;
  bool _initialized = false;
  Process? _process;
  // Diagnostics: surfaced when the persistent subprocess dies unexpectedly so
  // transcode() can log a single WARN per dead process rather than continuing
  // to write into a closed pipe. Set by the exit listener in startProcess().
  int? _processExitCode;
  final _outputBuffer = BytesBuilder();
  StreamSubscription<List<int>>? _stdoutSub;
  StreamSubscription<String>? _stderrSub;

  bool get isInitialized => _initialized;

  /// Find the ffmpeg binary in the native library directory.
  Future<bool> init() async {
    if (_initialized) return true;

    try {
      if (!Platform.isAndroid) {
        AppLogger.info('FfmpegTranscode: Not Android, skipping');
        return false;
      }

      final pmResult =
          await Process.run('pm', ['path', 'io.github.tregula501.flowtv']);
      if (pmResult.exitCode != 0) {
        AppLogger.error('FfmpegTranscode: Could not find package path');
        return false;
      }
      final apkPath =
          (pmResult.stdout as String).trim().replaceFirst('package:', '');
      final libDir = apkPath.replaceFirst('/base.apk', '/lib/arm64');
      final ffmpegFile = File('$libDir/libffmpeg.so');

      if (!await ffmpegFile.exists()) {
        AppLogger.error(
            'FfmpegTranscode: libffmpeg.so not found at ${ffmpegFile.path}');
        return false;
      }

      _ffmpegPath = ffmpegFile.path;

      // Verify it runs. Capture both stdout and stderr so binary-incompatibility
      // problems (wrong ARM variant, missing deps, etc.) are visible in logs
      // rather than silently failing init.
      try {
        final result = await Process.run(_ffmpegPath!, ['-version']);
        final stdoutText = (result.stdout as String);
        final stderrText = (result.stderr as String);
        if (result.exitCode == 0) {
          final version = stdoutText.split('\n').first;
          AppLogger.info('FfmpegTranscode: Ready — $version');
          _initialized = true;
          return true;
        } else {
          AppLogger.error(
            'FfmpegTranscode: Binary probe failed '
            '(path=$_ffmpegPath, exitCode=${result.exitCode}). '
            'stderr: $stderrText',
          );
          return false;
        }
      } on ProcessException catch (e) {
        AppLogger.error(
          'FfmpegTranscode: ProcessException running -version '
          '(path=$_ffmpegPath): $e',
        );
        return false;
      }
    } catch (e) {
      AppLogger.error('FfmpegTranscode: init failed — $e');
      return false;
    }
  }

  /// Start the persistent FFmpeg process.
  /// Reads MPEG-TS from stdin, outputs AAC ADTS to stdout continuously.
  Future<bool> startProcess() async {
    if (_process != null) return true;
    if (!_initialized || _ffmpegPath == null) return false;

    try {
      _process = await Process.start(_ffmpegPath!, [
        '-f', 'mpegts', // input is MPEG-TS packets
        '-probesize', '64k',
        '-i', 'pipe:0', // read from stdin
        '-vn', // no video
        '-c:a', 'aac',
        '-b:a', '128k',
        '-ar', '48000',
        '-ac', '2',
        '-f', 'adts', // output ADTS
        '-v', 'error',
        'pipe:1', // write to stdout
      ]);

      // Collect stdout output continuously into buffer
      _stdoutSub = _process!.stdout.listen((data) {
        _outputBuffer.add(data);
      });

      // Log stderr errors
      _stderrSub = _process!.stderr
          .transform(const SystemEncoding().decoder)
          .listen((data) {
        if (data.trim().isNotEmpty) {
          AppLogger.error('FfmpegTranscode: $data');
        }
      });

      // Monitor process exit
      _processExitCode = null;
      _process!.exitCode.then((code) {
        if (code != 0) {
          AppLogger.error('FfmpegTranscode: Process exited with code $code');
        }
        _processExitCode = code;
        _process = null;
      });

      AppLogger.info('FfmpegTranscode: Persistent process started');
      return true;
    } catch (e) {
      AppLogger.error('FfmpegTranscode: startProcess failed — $e');
      _process = null;
      return false;
    }
  }

  /// Write MPEG-TS audio data to the persistent process and collect
  /// whatever AAC output has accumulated.
  ///
  /// Returns the AAC ADTS bytes produced so far (may include output from
  /// data written in previous calls — this is fine since we parse frames).
  Future<Uint8List> transcode(Uint8List tsData) async {
    if (tsData.isEmpty) return Uint8List(0);

    // Diagnostics: detect a silently-dead persistent process before reusing it.
    // We do NOT auto-restart here — just surface the failure in logs so a
    // mid-stream FFmpeg crash is visible. The existing fallback path returns
    // empty data and the caller continues without transcoded audio.
    // _processExitCode is set by the exit listener in startProcess() the
    // moment the subprocess terminates, before _process is nulled out — so
    // checking it lets us distinguish "never started" from "died mid-stream".
    if (_processExitCode != null) {
      AppLogger.warning(
        'FfmpegTranscode: FFmpeg subprocess exited unexpectedly '
        '(code=$_processExitCode), will not transcode this segment',
      );
      _process = null;
      _processExitCode = null;
      return Uint8List(0);
    }

    // Start process on first call
    if (_process == null) {
      final started = await startProcess();
      if (!started) return Uint8List(0);
    }

    try {
      // Write data to FFmpeg's stdin
      _process!.stdin.add(tsData);
      await _process!.stdin.flush();

      // Give FFmpeg a moment to process and produce output
      // 200ms is enough for FFmpeg to process 8s of audio at 50x+ realtime
      await Future.delayed(const Duration(milliseconds: 200));

      // Collect whatever output has accumulated
      if (_outputBuffer.length > 0) {
        return _outputBuffer.takeBytes();
      }
      return Uint8List(0);
    } catch (e) {
      AppLogger.error('FfmpegTranscode: transcode failed — $e');
      // Process may have died — restart on next call
      await stopProcess();
      return Uint8List(0);
    }
  }

  /// Stop the persistent FFmpeg process.
  Future<void> stopProcess() async {
    _stdoutSub?.cancel();
    _stdoutSub = null;
    _stderrSub?.cancel();
    _stderrSub = null;
    _outputBuffer.clear();
    // Clear so a subsequent intentional restart isn't flagged as an unexpected
    // death by transcode()'s diagnostics check.
    _processExitCode = null;

    if (_process != null) {
      try {
        _process!.stdin.close();
      } catch (_) {}
      try {
        _process!.kill();
      } catch (_) {}
      _process = null;
    }
  }

  /// Full cleanup.
  Future<void> dispose() async {
    await stopProcess();
    _initialized = false;
    _ffmpegPath = null;
  }
}
