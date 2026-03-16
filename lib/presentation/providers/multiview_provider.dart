import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../data/datasources/local/drift/app_database.dart' show Channel;
import '../../core/utils/logger.dart';
import '../../core/utils/mpv_buffer_config.dart';
import '../../core/models/buffer_size.dart';

/// Maximum number of views in multi-view mode
const int maxMultiViewChannels = 4;

/// Multi-view slot state
class MultiViewSlot {
  final int index;
  final Channel? channel;
  final Player? player;
  final VideoController? videoController;
  final bool isPlaying;
  final bool isBuffering;
  final bool isAudioActive;
  final String? error;

  MultiViewSlot({
    required this.index,
    this.channel,
    this.player,
    this.videoController,
    this.isPlaying = false,
    this.isBuffering = false,
    this.isAudioActive = false,
    this.error,
  });

  MultiViewSlot copyWith({
    Channel? channel,
    Player? player,
    VideoController? videoController,
    bool? isPlaying,
    bool? isBuffering,
    bool? isAudioActive,
    String? error,
    bool clearChannel = false,
    bool clearError = false,
    bool clearPlayer = false,
  }) {
    return MultiViewSlot(
      index: index,
      channel: clearChannel ? null : (channel ?? this.channel),
      player: clearPlayer ? null : (player ?? this.player),
      videoController: clearPlayer ? null : (videoController ?? this.videoController),
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

  /// Per-slot stream subscriptions so we can cancel them individually
  final Map<int, List<StreamSubscription>> _slotSubscriptions = {};

  @override
  MultiViewState build() {
    // Clean up from any prior build() call (Notifier.build() re-runs on invalidation)
    _disposeAllPlayers();

    // Initialize slots with null players (lazy initialization)
    final slots = <MultiViewSlot>[];
    for (int i = 0; i < maxMultiViewChannels; i++) {
      slots.add(MultiViewSlot(
        index: i,
        isAudioActive: i == 0, // First slot has audio by default
      ));
    }

    // Register disposal callback
    ref.onDispose(() {
      _disposeAllPlayers();
    });

    return MultiViewState(slots: slots, activeAudioSlot: 0);
  }

  /// Create a Player and VideoController for a given slot index.
  /// Returns the (player, videoController) pair.
  (Player, VideoController) _createPlayerForSlot(int slotIndex) {
    // Calculate buffer size: 4MB per second for high-bitrate streams
    final bufferBytes = _bufferSize.durationSeconds * 4 * 1024 * 1024;

    final player = Player(
      configuration: PlayerConfiguration(
        bufferSize: bufferBytes,
      ),
    );
    final videoController = VideoController(player);

    // Set up listeners for the player
    _setupPlayerListeners(slotIndex, player);

    // Apply MPV-specific buffer settings
    _applyBufferSettings(player, slotIndex);

    AppLogger.info('MultiView slot $slotIndex: Player created (lazy init)');

    return (player, videoController);
  }

  /// Dispose a single slot's player and cancel its subscriptions
  void _disposeSlotPlayer(int slotIndex) {
    // Cancel subscriptions for this slot
    final subs = _slotSubscriptions.remove(slotIndex);
    if (subs != null) {
      for (final sub in subs) {
        sub.cancel();
      }
    }

    // Dispose the player if it exists
    try {
      final slot = state.slots[slotIndex];
      slot.player?.dispose();
    } catch (_) {
      // state may not be initialized yet
    }
  }

  /// Dispose all active players and cancel all subscriptions
  void _disposeAllPlayers() {
    for (final entry in _slotSubscriptions.entries) {
      for (final sub in entry.value) {
        sub.cancel();
      }
    }
    _slotSubscriptions.clear();

    try {
      for (final slot in state.slots) {
        slot.player?.dispose();
      }
    } catch (_) {
      // state not yet initialized on first build
    }
  }

  /// Apply MPV-specific buffer settings for stable streaming
  Future<void> _applyBufferSettings(Player player, int slotIndex) async {
    await applyMpvBufferSettings(
      player,
      _bufferSize,
      logPrefix: 'MultiView slot $slotIndex',
    );
  }

  void _setupPlayerListeners(int index, Player player) {
    final subs = <StreamSubscription>[];

    subs.add(
      player.stream.playing.listen((playing) {
        // When playback starts successfully, clear any previous error
        if (playing) {
          _updateSlot(index, (slot) => slot.copyWith(isPlaying: true, clearError: true));
        } else {
          _updateSlot(index, (slot) => slot.copyWith(isPlaying: false));
        }
      }),
    );

    subs.add(
      player.stream.buffering.listen((buffering) {
        _updateSlot(index, (slot) => slot.copyWith(isBuffering: buffering));
      }),
    );

    subs.add(
      player.stream.error.listen((error) {
        if (error.isNotEmpty) {
          AppLogger.error('MultiView slot $index error: $error');
          _updateSlot(index, (slot) => slot.copyWith(error: error));
        }
      }),
    );

    _slotSubscriptions[index] = subs;
  }

  void _updateSlot(int index, MultiViewSlot Function(MultiViewSlot) updater) {
    if (index < 0 || index >= state.slots.length) return;
    final oldSlot = state.slots[index];
    final newSlot = updater(oldSlot);
    // Skip state update if nothing actually changed
    if (identical(oldSlot, newSlot)) return;
    if (newSlot.isPlaying == oldSlot.isPlaying &&
        newSlot.isBuffering == oldSlot.isBuffering &&
        newSlot.isAudioActive == oldSlot.isAudioActive &&
        newSlot.error == oldSlot.error &&
        newSlot.channel == oldSlot.channel &&
        newSlot.player == oldSlot.player &&
        newSlot.videoController == oldSlot.videoController) {
      return;
    }
    final newSlots = List<MultiViewSlot>.from(state.slots);
    newSlots[index] = newSlot;
    state = state.copyWith(slots: newSlots);
  }

  /// Enable multi-view mode
  void enableMultiView() {
    state = state.copyWith(isEnabled: true);
    AppLogger.info('Multi-view enabled');
  }

  /// Disable multi-view mode and dispose all active players
  Future<void> disableMultiView() async {
    // Dispose all active players and cancel all subscriptions
    for (var i = 0; i < state.slots.length; i++) {
      _disposeSlotPlayer(i);
    }

    final newSlots = state.slots
        .map((slot) => slot.copyWith(
              clearChannel: true,
              clearError: true,
              clearPlayer: true,
              isPlaying: false,
              isBuffering: false,
            ))
        .toList();

    state = state.copyWith(
      isEnabled: false,
      slots: newSlots,
      activeAudioSlot: 0,
    );
    AppLogger.info('Multi-view disabled, all players disposed');
  }

  /// Add a channel to a specific slot (lazy-initializes the player if needed)
  Future<void> setChannelInSlot(int slotIndex, Channel channel) async {
    if (slotIndex < 0 || slotIndex >= state.slots.length) return;

    final slot = state.slots[slotIndex];

    try {
      // Lazy-initialize player if this slot doesn't have one yet
      Player player;
      if (slot.player == null) {
        final (newPlayer, newController) = _createPlayerForSlot(slotIndex);
        player = newPlayer;
        _updateSlot(
          slotIndex,
          (s) => s.copyWith(
            player: newPlayer,
            videoController: newController,
            channel: channel,
            clearError: true,
            isBuffering: true,
          ),
        );
      } else {
        player = slot.player!;
        _updateSlot(
          slotIndex,
          (s) => s.copyWith(
            channel: channel,
            clearError: true,
            isBuffering: true,
          ),
        );
      }

      await player.open(Media(channel.streamUrl));
      AppLogger.info('MultiView slot $slotIndex: Playing ${channel.name}');
    } catch (e) {
      AppLogger.error('MultiView slot $slotIndex: Failed to play', e);
      _updateSlot(slotIndex, (s) => s.copyWith(error: e.toString()));
    }
  }

  /// Clear a slot (stop playback, dispose player, free resources)
  Future<void> clearSlot(int slotIndex) async {
    if (slotIndex < 0 || slotIndex >= state.slots.length) return;

    // Dispose the player and cancel subscriptions for this slot
    _disposeSlotPlayer(slotIndex);

    _updateSlot(
      slotIndex,
      (s) => s.copyWith(
        clearChannel: true,
        clearError: true,
        clearPlayer: true,
        isPlaying: false,
        isBuffering: false,
      ),
    );

    AppLogger.info('MultiView slot $slotIndex: Cleared and player disposed');
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

      // Mute all except active audio slot (only if player exists)
      slot.player?.setVolume(isActive ? 100 : 0);

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

    // Stop both (only if players exist)
    await state.slots[slot1].player?.stop();
    await state.slots[slot2].player?.stop();

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
