import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flowtv/presentation/providers/player/prebuffer_controller.dart';

void main() {
  group('PrebufferController', () {
    late PrebufferController controller;

    setUp(() {
      controller = PrebufferController();
    });

    tearDown(() {
      controller.dispose();
    });

    group('startPrebuffering', () {
      test('should set isPrebuffering to true', () {
        fakeAsync((async) {
          controller.startPrebuffering(
            5,
            onComplete: () {},
            onProgress: (_) {},
          );

          expect(controller.isPrebuffering, isTrue);
        });
      });

      test('should set startTime', () {
        fakeAsync((async) {
          controller.startPrebuffering(
            5,
            onComplete: () {},
            onProgress: (_) {},
          );

          expect(controller.startTime, isNotNull);
        });
      });

      test('should trigger onProgress callbacks periodically', () {
        fakeAsync((async) {
          final progressCalls = <Duration>[];

          controller.startPrebuffering(
            5,
            onComplete: () {},
            onProgress: (elapsed) {
              progressCalls.add(elapsed);
            },
          );

          // Advance 500ms — should fire at 100ms, 200ms, 300ms, 400ms, 500ms
          async.elapse(const Duration(milliseconds: 500));

          expect(progressCalls.length, 5);
        });
      });

      test('should call onComplete after the specified duration', () {
        fakeAsync((async) {
          var completed = false;

          controller.startPrebuffering(
            3,
            onComplete: () {
              completed = true;
            },
            onProgress: (_) {},
          );

          // Advance to just before completion
          async.elapse(const Duration(seconds: 2, milliseconds: 999));
          expect(completed, isFalse);

          // Advance past completion
          async.elapse(const Duration(milliseconds: 1));
          expect(completed, isTrue);
        });
      });

      test('should reset isPrebuffering after completion', () {
        fakeAsync((async) {
          controller.startPrebuffering(
            2,
            onComplete: () {},
            onProgress: (_) {},
          );

          expect(controller.isPrebuffering, isTrue);

          async.elapse(const Duration(seconds: 2));

          expect(controller.isPrebuffering, isFalse);
        });
      });

      test('should reset startTime after completion', () {
        fakeAsync((async) {
          controller.startPrebuffering(
            2,
            onComplete: () {},
            onProgress: (_) {},
          );

          expect(controller.startTime, isNotNull);

          async.elapse(const Duration(seconds: 2));

          expect(controller.startTime, isNull);
        });
      });

      test('should cancel previous progress timer when called again', () {
        fakeAsync((async) {
          final firstProgressCalls = <Duration>[];
          final secondProgressCalls = <Duration>[];

          controller.startPrebuffering(
            5,
            onComplete: () {},
            onProgress: (elapsed) {
              firstProgressCalls.add(elapsed);
            },
          );

          // Advance 300ms to accumulate some progress from first call
          async.elapse(const Duration(milliseconds: 300));
          expect(firstProgressCalls.length, 3);

          // Start a new prebuffer — this cancels the old progress timer
          controller.startPrebuffering(
            2,
            onComplete: () {},
            onProgress: (elapsed) {
              secondProgressCalls.add(elapsed);
            },
          );

          // Advance more — first progress timer should be cancelled
          async.elapse(const Duration(milliseconds: 300));
          // First callback should not receive more calls
          expect(firstProgressCalls.length, 3);
          // Second callback should receive new calls
          expect(secondProgressCalls.length, 3);
        });
      });

      test('later startPrebuffering completes before earlier one', () {
        fakeAsync((async) {
          var firstCompleted = false;
          var secondCompleted = false;

          controller.startPrebuffering(
            5,
            onComplete: () {
              firstCompleted = true;
            },
            onProgress: (_) {},
          );

          // At t=1, start a shorter prebuffer
          async.elapse(const Duration(seconds: 1));

          controller.startPrebuffering(
            2,
            onComplete: () {
              secondCompleted = true;
            },
            onProgress: (_) {},
          );

          // At t=3 (1+2), second completes
          async.elapse(const Duration(seconds: 2));
          expect(secondCompleted, isTrue);

          // At t=5, the orphaned first timer fires but isPrebuffering is
          // already false, so completePrebuffering is a no-op.
          async.elapse(const Duration(seconds: 2));
          expect(firstCompleted, isFalse);
        });
      });

      test('should handle 0-second buffer duration', () {
        fakeAsync((async) {
          var completed = false;

          controller.startPrebuffering(
            0,
            onComplete: () {
              completed = true;
            },
            onProgress: (_) {},
          );

          // A Timer(Duration.zero, ...) fires on the next microtask/timer
          async.elapse(Duration.zero);
          expect(completed, isTrue);
        });
      });
    });

    group('cancelPrebuffering', () {
      test('should set isPrebuffering to false', () {
        fakeAsync((async) {
          controller.startPrebuffering(
            5,
            onComplete: () {},
            onProgress: (_) {},
          );

          expect(controller.isPrebuffering, isTrue);

          controller.cancelPrebuffering();

          expect(controller.isPrebuffering, isFalse);
        });
      });

      test('should set startTime to null', () {
        fakeAsync((async) {
          controller.startPrebuffering(
            5,
            onComplete: () {},
            onProgress: (_) {},
          );

          controller.cancelPrebuffering();

          expect(controller.startTime, isNull);
        });
      });

      test('should prevent onComplete from being called', () {
        fakeAsync((async) {
          var completed = false;

          controller.startPrebuffering(
            3,
            onComplete: () {
              completed = true;
            },
            onProgress: (_) {},
          );

          async.elapse(const Duration(seconds: 1));
          controller.cancelPrebuffering();

          // Advance well past the original completion time
          async.elapse(const Duration(seconds: 10));

          expect(completed, isFalse);
        });
      });

      test('should stop progress timer callbacks', () {
        fakeAsync((async) {
          final progressCalls = <Duration>[];

          controller.startPrebuffering(
            5,
            onComplete: () {},
            onProgress: (elapsed) {
              progressCalls.add(elapsed);
            },
          );

          // Accumulate some progress
          async.elapse(const Duration(milliseconds: 300));
          final countBeforeCancel = progressCalls.length;
          expect(countBeforeCancel, 3);

          controller.cancelPrebuffering();

          // No more progress after cancel
          async.elapse(const Duration(seconds: 5));
          expect(progressCalls.length, countBeforeCancel);
        });
      });

      test('should be safe to call when not prebuffering', () {
        // Should not throw
        controller.cancelPrebuffering();

        expect(controller.isPrebuffering, isFalse);
        expect(controller.startTime, isNull);
      });
    });

    group('completePrebuffering', () {
      test('should invoke onComplete callback', () {
        fakeAsync((async) {
          var completed = false;

          controller.startPrebuffering(
            10,
            onComplete: () {},
            onProgress: (_) {},
          );

          // Manually complete early
          controller.completePrebuffering(onComplete: () {
            completed = true;
          });

          expect(completed, isTrue);
        });
      });

      test('should reset isPrebuffering to false', () {
        fakeAsync((async) {
          controller.startPrebuffering(
            10,
            onComplete: () {},
            onProgress: (_) {},
          );

          controller.completePrebuffering(onComplete: () {});

          expect(controller.isPrebuffering, isFalse);
        });
      });

      test('should reset startTime to null', () {
        fakeAsync((async) {
          controller.startPrebuffering(
            10,
            onComplete: () {},
            onProgress: (_) {},
          );

          controller.completePrebuffering(onComplete: () {});

          expect(controller.startTime, isNull);
        });
      });

      test('should not invoke onComplete if not prebuffering', () {
        var completed = false;

        controller.completePrebuffering(onComplete: () {
          completed = true;
        });

        expect(completed, isFalse);
      });

      test('should stop progress timer after completion', () {
        fakeAsync((async) {
          final progressCalls = <Duration>[];

          controller.startPrebuffering(
            10,
            onComplete: () {},
            onProgress: (elapsed) {
              progressCalls.add(elapsed);
            },
          );

          async.elapse(const Duration(milliseconds: 300));
          final countBeforeComplete = progressCalls.length;

          controller.completePrebuffering(onComplete: () {});

          async.elapse(const Duration(seconds: 5));

          // No more progress calls after completion
          expect(progressCalls.length, countBeforeComplete);
        });
      });
    });

    group('dispose', () {
      test('should cancel progress timer', () {
        fakeAsync((async) {
          final progressCalls = <Duration>[];

          controller.startPrebuffering(
            10,
            onComplete: () {},
            onProgress: (elapsed) {
              progressCalls.add(elapsed);
            },
          );

          async.elapse(const Duration(milliseconds: 200));
          final countBeforeDispose = progressCalls.length;

          controller.dispose();

          async.elapse(const Duration(seconds: 5));

          expect(progressCalls.length, countBeforeDispose);
        });
      });

      test('should cancel complete timer', () {
        fakeAsync((async) {
          var completed = false;

          controller.startPrebuffering(
            3,
            onComplete: () {
              completed = true;
            },
            onProgress: (_) {},
          );

          controller.dispose();

          async.elapse(const Duration(seconds: 10));

          expect(completed, isFalse);
        });
      });

      test('should be safe to call when not prebuffering', () {
        // Should not throw
        controller.dispose();
      });

      test('should be safe to call multiple times', () {
        fakeAsync((async) {
          controller.startPrebuffering(
            5,
            onComplete: () {},
            onProgress: (_) {},
          );

          controller.dispose();
          controller.dispose(); // Should not throw
        });
      });
    });
  });
}
