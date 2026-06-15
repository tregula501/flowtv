import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:window_manager/window_manager.dart';

import '../../../core/themes/motion.dart';

/// A standalone popup player window for playing a stream in a separate window.
/// This is used by the desktop_multi_window package to create independent player windows.
class PopupPlayerWindow extends StatefulWidget {
  final String windowId;
  final String channelName;
  final String streamUrl;
  final String? logoUrl;

  const PopupPlayerWindow({
    super.key,
    required this.windowId,
    required this.channelName,
    required this.streamUrl,
    this.logoUrl,
  });

  @override
  State<PopupPlayerWindow> createState() => _PopupPlayerWindowState();
}

class _PopupPlayerWindowState extends State<PopupPlayerWindow>
    with SingleTickerProviderStateMixin {
  late final Player _player;
  late final VideoController _videoController;
  final _keyboardFocusNode = FocusNode();
  final List<StreamSubscription> _subscriptions = [];
  bool _isBuffering = true;
  bool _isMuted = false;
  double _volume = 1.0;
  String? _error;
  bool _controlsVisible = true;
  bool _isFullscreen = false;

  // Drives the play <-> pause icon morph. 1.0 = pause icon, 0.0 = play icon.
  late final AnimationController _playPauseController;

  @override
  void initState() {
    super.initState();
    _playPauseController = AnimationController(
      vsync: this,
      duration: MotionTokens.base,
    );
    _initPlayer();
  }

  void _initPlayer() {
    _player = Player(
      configuration: const PlayerConfiguration(
        bufferSize: 32 * 1024 * 1024, // 32MB buffer
      ),
    );
    _videoController = VideoController(_player);

    // Listen to player state (store subscriptions for cleanup)
    _subscriptions.add(
      _player.stream.playing.listen((playing) {
        if (mounted) {
          if (playing) {
            _playPauseController.forward();
          } else {
            _playPauseController.reverse();
          }
        }
      }),
    );

    _subscriptions.add(
      _player.stream.buffering.listen((buffering) {
        if (mounted) setState(() => _isBuffering = buffering);
      }),
    );

    _subscriptions.add(
      _player.stream.error.listen((error) {
        if (error.isNotEmpty && mounted) {
          setState(() => _error = error);
        }
      }),
    );

    _subscriptions.add(
      _player.stream.volume.listen((volume) {
        if (mounted) setState(() => _volume = volume / 100);
      }),
    );

    // Start playing the stream
    if (widget.streamUrl.isNotEmpty) {
      _player.open(Media(widget.streamUrl));
    }
  }

  @override
  void dispose() {
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _keyboardFocusNode.dispose();
    _playPauseController.dispose();
    _player.dispose();
    super.dispose();
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      switch (event.logicalKey) {
        case LogicalKeyboardKey.space:
          _player.playOrPause();
          break;
        case LogicalKeyboardKey.keyM:
          _toggleMute();
          break;
        case LogicalKeyboardKey.keyF:
          _toggleFullscreen();
          break;
        case LogicalKeyboardKey.escape:
          if (_isFullscreen) {
            _toggleFullscreen();
          } else {
            _closeWindow();
          }
          break;
      }
    }
  }

  void _toggleMute() {
    if (_isMuted) {
      _player.setVolume(_volume * 100);
    } else {
      _player.setVolume(0);
    }
    setState(() => _isMuted = !_isMuted);
  }

  Future<void> _toggleFullscreen() async {
    final newFullscreen = !_isFullscreen;
    setState(() => _isFullscreen = newFullscreen);

    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      await windowManager.setFullScreen(newFullscreen);
    }
  }

  Future<void> _closeWindow() async {
    await _player.stop();
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      await windowManager.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
      ),
      home: KeyboardListener(
        focusNode: _keyboardFocusNode,
        onKeyEvent: _handleKeyEvent,
        autofocus: true,
        child: Builder(
          builder: (context) {
            // Keep the video edge-to-edge but offset the control overlays
            // so they clear system status bar / nav bar / cutouts on devices
            // that render edge-to-edge (Android 15+, foldables like ZFold6).
            final mediaPadding = MediaQuery.of(context).padding;
            return Scaffold(
          backgroundColor: Colors.black,
          body: GestureDetector(
            onTap: () => setState(() => _controlsVisible = !_controlsVisible),
            child: MouseRegion(
              onEnter: (_) => setState(() => _controlsVisible = true),
              onExit: (_) => setState(() => _controlsVisible = false),
              child: Stack(
              children: [
                // Video player
                Positioned.fill(
                  child: Video(
                    controller: _videoController,
                    controls: NoVideoControls,
                    fit: BoxFit.contain,
                  ),
                ),

                // Buffering indicator — cross-faded
                AnimatedSwitcher(
                  duration: MotionTokens.base,
                  child: _isBuffering
                      ? const Center(
                          key: ValueKey('buffer'),
                          child: CircularProgressIndicator(color: Colors.white),
                        )
                      : const SizedBox.shrink(key: ValueKey('nobuffer')),
                ),

                // Error overlay — cross-faded
                AnimatedSwitcher(
                  duration: MotionTokens.base,
                  child: _error != null
                      ? Center(
                          key: const ValueKey('error'),
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
                                const Icon(Icons.error_outline, color: Colors.white, size: 48),
                                const SizedBox(height: 8),
                                const Text(
                                  'Playback Error',
                                  style: TextStyle(color: Colors.white, fontSize: 18),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _error!,
                                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 12),
                                ElevatedButton(
                                  onPressed: () {
                                    setState(() => _error = null);
                                    _player.open(Media(widget.streamUrl));
                                  },
                                  child: const Text('Retry'),
                                ),
                              ],
                            ),
                          ),
                        )
                      : const SizedBox.shrink(key: ValueKey('noerror')),
                ),

                // Top bar with channel info and close button. Offset by the
                // system top inset (status bar / cutout) so the overlay sits
                // flush below it on edge-to-edge devices.
                Positioned(
                  top: mediaPadding.top,
                  left: mediaPadding.left,
                  right: mediaPadding.right,
                  child: IgnorePointer(
                  ignoring: !_controlsVisible,
                  child: AnimatedOpacity(
                    opacity: _controlsVisible ? 1.0 : 0.0,
                    duration: MotionTokens.base,
                    child: Container(
                    padding: const EdgeInsets.all(12),
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
                        // Channel logo
                        if (widget.logoUrl != null && widget.logoUrl!.isNotEmpty)
                          Container(
                            width: 32,
                            height: 32,
                            margin: const EdgeInsets.only(right: 12),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(4),
                              color: Colors.white12,
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: CachedNetworkImage(
                                imageUrl: widget.logoUrl!,
                                fit: BoxFit.cover,
                                errorWidget: (_, _, _) => const Icon(
                                  Icons.tv,
                                  color: Colors.white54,
                                  size: 20,
                                ),
                              ),
                            ),
                          ),

                        // Channel name
                        Expanded(
                          child: Text(
                            widget.channelName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),

                        // Close button
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white70),
                          tooltip: 'Close window',
                          onPressed: _closeWindow,
                        ),
                      ],
                    ),
                  ),
                ),
                ),
                ),

                // Bottom controls. Lift by the system bottom inset (nav bar /
                // gesture area) so play/pause/volume/fullscreen remain visible
                // on edge-to-edge devices (Android 15+, foldables like ZFold6).
                Positioned(
                  left: mediaPadding.left,
                  right: mediaPadding.right,
                  bottom: mediaPadding.bottom,
                  child: IgnorePointer(
                    ignoring: !_controlsVisible,
                    child: AnimatedOpacity(
                      opacity: _controlsVisible ? 1.0 : 0.0,
                      duration: MotionTokens.base,
                      child: Container(
                        padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.7),
                            Colors.transparent,
                          ],
                        ),
                      ),
                      child: Row(
                        children: [
                          // Play/Pause (morphing icon)
                          IconButton(
                            icon: AnimatedIcon(
                              icon: AnimatedIcons.play_pause,
                              progress: _playPauseController,
                              color: Colors.white,
                            ),
                            tooltip: 'Play/Pause',
                            onPressed: () => _player.playOrPause(),
                          ),

                          // Volume
                          IconButton(
                            icon: Icon(
                              _isMuted ? Icons.volume_off : Icons.volume_up,
                              color: Colors.white,
                            ),
                            tooltip: 'Mute/Unmute',
                            onPressed: _toggleMute,
                          ),

                          // Volume slider
                          SizedBox(
                            width: 100,
                            child: Slider(
                              value: _isMuted ? 0 : _volume,
                              onChanged: (value) {
                                setState(() {
                                  _volume = value;
                                  _isMuted = value == 0;
                                });
                                _player.setVolume(value * 100);
                              },
                              activeColor: Colors.white,
                              inactiveColor: Colors.white24,
                            ),
                          ),

                          const Spacer(),

                          // Fullscreen toggle
                          IconButton(
                            icon: Icon(
                              _isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                              color: Colors.white,
                            ),
                            tooltip: 'Fullscreen',
                            onPressed: _toggleFullscreen,
                          ),
                        ],
                      ),
                    ),
                  ),
                  ),
                ),
              ],
            ),
          ),
          ),
            );
          },
        ),
      ),
    );
  }
}
