import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../providers/player_provider.dart';
import '../providers/channel_provider.dart';
import 'cast_button.dart';

class VideoPlayerControls extends ConsumerStatefulWidget {
  const VideoPlayerControls({super.key});

  @override
  ConsumerState<VideoPlayerControls> createState() => _VideoPlayerControlsState();
}

class _VideoPlayerControlsState extends ConsumerState<VideoPlayerControls> {
  bool _isVisible = true;
  bool _isHovering = false;
  Timer? _hideTimer;

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  void _showControls() {
    setState(() => _isVisible = true);
    _scheduleHide();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && !_isHovering) {
        final isPlaying = ref.read(playerControllerProvider).isPlaying;
        if (isPlaying) {
          setState(() => _isVisible = false);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final playerState = ref.watch(playerControllerProvider);
    final playerController = ref.read(playerControllerProvider.notifier);

    return MouseRegion(
      onEnter: (_) {
        _isHovering = true;
        _showControls();
      },
      onExit: (_) {
        _isHovering = false;
        _scheduleHide();
      },
      onHover: (_) {
        if (!_isVisible) {
          _showControls();
        }
      },
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () {
          setState(() => _isVisible = !_isVisible);
          if (_isVisible) {
            _scheduleHide();
          }
        },
        child: IgnorePointer(
          ignoring: !_isVisible,
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

                // Refresh button (for frozen streams)
                _RefreshButton(),

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

                // Cast button (only visible on Android)
                const CastButton(iconColor: Colors.white70),

                const Spacer(),

                // Quality/Settings button
                _QualitySettingsButton(),

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
      ),
    );
  }
}

class _QualitySettingsButton extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final playerState = ref.watch(playerControllerProvider);
    final hasMultipleTracks = playerState.audioTracks.length > 1 ||
        playerState.videoTracks.length > 1 ||
        playerState.subtitleTracks.isNotEmpty;

    return PopupMenuButton<String>(
      icon: Icon(
        Icons.settings,
        color: hasMultipleTracks ? Colors.white : Colors.white70,
      ),
      tooltip: l10n.qualitySettings,
      color: Colors.grey.shade900,
      itemBuilder: (context) => [
        // Audio tracks section
        if (playerState.audioTracks.length > 1) ...[
          const PopupMenuItem(
            enabled: false,
            height: 32,
            child: Text(
              'AUDIO',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
          ),
          ...playerState.audioTracks.map((track) => PopupMenuItem(
                value: 'audio:${track.id}',
                child: Row(
                  children: [
                    Icon(
                      playerState.currentAudioTrack == track.id
                          ? Icons.check
                          : Icons.radio_button_unchecked,
                      size: 18,
                      color: playerState.currentAudioTrack == track.id
                          ? Colors.blue
                          : Colors.grey,
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(track.displayName)),
                  ],
                ),
              ),),
          const PopupMenuDivider(),
        ],

        // Video tracks section
        if (playerState.videoTracks.length > 1) ...[
          const PopupMenuItem(
            enabled: false,
            height: 32,
            child: Text(
              'VIDEO QUALITY',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
          ),
          ...playerState.videoTracks.map((track) => PopupMenuItem(
                value: 'video:${track.id}',
                child: Row(
                  children: [
                    Icon(
                      playerState.currentVideoTrack == track.id
                          ? Icons.check
                          : Icons.radio_button_unchecked,
                      size: 18,
                      color: playerState.currentVideoTrack == track.id
                          ? Colors.blue
                          : Colors.grey,
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(track.displayName)),
                  ],
                ),
              ),),
          const PopupMenuDivider(),
        ],

        // Subtitle tracks section
        if (playerState.subtitleTracks.isNotEmpty) ...[
          const PopupMenuItem(
            enabled: false,
            height: 32,
            child: Text(
              'SUBTITLES',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
          ),
          PopupMenuItem(
            value: 'subtitle:off',
            child: Row(
              children: [
                Icon(
                  playerState.currentSubtitleTrack == null ||
                          playerState.currentSubtitleTrack == 'no'
                      ? Icons.check
                      : Icons.radio_button_unchecked,
                  size: 18,
                  color: playerState.currentSubtitleTrack == null ||
                          playerState.currentSubtitleTrack == 'no'
                      ? Colors.blue
                      : Colors.grey,
                ),
                const SizedBox(width: 8),
                Text(l10n.subtitleOff),
              ],
            ),
          ),
          ...playerState.subtitleTracks.map((track) => PopupMenuItem(
                value: 'subtitle:${track.id}',
                child: Row(
                  children: [
                    Icon(
                      playerState.currentSubtitleTrack == track.id
                          ? Icons.check
                          : Icons.radio_button_unchecked,
                      size: 18,
                      color: playerState.currentSubtitleTrack == track.id
                          ? Colors.blue
                          : Colors.grey,
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(track.displayName)),
                  ],
                ),
              ),),
          const PopupMenuDivider(),
        ],

        // Aspect ratio section
        const PopupMenuItem(
          enabled: false,
          height: 32,
          child: Text(
            'ASPECT RATIO',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
        ),
        ...AspectRatioMode.values.map((mode) => PopupMenuItem(
              value: 'aspect:${mode.index}',
              child: Row(
                children: [
                  Icon(
                    playerState.aspectRatioMode == mode
                        ? Icons.check
                        : Icons.radio_button_unchecked,
                    size: 18,
                    color:
                        playerState.aspectRatioMode == mode ? Colors.blue : Colors.grey,
                  ),
                  const SizedBox(width: 8),
                  Text(mode.displayName),
                ],
              ),
            ),),
        const PopupMenuDivider(),

        // Playback speed section
        const PopupMenuItem(
          enabled: false,
          height: 32,
          child: Text(
            'PLAYBACK SPEED',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
        ),
        ...[0.5, 0.75, 1.0, 1.25, 1.5, 2.0].map((speed) => PopupMenuItem(
              value: 'speed:$speed',
              child: Row(
                children: [
                  Icon(
                    playerState.playbackSpeed == speed
                        ? Icons.check
                        : Icons.radio_button_unchecked,
                    size: 18,
                    color:
                        playerState.playbackSpeed == speed ? Colors.blue : Colors.grey,
                  ),
                  const SizedBox(width: 8),
                  Text('${speed}x${speed == 1.0 ? ' (Normal)' : ''}'),
                ],
              ),
            ),),
        const PopupMenuDivider(),

        // Buffer size section (desktop only — MPV-specific setting)
        if (!Platform.isAndroid && !Platform.isIOS) ...[
          const PopupMenuItem(
            enabled: false,
            height: 32,
            child: Text(
              'BUFFER SIZE',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
          ),
          ...BufferSize.values.map((size) => PopupMenuItem(
                value: 'buffer:${size.index}',
                child: Row(
                  children: [
                    Icon(
                      playerState.bufferSize == size
                          ? Icons.check
                          : Icons.radio_button_unchecked,
                      size: 18,
                      color: playerState.bufferSize == size ? Colors.blue : Colors.grey,
                    ),
                    const SizedBox(width: 8),
                    Text(size.displayName),
                  ],
                ),
              ),),
        ],
      ],
      onSelected: (value) {
        final controller = ref.read(playerControllerProvider.notifier);
        final parts = value.split(':');
        final type = parts[0];
        final id = parts[1];

        switch (type) {
          case 'audio':
            controller.setAudioTrack(id);
            break;
          case 'video':
            controller.setVideoTrack(id);
            break;
          case 'subtitle':
            controller.setSubtitleTrack(id == 'off' ? null : id);
            break;
          case 'aspect':
            controller.setAspectRatioMode(AspectRatioMode.values[int.parse(id)]);
            break;
          case 'speed':
            controller.setPlaybackSpeed(double.parse(id));
            break;
          case 'buffer':
            controller.setBufferSize(BufferSize.values[int.parse(id)]);
            break;
        }
      },
    );
  }
}

class _RefreshButton extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final currentChannel = ref.watch(currentChannelProvider);
    final playerState = ref.watch(playerControllerProvider);

    if (currentChannel == null) {
      return const SizedBox.shrink();
    }

    return IconButton(
      icon: Icon(
        Icons.refresh,
        color: playerState.isBuffering ? Colors.orange : Colors.white70,
      ),
      tooltip: l10n.refreshStream,
      onPressed: playerState.isBuffering
          ? null
          : () async {
              final controller = ref.read(playerControllerProvider.notifier);
              await controller.refreshChannel(currentChannel);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(l10n.refreshingChannel(currentChannel.name)),
                    duration: const Duration(seconds: 1),
                  ),
                );
              }
            },
    );
  }
}
