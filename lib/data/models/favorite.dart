import 'package:isar/isar.dart';

part 'favorite.g.dart';

/// Favorite model - tracks favorite channels per playlist
@collection
class Favorite {
  Id id = Isar.autoIncrement;

  /// Channel ID
  @Index()
  late int channelId;

  /// Playlist ID (for profile separation)
  @Index()
  late int playlistId;

  /// When it was favorited
  late DateTime addedAt;

  /// Custom sort order
  int sortOrder = 0;

  Favorite();

  factory Favorite.create({
    required int channelId,
    required int playlistId,
  }) {
    return Favorite()
      ..channelId = channelId
      ..playlistId = playlistId
      ..addedAt = DateTime.now();
  }
}
