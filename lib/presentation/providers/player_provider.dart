import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:window_manager/window_manager.dart';
// ignore: implementation_imports
import 'package:media_kit/src/player/native/player/player.dart' as native;

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

/// Buffer size options for streaming
enum BufferSize {
  small,
  medium,
  large,
  veryLarge,
}

extension BufferSizeExtension on BufferSize {
  String get displayName {
    switch (this) {
      case BufferSize.small:
        return 'Small (1s)';
      case BufferSize.medium:
        return 'Medium (5s)';
      case BufferSize.large:
        return 'Large (15s)';
      case BufferSize.veryLarge:
        return 'Very Large (30s)';
    }
  }

  int get durationSeconds {
    switch (this) {
      case BufferSize.small:
        return 1;
      case BufferSize.medium:
        return 5;
      case BufferSize.large:
        return 15;
      case BufferSize.veryLarge:
        return 30;
    }
  }

  String get description {
    switch (this) {
      case BufferSize.small:
        return 'Lowest latency, may buffer more';
      case BufferSize.medium:
        return 'Balanced latency and stability';
      case BufferSize.large:
        return 'More stable, higher latency';
      case BufferSize.veryLarge:
        return 'Most stable for slow connections';
    }
  }
}

/// Player state
class PlayerState {
  final bool isPlaying;
  final bool isBuffering;
  final bool isPrebuffering; // Waiting for initial buffer to fill
  final bool isReconnecting; // Auto-retry in progress
  final bool isFullscreen;
  final double volume;
  final bool isMuted;
  final Duration position;
  final Duration duration;
  final Duration bufferedDuration; // How much is buffered ahead
  final String? error;
  final List<TrackInfo> videoTracks;
  final List<TrackInfo> audioTracks;
  final List<TrackInfo> subtitleTracks;
  final String? currentVideoTrack;
  final String? currentAudioTrack;
  final String? currentSubtitleTrack;
  final double playbackSpeed;
  final AspectRatioMode aspectRatioMode;
  final BufferSize bufferSize;
  final int retryAttempt; // Current retry attempt (0 = not retrying)
  final int maxRetries; // Maximum retry attempts

  const PlayerState({
    this.isPlaying = false,
    this.isBuffering = false,
    this.isPrebuffering = false,
    this.isReconnecting = false,
    this.isFullscreen = false,
    this.volume = 1.0,
    this.isMuted = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.bufferedDuration = Duration.zero,
    this.error,
    this.videoTracks = const [],
    this.audioTracks = const [],
    this.subtitleTracks = const [],
    this.currentVideoTrack,
    this.currentAudioTrack,
    this.currentSubtitleTrack,
    this.playbackSpeed = 1.0,
    this.aspectRatioMode = AspectRatioMode.auto,
    this.bufferSize = BufferSize.medium,
    this.retryAttempt = 0,
    this.maxRetries = 3,
  });

  PlayerState copyWith({
    bool? isPlaying,
    bool? isBuffering,
    bool? isPrebuffering,
    bool? isReconnecting,
    bool? isFullscreen,
    double? volume,
    bool? isMuted,
    Duration? position,
    Duration? duration,
    Duration? bufferedDuration,
    String? error,
    List<TrackInfo>? videoTracks,
    List<TrackInfo>? audioTracks,
    List<TrackInfo>? subtitleTracks,
    String? currentVideoTrack,
    String? currentAudioTrack,
    String? currentSubtitleTrack,
    double? playbackSpeed,
    AspectRatioMode? aspectRatioMode,
    BufferSize? bufferSize,
    int? retryAttempt,
    int? maxRetries,
  }) {
    return PlayerState(
      isPlaying: isPlaying ?? this.isPlaying,
      isBuffering: isBuffering ?? this.isBuffering,
      isPrebuffering: isPrebuffering ?? this.isPrebuffering,
      isReconnecting: isReconnecting ?? this.isReconnecting,
      isFullscreen: isFullscreen ?? this.isFullscreen,
      volume: volume ?? this.volume,
      isMuted: isMuted ?? this.isMuted,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      bufferedDuration: bufferedDuration ?? this.bufferedDuration,
      error: error,
      videoTracks: videoTracks ?? this.videoTracks,
      audioTracks: audioTracks ?? this.audioTracks,
      subtitleTracks: subtitleTracks ?? this.subtitleTracks,
      currentVideoTrack: currentVideoTrack ?? this.currentVideoTrack,
      currentAudioTrack: currentAudioTrack ?? this.currentAudioTrack,
      currentSubtitleTrack: currentSubtitleTrack ?? this.currentSubtitleTrack,
      playbackSpeed: playbackSpeed ?? this.playbackSpeed,
      aspectRatioMode: aspectRatioMode ?? this.aspectRatioMode,
      bufferSize: bufferSize ?? this.bufferSize,
      retryAttempt: retryAttempt ?? this.retryAttempt,
      maxRetries: maxRetries ?? this.maxRetries,
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
  BufferSize _currentBufferSize = BufferSize.medium;
  bool _isPrebuffering = false;
  DateTime? _prebufferStartTime;
  int _prebufferTimerId = 0;

  // Auto-retry state
  Channel? _currentChannel;
  int _retryAttempt = 0;
  static const int _maxRetries = 3;
  bool _isRetrying = false;
  int _retryTimerId = 0;
  DateTime? _lastSuccessfulPlay;
  bool _autoRetryEnabled = true;

  PlayerControllerNotifier() : super(const PlayerState()) {
    _initPlayer();
  }

  Player get player => _player!;
  VideoController get videoController => _videoController!;
  Channel? get currentChannel => _currentChannel;

  void _initPlayer() {
    // Initialize with buffer size configuration
    final bufferBytes = _currentBufferSize.durationSeconds * 2 * 1024 * 1024;
    _player = Player(
      configuration: PlayerConfiguration(
        bufferSize: bufferBytes,
      ),
    );
    _videoController = VideoController(_player!);

    // Apply MPV-specific buffer settings
    _applyBufferSettings();

    // Listen to player streams
    _player!.stream.playing.listen((playing) {
      state = state.copyWith(isPlaying: playing);
    });

    _player!.stream.buffering.listen((buffering) {
      state = state.copyWith(isBuffering: buffering);
    });

    // Listen to buffer position for display purposes
    _player!.stream.buffer.listen((buffer) {
      // For live streams, buffer is absolute position; for display we track elapsed prebuffer time
      state = state.copyWith(bufferedDuration: buffer);
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
        // Trigger auto-retry on error
        _handleStreamError(error);
      }
    });

    // Monitor for stream ending/disconnection
    _player!.stream.completed.listen((completed) {
      if (completed && _currentChannel != null && _autoRetryEnabled) {
        // Stream ended unexpectedly - could be a disconnect
        AppLogger.warning('Stream completed unexpectedly, attempting reconnect');
        _handleStreamError('Stream ended');
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

  /// Apply MPV-specific buffer settings via NativePlayer
  /// Note: MPV's cache options control how much is buffered, but for IPTV streams
  /// the buffer behavior is largely controlled by the stream itself.
  /// The "prebuffer" effect is simulated by keeping isBuffering=true until
  /// enough data has been received.
  Future<void> _applyBufferSettings() async {
    try {
      if (_player?.platform is native.NativePlayer) {
        final nativePlayer = _player!.platform as native.NativePlayer;
        final bufferSecs = _currentBufferSize.durationSeconds;
        final bufferBytes = bufferSecs * 2 * 1024 * 1024;

        // Core cache settings
        await nativePlayer.setProperty('cache', 'yes');
        await nativePlayer.setProperty('cache-secs', bufferSecs.toString());

        // Demuxer settings - how much to read ahead
        await nativePlayer.setProperty('demuxer-max-bytes', bufferBytes.toString());
        await nativePlayer.setProperty('demuxer-readahead-secs', bufferSecs.toString());

        // Try demuxer-cache-wait which should wait for cache to fill
        // This is the key option for "prebuffering"
        if (bufferSecs > 1) {
          await nativePlayer.setProperty('demuxer-cache-wait', 'yes');
        }

        AppLogger.info('Applied MPV buffer settings: cache-secs=$bufferSecs, demuxer-cache-wait=${bufferSecs > 1}');
      }
    } catch (e) {
      AppLogger.warning('Could not apply MPV buffer settings: $e');
    }
  }

  /// Complete prebuffering and start playback
  void _completePrebuffering(int timerId) {
    if (!_isPrebuffering || timerId != _prebufferTimerId) return;

    _isPrebuffering = false;
    _prebufferStartTime = null;
    state = state.copyWith(isPrebuffering: false, bufferedDuration: Duration.zero);
    _player!.play();
    AppLogger.info('Prebuffer complete, starting playback');
  }

  /// Cancel prebuffering (used when stopping or changing channels)
  void _cancelPrebuffering() {
    _isPrebuffering = false;
    _prebufferStartTime = null;
    _prebufferTimerId++; // Invalidate any pending timers
    state = state.copyWith(isPrebuffering: false, bufferedDuration: Duration.zero);
  }

  /// Update prebuffer progress display
  void _updatePrebufferProgress(int timerId) {
    if (!_isPrebuffering || timerId != _prebufferTimerId || _prebufferStartTime == null) return;
    if (!mounted) return;

    final elapsed = DateTime.now().difference(_prebufferStartTime!);
    state = state.copyWith(bufferedDuration: elapsed);

    // Schedule next update
    Future.delayed(const Duration(milliseconds: 100), () {
      _updatePrebufferProgress(timerId);
    });
  }

  /// Handle stream errors with auto-retry
  void _handleStreamError(String error) {
    if (!_autoRetryEnabled || _currentChannel == null || _isRetrying) return;

    // Check if we've exceeded max retries
    if (_retryAttempt >= _maxRetries) {
      AppLogger.error('Max retry attempts reached ($_maxRetries), giving up');
      state = state.copyWith(
        error: 'Connection lost after $_maxRetries retry attempts: $error',
        isReconnecting: false,
        retryAttempt: 0,
      );
      _resetRetryState();
      return;
    }

    // Calculate delay with exponential backoff: 1s, 2s, 4s
    final delaySeconds = 1 << _retryAttempt; // 2^retryAttempt
    _retryAttempt++;
    _retryTimerId++;
    final currentTimerId = _retryTimerId;

    AppLogger.info('Stream error, retry attempt $_retryAttempt/$_maxRetries in ${delaySeconds}s');

    state = state.copyWith(
      isReconnecting: true,
      retryAttempt: _retryAttempt,
      error: null, // Clear error during retry
    );

    Future.delayed(Duration(seconds: delaySeconds), () {
      _attemptReconnect(currentTimerId);
    });
  }

  /// Attempt to reconnect to the current channel
  Future<void> _attemptReconnect(int timerId) async {
    if (timerId != _retryTimerId || _currentChannel == null) return;
    if (!mounted) return;

    _isRetrying = true;
    AppLogger.info('Attempting reconnect to ${_currentChannel!.name}...');

    try {
      await _player!.stop();
      await Future.delayed(const Duration(milliseconds: 500));

      // Re-open the stream without resetting retry state yet
      await _player!.open(Media(_currentChannel!.streamUrl), play: true);

      // Wait a moment to see if playback starts successfully
      await Future.delayed(const Duration(seconds: 2));

      // Check if we're actually playing
      if (_player!.state.playing) {
        AppLogger.info('Reconnect successful!');
        _resetRetryState();
        _lastSuccessfulPlay = DateTime.now();
        state = state.copyWith(
          isReconnecting: false,
          retryAttempt: 0,
          error: null,
        );
      } else {
        // Still not playing, trigger another retry
        _isRetrying = false;
        _handleStreamError('Reconnect failed - not playing');
      }
    } catch (e) {
      AppLogger.error('Reconnect attempt failed: $e');
      _isRetrying = false;
      _handleStreamError(e.toString());
    }
  }

  /// Reset retry state
  void _resetRetryState() {
    _retryAttempt = 0;
    _isRetrying = false;
    _retryTimerId++;
  }

  /// Cancel any pending retry
  void _cancelRetry() {
    _resetRetryState();
    state = state.copyWith(isReconnecting: false, retryAttempt: 0);
  }

  /// Enable or disable auto-retry
  void setAutoRetryEnabled(bool enabled) {
    _autoRetryEnabled = enabled;
    AppLogger.info('Auto-retry ${enabled ? 'enabled' : 'disabled'}');
  }

  /// Play a channel with current buffer settings
  Future<void> playChannel(Channel channel) async {
    try {
      // Cancel any existing prebuffer and retry
      _cancelPrebuffering();
      _cancelRetry();

      // Store current channel for auto-retry
      _currentChannel = channel;

      final bufferSeconds = _currentBufferSize.durationSeconds;

      state = state.copyWith(
        error: null,
        isBuffering: true,
        isPrebuffering: bufferSeconds > 1,
        isReconnecting: false,
        bufferedDuration: Duration.zero,
        retryAttempt: 0,
      );
      AppLogger.info('Playing channel: ${channel.name} (buffer: ${_currentBufferSize.displayName})');

      // Apply buffer settings before playing
      await _applyBufferSettings();

      // Open the stream
      await _player!.open(Media(channel.streamUrl), play: bufferSeconds <= 1);

      // For buffer sizes > 1 second, wait before playing
      if (bufferSeconds > 1) {
        _isPrebuffering = true;
        _prebufferStartTime = DateTime.now();
        _prebufferTimerId++;
        final currentTimerId = _prebufferTimerId;

        // Start progress updates
        _updatePrebufferProgress(currentTimerId);

        // Wait for the buffer duration then start playback
        AppLogger.info('Prebuffering for ${bufferSeconds}s...');
        Future.delayed(Duration(seconds: bufferSeconds), () {
          _completePrebuffering(currentTimerId);
        });
      } else {
        // Mark successful play for immediate playback
        _lastSuccessfulPlay = DateTime.now();
      }
    } catch (e, stack) {
      AppLogger.error('Failed to play channel', e, stack);
      _cancelPrebuffering();
      state = state.copyWith(error: e.toString());
    }
  }

  /// Refresh/reload the current channel (useful for frozen streams)
  Future<void> refreshChannel(Channel channel) async {
    try {
      AppLogger.info('Refreshing channel: ${channel.name}');
      await _player!.stop();
      // Small delay before reopening
      await Future.delayed(const Duration(milliseconds: 300));
      await playChannel(channel);
    } catch (e, stack) {
      AppLogger.error('Failed to refresh channel', e, stack);
      state = state.copyWith(error: e.toString());
    }
  }

  /// Set buffer size for streaming
  /// If a channel is currently playing, refreshes the stream to apply new buffer
  Future<void> setBufferSize(BufferSize size) async {
    final previousSize = _currentBufferSize;
    _currentBufferSize = size;
    state = state.copyWith(bufferSize: size);
    AppLogger.info('Buffer size set: ${size.displayName}');

    // Apply new buffer settings
    await _applyBufferSettings();

    // If currently playing a channel and buffer size changed, refresh to apply new buffer
    if (_currentChannel != null && previousSize != size && state.isPlaying) {
      AppLogger.info('Refreshing stream to apply new buffer size...');
      await refreshChannel(_currentChannel!);
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
    _cancelPrebuffering();
    _cancelRetry();
    _currentChannel = null;
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
