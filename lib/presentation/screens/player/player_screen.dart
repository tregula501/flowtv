import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../../core/themes/motion.dart';
import '../../../l10n/app_localizations.dart';
import '../../../domain/services/cast_types.dart';
import '../../providers/cast_provider.dart';
import '../../providers/channel_provider.dart';
import '../../providers/player_provider.dart';
import '../../widgets/cast_device_sheet.dart';
import '../../widgets/video_player_controls.dart';

class PlayerScreen extends ConsumerWidget {
  const PlayerScreen({super.key});

  static Widget _buildVideoWithAspectRatio(
    VideoController controller,
    AspectRatioMode mode,
  ) {
    final video = Video(
      controller: controller,
      controls: NoVideoControls,
      fit: mode == AspectRatioMode.fill ? BoxFit.cover : BoxFit.contain,
    );

    final aspectRatio = mode.aspectRatio;
    if (aspectRatio != null) {
      return AspectRatio(
        aspectRatio: aspectRatio,
        child: video,
      );
    }

    return video;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final aspectRatioMode = ref.watch(playerControllerProvider.select((s) => s.aspectRatioMode));
    final playerController = ref.read(playerControllerProvider.notifier);
    final currentChannel = ref.watch(currentChannelProvider);

    if (currentChannel == null) {
      return Container(
        color: Colors.black,
        child: Center(
          child: Text(
            l10n.selectChannel,
            style: const TextStyle(color: Colors.white54),
          ),
        ),
      );
    }

    return Container(
      color: Colors.black,
      child: Column(
        children: [
          // Channel info header
          Container(
            padding: const EdgeInsets.all(12),
            color: Colors.black87,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        currentChannel.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (currentChannel.group != null)
                        Text(
                          currentChannel.group!,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ),
                // Chromecast button (only shown when supported, i.e. Android)
                Consumer(
                  builder: (context, ref, _) {
                    final isSupported = ref.watch(castControllerProvider.select((s) => s.isSupported));
                    final isConnected = ref.watch(castControllerProvider.select((s) => s.isConnected));
                    if (!isSupported) return const SizedBox.shrink();
                    return IconButton(
                      icon: Icon(
                        isConnected
                            ? Icons.cast_connected
                            : Icons.cast,
                        color: isConnected
                            ? Colors.blue
                            : Colors.white70,
                        size: 20,
                      ),
                      tooltip: l10n.cast,
                      onPressed: () =>
                          showCastSheet(context, ref, currentChannel),
                    );
                  },
                ),

                // PiP button (desktop only — uses window_manager)
                if (!Platform.isAndroid && !Platform.isIOS)
                  IconButton(
                    icon: const Icon(Icons.picture_in_picture, color: Colors.white70, size: 20),
                    tooltip: l10n.pictureInPicture,
                    onPressed: () => playerController.togglePiPMode(),
                  ),

                // Fullscreen button
                IconButton(
                  icon: const Icon(Icons.fullscreen, color: Colors.white70, size: 20),
                  tooltip: l10n.fullscreen,
                  onPressed: () => playerController.toggleFullscreen(),
                ),

                // Open in external player button (VLC) — desktop only
                if (!Platform.isAndroid && !Platform.isIOS)
                  IconButton(
                    icon: const Icon(Icons.launch, color: Colors.white70, size: 20),
                    tooltip: l10n.openExternalPlayer,
                    onPressed: () async {
                      final success = await playerController.openInExternalPlayer();
                      if (!success && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(l10n.externalPlayerError),
                            duration: const Duration(seconds: 3),
                          ),
                        );
                      }
                    },
                  ),

                // Close button
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white70),
                  tooltip: l10n.closePlayer,
                  onPressed: () {
                    ref.read(currentChannelProvider.notifier).select(null);
                    playerController.stop();
                  },
                ),
              ],
            ),
          ),

          // Video player / Cast overlay
          Expanded(
            child: Consumer(
              builder: (context, ref, _) {
                final castState = ref.watch(castControllerProvider);
                final isCasting = castState.isConnected &&
                    castState.playbackState != CastPlaybackState.idle;

                if (isCasting) {
                  return _CastOverlay(
                    deviceName: castState.connectedDevice?.name ?? '',
                    playbackState: castState.playbackState,
                    onStop: () async {
                      await ref
                          .read(castControllerProvider.notifier)
                          .disconnect();
                    },
                  );
                }

                final isPrebuffering = ref.watch(playerControllerProvider.select((s) => s.isPrebuffering));
                final isReconnecting = ref.watch(playerControllerProvider.select((s) => s.isReconnecting));
                final isBuffering = ref.watch(playerControllerProvider.select((s) => s.isBuffering));
                final error = ref.watch(playerControllerProvider.select((s) => s.error));
                final retryAttempt = ref.watch(playerControllerProvider.select((s) => s.retryAttempt));
                final maxRetries = ref.watch(playerControllerProvider.select((s) => s.maxRetries));
                final bufferedDuration = ref.watch(playerControllerProvider.select((s) => s.bufferedDuration));
                final bufferSize = ref.watch(playerControllerProvider.select((s) => s.bufferSize));

                // Status overlay (prebuffering / reconnecting / buffering),
                // built as a single keyed child so AnimatedSwitcher can cross-fade
                // between states. These are sibling overlays ABOVE the Video — the
                // Video widget itself is never wrapped or rebuilt.
                final Widget statusOverlay;
                if (isPrebuffering) {
                  statusOverlay = Center(
                    key: const ValueKey('prebuffer'),
                    child: Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(
                            color: Colors.white,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            l10n.prebuffering,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${bufferedDuration.inSeconds}s / ${bufferSize.durationSeconds}s',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: 150,
                            child: LinearProgressIndicator(
                              value: bufferSize.durationSeconds > 0
                                  ? (bufferedDuration.inMilliseconds /
                                          (bufferSize.durationSeconds * 1000))
                                      .clamp(0.0, 1.0)
                                  : 0.0,
                              backgroundColor: Colors.white24,
                              valueColor: const AlwaysStoppedAnimation<Color>(Colors.blue),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                } else if (isReconnecting) {
                  statusOverlay = Center(
                    key: const ValueKey('reconnect'),
                    child: Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(
                            color: Colors.orange,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            l10n.reconnecting,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            l10n.retryAttempt(retryAttempt, maxRetries),
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                } else if (isBuffering) {
                  statusOverlay = const Center(
                    key: ValueKey('buffer'),
                    child: CircularProgressIndicator(
                      color: Colors.white,
                    ),
                  );
                } else {
                  statusOverlay = const SizedBox.shrink(key: ValueKey('none'));
                }

                // Error overlay (only shown when not reconnecting), keyed for the
                // same cross-fade treatment.
                final Widget errorOverlay = (error != null && !isReconnecting)
                    ? Center(
                        key: const ValueKey('error'),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          margin: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.8),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.error_outline,
                                color: Colors.white,
                                size: 48,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                l10n.playbackError,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(color: Colors.white),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                error,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 12),
                              ElevatedButton(
                                onPressed: () {
                                  ref.read(playerControllerProvider.notifier).playChannel(currentChannel);
                                },
                                child: Text(l10n.retry),
                              ),
                            ],
                          ),
                        ),
                      )
                    : const SizedBox.shrink(key: ValueKey('noerror'));

                return Stack(
                  children: [
                    // Video with aspect ratio control
                    Center(
                      child: _buildVideoWithAspectRatio(
                        playerController.videoController,
                        aspectRatioMode,
                      ),
                    ),

                    // Buffering / reconnecting / prebuffering — cross-faded
                    AnimatedSwitcher(
                      duration: MotionTokens.base,
                      child: statusOverlay,
                    ),

                    // Error message — cross-faded
                    AnimatedSwitcher(
                      duration: MotionTokens.base,
                      child: errorOverlay,
                    ),

                    // Controls overlay
                    const Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: VideoPlayerControls(),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Overlay shown when casting to a Chromecast device.
class _CastOverlay extends StatelessWidget {
  final String deviceName;
  final CastPlaybackState playbackState;
  final VoidCallback onStop;

  const _CastOverlay({
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
