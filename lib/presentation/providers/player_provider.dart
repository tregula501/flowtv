import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:window_manager/window_manager.dart';
// ignore: implementation_imports
import 'package:media_kit/src/player/native/player/player.dart' as native;

import '../../data/datasources/local/drift/app_database.dart' show Channel;
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
  extraLarge, // For very unstable connections
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
      case BufferSize.extraLarge:
        return 'Extra Large (60s)';
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
      case BufferSize.extraLarge:
        return 60;
    }
  }

  /// Minimum seconds to buffer before resuming playback after a stall
  int get minBufferBeforeResume {
    switch (this) {
      case BufferSize.small:
        return 1;
      case BufferSize.medium:
        return 2;
      case BufferSize.large:
        return 5;
      case BufferSize.veryLarge:
        return 10;
      case BufferSize.extraLarge:
        return 15;
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
      case BufferSize.extraLarge:
        return 'Maximum stability for very unstable connections';
    }
  }
}

/// Player state
class PlayerState {
  final bool isPlaying;
  final bool isBuffering;
  final bool isPrebuffering; // Waiting for initial buffer to fill
  final bool isReconnecting; // Auto-retry in progress
  final bool isFullscreen; // OS fullscreen (covers entire monitor)
  final bool isExpanded; // In-app expanded (player fills app window)
  final bool isPiPMode; // Picture-in-Picture mode (small always-on-top window)
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
    this.isExpanded = false,
    this.isPiPMode = false,
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
    bool? isExpanded,
    bool? isPiPMode,
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
      isExpanded: isExpanded ?? this.isExpanded,
      isPiPMode: isPiPMode ?? this.isPiPMode,
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

/// Player controller notifier - migrated to Riverpod 3.x Notifier
class PlayerControllerNotifier extends Notifier<PlayerState> {
  Player? _player;
  VideoController? _videoController;
  BufferSize _currentBufferSize = BufferSize.medium;
  bool _isPrebuffering = false;
  DateTime? _prebufferStartTime;
  Timer? _prebufferProgressTimer;
  Timer? _prebufferCompleteTimer;

  // Auto-retry state
  Channel? _currentChannel;
  int _retryAttempt = 0;
  static const int _maxRetries = 3;
  bool _isRetrying = false;
  Timer? _retryTimer;
  bool _autoRetryEnabled = true;

  // Stream subscriptions for cleanup
  final List<StreamSubscription> _subscriptions = [];

  // Track if disposed
  bool _isDisposed = false;

  @override
  PlayerState build() {
    _initPlayer();

    // Register disposal callback
    ref.onDispose(() {
      _isDisposed = true;
      _prebufferProgressTimer?.cancel();
      _prebufferCompleteTimer?.cancel();
      _retryTimer?.cancel();
      for (final sub in _subscriptions) {
        sub.cancel();
      }
      _subscriptions.clear();
      _player?.dispose();
    });

    return const PlayerState();
  }

  Player get player => _player!;
  VideoController get videoController => _videoController!;
  Channel? get currentChannel => _currentChannel;

  void _initPlayer() {
    AppLogger.info('=== INITIALIZING PLAYER ===');
    AppLogger.info('Platform: ${Platform.operatingSystem}');

    // Initialize with buffer size configuration
    // Use 4MB per second for high-bitrate streams (up to 32 Mbps for HD/4K IPTV)
    final bufferBytes = _currentBufferSize.durationSeconds * 4 * 1024 * 1024;
    AppLogger.info('Buffer size: ${bufferBytes ~/ 1024 ~/ 1024}MB');

    try {
      _player = Player(
        configuration: PlayerConfiguration(
          bufferSize: bufferBytes,
        ),
      );
      AppLogger.info('Player created successfully');

      // Configure VideoController with platform-specific settings
      const videoConfig = VideoControllerConfiguration(
        // Use hardware acceleration on real devices, software on emulators may help
        enableHardwareAcceleration: true,
      );
      _videoController = VideoController(_player!, configuration: videoConfig);
      AppLogger.info('VideoController created with config: enableHardwareAcceleration=${videoConfig.enableHardwareAcceleration}');
    } catch (e, stack) {
      AppLogger.error('Failed to initialize player: $e');
      AppLogger.error('Stack: $stack');
      rethrow;
    }

    // Apply MPV-specific buffer settings (desktop only)
    _applyBufferSettings();

    // Listen to player streams (store subscriptions for cleanup)
    _subscriptions.add(
      _player!.stream.playing.listen((playing) {
        if (!_isDisposed) state = state.copyWith(isPlaying: playing);
      }),
    );

    _subscriptions.add(
      _player!.stream.buffering.listen((buffering) {
        if (!_isDisposed) state = state.copyWith(isBuffering: buffering);
      }),
    );

    _subscriptions.add(
      _player!.stream.buffer.listen((buffer) {
        if (!_isDisposed) state = state.copyWith(bufferedDuration: buffer);
      }),
    );

    _subscriptions.add(
      _player!.stream.volume.listen((volume) {
        if (!_isDisposed) state = state.copyWith(volume: volume / 100);
      }),
    );

    _subscriptions.add(
      _player!.stream.position.listen((position) {
        if (!_isDisposed) state = state.copyWith(position: position);
      }),
    );

    _subscriptions.add(
      _player!.stream.duration.listen((duration) {
        if (!_isDisposed) state = state.copyWith(duration: duration);
      }),
    );

    _subscriptions.add(
      _player!.stream.error.listen((error) {
        if (error.isNotEmpty && !_isDisposed) {
          AppLogger.error('Player error: $error');
          state = state.copyWith(error: error);
          _handleStreamError(error);
        }
      }),
    );

    _subscriptions.add(
      _player!.stream.completed.listen((completed) {
        if (completed && _currentChannel != null && _autoRetryEnabled && !_isDisposed) {
          AppLogger.warning('Stream completed unexpectedly, attempting reconnect');
          _handleStreamError('Stream ended');
        }
      }),
    );

    _subscriptions.add(
      _player!.stream.tracks.listen((tracks) {
        if (_isDisposed) return;

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
      }),
    );

    _subscriptions.add(
      _player!.stream.track.listen((track) {
        if (!_isDisposed) {
          state = state.copyWith(
            currentVideoTrack: track.video.id,
            currentAudioTrack: track.audio.id,
            currentSubtitleTrack: track.subtitle.id,
          );
        }
      }),
    );
  }

  /// Apply MPV-specific buffer settings via NativePlayer
  /// Optimized for live IPTV streaming stability
  Future<void> _applyBufferSettings() async {
    try {
      if (_player?.platform is native.NativePlayer) {
        final nativePlayer = _player!.platform as native.NativePlayer;
        final bufferSecs = _currentBufferSize.durationSeconds;
        final minResumeBuffer = _currentBufferSize.minBufferBeforeResume;

        // Calculate buffer size: 4MB per second for high-bitrate streams (up to 32 Mbps)
        // This is more generous than before to handle HD/4K IPTV streams
        final bufferBytes = bufferSecs * 4 * 1024 * 1024;

        // ===== Core Cache Settings =====
        await nativePlayer.setProperty('cache', 'yes');
        await nativePlayer.setProperty('cache-secs', bufferSecs.toString());

        // ===== Network Timeout Settings =====
        // Increase timeouts to handle slow/unstable networks
        await nativePlayer.setProperty('network-timeout', '30'); // 30 sec network timeout
        await nativePlayer.setProperty('stream-lavf-o', 'reconnect=1,reconnect_streamed=1,reconnect_delay_max=5');

        // ===== Demuxer Buffer Settings =====
        await nativePlayer.setProperty('demuxer-max-bytes', bufferBytes.toString());
        await nativePlayer.setProperty('demuxer-max-back-bytes', (bufferBytes ~/ 2).toString());
        await nativePlayer.setProperty('demuxer-readahead-secs', bufferSecs.toString());

        // ===== Cache Pause/Resume Settings =====
        // These are critical for stable playback - pause when buffer is low, resume when refilled
        await nativePlayer.setProperty('cache-pause', 'yes');
        await nativePlayer.setProperty('cache-pause-initial', 'yes');
        await nativePlayer.setProperty('cache-pause-wait', minResumeBuffer.toString());

        // For larger buffers, wait for cache to fill before playing
        if (bufferSecs > 1) {
          await nativePlayer.setProperty('demuxer-cache-wait', 'yes');
        }

        // ===== HLS-specific Optimizations =====
        // Many IPTV streams use HLS - optimize for it
        await nativePlayer.setProperty('hls-bitrate', 'max'); // Use highest quality
        await nativePlayer.setProperty('demuxer-lavf-o', 'live_start_index=-3'); // Start 3 segments back

        // ===== Stability Settings =====
        await nativePlayer.setProperty('force-seekable', 'yes'); // Allow seeking in live streams
        await nativePlayer.setProperty('hr-seek', 'yes'); // Accurate seeking

        AppLogger.info(
          'Applied MPV buffer settings: cache-secs=$bufferSecs, '
          'buffer=${bufferBytes ~/ 1024 ~/ 1024}MB, '
          'cache-pause-wait=$minResumeBuffer, '
          'network-timeout=30s'
        );
      }
    } catch (e) {
      AppLogger.warning('Could not apply MPV buffer settings: $e');
    }
  }

  /// Complete prebuffering and start playback
  void _completePrebuffering() {
    if (!_isPrebuffering || _isDisposed) return;

    _isPrebuffering = false;
    _prebufferStartTime = null;
    _prebufferProgressTimer?.cancel();
    _prebufferProgressTimer = null;
    _prebufferCompleteTimer = null;
    state = state.copyWith(isPrebuffering: false, bufferedDuration: Duration.zero);
    _player!.play();
    AppLogger.info('Prebuffer complete, starting playback');
  }

  /// Cancel prebuffering (used when stopping or changing channels)
  void _cancelPrebuffering() {
    _isPrebuffering = false;
    _prebufferStartTime = null;
    _prebufferProgressTimer?.cancel();
    _prebufferProgressTimer = null;
    _prebufferCompleteTimer?.cancel();
    _prebufferCompleteTimer = null;
    state = state.copyWith(isPrebuffering: false, bufferedDuration: Duration.zero);
  }

  /// Start periodic prebuffer progress updates
  void _startPrebufferProgress() {
    _prebufferProgressTimer?.cancel();
    _prebufferProgressTimer = Timer.periodic(
      const Duration(milliseconds: 100),
      (_) {
        if (!_isPrebuffering || _prebufferStartTime == null || _isDisposed) {
          _prebufferProgressTimer?.cancel();
          _prebufferProgressTimer = null;
          return;
        }
        final elapsed = DateTime.now().difference(_prebufferStartTime!);
        state = state.copyWith(bufferedDuration: elapsed);
      },
    );
  }

  /// Handle stream errors with auto-retry
  void _handleStreamError(String error) {
    if (!_autoRetryEnabled || _currentChannel == null || _isRetrying || _isDisposed) return;

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

    // Calculate delay with exponential backoff + jitter: ~1s, ~2s, ~4s
    final baseDelayMs = (1 << _retryAttempt) * 1000; // 2^retryAttempt seconds
    final jitter = (baseDelayMs * 0.25 * (2 * Random().nextDouble() - 1)).toInt();
    final delayMs = baseDelayMs + jitter;
    _retryAttempt++;

    AppLogger.info('Stream error, retry attempt $_retryAttempt/$_maxRetries in ${delayMs}ms');

    state = state.copyWith(
      isReconnecting: true,
      retryAttempt: _retryAttempt,
      error: null, // Clear error during retry
    );

    _retryTimer?.cancel();
    _retryTimer = Timer(Duration(milliseconds: delayMs), () {
      _attemptReconnect();
    });
  }

  /// Attempt to reconnect to the current channel
  Future<void> _attemptReconnect() async {
    if (_currentChannel == null || _isDisposed) return;

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
        if (!_isDisposed) {
          state = state.copyWith(
            isReconnecting: false,
            retryAttempt: 0,
            error: null,
          );
        }
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
    _retryTimer?.cancel();
    _retryTimer = null;
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

      // Enhanced logging for debugging
      AppLogger.info('=== PLAY CHANNEL START ===');
      AppLogger.info('Channel: ${channel.name}');
      AppLogger.info('Stream URL: ${AppLogger.redactUrl(channel.streamUrl)}');
      AppLogger.info('Buffer size: ${_currentBufferSize.displayName}');
      AppLogger.info('Platform: ${Platform.operatingSystem}');

      // Apply buffer settings before playing (desktop only - uses MPV)
      await _applyBufferSettings();

      AppLogger.info('Opening media stream...');

      // Open the stream
      await _player!.open(Media(channel.streamUrl), play: bufferSeconds <= 1);

      AppLogger.info('Media opened successfully, play=${bufferSeconds <= 1}');

      // For buffer sizes > 1 second, wait before playing
      if (bufferSeconds > 1) {
        _isPrebuffering = true;
        _prebufferStartTime = DateTime.now();

        // Start periodic progress updates
        _startPrebufferProgress();

        // Schedule playback start after buffer duration
        AppLogger.info('Prebuffering for ${bufferSeconds}s...');
        _prebufferCompleteTimer = Timer(Duration(seconds: bufferSeconds), () {
          _completePrebuffering();
        });
      }
    } catch (e, stack) {
      AppLogger.error('=== PLAY CHANNEL FAILED ===');
      AppLogger.error('Error: $e');
      AppLogger.error('Stack: $stack');
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
    if (tracks.isEmpty) return;
    final track = tracks.firstWhere(
      (t) => t.id == trackId,
      orElse: () => tracks[0],
    );
    await _player!.setVideoTrack(track);
    AppLogger.info('Video track set: $trackId');
  }

  /// Set audio track
  Future<void> setAudioTrack(String trackId) async {
    final tracks = _player!.state.tracks.audio;
    if (tracks.isEmpty) return;
    final track = tracks.firstWhere(
      (t) => t.id == trackId,
      orElse: () => tracks[0],
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

  // ===== Display Mode Methods =====

  /// Toggle in-app expanded mode (player fills app window, hides sidebar/grid)
  void toggleExpanded() {
    setExpanded(!state.isExpanded);
  }

  /// Set in-app expanded mode
  void setExpanded(bool expanded) {
    // Exit other modes when entering expanded
    if (expanded && state.isPiPMode) {
      setPiPMode(false);
    }
    state = state.copyWith(isExpanded: expanded);
    AppLogger.info('Expanded mode: $expanded');
  }

  /// Saved window state for restoring after PiP
  Size? _savedWindowSize;
  Offset? _savedWindowPosition;
  bool _savedAlwaysOnTop = false;

  /// Toggle Picture-in-Picture mode (small always-on-top window)
  Future<void> togglePiPMode() async {
    await setPiPMode(!state.isPiPMode);
  }

  /// Set Picture-in-Picture mode
  Future<void> setPiPMode(bool pip) async {
    if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) {
      AppLogger.warning('PiP mode only supported on desktop');
      return;
    }

    try {
      await windowManager.ensureInitialized();

      if (pip) {
        // Save current window state before entering PiP
        _savedWindowSize = await windowManager.getSize();
        _savedWindowPosition = await windowManager.getPosition();
        _savedAlwaysOnTop = await windowManager.isAlwaysOnTop();

        // Exit fullscreen if active
        if (state.isFullscreen) {
          await windowManager.setFullScreen(false);
        }

        // Configure PiP window: small, always on top, positioned in corner
        await windowManager.setAlwaysOnTop(true);
        const pipSize = Size(400, 250);
        await windowManager.setSize(pipSize);

        // Position in bottom-right area relative to the previous window bounds
        const padding = 20.0;
        final savedPos = _savedWindowPosition ?? Offset.zero;
        final savedSize = _savedWindowSize ?? const Size(1280, 720);
        final right = savedPos.dx + savedSize.width;
        final bottom = savedPos.dy + savedSize.height;
        await windowManager.setPosition(Offset(
          right - pipSize.width - padding,
          bottom - pipSize.height - padding,
        ),);

        state = state.copyWith(
          isPiPMode: true,
          isFullscreen: false,
          isExpanded: false,
        );
        AppLogger.info('Entered PiP mode');
      } else {
        // Restore previous window state
        await windowManager.setAlwaysOnTop(_savedAlwaysOnTop);

        if (_savedWindowSize != null) {
          await windowManager.setSize(_savedWindowSize!);
        }
        if (_savedWindowPosition != null) {
          await windowManager.setPosition(_savedWindowPosition!);
        }

        state = state.copyWith(isPiPMode: false);
        AppLogger.info('Exited PiP mode');
      }
    } catch (e) {
      AppLogger.error('Failed to toggle PiP mode: $e');
    }
  }

  /// Open current stream in external player (VLC, mpv, etc.)
  ///
  /// Uses direct process invocation (no shell) to prevent command injection
  /// from malicious stream URLs in untrusted M3U playlists.
  Future<bool> openInExternalPlayer() async {
    if (_currentChannel == null) {
      AppLogger.warning('No channel to open in external player');
      return false;
    }

    final streamUrl = _currentChannel!.streamUrl;

    // Validate URL scheme to prevent file:// or other dangerous URIs
    final uri = Uri.tryParse(streamUrl);
    if (uri == null || !['http', 'https', 'rtsp', 'rtmp'].contains(uri.scheme)) {
      AppLogger.warning('Refusing to open non-network URL in external player');
      return false;
    }

    try {
      if (Platform.isWindows) {
        // Try VLC directly (no shell, URL passed as argument)
        try {
          final vlcResult = await Process.run('vlc', [streamUrl]);
          if (vlcResult.exitCode == 0) {
            AppLogger.info('Opened stream in VLC');
            return true;
          }
        } catch (_) {
          // VLC not in PATH, try common install locations
        }

        // Try VLC from default install path
        const vlcPaths = [
          r'C:\Program Files\VideoLAN\VLC\vlc.exe',
          r'C:\Program Files (x86)\VideoLAN\VLC\vlc.exe',
        ];
        for (final vlcPath in vlcPaths) {
          try {
            final result = await Process.run(vlcPath, [streamUrl]);
            if (result.exitCode == 0) {
              AppLogger.info('Opened stream in VLC');
              return true;
            }
          } catch (_) {
            continue;
          }
        }

        // Fallback: use PowerShell Start-Process (safe, no shell injection)
        final result = await Process.run(
          'powershell',
          ['-NoProfile', '-Command', 'Start-Process', streamUrl],
        );
        if (result.exitCode == 0) {
          AppLogger.info('Opened stream with system default player');
          return true;
        }
      } else if (Platform.isMacOS) {
        // Try VLC first (no shell)
        final result = await Process.run(
          'open',
          ['-a', 'VLC', streamUrl],
        );

        if (result.exitCode == 0) {
          AppLogger.info('Opened stream in VLC');
          return true;
        }

        // Fallback to default handler (no shell)
        await Process.run('open', [streamUrl]);
        return true;
      } else if (Platform.isLinux) {
        // Try common players in order (no shell)
        for (final player in ['vlc', 'mpv', 'celluloid', 'xdg-open']) {
          try {
            final result = await Process.run(player, [streamUrl]);
            if (result.exitCode == 0) {
              AppLogger.info('Opened stream in $player');
              return true;
            }
          } catch (_) {
            continue;
          }
        }
      }

      AppLogger.warning('Could not open stream in external player');
      return false;
    } catch (e) {
      AppLogger.error('Failed to open in external player: $e');
      return false;
    }
  }

  /// Open current channel in a new FlowTV window
  /// NOTE: Multi-window feature requires additional native code setup.
  /// For now, this feature is disabled. Use external player (VLC) instead.
  Future<bool> openInNewWindow() async {
    if (_currentChannel == null) {
      AppLogger.warning('No channel to open in new window');
      return false;
    }

    // Multi-window support requires native code integration that isn't complete yet.
    // The desktop_multi_window package needs additional setup in main.cpp.
    // For now, we recommend using the "Open in External Player" option instead.
    AppLogger.warning('Multi-window feature not yet available. Use external player instead.');
    return false;
  }
}

/// Video player controller provider
final playerControllerProvider =
    NotifierProvider<PlayerControllerNotifier, PlayerState>(
  PlayerControllerNotifier.new,
);
