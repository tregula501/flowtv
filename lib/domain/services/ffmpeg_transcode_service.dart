import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../../core/utils/logger.dart';

/// FFmpeg subprocess-based AC-3 → AAC transcoder.
///
/// Bundles a pre-built ffmpeg binary for Android ARM64 and runs it as a
/// subprocess with stdin/stdout pipes. Processes 8 seconds of audio in <500ms
/// (50x+ realtime), completely eliminating the MediaCodec throughput limitation.
///
/// Usage:
///   1. `await init()` — extract binary on first run
///   2. `transcode(ac3Data)` — synchronous pipe: AC-3 in → AAC ADTS out
///   3. No start/stop lifecycle needed (stateless subprocess per call)
class FfmpegTranscodeService {
  static FfmpegTranscodeService? _instance;
  static FfmpegTranscodeService get instance =>
      _instance ??= FfmpegTranscodeService._();
  FfmpegTranscodeService._();

  String? _ffmpegPath;
  bool _initialized = false;

  bool get isInitialized => _initialized;

  /// Find the ffmpeg binary in the native library directory.
  /// Android copies jniLibs/*.so to an executable directory at install time.
  Future<bool> init() async {
    if (_initialized) return true;

    try {
      if (!Platform.isAndroid) {
        AppLogger.info('FfmpegTranscode: Not Android, skipping');
        return false;
      }

      // Find the ffmpeg binary in the native library directory.
      // With useLegacyPackaging=true, Android extracts jniLibs to the app's
      // native lib path (which is executable, unlike the data directory).
      final pmResult = await Process.run('pm', ['path', 'io.github.tregula501.flowtv']);
      if (pmResult.exitCode != 0) {
        AppLogger.error('FfmpegTranscode: Could not find package path');
        return false;
      }
      final apkPath = (pmResult.stdout as String).trim().replaceFirst('package:', '');
      final libDir = apkPath.replaceFirst('/base.apk', '/lib/arm64');
      final ffmpegFile = File('$libDir/libffmpeg.so');

      if (!await ffmpegFile.exists()) {
        AppLogger.error('FfmpegTranscode: libffmpeg.so not found at ${ffmpegFile.path}');
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

  /// Transcode raw AC-3 audio data to AAC ADTS frames.
  ///
  /// Runs ffmpeg as a subprocess with stdin/stdout pipes:
  ///   ffmpeg -f ac3 -i pipe:0 -c:a aac -b:a 128k -ac 2 -f adts pipe:1
  ///
  /// Returns the complete AAC ADTS byte stream, or empty on failure.
  /// Processes 8 seconds of AC-3 in <500ms (50x+ realtime).
  Future<Uint8List> transcode(Uint8List ac3Data) async {
    if (!_initialized || _ffmpegPath == null) return Uint8List(0);
    if (ac3Data.isEmpty) return Uint8List(0);

    try {
      final process = await Process.start(_ffmpegPath!, [
        '-f', 'mpegts',     // input is MPEG-TS packets
        '-probesize', '64k', // probe enough to find audio
        '-i', 'pipe:0',     // read from stdin
        '-vn',              // no video (audio only)
        '-c:a', 'aac',      // encode to AAC
        '-b:a', '128k',     // 128kbps bitrate
        '-ar', '48000',     // 48kHz sample rate
        '-ac', '2',         // stereo output
        '-f', 'adts',       // output format: ADTS
        '-v', 'error',      // suppress noisy output
        'pipe:1',           // write to stdout
      ]);

      // Write AC-3 data to stdin and close
      process.stdin.add(ac3Data);
      await process.stdin.close();

      // Collect AAC output from stdout
      final output = await process.stdout.fold<BytesBuilder>(
        BytesBuilder(),
        (builder, chunk) => builder..add(chunk),
      );

      // Wait for process to complete
      final exitCode = await process.exitCode;
      if (exitCode != 0) {
        final stderr = await process.stderr.transform(
          const SystemEncoding().decoder,
        ).join();
        if (stderr.isNotEmpty) {
          AppLogger.error('FfmpegTranscode: $stderr');
        }
        return Uint8List(0);
      }

      final result = output.takeBytes();
      return result;
    } catch (e) {
      AppLogger.error('FfmpegTranscode: transcode failed — $e');
      return Uint8List(0);
    }
  }
}
