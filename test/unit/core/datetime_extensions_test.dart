import 'package:flutter_test/flutter_test.dart';
import 'package:flowtv/core/extensions/datetime_extensions.dart';

void main() {
  group('DateTimeExtensions', () {
    group('timeString', () {
      test('should format time with padded hours and minutes', () {
        final date = DateTime(2024, 1, 15, 9, 5);
        expect(date.timeString, '09:05');
      });

      test('should format time without padding when not needed', () {
        final date = DateTime(2024, 1, 15, 14, 30);
        expect(date.timeString, '14:30');
      });

      test('should handle midnight', () {
        final date = DateTime(2024, 1, 15, 0, 0);
        expect(date.timeString, '00:00');
      });

      test('should handle end of day', () {
        final date = DateTime(2024, 1, 15, 23, 59);
        expect(date.timeString, '23:59');
      });
    });

    group('shortDateString', () {
      test('should format date as MM/DD with padding', () {
        final date = DateTime(2024, 1, 5);
        expect(date.shortDateString, '01/05');
      });

      test('should format double digit month and day', () {
        final date = DateTime(2024, 12, 25);
        expect(date.shortDateString, '12/25');
      });
    });

    group('dateString', () {
      test('should format date as YYYY-MM-DD', () {
        final date = DateTime(2024, 1, 15);
        expect(date.dateString, '2024-01-15');
      });

      test('should handle single digit month and day with padding', () {
        final date = DateTime(2024, 3, 5);
        expect(date.dateString, '2024-03-05');
      });
    });

    group('dateTimeString', () {
      test('should format date and time together', () {
        final date = DateTime(2024, 1, 15, 14, 30);
        expect(date.dateTimeString, '01/15 14:30');
      });

      test('should handle padded values', () {
        final date = DateTime(2024, 3, 5, 9, 5);
        expect(date.dateTimeString, '03/05 09:05');
      });
    });

    group('isToday', () {
      test('should return true for today', () {
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day, 10, 30);
        expect(today.isToday, true);
      });

      test('should return false for yesterday', () {
        final yesterday = DateTime.now().subtract(const Duration(days: 1));
        expect(yesterday.isToday, false);
      });

      test('should return false for tomorrow', () {
        final tomorrow = DateTime.now().add(const Duration(days: 1));
        expect(tomorrow.isToday, false);
      });

      test('should handle different times on same day', () {
        final now = DateTime.now();
        final earlyToday = DateTime(now.year, now.month, now.day, 0, 0);
        final lateToday = DateTime(now.year, now.month, now.day, 23, 59);
        expect(earlyToday.isToday, true);
        expect(lateToday.isToday, true);
      });
    });

    group('isTomorrow', () {
      test('should return true for tomorrow', () {
        final tomorrow = DateTime.now().add(const Duration(days: 1));
        final tomorrowDate = DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 10, 30);
        expect(tomorrowDate.isTomorrow, true);
      });

      test('should return false for today', () {
        final now = DateTime.now();
        expect(now.isTomorrow, false);
      });

      test('should return false for day after tomorrow', () {
        final dayAfter = DateTime.now().add(const Duration(days: 2));
        expect(dayAfter.isTomorrow, false);
      });
    });

    group('startOfDay', () {
      test('should return midnight of same day', () {
        final date = DateTime(2024, 1, 15, 14, 30, 45);
        final start = date.startOfDay;

        expect(start.year, 2024);
        expect(start.month, 1);
        expect(start.day, 15);
        expect(start.hour, 0);
        expect(start.minute, 0);
        expect(start.second, 0);
      });

      test('should return same result for any time on same day', () {
        final morning = DateTime(2024, 1, 15, 6, 0);
        final evening = DateTime(2024, 1, 15, 20, 0);

        expect(morning.startOfDay, evening.startOfDay);
      });
    });

    group('endOfDay', () {
      test('should return 23:59:59 of same day', () {
        final date = DateTime(2024, 1, 15, 14, 30, 45);
        final end = date.endOfDay;

        expect(end.year, 2024);
        expect(end.month, 1);
        expect(end.day, 15);
        expect(end.hour, 23);
        expect(end.minute, 59);
        expect(end.second, 59);
      });

      test('should return same result for any time on same day', () {
        final morning = DateTime(2024, 1, 15, 6, 0);
        final evening = DateTime(2024, 1, 15, 20, 0);

        expect(morning.endOfDay, evening.endOfDay);
      });
    });

    group('relativeTime', () {
      test('should show minutes ago for recent past', () {
        final date = DateTime.now().subtract(const Duration(minutes: 30));
        expect(date.relativeTime, '30 min ago');
      });

      test('should show hours ago for hours past', () {
        final date = DateTime.now().subtract(const Duration(hours: 5));
        expect(date.relativeTime, '5h ago');
      });

      test('should show days ago for days past', () {
        final date = DateTime.now().subtract(const Duration(days: 3));
        expect(date.relativeTime, '3d ago');
      });

      test('should show "in X min" for near future', () {
        final date = DateTime.now().add(const Duration(minutes: 45));
        expect(date.relativeTime, 'in 45 min');
      });

      test('should show "in Xh" for hours in future', () {
        final date = DateTime.now().add(const Duration(hours: 2));
        expect(date.relativeTime, 'in 2h');
      });

      test('should show "in Xd" for days in future', () {
        final date = DateTime.now().add(const Duration(days: 5));
        expect(date.relativeTime, 'in 5d');
      });

      test('should show 0 min ago for just now', () {
        final date = DateTime.now();
        expect(date.relativeTime, '0 min ago');
      });
    });
  });
}
