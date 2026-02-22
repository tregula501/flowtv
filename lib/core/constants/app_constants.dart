/// Application-wide constants
class AppConstants {
  AppConstants._();

  static const String appName = 'FlowTV';
  static const String appVersion = '0.3.2';

  // Default settings
  static const int defaultBufferDuration = 30; // seconds
  static const int epgRefreshInterval = 6; // hours
  static const int playlistRefreshInterval = 24; // hours

  // UI constants
  static const double sidebarWidth = 280.0;
  static const double channelTileHeight = 80.0;
  static const double epgRowHeight = 60.0;

  // EPG grid dimensions
  static const double epgTimeSlotWidth = 200.0;
  static const double epgChannelColumnWidth = 200.0;
  static const double epgGridRowHeight = 70.0;
  static const int epgHoursToShow = 24;

  // Player panel dimensions
  static const double minPlayerWidth = 320.0;
  static const double maxPlayerWidth = 800.0;
  static const double defaultPlayerPanelWidth = 480.0;

  // Player constants
  static const double defaultVolume = 1.0;
  static const int seekDuration = 10; // seconds

  // Cache settings
  static const int maxCachedImages = 500;
  static const int imageCacheDays = 7;

  // Network timeouts
  static const int castConnectionTimeoutSecs = 15;
  static const int m3uFetchTimeoutSecs = 60;
  static const int epgFetchTimeoutSecs = 120;

  // Database batch sizes
  static const int epgBatchSize = 1000;
  static const int channelBatchSize = 500;
}
