import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../../l10n/app_localizations.dart';
import '../../providers/channel_provider.dart';
import '../../providers/player_provider.dart';
import '../../widgets/video_player_controls.dart';

class FullscreenPlayerScreen extends ConsumerStatefulWidget {
  const FullscreenPlayerScreen({super.key});

  @override
  ConsumerState<FullscreenPlayerScreen> createState() =>
      _FullscreenPlayerScreenState();
}

class _FullscreenPlayerScreenState
    extends ConsumerState<FullscreenPlayerScreen> {
  bool _showControls = true;
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isPrebuffering = ref.watch(playerControllerProvider.select((s) => s.isPrebuffering));
    final isReconnecting = ref.watch(playerControllerProvider.select((s) => s.isReconnecting));
    final isBuffering = ref.watch(playerControllerProvider.select((s) => s.isBuffering));
    final error = ref.watch(playerControllerProvider.select((s) => s.error));
    final retryAttempt = ref.watch(playerControllerProvider.select((s) => s.retryAttempt));
    final maxRetries = ref.watch(playerControllerProvider.select((s) => s.maxRetries));
    final bufferedDuration = ref.watch(playerControllerProvider.select((s) => s.bufferedDuration));
    final bufferSize = ref.watch(playerControllerProvider.select((s) => s.bufferSize));
    final isPlaying = ref.watch(playerControllerProvider.select((s) => s.isPlaying));
    final playerController = ref.read(playerControllerProvider.notifier);
    final currentChannel = ref.watch(currentChannelProvider);
    // Keep the video edge-to-edge but offset the control overlays so they
    // clear system status bar / nav bar / cutouts on devices that render
    // edge-to-edge (Android 15+, foldables like ZFold6).
    final mediaPadding = MediaQuery.of(context).padding;

    if (currentChannel == null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Text(
            l10n.selectChannel,
            style: const TextStyle(color: Colors.white54),
          ),
        ),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        // Exit fullscreen and go back
        playerController.setFullscreen(false);
        Navigator.of(context).pop();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: MouseRegion(
        onEnter: (_) => setState(() {
          _isHovering = true;
          _showControls = true;
        }),
        onExit: (_) => setState(() {
          _isHovering = false;
          if (isPlaying) {
            Future.delayed(const Duration(seconds: 3), () {
              // Read fresh state to avoid stale closure
              if (mounted && !_isHovering &&
                  ref.read(playerControllerProvider).isPlaying) {
                setState(() => _showControls = false);
              }
            });
          }
        }),
        child: GestureDetector(
          onTap: () => setState(() => _showControls = !_showControls),
          onDoubleTap: () => playerController.toggleFullscreen(),
          child: Stack(
            children: [
              // Video fills entire screen
              Positioned.fill(
                child: Video(
                  controller: playerController.videoController,
                  controls: NoVideoControls,
                ),
              ),

              // Prebuffering indicator with progress
              if (isPrebuffering)
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(color: Colors.white),
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
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
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
                )
              // Reconnecting indicator (auto-retry in progress)
              else if (isReconnecting)
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(color: Colors.orange),
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
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                )
              // Regular buffering indicator
              else if (isBuffering)
                const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),

              // Error message (only when not reconnecting)
              if (error != null && !isReconnecting)
                Center(
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
                            playerController.playChannel(currentChannel);
                          },
                          child: Text(l10n.retry),
                        ),
                      ],
                    ),
                  ),
                ),

              // Top bar with channel info (animated). Offset by the system
              // top inset (status bar / cutout) so the overlay sits flush
              // below it on edge-to-edge devices.
              AnimatedPositioned(
                duration: const Duration(milliseconds: 200),
                top: _showControls ? mediaPadding.top : -80,
                left: mediaPadding.left,
                right: mediaPadding.right,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.7),
                        Colors.transparent,
                      ],
                    ),
                  ),
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
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (currentChannel.group != null)
                              Text(
                                currentChannel.group!,
                                style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 14,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                          ],
                        ),
                      ),
                      // Exit fullscreen hint (desktop only — has ESC key)
                      if (!Platform.isAndroid && !Platform.isIOS)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            l10n.escToExitFullscreen,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              // Bottom controls (animated). Lift by the system bottom inset
              // (nav bar / gesture area) so play/pause/volume/refresh remain
              // visible on edge-to-edge devices (Android 15+, foldables like
              // ZFold6).
              AnimatedPositioned(
                duration: const Duration(milliseconds: 200),
                bottom: _showControls ? mediaPadding.bottom : -80,
                left: mediaPadding.left,
                right: mediaPadding.right,
                child: const VideoPlayerControls(),
              ),
            ],
          ),
        ),
      ),
    ),
    );
  }
}
