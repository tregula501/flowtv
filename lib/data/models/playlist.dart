import 'package:isar/isar.dart';

part 'playlist.g.dart';

/// Type of playlist source
enum PlaylistType {
  m3u,      // Standard M3U/M3U8 file
  xtream,   // Xtream Codes API
  file,     // Local file
}

/// Playlist model - represents an IPTV playlist profile
@collection
class Playlist {
  Id id = Isar.autoIncrement;

  @Index()
  late String name;

  /// URL for M3U or Xtream server URL
  late String url;

  /// Xtream Codes username (if applicable)
  String? username;

  /// Xtream Codes password (if applicable)
  String? password;

  /// EPG URL (can be embedded in M3U or separate)
  String? epgUrl;

  @Enumerated(EnumType.name)
  late PlaylistType type;

  /// Last time this playlist was refreshed
  DateTime? lastRefresh;

  /// Number of channels in this playlist
  int channelCount = 0;

  /// Is this the active playlist?
  bool isActive = false;

  /// Creation timestamp
  late DateTime createdAt;

  /// Order for display
  int sortOrder = 0;

  Playlist();

  factory Playlist.create({
    required String name,
    required String url,
    required PlaylistType type,
    String? username,
    String? password,
    String? epgUrl,
  }) {
    return Playlist()
      ..name = name
      ..url = url
      ..type = type
      ..username = username
      ..password = password
      ..epgUrl = epgUrl
      ..createdAt = DateTime.now();
  }
}
