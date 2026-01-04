import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../data/models/channel.dart';
import '../../core/utils/logger.dart';

/// Player state
class PlayerState {
  final bool isPlaying;
  final bool isBuffering;
  final bool isFullscreen;
  final double volume;
  final bool isMuted;
  final Duration position;
  final Duration duration;
  final String? error;

  const PlayerState({
    this.isPlaying = false,
    this.isBuffering = false,
    this.isFullscreen = false,
    this.volume = 1.0,
    this.isMuted = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.error,
  });

  PlayerState copyWith({
    bool? isPlaying,
    bool? isBuffering,
    bool? isFullscreen,
    double? volume,
    bool? isMuted,
    Duration? position,
    Duration? duration,
    String? error,
  }) {
    return PlayerState(
      isPlaying: isPlaying ?? this.isPlaying,
      isBuffering: isBuffering ?? this.isBuffering,
      isFullscreen: isFullscreen ?? this.isFullscreen,
      volume: volume ?? this.volume,
      isMuted: isMuted ?? this.isMuted,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      error: error,
    );
  }
}

/// Video player controller provider
final playerControllerProvider =
    StateNotifierProvider<PlayerControllerNotifier, PlayerState>((ref) {
  return PlayerControllerNotifier();
});

class PlayerControllerNotifier extends StateNotifier<PlayerState> {
  Player? _player;
  VideoController? _videoController;

  PlayerControllerNotifier() : super(const PlayerState()) {
    _initPlayer();
  }

  Player get player => _player!;
  VideoController get videoController => _videoController!;

  void _initPlayer() {
    _player = Player();
    _videoController = VideoController(_player!);

    // Listen to player streams
    _player!.stream.playing.listen((playing) {
      state = state.copyWith(isPlaying: playing);
    });

    _player!.stream.buffering.listen((buffering) {
      state = state.copyWith(isBuffering: buffering);
    });

    _player!.stream.volume.listen((volume) {
      state = state.copyWith(volume: volume / 100);
    });

    _player!.stream.position.listen((position) {
      state = state.copyWith(position: position);
    });

    _player!.stream.duration.listen((duration) {
      state = state.copyWith(duration: duration);
    });

    _player!.stream.error.listen((error) {
      if (error.isNotEmpty) {
        AppLogger.error('Player error: $error');
        state = state.copyWith(error: error);
      }
    });
  }

  /// Play a channel
  Future<void> playChannel(Channel channel) async {
    try {
      state = state.copyWith(error: null, isBuffering: true);
      AppLogger.info('Playing channel: ${channel.name}');

      await _player!.open(Media(channel.streamUrl));
    } catch (e, stack) {
      AppLogger.error('Failed to play channel', e, stack);
      state = state.copyWith(error: e.toString());
    }
  }

  /// Play/Pause toggle
  Future<void> playPause() async {
    await _player!.playOrPause();
  }

  /// Play
  Future<void> play() async {
    await _player!.play();
  }

  /// Pause
  Future<void> pause() async {
    await _player!.pause();
  }

  /// Stop
  Future<void> stop() async {
    await _player!.stop();
  }

  /// Set volume (0.0 to 1.0)
  Future<void> setVolume(double volume) async {
    await _player!.setVolume(volume * 100);
  }

  /// Toggle mute
  void toggleMute() {
    if (state.isMuted) {
      _player!.setVolume(state.volume * 100);
    } else {
      _player!.setVolume(0);
    }
    state = state.copyWith(isMuted: !state.isMuted);
  }

  /// Seek to position
  Future<void> seek(Duration position) async {
    await _player!.seek(position);
  }

  /// Toggle fullscreen
  void toggleFullscreen() {
    state = state.copyWith(isFullscreen: !state.isFullscreen);
  }

  /// Set fullscreen state
  void setFullscreen(bool fullscreen) {
    state = state.copyWith(isFullscreen: fullscreen);
  }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }
}
