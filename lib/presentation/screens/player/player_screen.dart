import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../providers/channel_provider.dart';
import '../../providers/player_provider.dart';
import '../../widgets/video_player_controls.dart';

class PlayerScreen extends ConsumerWidget {
  const PlayerScreen({super.key});

  Widget _buildVideoWithAspectRatio(
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
    final playerState = ref.watch(playerControllerProvider);
    final playerController = ref.watch(playerControllerProvider.notifier);
    final currentChannel = ref.watch(currentChannelProvider);

    if (currentChannel == null) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: Text(
            'Select a channel to start watching',
            style: TextStyle(color: Colors.white54),
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
                // Expand/Collapse button (in-app fullscreen)
                IconButton(
                  icon: Icon(
                    playerState.isExpanded ? Icons.close_fullscreen : Icons.open_in_full,
                    color: Colors.white70,
                    size: 20,
                  ),
                  tooltip: playerState.isExpanded ? 'Exit expanded' : 'Expand player',
                  onPressed: () => playerController.toggleExpanded(),
                ),

                // PiP button
                IconButton(
                  icon: const Icon(Icons.picture_in_picture, color: Colors.white70, size: 20),
                  tooltip: 'Picture-in-Picture',
                  onPressed: () => playerController.togglePiPMode(),
                ),

                // Fullscreen button
                IconButton(
                  icon: const Icon(Icons.fullscreen, color: Colors.white70, size: 20),
                  tooltip: 'Fullscreen',
                  onPressed: () => playerController.toggleFullscreen(),
                ),

                // Open in new window button
                IconButton(
                  icon: const Icon(Icons.open_in_new_rounded, color: Colors.white70, size: 20),
                  tooltip: 'Open in New Window',
                  onPressed: () async {
                    final success = await playerController.openInNewWindow();
                    if (!success && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Could not open in new window'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    }
                  },
                ),

                // Open in external player button (VLC)
                IconButton(
                  icon: const Icon(Icons.launch, color: Colors.white70, size: 20),
                  tooltip: 'Open in VLC/External Player',
                  onPressed: () async {
                    final success = await playerController.openInExternalPlayer();
                    if (!success && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Could not open in external player. Make sure VLC is installed.'),
                          duration: Duration(seconds: 3),
                        ),
                      );
                    }
                  },
                ),

                // Close button
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white70),
                  tooltip: 'Close player',
                  onPressed: () {
                    ref.read(currentChannelProvider.notifier).select(null);
                    playerController.stop();
                  },
                ),
              ],
            ),
          ),

          // Video player
          Expanded(
            child: Stack(
              children: [
                // Video with aspect ratio control
                Center(
                  child: _buildVideoWithAspectRatio(
                    playerController.videoController,
                    playerState.aspectRatioMode,
                  ),
                ),

                // Prebuffering indicator with progress
                if (playerState.isPrebuffering)
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
                          const CircularProgressIndicator(
                            color: Colors.white,
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Prebuffering...',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${playerState.bufferedDuration.inSeconds}s / ${playerState.bufferSize.durationSeconds}s',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: 150,
                            child: LinearProgressIndicator(
                              value: playerState.bufferSize.durationSeconds > 0
                                  ? (playerState.bufferedDuration.inMilliseconds /
                                          (playerState.bufferSize.durationSeconds * 1000))
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
                else if (playerState.isReconnecting)
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
                          const CircularProgressIndicator(
                            color: Colors.orange,
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Reconnecting...',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Attempt ${playerState.retryAttempt} of ${playerState.maxRetries}',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                // Regular buffering indicator (during playback)
                else if (playerState.isBuffering)
                  const Center(
                    child: CircularProgressIndicator(
                      color: Colors.white,
                    ),
                  ),

                // Error message (only shown when not reconnecting)
                if (playerState.error != null && !playerState.isReconnecting)
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      margin: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.8),
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
                            'Playback Error',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(color: Colors.white),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            playerState.error!,
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
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Controls overlay
                const Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: VideoPlayerControls(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
