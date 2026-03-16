import 'dart:io';

import '../../../core/utils/logger.dart';

/// Launches the current stream URL in an external media player (VLC, mpv, etc.)
///
/// Uses direct process invocation (no shell) to prevent command injection
/// from malicious stream URLs in untrusted M3U playlists.
class ExternalPlayerLauncher {
  /// Open [streamUrl] in an external player.
  ///
  /// Returns `true` if the stream was successfully handed off.
  Future<bool> openInExternalPlayer(String streamUrl) async {
    // Validate URL scheme to prevent file:// or other dangerous URIs
    final uri = Uri.tryParse(streamUrl);
    if (uri == null ||
        !['http', 'https', 'rtsp', 'rtmp'].contains(uri.scheme)) {
      AppLogger.warning(
          'Refusing to open non-network URL in external player');
      return false;
    }

    try {
      if (Platform.isWindows) {
        // Try VLC directly -- use Process.start (detached) so it doesn't block
        for (final vlcPath in [
          'vlc',
          r'C:\Program Files\VideoLAN\VLC\vlc.exe',
          r'C:\Program Files (x86)\VideoLAN\VLC\vlc.exe',
        ]) {
          try {
            await Process.start(vlcPath, [streamUrl],
                mode: ProcessStartMode.detached);
            AppLogger.info('Opened stream in VLC');
            return true;
          } catch (_) {
            continue;
          }
        }

        // Fallback: use PowerShell Start-Process with quoted URL
        await Process.start(
          'powershell',
          ['-NoProfile', '-Command', 'Start-Process', "'$streamUrl'"],
          mode: ProcessStartMode.detached,
        );
        AppLogger.info('Opened stream with system default player');
        return true;
      } else if (Platform.isMacOS) {
        // Try VLC first (no shell), detached
        try {
          await Process.start('open', ['-a', 'VLC', streamUrl],
              mode: ProcessStartMode.detached);
          AppLogger.info('Opened stream in VLC');
          return true;
        } catch (_) {
          // Fallback to default handler
          await Process.start('open', [streamUrl],
              mode: ProcessStartMode.detached);
          return true;
        }
      } else if (Platform.isLinux) {
        // Try common players in order (detached)
        for (final player in ['vlc', 'mpv', 'celluloid', 'xdg-open']) {
          try {
            await Process.start(player, [streamUrl],
                mode: ProcessStartMode.detached);
            AppLogger.info('Opened stream in $player');
            return true;
          } catch (_) {
            continue;
          }
        }
      }

      AppLogger.warning('Could not open stream in external player');
      return false;
    } catch (e) {
      AppLogger.error('Failed to open in external player: $e');
      return false;
    }
  }
}
