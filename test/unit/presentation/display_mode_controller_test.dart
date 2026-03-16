import 'package:flutter_test/flutter_test.dart';
import 'package:flowtv/presentation/providers/player/display_mode_controller.dart';

// NOTE: The DisplayModeController class depends heavily on `dart:io` (Platform)
// and `window_manager` for all of its public methods (toggleFullscreen,
// setFullscreen, togglePiPMode, setPiPMode). These require platform channels
// that are not available in unit tests.
//
// Full behavioral testing of this class requires either:
//   - Integration tests running on a desktop platform, or
//   - Refactoring the class to accept an abstract WindowManager interface
//     that can be mocked in unit tests.
//
// The tests below verify only construction and basic type safety.

void main() {
  group('DisplayModeController', () {
    test('can be instantiated', () {
      final controller = DisplayModeController();
      expect(controller, isNotNull);
      expect(controller, isA<DisplayModeController>());
    });

    test('multiple instances are independent', () {
      final controller1 = DisplayModeController();
      final controller2 = DisplayModeController();
      expect(controller1, isNot(same(controller2)));
    });

    test('exposes toggleFullscreen method', () {
      final controller = DisplayModeController();
      // Verify the method exists and has the correct signature.
      // We cannot call it without platform channels, but we can confirm
      // it is accessible.
      expect(controller.toggleFullscreen, isA<Function>());
    });

    test('exposes setFullscreen method', () {
      final controller = DisplayModeController();
      expect(controller.setFullscreen, isA<Function>());
    });

    test('exposes togglePiPMode method', () {
      final controller = DisplayModeController();
      expect(controller.togglePiPMode, isA<Function>());
    });

    test('exposes setPiPMode method', () {
      final controller = DisplayModeController();
      expect(controller.setPiPMode, isA<Function>());
    });
  });
}
