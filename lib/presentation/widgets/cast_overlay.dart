import 'package:flutter/material.dart';

import '../../domain/services/cast_types.dart';
import '../../l10n/app_localizations.dart';

/// Overlay shown in place of the video while casting to a Chromecast device.
///
/// Shared by the desktop player panel and the mobile fullscreen player so
/// both layouts present the same "Casting to X" state with a stop button.
class CastOverlay extends StatelessWidget {
  final String deviceName;
  final CastPlaybackState playbackState;
  final VoidCallback onStop;

  const CastOverlay({
    super.key,
    required this.deviceName,
    required this.playbackState,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Container(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cast_connected,
              color: Colors.blue,
              size: 64,
            ),
            const SizedBox(height: 16),
            Text(
              l10n.castingToDevice(deviceName),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              _playbackLabel(l10n, playbackState),
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: onStop,
              icon: const Icon(Icons.stop),
              label: Text(l10n.stopCasting),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade700,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _playbackLabel(AppLocalizations l10n, CastPlaybackState state) {
    switch (state) {
      case CastPlaybackState.playing:
        return l10n.castPlaying;
      case CastPlaybackState.buffering:
        return l10n.castBuffering;
      case CastPlaybackState.loading:
        return l10n.castLoading;
      case CastPlaybackState.paused:
        return l10n.castPaused;
      case CastPlaybackState.stopped:
        return l10n.castStopped;
      case CastPlaybackState.idle:
        return '';
    }
  }
}
