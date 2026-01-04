/// Keys used for local storage
class StorageKeys {
  StorageKeys._();

  // Settings
  static const String themeMode = 'theme_mode';
  static const String language = 'language';
  static const String volume = 'volume';
  static const String lastPlaylistId = 'last_playlist_id';
  static const String lastChannelId = 'last_channel_id';

  // EPG
  static const String epgLastUpdate = 'epg_last_update';
  static const String epgUrl = 'epg_url';

  // Playback
  static const String autoPlay = 'auto_play';
  static const String hardwareAcceleration = 'hardware_acceleration';
  static const String defaultQuality = 'default_quality';

  // Window
  static const String windowWidth = 'window_width';
  static const String windowHeight = 'window_height';
  static const String windowX = 'window_x';
  static const String windowY = 'window_y';
  static const String windowMaximized = 'window_maximized';

  // Parental
  static const String parentalPin = 'parental_pin';
  static const String parentalEnabled = 'parental_enabled';
}
