import 'package:flutter_test/flutter_test.dart';
import 'package:flowtv/presentation/providers/epg_provider.dart';

void main() {
  group('ProgressState', () {
    test('should have correct default values', () {
      const state = ProgressState();

      expect(state.current, 0);
      expect(state.total, 0);
      expect(state.phase, '');
      expect(state.isLoading, false);
    });

    test('should create with custom values', () {
      const state = ProgressState(
        current: 50,
        total: 100,
        phase: 'Downloading...',
        isLoading: true,
      );

      expect(state.current, 50);
      expect(state.total, 100);
      expect(state.phase, 'Downloading...');
      expect(state.isLoading, true);
    });

    group('progress', () {
      test('should calculate progress correctly', () {
        const state = ProgressState(current: 50, total: 100);

        expect(state.progress, 0.5);
      });

      test('should return 0 when total is 0', () {
        const state = ProgressState(current: 10, total: 0);

        expect(state.progress, 0.0);
      });

      test('should clamp to 1.0 when current exceeds total', () {
        const state = ProgressState(current: 150, total: 100);

        expect(state.progress, 1.0);
      });

      test('should clamp to 0.0 when current is negative', () {
        const state = ProgressState(current: -10, total: 100);

        expect(state.progress, 0.0);
      });

      test('should return 1.0 at completion', () {
        const state = ProgressState(current: 100, total: 100);

        expect(state.progress, 1.0);
      });

      test('should handle small progress values', () {
        const state = ProgressState(current: 1, total: 1000);

        expect(state.progress, closeTo(0.001, 0.0001));
      });
    });

    group('copyWith', () {
      test('should update current', () {
        const state = ProgressState(current: 10, total: 100);
        final newState = state.copyWith(current: 50);

        expect(newState.current, 50);
        expect(newState.total, 100); // unchanged
      });

      test('should update total', () {
        const state = ProgressState(current: 10, total: 100);
        final newState = state.copyWith(total: 200);

        expect(newState.total, 200);
        expect(newState.current, 10); // unchanged
      });

      test('should update phase', () {
        const state = ProgressState(phase: 'Starting...');
        final newState = state.copyWith(phase: 'Processing...');

        expect(newState.phase, 'Processing...');
      });

      test('should update isLoading', () {
        const state = ProgressState(isLoading: false);
        final newState = state.copyWith(isLoading: true);

        expect(newState.isLoading, true);
      });

      test('should update multiple properties', () {
        const state = ProgressState();
        final newState = state.copyWith(
          current: 25,
          total: 50,
          phase: 'Halfway done',
          isLoading: true,
        );

        expect(newState.current, 25);
        expect(newState.total, 50);
        expect(newState.phase, 'Halfway done');
        expect(newState.isLoading, true);
        expect(newState.progress, 0.5);
      });

      test('should preserve unchanged values', () {
        const state = ProgressState(
          current: 10,
          total: 100,
          phase: 'Loading',
          isLoading: true,
        );
        final newState = state.copyWith(current: 20);

        expect(newState.current, 20);
        expect(newState.total, 100);
        expect(newState.phase, 'Loading');
        expect(newState.isLoading, true);
      });
    });

    group('typical usage scenarios', () {
      test('should track EPG loading progress', () {
        // Starting state
        const initial = ProgressState(
          phase: 'Downloading EPG...',
          isLoading: true,
        );
        expect(initial.progress, 0.0);

        // After parsing
        final parsing = initial.copyWith(
          phase: 'Parsing programs...',
          current: 0,
          total: 1000,
        );
        expect(parsing.phase, 'Parsing programs...');

        // Midway through
        final midway = parsing.copyWith(current: 500);
        expect(midway.progress, 0.5);

        // Complete
        final complete = midway.copyWith(
          current: 1000,
          phase: 'Complete',
          isLoading: false,
        );
        expect(complete.progress, 1.0);
        expect(complete.isLoading, false);
      });

      test('should track playlist import progress', () {
        const importing = ProgressState(
          current: 250,
          total: 500,
          phase: 'Adding channels...',
          isLoading: true,
        );

        expect(importing.progress, 0.5);
        expect(importing.phase, 'Adding channels...');
      });
    });
  });
}
