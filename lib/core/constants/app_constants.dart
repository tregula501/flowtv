/// Application-wide constants
class AppConstants {
  AppConstants._();

  static const String appName = 'FlowTV';
  static const String appVersion = '0.2.4';

  // Default settings
  static const int defaultBufferDuration = 30; // seconds
  static const int epgRefreshInterval = 6; // hours
  static const int playlistRefreshInterval = 24; // hours

  // UI constants
  static const double sidebarWidth = 280.0;
  static const double channelTileHeight = 80.0;
  static const double epgRowHeight = 60.0;

  // Player constants
  static const double defaultVolume = 1.0;
  static const int seekDuration = 10; // seconds

  // Cache settings
  static const int maxCachedImages = 500;
  static const int imageCacheDays = 7;
}
