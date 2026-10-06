import 'package:drift/drift.dart' show Value;

import '../../../core/database/app_database.dart';
import '../../../models/platform_type.dart';
import '../../../models/toplist.dart';

/// Persistence for the 榜单中心 catalogue.
///
/// The hub used to hit three platforms on every visit with no cache at all, so
/// opening it offline produced a blank page even though the chart list is
/// essentially static (QQ publishes 30 charts that change daily, not per
/// second). WS-F added the `ToplistsCache` table; this is the store the hub
/// reads and writes through, and it is deliberately thin so tests can point it
/// at an in-memory database.
class ToplistsCacheStore {
  ToplistsCacheStore({AppDatabase? database}) : _db = database ?? _appDatabase();

  final AppDatabase _db;

  /// The app-wide database. Resolved through a function so the constructor
  /// parameter named `database` cannot shadow it (same trick as
  /// `DriftLocalTrackStore`).
  static AppDatabase _appDatabase() => database;

  /// Replaces one platform's cached charts atomically.
  Future<void> saveForPlatform(
    PlatformType platform,
    List<Toplist> toplists, {
    DateTime? fetchedAt,
  }) async {
    final at = fetchedAt ?? DateTime.now();
    await _db.toplistsCacheDao.replaceForPlatform(
      platform.name,
      [
        for (final toplist in toplists)
          ToplistsCacheCompanion.insert(
            platform: platform.name,
            toplistId: toplist.id,
            name: toplist.name,
            coverUrl: Value(toplist.coverUrl),
            updateFrequency: Value(toplist.updateFrequency),
            period: Value(toplist.period),
            songCount: Value(toplist.songCount),
            groupName: Value(toplist.groupName),
            intro: Value(toplist.intro),
            fetchedAt: at.millisecondsSinceEpoch,
          ),
      ],
    );
  }

  /// Cached charts for one platform, in the order they were written.
  Future<List<Toplist>> byPlatform(PlatformType platform) async {
    final rows = await _db.toplistsCacheDao.byPlatform(platform.name);
    return rows.map(_toToplist).toList();
  }

  /// Every cached chart, keyed by platform (used to render offline before any
  /// network call happens).
  Future<Map<PlatformType, List<Toplist>>> all() async {
    final rows = await _db.toplistsCacheDao.all();
    final grouped = <PlatformType, List<Toplist>>{};
    for (final row in rows) {
      // Persisted rows can outlive a platform (or be written by an older
      // build), so an unknown name is dropped rather than throwing.
      final platform = PlatformType.tryParse(row.platform);
      if (platform == null) continue;
      grouped.putIfAbsent(platform, () => []).add(_toToplist(row));
    }
    return grouped;
  }

  Future<DateTime?> lastFetchedAt(PlatformType platform) =>
      _db.toplistsCacheDao.lastFetchedAt(platform.name);

  Future<void> clearAll() => _db.toplistsCacheDao.clearAll();

  static Toplist _toToplist(ToplistCacheRow row) => Toplist(
    id: row.toplistId,
    name: row.name,
    coverUrl: row.coverUrl,
    updateFrequency: row.updateFrequency,
    period: row.period,
    songCount: row.songCount,
    groupName: row.groupName,
    intro: row.intro,
  );
}
