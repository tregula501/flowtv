import '../../data/datasources/local/drift/app_database.dart' show EpgProgram;

/// Extension methods for EpgProgram to add computed properties
extension EpgProgramExtensions on EpgProgram {
  /// Is this program currently live?
  bool get isLive {
    final now = DateTime.now();
    return now.isAfter(startTime) && now.isBefore(endTime);
  }

  /// Program duration in minutes
  int get durationMinutes {
    return endTime.difference(startTime).inMinutes;
  }

  /// Progress percentage (0.0 to 1.0) if currently live
  double get progress {
    if (!isLive) return 0.0;
    final now = DateTime.now();
    final elapsed = now.difference(startTime).inSeconds;
    final total = endTime.difference(startTime).inSeconds;
    if (total <= 0) return 0.0;
    return (elapsed / total).clamp(0.0, 1.0);
  }
}
