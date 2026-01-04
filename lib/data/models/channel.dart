import 'package:isar/isar.dart';

part 'channel.g.dart';

/// Channel model - represents a single TV channel
@collection
class Channel {
  Id id = Isar.autoIncrement;

  /// Playlist this channel belongs to
  @Index()
  late int playlistId;

  /// Channel name from playlist
  @Index()
  late String name;

  /// Stream URL
  late String streamUrl;

  /// Logo URL (tvg-logo)
  String? logoUrl;

  /// EPG channel ID (tvg-id) for matching with EPG data
  @Index()
  String? epgId;

  /// Group/Category name (group-title)
  @Index()
  String? group;

  /// Channel number (if provided)
  int? channelNumber;

  /// Is this channel a favorite?
  @Index()
  bool isFavorite = false;

  /// Is this channel locked (parental control)?
  bool isLocked = false;

  /// Last watched timestamp
  DateTime? lastWatched;

  /// Custom sort order within group
  int sortOrder = 0;

  /// Is this a VOD item or live channel?
  bool isVod = false;

  /// Additional attributes from M3U
  String? language;
  String? country;

  Channel();

  factory Channel.create({
    required int playlistId,
    required String name,
    required String streamUrl,
    String? logoUrl,
    String? epgId,
    String? group,
    int? channelNumber,
  }) {
    return Channel()
      ..playlistId = playlistId
      ..name = name
      ..streamUrl = streamUrl
      ..logoUrl = logoUrl
      ..epgId = epgId
      ..group = group
      ..channelNumber = channelNumber;
  }
}
