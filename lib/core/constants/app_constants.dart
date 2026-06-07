class AppConstants {
  AppConstants._();

  static const String appName = 'Mconnect';
  static const String appVersion = 'v1.2.3';

  static const int searchPageSize = 30;
  static const int maxDownloadRetries = 3;
  static const int maxConcurrentDownloads = 3;
  static const Duration urlCacheExpiry = Duration(minutes: 20);
  static const int searchCacheSize = 50;
  static const int imageCacheSizeMB = 200;

  static const String downloadBasePath = '/storage/emulated/0/Mconnect';
}
