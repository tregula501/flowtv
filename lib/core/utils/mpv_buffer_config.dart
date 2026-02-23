// ignore: implementation_imports
import 'package:media_kit/src/player/native/player/player.dart' as native;
import 'package:media_kit/media_kit.dart';

import '../../presentation/providers/player_provider.dart' show BufferSize, BufferSizeExtension;
import 'logger.dart';

/// Apply MPV-specific buffer settings for stable live IPTV streaming.
/// Shared between the main player and multi-view players.
Future<void> applyMpvBufferSettings(
  Player player,
  BufferSize bufferSize, {
  String? logPrefix,
}) async {
  try {
    if (player.platform is native.NativePlayer) {
      final nativePlayer = player.platform as native.NativePlayer;
      final bufferSecs = bufferSize.durationSeconds;
      final minResumeBuffer = bufferSize.minBufferBeforeResume;
      final bufferBytes = bufferSecs * 4 * 1024 * 1024;

      // Core cache settings
      await nativePlayer.setProperty('cache', 'yes');
      await nativePlayer.setProperty('cache-secs', bufferSecs.toString());

      // Network timeout settings
      await nativePlayer.setProperty('network-timeout', '30');
      await nativePlayer.setProperty('stream-lavf-o', 'reconnect=1,reconnect_streamed=1,reconnect_delay_max=5');

      // Demuxer buffer settings
      await nativePlayer.setProperty('demuxer-max-bytes', bufferBytes.toString());
      await nativePlayer.setProperty('demuxer-max-back-bytes', (bufferBytes ~/ 2).toString());
      await nativePlayer.setProperty('demuxer-readahead-secs', bufferSecs.toString());

      // Cache pause/resume settings
      await nativePlayer.setProperty('cache-pause', 'yes');
      await nativePlayer.setProperty('cache-pause-initial', 'yes');
      await nativePlayer.setProperty('cache-pause-wait', minResumeBuffer.toString());

      if (bufferSecs > 1) {
        await nativePlayer.setProperty('demuxer-cache-wait', 'yes');
      }

      // HLS optimizations
      await nativePlayer.setProperty('hls-bitrate', 'max');
      await nativePlayer.setProperty('demuxer-lavf-o', 'live_start_index=-3');

      // Stability settings
      await nativePlayer.setProperty('force-seekable', 'yes');
      await nativePlayer.setProperty('hr-seek', 'yes');

      final prefix = logPrefix != null ? '$logPrefix: ' : '';
      AppLogger.info(
        '${prefix}Applied MPV buffer settings: cache-secs=$bufferSecs, '
        'buffer=${bufferBytes ~/ 1024 ~/ 1024}MB, '
        'cache-pause-wait=$minResumeBuffer, '
        'network-timeout=30s',
      );
    }
  } catch (e) {
    final prefix = logPrefix != null ? '$logPrefix: ' : '';
    AppLogger.warning('${prefix}Could not apply MPV buffer settings: $e');
  }
}
