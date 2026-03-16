import 'package:flutter_test/flutter_test.dart';
import 'package:flowtv/core/utils/retry.dart';
import 'package:flowtv/core/errors/exceptions.dart';

void main() {
  // Use a tiny initial delay so tests run fast.
  const fastDelay = Duration(milliseconds: 1);

  group('withRetry', () {
    test('succeeds on first attempt without retrying', () async {
      int callCount = 0;

      final result = await withRetry<String>(
        () async {
          callCount++;
          return 'ok';
        },
        initialDelay: fastDelay,
      );

      expect(result, 'ok');
      expect(callCount, 1);
    });

    test('retries on transient failure and eventually succeeds', () async {
      int callCount = 0;

      final result = await withRetry<String>(
        () async {
          callCount++;
          if (callCount < 3) {
            throw Exception('transient error');
          }
          return 'recovered';
        },
        maxAttempts: 3,
        initialDelay: fastDelay,
      );

      expect(result, 'recovered');
      expect(callCount, 3);
    });

    test('stops retrying after max attempts and rethrows', () async {
      int callCount = 0;

      expect(
        () => withRetry<String>(
          () async {
            callCount++;
            throw Exception('persistent error');
          },
          maxAttempts: 3,
          initialDelay: fastDelay,
        ),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('persistent error'),
        )),
      );

      // Wait for the future to finish before checking callCount.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(callCount, 3);
    });

    group('does NOT retry on non-transient HTTP errors', () {
      test('does not retry on 401 Unauthorized', () async {
        int callCount = 0;

        expect(
          () => withRetry<String>(
            () async {
              callCount++;
              throw const ApiException('Unauthorized', statusCode: 401);
            },
            maxAttempts: 3,
            initialDelay: fastDelay,
          ),
          throwsA(isA<ApiException>().having(
            (e) => e.statusCode,
            'statusCode',
            401,
          )),
        );

        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(callCount, 1, reason: '401 should not be retried');
      });

      test('does not retry on 403 Forbidden', () async {
        int callCount = 0;

        expect(
          () => withRetry<String>(
            () async {
              callCount++;
              throw const ApiException('Forbidden', statusCode: 403);
            },
            maxAttempts: 3,
            initialDelay: fastDelay,
          ),
          throwsA(isA<ApiException>().having(
            (e) => e.statusCode,
            'statusCode',
            403,
          )),
        );

        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(callCount, 1, reason: '403 should not be retried');
      });

      test('does not retry on 404 Not Found', () async {
        int callCount = 0;

        expect(
          () => withRetry<String>(
            () async {
              callCount++;
              throw const ApiException('Not Found', statusCode: 404);
            },
            maxAttempts: 3,
            initialDelay: fastDelay,
          ),
          throwsA(isA<ApiException>().having(
            (e) => e.statusCode,
            'statusCode',
            404,
          )),
        );

        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(callCount, 1, reason: '404 should not be retried');
      });
    });

    group('retries on server errors (5xx)', () {
      test('retries on 500 Internal Server Error', () async {
        int callCount = 0;

        final result = await withRetry<String>(
          () async {
            callCount++;
            if (callCount < 2) {
              throw const ApiException('Server Error', statusCode: 500);
            }
            return 'recovered';
          },
          maxAttempts: 3,
          initialDelay: fastDelay,
        );

        expect(result, 'recovered');
        expect(callCount, 2);
      });

      test('retries on 502 Bad Gateway', () async {
        int callCount = 0;

        final result = await withRetry<String>(
          () async {
            callCount++;
            if (callCount < 2) {
              throw const ApiException('Bad Gateway', statusCode: 502);
            }
            return 'recovered';
          },
          maxAttempts: 3,
          initialDelay: fastDelay,
        );

        expect(result, 'recovered');
        expect(callCount, 2);
      });

      test('retries on 503 Service Unavailable', () async {
        int callCount = 0;

        final result = await withRetry<String>(
          () async {
            callCount++;
            if (callCount < 2) {
              throw const ApiException('Service Unavailable', statusCode: 503);
            }
            return 'recovered';
          },
          maxAttempts: 3,
          initialDelay: fastDelay,
        );

        expect(result, 'recovered');
        expect(callCount, 2);
      });
    });

    test('retries on ApiException without a statusCode', () async {
      int callCount = 0;

      final result = await withRetry<String>(
        () async {
          callCount++;
          if (callCount < 2) {
            throw const ApiException('Unknown API error');
          }
          return 'recovered';
        },
        maxAttempts: 3,
        initialDelay: fastDelay,
      );

      expect(result, 'recovered');
      expect(callCount, 2);
    });

    test('retries on generic network exceptions', () async {
      int callCount = 0;

      final result = await withRetry<String>(
        () async {
          callCount++;
          if (callCount < 2) {
            throw const NetworkException('Connection timed out');
          }
          return 'recovered';
        },
        maxAttempts: 3,
        initialDelay: fastDelay,
      );

      expect(result, 'recovered');
      expect(callCount, 2);
    });

    test('label parameter does not crash when provided', () async {
      final result = await withRetry<int>(
        () async => 42,
        label: 'test-operation',
        initialDelay: fastDelay,
      );

      expect(result, 42);
    });

    test('label parameter does not crash on retries', () async {
      int callCount = 0;

      final result = await withRetry<String>(
        () async {
          callCount++;
          if (callCount < 2) {
            throw Exception('fail once');
          }
          return 'ok';
        },
        maxAttempts: 3,
        label: 'labeled-retry',
        initialDelay: fastDelay,
      );

      expect(result, 'ok');
      expect(callCount, 2);
    });

    test('works with maxAttempts of 1 (no retries)', () async {
      expect(
        () => withRetry<String>(
          () async {
            throw Exception('fail');
          },
          maxAttempts: 1,
          initialDelay: fastDelay,
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('returns correct generic type', () async {
      final intResult = await withRetry<int>(
        () async => 123,
        initialDelay: fastDelay,
      );
      expect(intResult, isA<int>());
      expect(intResult, 123);

      final listResult = await withRetry<List<String>>(
        () async => ['a', 'b'],
        initialDelay: fastDelay,
      );
      expect(listResult, isA<List<String>>());
      expect(listResult, ['a', 'b']);
    });
  });
}
