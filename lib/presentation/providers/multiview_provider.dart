import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
// ignore: implementation_imports
import 'package:media_kit/src/player/native/player/player.dart' as native;

import '../../data/datasources/local/drift/app_database.dart' show Channel;
import '../../core/utils/logger.dart';
import 'player_provider.dart' show BufferSize, BufferSizeExtension;

/// Maximum number of views in multi-view mode
const int maxMultiViewChannels = 4;

/// Multi-view slot state
class MultiViewSlot {
  final int index;
  final Channel? channel;
  final Player player;
  final VideoController videoController;
  final bool isPlaying;
  final bool isBuffering;
  final bool isAudioActive;
  final String? error;

  MultiViewSlot({
    required this.index,
    this.channel,
    required this.player,
    required this.videoController,
    this.isPlaying = false,
    this.isBuffering = false,
    this.isAudioActive = false,
    this.error,
  });

  MultiViewSlot copyWith({
    Channel? channel,
    bool? isPlaying,
    bool? isBuffering,
    bool? isAudioActive,
    String? error,
    bool clearChannel = false,
    bool clearError = false,
  }) {
    return MultiViewSlot(
      index: index,
      channel: clearChannel ? null : (channel ?? this.channel),
      player: player,
      videoController: videoController,
      isPlaying: isPlaying ?? this.isPlaying,
      isBuffering: isBuffering ?? this.isBuffering,
      isAudioActive: isAudioActive ?? this.isAudioActive,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// Multi-view state
class MultiViewState {
  final List<MultiViewSlot> slots;
  final bool isEnabled;
  final int activeAudioSlot;

  const MultiViewState({
    required this.slots,
    this.isEnabled = false,
    this.activeAudioSlot = 0,
  });

  MultiViewState copyWith({
    List<MultiViewSlot>? slots,
    bool? isEnabled,
    int? activeAudioSlot,
  }) {
    return MultiViewState(
      slots: slots ?? this.slots,
      isEnabled: isEnabled ?? this.isEnabled,
      activeAudioSlot: activeAudioSlot ?? this.activeAudioSlot,
    );
  }
}

/// Multi-view controller notifier - migrated to Riverpod 3.x Notifier
class MultiViewControllerNotifier extends Notifier<MultiViewState> {
  // Use medium buffer for multi-view (balance between stability and resources)
  static const BufferSize _bufferSize = BufferSize.medium;

  @override
  MultiViewState build() {
    // Initialize slots when building
    final slots = <MultiViewSlot>[];

    // Calculate buffer size: 4MB per second for high-bitrate streams
    final bufferBytes = _bufferSize.durationSeconds * 4 * 1024 * 1024;

    for (int i = 0; i < maxMultiViewChannels; i++) {
      final player = Player(
        configuration: PlayerConfiguration(
          bufferSize: bufferBytes,
        ),
      );
      final videoController = VideoController(player);

      // Set up listeners for each player
      _setupPlayerListeners(i, player);

      // Apply MPV-specific buffer settings
      _applyBufferSettings(player, i);

      slots.add(MultiViewSlot(
        index: i,
        player: player,
        videoController: videoController,
        isAudioActive: i == 0, // First slot has audio by default
      ),);
    }

    // Register disposal callback
    ref.onDispose(() {
      for (final slot in state.slots) {
        slot.player.dispose();
      }
    });

    final initialState = MultiViewState(slots: slots, activeAudioSlot: 0);

    // Schedule audio state update after build
    Future.microtask(() => _updateAudioState());

    return initialState;
  }

  /// Apply MPV-specific buffer settings for stable streaming
  Future<void> _applyBufferSettings(Player player, int slotIndex) async {
    try {
      if (player.platform is native.NativePlayer) {
        final nativePlayer = player.platform as native.NativePlayer;
        final bufferSecs = _bufferSize.durationSeconds;
        final minResumeBuffer = _bufferSize.minBufferBeforeResume;
        final bufferBytes = bufferSecs * 4 * 1024 * 1024;

        // Core cache settings
        await nativePlayer.setProperty('cache', 'yes');
        await nativePlayer.setProperty('cache-secs', bufferSecs.toString());

        // Network timeout settings
        await nativePlayer.setProperty('network-timeout', '30');
        await nativePlayer.setProperty('stream-lavf-o', 'reconnect=1,reconnect_streamed=1,reconnect_delay_max=5');

        // Demuxer buffer settings
        await nativePlayer.setProperty('demuxer-max-bytes', bufferBytes.toString());
        await nativePlayer.setProperty('demuxer-max-back-bytes', (bufferBytes ~/ 2).toString());
        await nativePlayer.setProperty('demuxer-readahead-secs', bufferSecs.toString());

        // Cache pause/resume settings
        await nativePlayer.setProperty('cache-pause', 'yes');
        await nativePlayer.setProperty('cache-pause-initial', 'yes');
        await nativePlayer.setProperty('cache-pause-wait', minResumeBuffer.toString());

        if (bufferSecs > 1) {
          await nativePlayer.setProperty('demuxer-cache-wait', 'yes');
        }

        // HLS optimizations
        await nativePlayer.setProperty('hls-bitrate', 'max');
        await nativePlayer.setProperty('demuxer-lavf-o', 'live_start_index=-3');

        // Stability settings
        await nativePlayer.setProperty('force-seekable', 'yes');
        await nativePlayer.setProperty('hr-seek', 'yes');

        AppLogger.info(
          'MultiView slot $slotIndex: Applied buffer settings (${_bufferSize.displayName})',
        );
      }
    } catch (e) {
      AppLogger.warning('MultiView slot $slotIndex: Could not apply buffer settings: $e');
    }
  }

  void _setupPlayerListeners(int index, Player player) {
    player.stream.playing.listen((playing) {
      // When playback starts successfully, clear any previous error
      if (playing) {
        _updateSlot(index, (slot) => slot.copyWith(isPlaying: true, clearError: true));
      } else {
        _updateSlot(index, (slot) => slot.copyWith(isPlaying: false));
      }
    });

    player.stream.buffering.listen((buffering) {
      _updateSlot(index, (slot) => slot.copyWith(isBuffering: buffering));
    });

    player.stream.error.listen((error) {
      if (error.isNotEmpty) {
        AppLogger.error('MultiView slot $index error: $error');
        _updateSlot(index, (slot) => slot.copyWith(error: error));
      }
    });
  }

  void _updateSlot(int index, MultiViewSlot Function(MultiViewSlot) updater) {
    final newSlots = List<MultiViewSlot>.from(state.slots);
    if (index >= 0 && index < newSlots.length) {
      newSlots[index] = updater(newSlots[index]);
      state = state.copyWith(slots: newSlots);
    }
  }

  /// Enable multi-view mode
  void enableMultiView() {
    state = state.copyWith(isEnabled: true);
    AppLogger.info('Multi-view enabled');
  }

  /// Disable multi-view mode and stop all players
  Future<void> disableMultiView() async {
    for (final slot in state.slots) {
      await slot.player.stop();
    }

    final newSlots = state.slots
        .map((slot) => slot.copyWith(clearChannel: true, clearError: true))
        .toList();

    state = state.copyWith(
      isEnabled: false,
      slots: newSlots,
      activeAudioSlot: 0,
    );
    _updateAudioState();
    AppLogger.info('Multi-view disabled');
  }

  /// Add a channel to a specific slot
  Future<void> setChannelInSlot(int slotIndex, Channel channel) async {
    if (slotIndex < 0 || slotIndex >= state.slots.length) return;

    final slot = state.slots[slotIndex];

    try {
      _updateSlot(
        slotIndex,
        (s) => s.copyWith(
          channel: channel,
          clearError: true,
          isBuffering: true,
        ),
      );

      await slot.player.open(Media(channel.streamUrl));
      AppLogger.info('MultiView slot $slotIndex: Playing ${channel.name}');
    } catch (e) {
      AppLogger.error('MultiView slot $slotIndex: Failed to play', e);
      _updateSlot(slotIndex, (s) => s.copyWith(error: e.toString()));
    }
  }

  /// Clear a slot (stop playback)
  Future<void> clearSlot(int slotIndex) async {
    if (slotIndex < 0 || slotIndex >= state.slots.length) return;

    final slot = state.slots[slotIndex];
    await slot.player.stop();

    _updateSlot(
      slotIndex,
      (s) => s.copyWith(
        clearChannel: true,
        clearError: true,
        isPlaying: false,
        isBuffering: false,
      ),
    );

    AppLogger.info('MultiView slot $slotIndex: Cleared');
  }

  /// Set which slot has active audio
  void setActiveAudioSlot(int slotIndex) {
    if (slotIndex < 0 || slotIndex >= state.slots.length) return;

    state = state.copyWith(activeAudioSlot: slotIndex);
    _updateAudioState();
    AppLogger.info('MultiView audio active on slot $slotIndex');
  }

  /// Update audio state (mute/unmute based on active slot)
  void _updateAudioState() {
    final newSlots = <MultiViewSlot>[];

    for (int i = 0; i < state.slots.length; i++) {
      final slot = state.slots[i];
      final isActive = i == state.activeAudioSlot;

      // Mute all except active audio slot
      slot.player.setVolume(isActive ? 100 : 0);

      newSlots.add(slot.copyWith(isAudioActive: isActive));
    }

    state = state.copyWith(slots: newSlots);
  }

  /// Swap channels between two slots
  Future<void> swapSlots(int slot1, int slot2) async {
    if (slot1 < 0 ||
        slot1 >= state.slots.length ||
        slot2 < 0 ||
        slot2 >= state.slots.length) {
      return;
    }

    final channel1 = state.slots[slot1].channel;
    final channel2 = state.slots[slot2].channel;

    // Stop both
    await state.slots[slot1].player.stop();
    await state.slots[slot2].player.stop();

    // Swap channels
    if (channel2 != null) {
      await setChannelInSlot(slot1, channel2);
    } else {
      await clearSlot(slot1);
    }

    if (channel1 != null) {
      await setChannelInSlot(slot2, channel1);
    } else {
      await clearSlot(slot2);
    }

    AppLogger.info('MultiView: Swapped slots $slot1 and $slot2');
  }

  /// Get count of active slots
  int get activeSlotCount =>
      state.slots.where((s) => s.channel != null).length;
}

/// Multi-view controller provider
final multiViewControllerProvider =
    NotifierProvider<MultiViewControllerNotifier, MultiViewState>(
  MultiViewControllerNotifier.new,
);
