/// App-wide constants.
///
/// Only values that are genuinely read by shipping code belong here. The file
/// previously carried seven constants (`searchPageSize`, `maxDownloadRetries`,
/// `maxConcurrentDownloads`, `urlCacheExpiry`, `searchCacheSize`,
/// `imageCacheSizeMB`, `downloadBasePath`) that were **never referenced
/// anywhere**: they looked like tunables but changing them had no effect, and
/// `downloadBasePath` advertised a hardcoded Android path
/// (`/storage/emulated/0/Mconnect`) that the download subsystem does not use at
/// all — it resolves its root through `path_provider`.
///
/// Those were removed. When a real tunable is needed, declare it next to the
/// code that reads it (or here **with** its reader landing in the same change),
/// so a constant here always means "this actually changes behaviour".
class AppConstants {
  AppConstants._();

  static const String appName = 'Mconnect';

  /// Shown on the settings page. Must be kept in sync with `pubspec.yaml`,
  /// `installer/mconnect.iss`, `windows/runner/Runner.rc`, `PROJECT.md` and
  /// `test/settings_page_test.dart` (see `AGENTS.md` §2).
  static const String appVersion = 'v1.4.1';

  /// Image cache budget, applied by `main.dart` to
  /// `PaintingBinding.instance.imageCache.maximumSizeBytes`.
  ///
  /// This value existed before but nothing ever read it, so the app silently
  /// ran on the framework's default 100 MB while the source claimed 200 MB.
  /// It is declared here **and** read in `main.dart` in the same change, so it
  /// is a real tunable rather than pretend configuration.
  static const int imageCacheSizeMb = 200;
}
