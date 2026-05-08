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

      // Verify it runs
      final result = await Process.run(_ffmpegPath!, ['-version']);
      if (result.exitCode == 0) {
        final version = (result.stdout as String).split('\n').first;
        AppLogger.info('FfmpegTranscode: Ready — $version');
        _initialized = true;
        return true;
      } else {
        AppLogger.error('FfmpegTranscode: Binary failed: ${result.stderr}');
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
      _process!.exitCode.then((code) {
        if (code != 0) {
          AppLogger.error('FfmpegTranscode: Process exited with code $code');
        }
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

    // Start process on first call
    if (_process == null) {
      final started = await startProcess();
      if (!started) return Uint8List(0);
    }

    try {
      // Discard any leftover output from prior calls so the bytes we
      // return correspond only to this segment's input. Without this,
      // accumulated output across segment boundaries causes audio
      // payload from prior segments to be muxed against the current
      // segment's PTS — drifting past the Cast SDK's A/V sync
      // tolerance after ~2-3 segments and stalling playback.
      _outputBuffer.clear();

      // Write data to FFmpeg's stdin
      _process!.stdin.add(tsData);
      await _process!.stdin.flush();

      // Poll for stable output: bail when the buffer length stops
      // growing for 2 consecutive 50ms ticks (or after a 1s timeout
      // cap). Replaces a fixed 200ms sleep so fast streams return
      // earlier and slow streams have up to 1s of headroom.
      var lastLen = -1;
      for (var i = 0; i < 20; i++) {
        await Future.delayed(const Duration(milliseconds: 50));
        if (_outputBuffer.length == lastLen && lastLen > 0) break;
        lastLen = _outputBuffer.length;
      }

      // Collect whatever output has accumulated
      if (_outputBuffer.length > 0) {
        return _outputBuffer.takeBytes();
      }
      AppLogger.warning(
        'FfmpegTranscode: 0 bytes returned for ${tsData.length}-byte '
        'input segment after stability poll',
      );
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
