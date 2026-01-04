import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../data/datasources/local/drift/app_database.dart' show Channel;
import '../../core/utils/logger.dart';

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

/// Multi-view controller provider
final multiViewControllerProvider =
    StateNotifierProvider<MultiViewControllerNotifier, MultiViewState>((ref) {
  return MultiViewControllerNotifier();
});

class MultiViewControllerNotifier extends StateNotifier<MultiViewState> {
  MultiViewControllerNotifier() : super(const MultiViewState(slots: [])) {
    _initSlots();
  }

  void _initSlots() {
    final slots = <MultiViewSlot>[];

    for (int i = 0; i < maxMultiViewChannels; i++) {
      final player = Player();
      final videoController = VideoController(player);

      // Set up listeners for each player
      _setupPlayerListeners(i, player);

      slots.add(MultiViewSlot(
        index: i,
        player: player,
        videoController: videoController,
        isAudioActive: i == 0, // First slot has audio by default
      ),);
    }

    state = state.copyWith(slots: slots, activeAudioSlot: 0);
    _updateAudioState();
  }

  void _setupPlayerListeners(int index, Player player) {
    player.stream.playing.listen((playing) {
      _updateSlot(index, (slot) => slot.copyWith(isPlaying: playing));
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

  @override
  void dispose() {
    for (final slot in state.slots) {
      slot.player.dispose();
    }
    super.dispose();
  }
}
