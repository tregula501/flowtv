import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../providers/channel_provider.dart';
import '../../providers/player_provider.dart';
import '../../widgets/video_player_controls.dart';

class PlayerScreen extends ConsumerWidget {
  const PlayerScreen({super.key});

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
                // Close button
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white70),
                  onPressed: () {
                    ref.read(currentChannelProvider.notifier).state = null;
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
                // Video
                Video(
                  controller: playerController.videoController,
                  controls: NoVideoControls,
                ),

                // Buffering indicator
                if (playerState.isBuffering)
                  const Center(
                    child: CircularProgressIndicator(
                      color: Colors.white,
                    ),
                  ),

                // Error message
                if (playerState.error != null)
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
