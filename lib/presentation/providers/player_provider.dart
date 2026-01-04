import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:window_manager/window_manager.dart';

import '../../data/models/channel.dart';
import '../../core/utils/logger.dart';

/// Track info for audio/video/subtitle tracks
class TrackInfo {
  final String id;
  final String? title;
  final String? language;
  final String? codec;
  final int? width;
  final int? height;
  final int? bitrate;

  const TrackInfo({
    required this.id,
    this.title,
    this.language,
    this.codec,
    this.width,
    this.height,
    this.bitrate,
  });

  String get displayName {
    if (title != null && title!.isNotEmpty) return title!;
    if (language != null && language!.isNotEmpty) return language!;
    if (width != null && height != null) return '${width}x$height';
    if (codec != null) return codec!;
    return 'Track $id';
  }
}

/// Aspect ratio options
enum AspectRatioMode {
  auto,
  fit,
  fill,
  ratio16x9,
  ratio4x3,
  ratio21x9,
}

extension AspectRatioModeExtension on AspectRatioMode {
  String get displayName {
    switch (this) {
      case AspectRatioMode.auto:
        return 'Auto';
      case AspectRatioMode.fit:
        return 'Fit';
      case AspectRatioMode.fill:
        return 'Fill';
      case AspectRatioMode.ratio16x9:
        return '16:9';
      case AspectRatioMode.ratio4x3:
        return '4:3';
      case AspectRatioMode.ratio21x9:
        return '21:9';
    }
  }

  double? get aspectRatio {
    switch (this) {
      case AspectRatioMode.auto:
        return null;
      case AspectRatioMode.fit:
        return null;
      case AspectRatioMode.fill:
        return null;
      case AspectRatioMode.ratio16x9:
        return 16 / 9;
      case AspectRatioMode.ratio4x3:
        return 4 / 3;
      case AspectRatioMode.ratio21x9:
        return 21 / 9;
    }
  }
}

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
  final List<TrackInfo> videoTracks;
  final List<TrackInfo> audioTracks;
  final List<TrackInfo> subtitleTracks;
  final String? currentVideoTrack;
  final String? currentAudioTrack;
  final String? currentSubtitleTrack;
  final double playbackSpeed;
  final AspectRatioMode aspectRatioMode;

  const PlayerState({
    this.isPlaying = false,
    this.isBuffering = false,
    this.isFullscreen = false,
    this.volume = 1.0,
    this.isMuted = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.error,
    this.videoTracks = const [],
    this.audioTracks = const [],
    this.subtitleTracks = const [],
    this.currentVideoTrack,
    this.currentAudioTrack,
    this.currentSubtitleTrack,
    this.playbackSpeed = 1.0,
    this.aspectRatioMode = AspectRatioMode.auto,
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
    List<TrackInfo>? videoTracks,
    List<TrackInfo>? audioTracks,
    List<TrackInfo>? subtitleTracks,
    String? currentVideoTrack,
    String? currentAudioTrack,
    String? currentSubtitleTrack,
    double? playbackSpeed,
    AspectRatioMode? aspectRatioMode,
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
      videoTracks: videoTracks ?? this.videoTracks,
      audioTracks: audioTracks ?? this.audioTracks,
      subtitleTracks: subtitleTracks ?? this.subtitleTracks,
      currentVideoTrack: currentVideoTrack ?? this.currentVideoTrack,
      currentAudioTrack: currentAudioTrack ?? this.currentAudioTrack,
      currentSubtitleTrack: currentSubtitleTrack ?? this.currentSubtitleTrack,
      playbackSpeed: playbackSpeed ?? this.playbackSpeed,
      aspectRatioMode: aspectRatioMode ?? this.aspectRatioMode,
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

    // Listen to track changes
    _player!.stream.tracks.listen((tracks) {
      final videoTracks = tracks.video.map((t) => TrackInfo(
        id: t.id,
        title: t.title,
        language: t.language,
        codec: null,
        width: t.w,
        height: t.h,
      ),).toList();

      final audioTracks = tracks.audio.map((t) => TrackInfo(
        id: t.id,
        title: t.title,
        language: t.language,
        codec: null,
      ),).toList();

      final subtitleTracks = tracks.subtitle.map((t) => TrackInfo(
        id: t.id,
        title: t.title,
        language: t.language,
        codec: null,
      ),).toList();

      state = state.copyWith(
        videoTracks: videoTracks,
        audioTracks: audioTracks,
        subtitleTracks: subtitleTracks,
      );
    });

    // Listen to track selection changes
    _player!.stream.track.listen((track) {
      state = state.copyWith(
        currentVideoTrack: track.video.id,
        currentAudioTrack: track.audio.id,
        currentSubtitleTrack: track.subtitle.id,
      );
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
  Future<void> toggleFullscreen() async {
    final newFullscreen = !state.isFullscreen;
    await setFullscreen(newFullscreen);
  }

  /// Set fullscreen state
  Future<void> setFullscreen(bool fullscreen) async {
    // For desktop platforms, use window_manager
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      try {
        await windowManager.ensureInitialized();
        await windowManager.setFullScreen(fullscreen);
        state = state.copyWith(isFullscreen: fullscreen);
        AppLogger.info('Fullscreen: $fullscreen');
      } catch (e) {
        AppLogger.error('Failed to toggle fullscreen: $e');
      }
    } else {
      // For mobile/other platforms, just update state (UI will handle it)
      state = state.copyWith(isFullscreen: fullscreen);
    }
  }

  /// Set video track
  Future<void> setVideoTrack(String trackId) async {
    final tracks = _player!.state.tracks.video;
    final track = tracks.firstWhere(
      (t) => t.id == trackId,
      orElse: () => tracks.first,
    );
    await _player!.setVideoTrack(track);
    AppLogger.info('Video track set: $trackId');
  }

  /// Set audio track
  Future<void> setAudioTrack(String trackId) async {
    final tracks = _player!.state.tracks.audio;
    final track = tracks.firstWhere(
      (t) => t.id == trackId,
      orElse: () => tracks.first,
    );
    await _player!.setAudioTrack(track);
    AppLogger.info('Audio track set: $trackId');
  }

  /// Set subtitle track
  Future<void> setSubtitleTrack(String? trackId) async {
    if (trackId == null) {
      await _player!.setSubtitleTrack(SubtitleTrack.no());
      AppLogger.info('Subtitles disabled');
      return;
    }
    final tracks = _player!.state.tracks.subtitle;
    final track = tracks.firstWhere(
      (t) => t.id == trackId,
      orElse: () => SubtitleTrack.no(),
    );
    await _player!.setSubtitleTrack(track);
    AppLogger.info('Subtitle track set: $trackId');
  }

  /// Set playback speed
  Future<void> setPlaybackSpeed(double speed) async {
    await _player!.setRate(speed);
    state = state.copyWith(playbackSpeed: speed);
    AppLogger.info('Playback speed set: ${speed}x');
  }

  /// Set aspect ratio mode
  void setAspectRatioMode(AspectRatioMode mode) {
    state = state.copyWith(aspectRatioMode: mode);
    AppLogger.info('Aspect ratio mode set: ${mode.displayName}');
  }

  /// Cycle through aspect ratio modes
  void cycleAspectRatio() {
    const modes = AspectRatioMode.values;
    final currentIndex = modes.indexOf(state.aspectRatioMode);
    final nextIndex = (currentIndex + 1) % modes.length;
    setAspectRatioMode(modes[nextIndex]);
  }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }
}
