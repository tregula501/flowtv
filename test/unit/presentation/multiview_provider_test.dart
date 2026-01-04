import 'package:flutter_test/flutter_test.dart';
import 'package:flowtv/presentation/providers/multiview_provider.dart';
import 'package:flowtv/data/datasources/local/drift/app_database.dart';

// Note: Tests for MultiViewSlot and MultiViewState are limited because
// they require Player/VideoController instances which need native media_kit
// initialization. We test the copyWith behavior and state management logic
// that doesn't require actual Player instances.

void main() {
  group('MultiViewState', () {
    test('should create with default values', () {
      const state = MultiViewState(slots: []);

      expect(state.slots, isEmpty);
      expect(state.isEnabled, false);
      expect(state.activeAudioSlot, 0);
    });

    test('should create with all fields', () {
      const state = MultiViewState(
        slots: [],
        isEnabled: true,
        activeAudioSlot: 2,
      );

      expect(state.isEnabled, true);
      expect(state.activeAudioSlot, 2);
    });

    group('copyWith', () {
      test('should update isEnabled', () {
        const state = MultiViewState(slots: []);
        final newState = state.copyWith(isEnabled: true);

        expect(newState.isEnabled, true);
        expect(newState.activeAudioSlot, 0); // unchanged
      });

      test('should update activeAudioSlot', () {
        const state = MultiViewState(slots: []);
        final newState = state.copyWith(activeAudioSlot: 3);

        expect(newState.activeAudioSlot, 3);
        expect(newState.isEnabled, false); // unchanged
      });

      test('should update multiple properties', () {
        const state = MultiViewState(slots: []);

        final newState = state.copyWith(
          isEnabled: true,
          activeAudioSlot: 1,
        );

        expect(newState.isEnabled, true);
        expect(newState.activeAudioSlot, 1);
      });

      test('should preserve unchanged values', () {
        const state = MultiViewState(
          slots: [],
          isEnabled: true,
          activeAudioSlot: 2,
        );

        final newState = state.copyWith(activeAudioSlot: 3);

        expect(newState.isEnabled, true); // unchanged
        expect(newState.activeAudioSlot, 3);
      });
    });
  });

  group('maxMultiViewChannels constant', () {
    test('should be 4', () {
      expect(maxMultiViewChannels, 4);
    });
  });

  group('Channel model (used in multi-view)', () {
    test('should create channel for multi-view slot', () {
      final channel = Channel(
        id: 1,
        playlistId: 1,
        name: 'ESPN HD',
        streamUrl: 'http://example.com/stream.m3u8',
        logoUrl: 'http://example.com/logo.png',
        group: 'Sports',
        isFavorite: true,
        isLocked: false,
        sortOrder: 0,
        isVod: false,
      );

      expect(channel.name, 'ESPN HD');
      expect(channel.streamUrl, 'http://example.com/stream.m3u8');
      expect(channel.logoUrl, 'http://example.com/logo.png');
      expect(channel.group, 'Sports');
      expect(channel.isFavorite, true);
    });
  });
}
