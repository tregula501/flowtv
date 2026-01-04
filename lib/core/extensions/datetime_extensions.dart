/// DateTime extension methods
extension DateTimeExtensions on DateTime {
  /// Format as time (HH:mm)
  String get timeString {
    return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
  }

  /// Format as date (MM/DD)
  String get shortDateString {
    return '${month.toString().padLeft(2, '0')}/${day.toString().padLeft(2, '0')}';
  }

  /// Format as full date (YYYY-MM-DD)
  String get dateString {
    return '${year.toString()}-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
  }

  /// Format as date and time (MM/DD HH:mm)
  String get dateTimeString {
    return '$shortDateString $timeString';
  }

  /// Check if date is today
  bool get isToday {
    final now = DateTime.now();
    return year == now.year && month == now.month && day == now.day;
  }

  /// Check if date is tomorrow
  bool get isTomorrow {
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    return year == tomorrow.year && month == tomorrow.month && day == tomorrow.day;
  }

  /// Get start of day
  DateTime get startOfDay {
    return DateTime(year, month, day);
  }

  /// Get end of day
  DateTime get endOfDay {
    return DateTime(year, month, day, 23, 59, 59);
  }

  /// Get relative time string (e.g., "2 hours ago", "in 30 minutes")
  String get relativeTime {
    final now = DateTime.now();
    final difference = now.difference(this);

    if (difference.isNegative) {
      // Future
      final futureDiff = difference.abs();
      if (futureDiff.inMinutes < 60) {
        return 'in ${futureDiff.inMinutes} min';
      } else if (futureDiff.inHours < 24) {
        return 'in ${futureDiff.inHours}h';
      } else {
        return 'in ${futureDiff.inDays}d';
      }
    } else {
      // Past
      if (difference.inMinutes < 60) {
        return '${difference.inMinutes} min ago';
      } else if (difference.inHours < 24) {
        return '${difference.inHours}h ago';
      } else {
        return '${difference.inDays}d ago';
      }
    }
  }
}
