import 'package:isar/isar.dart';

part 'recording.g.dart';

/// Recording status
enum RecordingStatus {
  scheduled,  // Waiting to start
  recording,  // Currently recording
  completed,  // Finished recording
  failed,     // Recording failed
  cancelled,  // User cancelled
}

/// Recording model - represents a DVR recording
@collection
class Recording {
  Id id = Isar.autoIncrement;

  /// Channel ID being recorded
  @Index()
  late int channelId;

  /// Recording title (from EPG or channel name)
  late String title;

  /// File path where recording is saved
  late String filePath;

  /// Scheduled start time
  late DateTime scheduledStart;

  /// Scheduled end time
  late DateTime scheduledEnd;

  /// Actual start time
  DateTime? actualStart;

  /// Actual end time
  DateTime? actualEnd;

  @Enumerated(EnumType.name)
  late RecordingStatus status;

  /// File size in bytes
  int fileSize = 0;

  /// Duration in seconds
  int durationSeconds = 0;

  /// EPG program ID (if scheduled from EPG)
  int? epgProgramId;

  /// Error message if failed
  String? errorMessage;

  /// Creation timestamp
  late DateTime createdAt;

  Recording();

  factory Recording.create({
    required int channelId,
    required String title,
    required String filePath,
    required DateTime scheduledStart,
    required DateTime scheduledEnd,
    int? epgProgramId,
  }) {
    return Recording()
      ..channelId = channelId
      ..title = title
      ..filePath = filePath
      ..scheduledStart = scheduledStart
      ..scheduledEnd = scheduledEnd
      ..epgProgramId = epgProgramId
      ..status = RecordingStatus.scheduled
      ..createdAt = DateTime.now();
  }
}
