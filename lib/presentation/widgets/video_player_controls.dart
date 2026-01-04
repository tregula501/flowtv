import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/player_provider.dart';
import '../providers/channel_provider.dart';
import '../providers/recording_provider.dart';

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

                const SizedBox(width: 16),

                // Record button
                _RecordButton(),

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

class _RecordButton extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentChannel = ref.watch(currentChannelProvider);
    final activeRecordings = ref.watch(activeRecordingsProvider);

    if (currentChannel == null) {
      return const SizedBox.shrink();
    }

    final isRecording = activeRecordings.any((r) => r.channelId == currentChannel.id);

    return IconButton(
      icon: Icon(
        Icons.fiber_manual_record,
        color: isRecording ? Colors.red : Colors.white70,
      ),
      tooltip: isRecording ? 'Stop Recording' : 'Start Recording',
      onPressed: () async {
        final manager = ref.read(recordingManagerProvider);
        if (isRecording) {
          await manager.stopRecording(currentChannel.id);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Stopped recording ${currentChannel.name}')),
            );
          }
        } else {
          await manager.startRecording(currentChannel);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Started recording ${currentChannel.name}')),
            );
          }
        }
      },
    );
  }
}
