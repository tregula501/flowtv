import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/player_provider.dart';

class VideoPlayerControls extends ConsumerStatefulWidget {
  const VideoPlayerControls({super.key});

  @override
  ConsumerState<VideoPlayerControls> createState() => _VideoPlayerControlsState();
}

class _VideoPlayerControlsState extends ConsumerState<VideoPlayerControls> {
  bool _isVisible = true;
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    final playerState = ref.watch(playerControllerProvider);
    final playerController = ref.watch(playerControllerProvider.notifier);

    return MouseRegion(
      onEnter: (_) => setState(() {
        _isHovering = true;
        _isVisible = true;
      }),
      onExit: (_) => setState(() {
        _isHovering = false;
        if (playerState.isPlaying) {
          Future.delayed(const Duration(seconds: 3), () {
            if (mounted && !_isHovering && playerState.isPlaying) {
              setState(() => _isVisible = false);
            }
          });
        }
      }),
      child: GestureDetector(
        onTap: () => setState(() => _isVisible = !_isVisible),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: _isVisible ? 1.0 : 0.0,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.7),
                ],
              ),
            ),
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Play/Pause button
                IconButton(
                  icon: Icon(
                    playerState.isPlaying ? Icons.pause : Icons.play_arrow,
                    color: Colors.white,
                    size: 32,
                  ),
                  onPressed: () => playerController.playPause(),
                ),

                // Stop button
                IconButton(
                  icon: const Icon(
                    Icons.stop,
                    color: Colors.white70,
                  ),
                  onPressed: () => playerController.stop(),
                ),

                const SizedBox(width: 16),

                // Volume controls
                IconButton(
                  icon: Icon(
                    playerState.isMuted
                        ? Icons.volume_off
                        : playerState.volume > 0.5
                            ? Icons.volume_up
                            : Icons.volume_down,
                    color: Colors.white70,
                  ),
                  onPressed: () => playerController.toggleMute(),
                ),

                SizedBox(
                  width: 100,
                  child: Slider(
                    value: playerState.isMuted ? 0 : playerState.volume,
                    onChanged: (value) => playerController.setVolume(value),
                    activeColor: Colors.white,
                    inactiveColor: Colors.white30,
                  ),
                ),

                const Spacer(),

                // Fullscreen button
                IconButton(
                  icon: Icon(
                    playerState.isFullscreen
                        ? Icons.fullscreen_exit
                        : Icons.fullscreen,
                    color: Colors.white70,
                  ),
                  onPressed: () => playerController.toggleFullscreen(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
