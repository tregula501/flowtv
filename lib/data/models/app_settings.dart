import 'package:isar/isar.dart';

part 'app_settings.g.dart';

/// Video quality preference
enum VideoQuality {
  auto,
  low,    // SD
  medium, // HD
  high,   // FHD
  ultra,  // 4K
}

/// App settings model - stores user preferences
@collection
class AppSettings {
  Id id = Isar.autoIncrement;

  /// Theme mode: 0 = system, 1 = light, 2 = dark
  int themeMode = 2; // Default to dark

  /// Language code
  String languageCode = 'en';

  /// Volume (0.0 to 1.0)
  double volume = 1.0;

  /// Is muted
  bool isMuted = false;

  /// Auto-play on channel select
  bool autoPlay = true;

  /// Hardware acceleration enabled
  bool hardwareAcceleration = true;

  @Enumerated(EnumType.name)
  VideoQuality defaultQuality = VideoQuality.auto;

  /// EPG auto-refresh interval in hours
  int epgRefreshHours = 6;

  /// Playlist auto-refresh interval in hours
  int playlistRefreshHours = 24;

  /// Buffer size in seconds
  int bufferSeconds = 30;

  /// Show channel numbers
  bool showChannelNumbers = true;

  /// Show EPG on channel list
  bool showEpgPreview = true;

  /// Remember last channel
  bool rememberLastChannel = true;

  /// Last active playlist ID
  int? lastPlaylistId;

  /// Last watched channel ID
  int? lastChannelId;

  /// Window width (desktop)
  double? windowWidth;

  /// Window height (desktop)
  double? windowHeight;

  /// Window X position (desktop)
  double? windowX;

  /// Window Y position (desktop)
  double? windowY;

  /// Window maximized state (desktop)
  bool windowMaximized = false;

  AppSettings();

  factory AppSettings.defaults() {
    return AppSettings();
  }
}
