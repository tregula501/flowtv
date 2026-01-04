import 'package:isar/isar.dart';

part 'epg_program.g.dart';

/// EPG Program model - represents a TV program in the guide
@collection
class EpgProgram {
  Id id = Isar.autoIncrement;

  /// Channel ID this program belongs to (matches Channel.epgId)
  @Index()
  late String channelId;

  /// Program title
  late String title;

  /// Program description
  String? description;

  /// Start time
  @Index()
  late DateTime startTime;

  /// End time
  late DateTime endTime;

  /// Category/Genre
  String? category;

  /// Episode info (e.g., "S01E05")
  String? episode;

  /// Program icon/poster URL
  String? iconUrl;

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
    return (elapsed / total).clamp(0.0, 1.0);
  }

  EpgProgram();

  factory EpgProgram.create({
    required String channelId,
    required String title,
    required DateTime startTime,
    required DateTime endTime,
    String? description,
    String? category,
    String? episode,
    String? iconUrl,
  }) {
    return EpgProgram()
      ..channelId = channelId
      ..title = title
      ..startTime = startTime
      ..endTime = endTime
      ..description = description
      ..category = category
      ..episode = episode
      ..iconUrl = iconUrl;
  }
}
