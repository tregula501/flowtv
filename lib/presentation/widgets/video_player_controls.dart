import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/themes/motion.dart';
import '../../l10n/app_localizations.dart';
import '../providers/player_provider.dart';
import '../providers/channel_provider.dart';

class VideoPlayerControls extends ConsumerStatefulWidget {
  const VideoPlayerControls({super.key});

  @override
  ConsumerState<VideoPlayerControls> createState() => _VideoPlayerControlsState();
}

class _VideoPlayerControlsState extends ConsumerState<VideoPlayerControls>
    with SingleTickerProviderStateMixin {
  bool _isVisible = true;
  bool _isHovering = false;
  Timer? _hideTimer;

  // Drives the play <-> pause icon morph. 1.0 = pause icon, 0.0 = play icon.
  late final AnimationController _playPauseController;

  @override
  void initState() {
    super.initState();
    _playPauseController = AnimationController(
      vsync: this,
      duration: MotionTokens.base,
      value: ref.read(playerControllerProvider).isPlaying ? 1.0 : 0.0,
    );
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _playPauseController.dispose();
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
    final isMuted = ref.watch(playerControllerProvider.select((s) => s.isMuted));
    final volume = ref.watch(playerControllerProvider.select((s) => s.volume));
    final isFullscreen = ref.watch(playerControllerProvider.select((s) => s.isFullscreen));
    final playerController = ref.read(playerControllerProvider.notifier);

    // Morph the play/pause icon when playback state changes. Presentation only —
    // it never triggers playback; the button's onPressed still drives playPause.
    ref.listen(playerControllerProvider.select((s) => s.isPlaying), (_, playing) {
      if (context.reduceMotion) {
        _playPauseController.value = playing ? 1.0 : 0.0;
      } else if (playing) {
        _playPauseController.forward();
      } else {
        _playPauseController.reverse();
      }
    });

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
            duration: MotionTokens.base,
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
                // Play/Pause button (morphing icon)
                IconButton(
                  icon: AnimatedIcon(
                    icon: AnimatedIcons.play_pause,
                    progress: _playPauseController,
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
                    isMuted
                        ? Icons.volume_off
                        : volume > 0.5
                            ? Icons.volume_up
                            : Icons.volume_down,
                    color: Colors.white70,
                  ),
                  onPressed: () => playerController.toggleMute(),
                ),

                SizedBox(
                  width: 100,
                  child: Slider(
                    value: isMuted ? 0 : volume,
                    onChanged: (value) => playerController.setVolume(value),
                    activeColor: Colors.white,
                    inactiveColor: Colors.white30,
                  ),
                ),

                const SizedBox(width: 16),

                const Spacer(),

                // Quality/Settings button
                _QualitySettingsButton(),

                // Fullscreen button
                IconButton(
                  icon: Icon(
                    isFullscreen
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
    final ps = ref.watch(playerControllerProvider.select((s) => (
        audioTracks: s.audioTracks,
        videoTracks: s.videoTracks,
        subtitleTracks: s.subtitleTracks,
        currentAudioTrack: s.currentAudioTrack,
        currentVideoTrack: s.currentVideoTrack,
        currentSubtitleTrack: s.currentSubtitleTrack,
        aspectRatioMode: s.aspectRatioMode,
        playbackSpeed: s.playbackSpeed,
        bufferSize: s.bufferSize,
    )));
    final hasMultipleTracks = ps.audioTracks.length > 1 ||
        ps.videoTracks.length > 1 ||
        ps.subtitleTracks.isNotEmpty;

    return PopupMenuButton<String>(
      icon: Icon(
        Icons.settings,
        color: hasMultipleTracks ? Colors.white : Colors.white70,
      ),
      tooltip: l10n.qualitySettings,
      color: Colors.grey.shade900,
      itemBuilder: (context) => [
        // Audio tracks section
        if (ps.audioTracks.length > 1) ...[
          PopupMenuItem(
            enabled: false,
            height: 32,
            child: Text(
              l10n.audioSection,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
          ),
          ...ps.audioTracks.map((track) => PopupMenuItem(
                value: 'audio:${track.id}',
                child: Row(
                  children: [
                    Icon(
                      ps.currentAudioTrack == track.id
                          ? Icons.check
                          : Icons.radio_button_unchecked,
                      size: 18,
                      color: ps.currentAudioTrack == track.id
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
        if (ps.videoTracks.length > 1) ...[
          PopupMenuItem(
            enabled: false,
            height: 32,
            child: Text(
              l10n.videoQualitySection,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
          ),
          ...ps.videoTracks.map((track) => PopupMenuItem(
                value: 'video:${track.id}',
                child: Row(
                  children: [
                    Icon(
                      ps.currentVideoTrack == track.id
                          ? Icons.check
                          : Icons.radio_button_unchecked,
                      size: 18,
                      color: ps.currentVideoTrack == track.id
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
        if (ps.subtitleTracks.isNotEmpty) ...[
          PopupMenuItem(
            enabled: false,
            height: 32,
            child: Text(
              l10n.subtitlesSection,
              style: const TextStyle(
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
                  ps.currentSubtitleTrack == null ||
                          ps.currentSubtitleTrack == 'no'
                      ? Icons.check
                      : Icons.radio_button_unchecked,
                  size: 18,
                  color: ps.currentSubtitleTrack == null ||
                          ps.currentSubtitleTrack == 'no'
                      ? Colors.blue
                      : Colors.grey,
                ),
                const SizedBox(width: 8),
                Text(l10n.subtitleOff),
              ],
            ),
          ),
          ...ps.subtitleTracks.map((track) => PopupMenuItem(
                value: 'subtitle:${track.id}',
                child: Row(
                  children: [
                    Icon(
                      ps.currentSubtitleTrack == track.id
                          ? Icons.check
                          : Icons.radio_button_unchecked,
                      size: 18,
                      color: ps.currentSubtitleTrack == track.id
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
        PopupMenuItem(
          enabled: false,
          height: 32,
          child: Text(
            l10n.aspectRatioSection,
            style: const TextStyle(
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
                    ps.aspectRatioMode == mode
                        ? Icons.check
                        : Icons.radio_button_unchecked,
                    size: 18,
                    color:
                        ps.aspectRatioMode == mode ? Colors.blue : Colors.grey,
                  ),
                  const SizedBox(width: 8),
                  Text(mode.displayName),
                ],
              ),
            ),),
        const PopupMenuDivider(),

        // Playback speed section
        PopupMenuItem(
          enabled: false,
          height: 32,
          child: Text(
            l10n.playbackSpeedSection,
            style: const TextStyle(
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
                    ps.playbackSpeed == speed
                        ? Icons.check
                        : Icons.radio_button_unchecked,
                    size: 18,
                    color:
                        ps.playbackSpeed == speed ? Colors.blue : Colors.grey,
                  ),
                  const SizedBox(width: 8),
                  Text('${speed}x${speed == 1.0 ? ' (Normal)' : ''}'),
                ],
              ),
            ),),
        const PopupMenuDivider(),

        // Buffer size section (desktop only — MPV-specific setting)
        if (!Platform.isAndroid && !Platform.isIOS) ...[
          PopupMenuItem(
            enabled: false,
            height: 32,
            child: Text(
              l10n.bufferSizeSection,
              style: const TextStyle(
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
                      ps.bufferSize == size
                          ? Icons.check
                          : Icons.radio_button_unchecked,
                      size: 18,
                      color: ps.bufferSize == size ? Colors.blue : Colors.grey,
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
    final isBuffering = ref.watch(playerControllerProvider.select((s) => s.isBuffering));

    if (currentChannel == null) {
      return const SizedBox.shrink();
    }

    return IconButton(
      icon: Icon(
        Icons.refresh,
        color: isBuffering ? Colors.orange : Colors.white70,
      ),
      tooltip: l10n.refreshStream,
      onPressed: isBuffering
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
