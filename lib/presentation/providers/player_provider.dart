import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
// ignore: implementation_imports
import 'package:media_kit/src/player/native/player/player.dart' as native_player;
import 'package:media_kit_video/media_kit_video.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:drift/drift.dart' show Value;

import '../../data/datasources/local/database_service.dart';
import '../../core/utils/logger.dart';
import '../../core/utils/mpv_buffer_config.dart';
import '../../core/models/buffer_size.dart';
export '../../core/models/buffer_size.dart';

import 'player/prebuffer_controller.dart';
import 'player/retry_controller.dart';
import 'player/display_mode_controller.dart';
import 'player/external_player_launcher.dart';

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
  final bool isPrebuffering; // Waiting for initial buffer to fill
  final bool isReconnecting; // Auto-retry in progress
  final bool isFullscreen; // OS fullscreen (covers entire monitor)
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
    bool? isPiPMode,
    double? volume,
    bool? isMuted,
    Duration? position,
    Duration? duration,
    Duration? bufferedDuration,
    String? error,
    bool clearError = false,
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
      isPiPMode: isPiPMode ?? this.isPiPMode,
      volume: volume ?? this.volume,
      isMuted: isMuted ?? this.isMuted,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      bufferedDuration: bufferedDuration ?? this.bufferedDuration,
      error: clearError ? null : (error ?? this.error),
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

  // Delegate controllers
  final PrebufferController _prebuffer = PrebufferController();
  final RetryController _retry = RetryController();
  final DisplayModeController _displayMode = DisplayModeController();
  final ExternalPlayerLauncher _externalPlayer = ExternalPlayerLauncher();

  // Channel currently being played (needed for retry & external player)
  Channel? _currentChannel;

  // Saved volume for mute/unmute (the stream listener overwrites state.volume)
  double _preMuteVolume = 1.0;

  // Stream subscriptions for cleanup
  final List<StreamSubscription> _subscriptions = [];

  // Track if disposed
  bool _isDisposed = false;

  // Watchdog for streams that connect but never deliver data. Some IPTV
  // servers accept the connection and send nothing, so mpv's network-timeout
  // never fires and no error event ever arrives — without this, the player
  // spins on "buffering" forever.
  Timer? _openStallTimer;
  static const _openStallTimeout = Duration(seconds: 20);

  @override
  PlayerState build() {
    // Clean up from any prior build() call (Notifier.build() re-runs on invalidation)
    _isDisposed = false;
    _prebuffer.dispose();
    _retry.dispose();
    _openStallTimer?.cancel();
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
    _player?.dispose();
    _player = null;
    _videoController = null;

    _loadBufferSizeFromDb();
    _initPlayer();

    // Reconnect reopens can stall silently just like the initial open.
    _retry.onOpenAttempt = _armOpenStallWatchdog;

    // Register disposal callback
    ref.onDispose(() {
      _isDisposed = true;
      _prebuffer.dispose();
      _retry.dispose();
      _openStallTimer?.cancel();
      for (final sub in _subscriptions) {
        sub.cancel();
      }
      _subscriptions.clear();
      _player?.dispose();
      // Ensure screen can sleep when provider is disposed
      try {
        WakelockPlus.disable();
      } catch (e) {
        // Silently ignore — app may be shutting down
      }
    });

    return const PlayerState();
  }

  /// Load persisted buffer size from database
  Future<void> _loadBufferSizeFromDb() async {
    try {
      final db = DatabaseService.instance;
      final settings = await (db.select(db.appSettingsTable)..limit(1)).getSingle();
      var saved = _bufferSizeFromSeconds(settings.bufferSeconds);
      // Cap extraLarge on mobile — 240MB causes OOM on most devices
      if ((Platform.isAndroid || Platform.isIOS) && saved == BufferSize.extraLarge) {
        saved = BufferSize.large;
        AppLogger.warning('Extra large buffer capped to large on mobile');
      }
      if (saved != _currentBufferSize) {
        _currentBufferSize = saved;
        state = state.copyWith(bufferSize: saved);
        await _applyBufferSettings();
        AppLogger.info('Loaded buffer size from DB: ${saved.displayName}');
      }
    } catch (e) {
      AppLogger.warning('Could not load buffer size from database: $e');
    }
  }

  /// Convert seconds to BufferSize enum (nearest match)
  static BufferSize _bufferSizeFromSeconds(int seconds) {
    if (seconds <= 3) return BufferSize.small;
    if (seconds <= 5) return BufferSize.medium;
    if (seconds <= 15) return BufferSize.large;
    if (seconds <= 30) return BufferSize.veryLarge;
    return BufferSize.extraLarge;
  }

  /// Persist buffer size to database
  Future<void> _persistBufferSize(BufferSize size) async {
    try {
      final db = DatabaseService.instance;
      await (db.update(db.appSettingsTable)..where((t) => t.id.equals(1)))
          .write(AppSettingsTableCompanion(bufferSeconds: Value(size.durationSeconds)));
    } catch (e) {
      AppLogger.warning('Could not save buffer size to database: $e');
    }
  }

  Player get player {
    final p = _player;
    if (p == null) throw StateError('Player not initialized');
    return p;
  }

  VideoController get videoController {
    final vc = _videoController;
    if (vc == null) throw StateError('VideoController not initialized');
    return vc;
  }
  Channel? get currentChannel => _currentChannel;

  /// Helper to pass a state-updating function to delegate controllers.
  void _updateState(PlayerState Function(PlayerState) transform) {
    if (!_isDisposed) {
      state = transform(state);
    }
  }

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
        if (_isDisposed) return;
        // Don't overwrite volume state while muted (keep showing pre-mute volume)
        if (!state.isMuted) {
          state = state.copyWith(volume: volume / 100);
        }
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
          _retry.handleStreamError(
            error,
            player: _player,
            channel: _currentChannel,
            updateState: _updateState,
          );
        }
      }),
    );

    _subscriptions.add(
      _player!.stream.completed.listen((completed) {
        if (completed && _currentChannel != null && _retry.autoRetryEnabled && !_isDisposed) {
          AppLogger.warning('Stream completed unexpectedly, attempting reconnect');
          _retry.handleStreamError(
            'Stream ended',
            player: _player,
            channel: _currentChannel,
            updateState: _updateState,
          );
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

  /// Apply MPV-specific buffer settings via shared utility
  Future<void> _applyBufferSettings() async {
    final player = _player;
    if (player == null) return;
    await applyMpvBufferSettings(player, _currentBufferSize);
  }

  /// Enable or disable auto-retry
  void setAutoRetryEnabled(bool enabled) {
    _retry.autoRetryEnabled = enabled;
    AppLogger.info('Auto-retry ${enabled ? 'enabled' : 'disabled'}');
  }

  /// Play a channel with current buffer settings
  Future<void> playChannel(Channel channel) async {
    try {
      // Cancel any existing prebuffer and retry
      _prebuffer.cancelPrebuffering();
      state = state.copyWith(isPrebuffering: false, bufferedDuration: Duration.zero);
      _retry.cancelRetry(_updateState);

      // Store current channel for auto-retry
      _currentChannel = channel;

      state = state.copyWith(
        clearError: true,
        isBuffering: true,
        isPrebuffering: false,
        isReconnecting: false,
        bufferedDuration: Duration.zero,
        retryAttempt: 0,
        videoTracks: const [],
        audioTracks: const [],
        subtitleTracks: const [],
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

      // Always open with play=true — MPV's cache-pause-initial and
      // cache-pause-wait settings handle prebuffering natively. Opening
      // with play=false on live MPEG-TS streams causes the server to
      // drop the stalled connection.
      if (_player == null) return;
      // Armed BEFORE open: on a silent server this await never returns.
      _armOpenStallWatchdog();
      await _player!.open(Media(channel.streamUrl), play: true);

      AppLogger.info('Media opened successfully, play=true');

      // Keep screen awake during playback
      try {
        WakelockPlus.enable();
      } catch (e) {
        AppLogger.warning('Could not enable wakelock: $e');
      }
    } catch (e, stack) {
      AppLogger.error('=== PLAY CHANNEL FAILED ===');
      AppLogger.error('Error: $e');
      AppLogger.error('Stack: $stack');
      _prebuffer.cancelPrebuffering();
      state = state.copyWith(isPrebuffering: false, bufferedDuration: Duration.zero, error: e.toString());
    }
  }

  /// Arm (or re-arm) the open-stall watchdog. If the stream hasn't reached
  /// healthy playback when it fires — and no error/retry flow has taken over
  /// by producing an error state — the stream is declared dead: the stalled
  /// connection is aborted (freeing the provider's connection slot) and the
  /// error card with its Retry button is shown. A healthy stream makes the
  /// timer a no-op, so there is no need to cancel it on success.
  void _armOpenStallWatchdog() {
    _openStallTimer?.cancel();
    _openStallTimer = Timer(_openStallTimeout, () {
      if (_isDisposed || _currentChannel == null) return;
      if (state.error != null) return; // error card already showing
      if (state.isPlaying && !state.isBuffering) return; // stream is healthy
      AppLogger.warning(
          'Stream stalled: no playback ${_openStallTimeout.inSeconds}s after '
          'open and no error from mpv — giving up');
      // A server that answers but sends nothing is not a transient failure;
      // don't burn retry attempts on it. Manual Retry stays available.
      _retry.resetRetryState();
      // stop() aborts the hung open and closes the connection.
      _player?.stop().catchError((Object e) {
        AppLogger.warning('Stall watchdog: player stop failed: $e');
      });
      state = state.copyWith(
        isBuffering: false,
        isPrebuffering: false,
        isReconnecting: false,
        retryAttempt: 0,
        error:
            'The channel is not sending any data — it may be offline right now.',
      );
    });
  }

  /// Fully release the native player before the Android activity finishes.
  ///
  /// Exiting with a live video texture crashes the app: the engine's
  /// ImageReaderSurfaceProducer delivers leftover frames after FlutterJNI
  /// detaches (flutter/flutter#188300). Awaiting the player's disposal tears
  /// the texture down first so no callback can fire into the dead engine.
  Future<void> shutdownForExit() async {
    _isDisposed = true;
    _openStallTimer?.cancel();
    _prebuffer.dispose();
    _retry.dispose();
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
    _currentChannel = null;

    final player = _player;
    _player = null;
    _videoController = null;
    if (player != null) {
      await player.dispose();
    }

    try {
      WakelockPlus.disable();
    } catch (_) {
      // App is exiting — nothing to do.
    }
  }

  /// Refresh/reload the current channel (useful for frozen streams)
  Future<void> refreshChannel(Channel channel) async {
    try {
      AppLogger.info('Refreshing channel: ${channel.name}');
      await _player?.stop();
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

    // Persist to database
    _persistBufferSize(size);

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
    await _player?.playOrPause();
  }

  /// Play
  Future<void> play() async {
    await _player?.play();
  }

  /// Pause
  Future<void> pause() async {
    await _player?.pause();
  }

  /// Stop playback and release the stream connection.
  Future<void> stop() async {
    _openStallTimer?.cancel();
    _prebuffer.cancelPrebuffering();
    state = state.copyWith(isPrebuffering: false, bufferedDuration: Duration.zero);
    _retry.cancelRetry(_updateState);
    _currentChannel = null;

    // Disable mpv's auto-reconnect before stopping to ensure the HTTP
    // connection is actually closed, not kept alive for reuse.
    final player = _player;
    if (player != null) {
      try {
        final nativePlayer = player.platform;
        if (nativePlayer is native_player.NativePlayer) {
          await nativePlayer.setProperty('stream-open-filename', '');
        }
      } catch (_) {}
      await player.stop();
    }
    // Allow screen to sleep when not playing
    try {
      WakelockPlus.disable();
    } catch (e) {
      AppLogger.warning('Could not disable wakelock: $e');
    }
  }

  /// Set volume (0.0 to 1.0)
  Future<void> setVolume(double volume) async {
    await _player?.setVolume(volume * 100);
  }

  /// Toggle mute
  void toggleMute() {
    final player = _player;
    if (player == null) return;
    if (state.isMuted) {
      // Restore the saved volume
      player.setVolume(_preMuteVolume * 100);
    } else {
      // Save current volume before muting
      _preMuteVolume = state.volume > 0 ? state.volume : 1.0;
      player.setVolume(0);
    }
    state = state.copyWith(isMuted: !state.isMuted);
  }

  /// Seek to position
  Future<void> seek(Duration position) async {
    await _player?.seek(position);
  }

  /// Toggle fullscreen
  Future<void> toggleFullscreen() async {
    await _displayMode.toggleFullscreen(
      state.isFullscreen,
      onChanged: (fullscreen) {
        state = state.copyWith(isFullscreen: fullscreen);
      },
    );
  }

  /// Set fullscreen state
  Future<void> setFullscreen(bool fullscreen) async {
    await _displayMode.setFullscreen(
      fullscreen,
      onChanged: (fs) {
        state = state.copyWith(isFullscreen: fs);
      },
    );
  }

  /// Set video track
  Future<void> setVideoTrack(String trackId) async {
    final tracks = _player?.state.tracks.video ?? [];
    if (tracks.isEmpty) return;
    final track = tracks.firstWhere(
      (t) => t.id == trackId,
      orElse: () => tracks[0],
    );
    await _player?.setVideoTrack(track);
    AppLogger.info('Video track set: $trackId');
  }

  /// Set audio track
  Future<void> setAudioTrack(String trackId) async {
    final tracks = _player?.state.tracks.audio ?? [];
    if (tracks.isEmpty) return;
    final track = tracks.firstWhere(
      (t) => t.id == trackId,
      orElse: () => tracks[0],
    );
    await _player?.setAudioTrack(track);
    AppLogger.info('Audio track set: $trackId');
  }

  /// Set subtitle track
  Future<void> setSubtitleTrack(String? trackId) async {
    if (_player == null) return;
    if (trackId == null) {
      await _player?.setSubtitleTrack(SubtitleTrack.no());
      AppLogger.info('Subtitles disabled');
      return;
    }
    final tracks = _player?.state.tracks.subtitle ?? [];
    final track = tracks.firstWhere(
      (t) => t.id == trackId,
      orElse: () => SubtitleTrack.no(),
    );
    await _player?.setSubtitleTrack(track);
    AppLogger.info('Subtitle track set: $trackId');
  }

  /// Set playback speed
  Future<void> setPlaybackSpeed(double speed) async {
    await _player?.setRate(speed);
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

  /// Toggle Picture-in-Picture mode (small always-on-top window)
  Future<void> togglePiPMode() async {
    await _displayMode.togglePiPMode(
      currentPiP: state.isPiPMode,
      currentFullscreen: state.isFullscreen,
      onChanged: ({required bool isPiP, bool? isFullscreen}) {
        state = state.copyWith(
          isPiPMode: isPiP,
          isFullscreen: isFullscreen ?? state.isFullscreen,
        );
      },
    );
  }

  /// Set Picture-in-Picture mode
  Future<void> setPiPMode(bool pip) async {
    await _displayMode.setPiPMode(
      pip,
      currentFullscreen: state.isFullscreen,
      onChanged: ({required bool isPiP, bool? isFullscreen}) {
        state = state.copyWith(
          isPiPMode: isPiP,
          isFullscreen: isFullscreen ?? state.isFullscreen,
        );
      },
    );
  }

  /// Open current stream in external player (VLC, mpv, etc.)
  Future<bool> openInExternalPlayer() async {
    if (_currentChannel == null) {
      AppLogger.warning('No channel to open in external player');
      return false;
    }
    return _externalPlayer.openInExternalPlayer(_currentChannel!.streamUrl);
  }

}

/// Video player controller provider
final playerControllerProvider =
    NotifierProvider<PlayerControllerNotifier, PlayerState>(
  PlayerControllerNotifier.new,
);
