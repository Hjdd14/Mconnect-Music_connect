import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

part 'app_database.g.dart';

// --- Tables ---

@DataClassName('SongRecord')
class Songs extends Table {
  TextColumn get id => text()();
  TextColumn get platform => text()();
  TextColumn get name => text()();
  // NOTE: despite the name this is **not** a JSON array — writers store the
  // comma-joined artist names (likes_provider.dart:136, history_provider.dart:169),
  // which is why the platform artist id had to be added separately below.
  TextColumn get artists => text()();
  TextColumn get albumName => text().nullable()();
  TextColumn get albumCover => text().nullable()();
  IntColumn get durationMs => integer().withDefault(const Constant(0))();
  TextColumn get fingerprint => text()();

  /// Owning-platform album id, so a cached song can open the album page.
  TextColumn get albumId => text().nullable()();

  /// Owning-platform primary artist id, so a cached song can open the artist
  /// page. Rows written before schema v2 leave this null; the UI falls back to
  /// a name search for those (see the migration notes in `docs/`).
  TextColumn get artistId => text().nullable()();

  /// 1-based track number inside the album.
  IntColumn get trackNumber => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id, platform};
}

/// `HistoryDao._newest` and `HistoryDao.getRecentHistory` both order by
/// [listenedAt] (the first one inside a transaction, on every recorded listen),
/// which without an index is a full table scan plus a sort over the whole
/// history.
@TableIndex(name: 'listening_history_listened_at', columns: {#listenedAt})
@DataClassName('ListeningHistoryEntry')
class ListeningHistory extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get songId => text()();
  TextColumn get platform => text()();
  IntColumn get listenedAt => integer()(); // epoch ms
  IntColumn get durationListened => integer().withDefault(const Constant(0))();

  /// Kept for historical schema compatibility only.
  ///
  /// This constraint can **never** fire: [listenedAt] is the *current* epoch
  /// millisecond value, so two rows about the same song always differ. It used
  /// to give the false impression that duplicate history rows were impossible
  /// while pause/resume/seek storms happily stacked identical entries.
  ///
  /// The real "same stretch of playback" rule is now enforced in
  /// [HistoryDao.recordListen] with a time window, which is the only place that
  /// can tell a genuine replay from a resume. Removing the constraint would
  /// change the created schema for fresh installs and require a v3 table
  /// rebuild; the frozen v2 contract is kept intact instead.
  @override
  List<Set<Column>> get uniqueKeys => [{songId, platform, listenedAt}];
}

@DataClassName('UserLike')
class UserLikes extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get songId => text()();
  TextColumn get platform => text()();
  IntColumn get addedAt => integer()(); // epoch ms

  @override
  List<Set<Column>> get uniqueKeys => [{songId, platform}];
}

class LyricsCache extends Table {
  TextColumn get songId => text()();
  TextColumn get platform => text()();
  TextColumn get content => text()();
  TextColumn get format => text()(); // lrc / qrc / krc
  IntColumn get syncedAt => integer()();

  @override
  Set<Column> get primaryKey => {songId, platform};
}

/// Local audio files discovered by the folder scanner.
///
/// Persisted so a rescan can skip unchanged files (path + mtime + size) instead
/// of walking the whole tree every time the page opens, and so tags/cover art
/// are read once rather than on every visit.
///
/// The `local_tracks_path` index is named in the W0-D contract, but [path] is
/// already the primary key, so SQLite maintains its own implicit unique index
/// (`sqlite_autoindex_local_tracks_1`) for the same column. The planner never
/// picks this second index; it is kept only to honour the contract and costs a
/// little write time on every scan upsert.
@TableIndex(name: 'local_tracks_path', columns: {#path})
@DataClassName('LocalTrack')
class LocalTracks extends Table {
  TextColumn get path => text()();
  IntColumn get mtime => integer()();
  IntColumn get size => integer()();
  TextColumn get title => text().nullable()();
  TextColumn get artistName => text().nullable()();
  TextColumn get albumName => text().nullable()();
  IntColumn get durationMs => integer().withDefault(const Constant(0))();
  IntColumn get trackNumber => integer().nullable()();
  TextColumn get coverPath => text().nullable()();
  IntColumn get scannedAt => integer().nullable()();

  /// `(mtime, size)` of the sidecar lyric file this row's lyrics were read
  /// from, so replacing a `.lrc` in place is noticed and re-read (schema v3).
  ///
  /// Null on rows written before v3: those are re-read once and stamped, which
  /// is also what repairs a library scanned by a build that never looked at the
  /// sidecar's timestamp at all.
  IntColumn get lyricsMtime => integer().nullable()();
  IntColumn get lyricsSize => integer().nullable()();

  @override
  Set<Column> get primaryKey => {path};
}

/// What produced a [PlayEvents] row.
///
/// Persisted by [name]; the statistics tracker uses it to keep a
/// pause-and-resume from being counted as a brand-new play.
enum PlayEventSource { play, resume, skip, seek }

/// One song's rolled-up playback totals.
typedef SongPlayAggregate = ({
  String songId,
  String platform,
  int playCount,
  int listenMs,
  int lastPlayedAt,
});

/// Global totals over every [PlayEvents] row.
typedef StatsTotals = ({
  int playCount,
  int listenMs,
  int distinctSongs,
  int eventCount,
});

/// A labelled dimension row (artist / album / platform).
typedef StatsDimensionEntry = ({String label, int playCount, int listenMs});

/// Cached chart listings (榜单中心), so the hub renders offline and does not
/// re-hit three platforms on every visit.
@DataClassName('ToplistCacheRow')
class ToplistsCache extends Table {
  TextColumn get platform => text()();
  TextColumn get toplistId => text()();
  TextColumn get name => text()();
  TextColumn get coverUrl => text().nullable()();
  TextColumn get updateFrequency => text().nullable()();
  TextColumn get period => text().nullable()();
  IntColumn get songCount => integer().nullable()();
  TextColumn get groupName => text().nullable()();
  TextColumn get intro => text().nullable()();
  IntColumn get fetchedAt => integer()();

  @override
  Set<Column> get primaryKey => {platform, toplistId};
}

/// One playback event per contiguous listening stretch.
///
/// Replaces the previous "keep the top 100 songs in a Hive snapshot" approach,
/// which silently destroyed the statistics of the 101st song onwards while the
/// totals stayed global (so the numbers could not be reconciled).
/// `StatsDao.addListenedDuration` looks up the newest event of one
/// `(song_id, platform)` pair on every flush (once per ten seconds of
/// playback), and `restorePlayEvents` probes the same pair per imported row.
/// Both are full table scans without these indexes.
@TableIndex(name: 'play_events_song_platform', columns: {#songId, #platform})
@TableIndex(name: 'play_events_started_at', columns: {#startedAt})
@DataClassName('PlayEvent')
class PlayEvents extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get songId => text()();
  TextColumn get platform => text()();
  IntColumn get startedAt => integer()();
  IntColumn get endedAt => integer().nullable()();
  IntColumn get durationListened => integer().withDefault(const Constant(0))();
  RealColumn get completedRatio => real().withDefault(const Constant(0))();

  /// `play` / `resume` / `skip` / `seek` — lets the UI stop counting a
  /// pause-and-resume as a brand new play.
  TextColumn get source => text().nullable()();
}

/// Daily roll-up derived from [PlayEvents], for fast charts on the stats page.
@DataClassName('DailyStat')
class DailyStats extends Table {
  TextColumn get day => text()(); // 'YYYY-MM-DD', local time
  TextColumn get songId => text()();
  TextColumn get platform => text()();
  IntColumn get playCount => integer().withDefault(const Constant(0))();
  IntColumn get listenMs => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {day, songId, platform};
}

/// A generated smart-playlist result, so previews can be saved and reopened.
@DataClassName('SmartPlaylistSnapshot')
class SmartPlaylistSnapshots extends Table {
  TextColumn get ruleId => text()();
  TextColumn get songKeys => text()(); // JSON array of "platform:id"
  IntColumn get generatedAt => integer()();

  @override
  Set<Column> get primaryKey => {ruleId};
}

/// Per-song lyrics offset, keyed by `"<platform>:<songId>"`.
///
/// A single row per song rather than one per platform-plus-id pair, because the
/// offset is a property of the *recording* the user is looking at, and the same
/// key shape is what `Song`-keyed caches elsewhere in the app already use.
///
/// Replaces nothing: until schema v3 the manual lyrics calibration
/// (`lyrics_offset_provider`) was a single global value, so correcting one song
/// shifted every other song's lyrics with it.
@DataClassName('LyricsOffsetRow')
class LyricsOffsets extends Table {
  TextColumn get songKey => text()();
  IntColumn get offsetMs => integer().withDefault(const Constant(0))();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {songKey};
}

/// Cross-platform "same recording elsewhere" cache.
///
/// One row per `(song, targetPlatform)`: which song id the match resolved to,
/// the stream URL that was fetched for it, and when that URL must be considered
/// stale. `expiresAt` is what makes the cache safe to trust — platform stream
/// URLs are signed and short-lived, so a stale row is discarded rather than
/// replayed into a 403.
@DataClassName('SourceMatchCacheRow')
class SourceMatchCaches extends Table {
  TextColumn get songKey => text()();
  TextColumn get targetPlatform => text()();
  TextColumn get targetSongId => text()();

  /// Last resolved stream URL, or null when only the identity was cached.
  TextColumn get url => text().nullable()();

  /// When [url] was fetched, for "is this still worth trying" diagnostics.
  IntColumn get urlFetchedAt => integer().nullable()();

  /// Match confidence in `[0, 1]`, so a weak match can be re-evaluated first.
  RealColumn get score => real().withDefault(const Constant(0))();

  /// Epoch ms after which the row must be re-resolved.
  IntColumn get expiresAt => integer()();

  @override
  Set<Column> get primaryKey => {songKey, targetPlatform};
}

// --- DAOs ---

@DriftAccessor(
  tables: [Songs, ListeningHistory, UserLikes, LyricsCache],
)
class SongsDao extends DatabaseAccessor<AppDatabase> with _$SongsDaoMixin {
  SongsDao(super.db);

  Future<void> insertSong(SongsCompanion song) async {
    await into(songs).insert(song, mode: InsertMode.insertOrReplace);
  }

  Future<void> insertSongs(List<SongsCompanion> songList) async {
    await batch((batch) {
      batch.insertAll(songs, songList, mode: InsertMode.insertOrReplace);
    });
  }

  Future<SongRecord?> getSong(String id, String platform) async {
    return (select(songs)
          ..where((t) => t.id.equals(id) & t.platform.equals(platform)))
        .getSingleOrNull();
  }

  Future<List<SongRecord>> getSongsByIds(List<({String id, String platform})> keys) async {
    if (keys.isEmpty) return [];
    final results = <SongRecord>[];
    // Process in batches of 50 to avoid SQL variable limit
    for (var i = 0; i < keys.length; i += 50) {
      final batch = keys.skip(i).take(50).toList();
      final query = select(songs)..where((t) {
        final conditions = batch.map((k) =>
          t.id.equals(k.id) & t.platform.equals(k.platform));
        return conditions.reduce((a, b) => a | b);
      });
      results.addAll(await query.get());
    }
    return results;
  }

  /// Every cached song row. Used by backup export, so it must **not** paginate.
  Future<List<SongRecord>> getAllSongs() => select(songs).get();

  /// Replaces [SongRecord]s coming back from a backup. Conflicts are resolved by
  /// the `(id, platform)` primary key, so an import merges instead of wiping.
  Future<void> replaceSongRecords(List<SongRecord> records) async {
    if (records.isEmpty) return;
    await batch((batch) {
      batch.insertAll(
        songs,
        records.map(
          (r) => SongsCompanion(
            id: Value(r.id),
            platform: Value(r.platform),
            name: Value(r.name),
            artists: Value(r.artists),
            albumName: Value(r.albumName),
            albumCover: Value(r.albumCover),
            durationMs: Value(r.durationMs),
            fingerprint: Value(r.fingerprint),
            albumId: Value(r.albumId),
            artistId: Value(r.artistId),
            trackNumber: Value(r.trackNumber),
          ),
        ),
        mode: InsertMode.insertOrReplace,
      );
    });
  }
}

@DriftAccessor(tables: [Songs, ListeningHistory])
class HistoryDao extends DatabaseAccessor<AppDatabase> with _$HistoryDaoMixin {
  HistoryDao(super.db);

  /// Two listens of the same song closer than this are treated as one stretch of
  /// playback, so a pause/resume or a seek does not create a second row.
  static const Duration dedupeWindow = Duration(seconds: 10);

  /// How long after the last row a duration update still targets that row.
  static const Duration backfillWindow = Duration(minutes: 30);

  /// Records one listen.
  ///
  /// Consecutive listens of the same song inside [dedupeWindow] are merged into
  /// the newest row instead of inserted again. The table-level
  /// `uniqueKeys` could never fire (see [ListeningHistory]), so this window is
  /// what actually enforces "one row per contiguous stretch".
  Future<void> recordListen(
    String songId,
    String platform, {
    int durationMs = 0,
    DateTime? at,
  }) async {
    final now = at ?? DateTime.now();
    final timestamp = now.millisecondsSinceEpoch;
    await transaction(() async {
      final newest = await _newest(songId, platform);
      if (newest != null &&
          timestamp >= newest.listenedAt &&
          timestamp - newest.listenedAt <= dedupeWindow.inMilliseconds) {
        await (update(listeningHistory)
              ..where((t) => t.id.equals(newest.id)))
            .write(
              ListeningHistoryCompanion(
                durationListened: Value(
                  durationMs > newest.durationListened
                      ? durationMs
                      : newest.durationListened,
                ),
              ),
            );
        return;
      }
      await into(listeningHistory).insert(
        ListeningHistoryCompanion.insert(
          songId: songId,
          platform: platform,
          listenedAt: timestamp,
          durationListened: Value(durationMs),
        ),
      );
    });
  }

  /// Adds listened time to the newest history row for the song.
  ///
  /// This is the data-layer half of the "history always shows 0:00" fix: the
  /// history provider records a row when playback starts (it cannot know the
  /// duration yet), and the statistics tracker feeds the elapsed time back in
  /// here. Creates a row if none exists inside [backfillWindow].
  Future<void> backfillListenedDuration(
    String songId,
    String platform,
    Duration duration, {
    DateTime? at,
  }) async {
    if (duration <= Duration.zero) return;
    final now = at ?? DateTime.now();
    final timestamp = now.millisecondsSinceEpoch;
    await transaction(() async {
      final newest = await _newest(songId, platform);
      if (newest != null &&
          timestamp >= newest.listenedAt &&
          timestamp - newest.listenedAt <= backfillWindow.inMilliseconds) {
        await (update(listeningHistory)
              ..where((t) => t.id.equals(newest.id)))
            .write(
              ListeningHistoryCompanion(
                durationListened: Value(
                  newest.durationListened + duration.inMilliseconds,
                ),
              ),
            );
        return;
      }
      await into(listeningHistory).insert(
        ListeningHistoryCompanion.insert(
          songId: songId,
          platform: platform,
          listenedAt: timestamp,
          durationListened: Value(duration.inMilliseconds),
        ),
      );
    });
  }

  Future<ListeningHistoryEntry?> _newest(String songId, String platform) {
    return (select(listeningHistory)
          ..where((t) => t.songId.equals(songId) & t.platform.equals(platform))
          ..orderBy([(t) => OrderingTerm.desc(t.listenedAt)])
          ..limit(1))
        .getSingleOrNull();
  }

  Future<List<ListeningHistoryEntry>> getRecentHistory({int limit = 50}) async {
    return (select(listeningHistory)
          ..orderBy([(t) => OrderingTerm.desc(t.listenedAt)])
          ..limit(limit))
        .get();
  }

  Future<int> countHistory() async {
    final count = listeningHistory.id.count();
    final row = await (selectOnly(listeningHistory)..addColumns([count])).getSingle();
    return row.read(count) ?? 0;
  }

  Future<void> clearHistory() async {
    await delete(listeningHistory).go();
  }
}

@DriftAccessor(tables: [Songs, UserLikes])
class LikesDao extends DatabaseAccessor<AppDatabase> with _$LikesDaoMixin {
  LikesDao(super.db);

  Future<void> likeSong(String songId, String platform) async {
    await into(userLikes).insert(
      UserLikesCompanion.insert(
        songId: songId,
        platform: platform,
        addedAt: DateTime.now().millisecondsSinceEpoch,
      ),
      mode: InsertMode.insertOrReplace,
    );
  }

  Future<void> unlikeSong(String songId, String platform) async {
    await (delete(userLikes)
          ..where((t) => t.songId.equals(songId) & t.platform.equals(platform)))
        .go();
  }

  Future<bool> isLiked(String songId, String platform) async {
    final result = await (select(userLikes)
          ..where((t) => t.songId.equals(songId) & t.platform.equals(platform))
          ..limit(1))
        .get();
    return result.isNotEmpty;
  }

  Future<List<UserLike>> getAllLikes({int limit = 100}) async {
    return (select(userLikes)
          ..orderBy([(t) => OrderingTerm.desc(t.addedAt)])
          ..limit(limit))
        .get();
  }

  /// Every like row, unpaginated — backup export must not silently drop rows
  /// past the UI page size (the likes page itself pages at 500).
  Future<List<UserLike>> getAllLikeRows() =>
      (select(userLikes)..orderBy([(t) => OrderingTerm.asc(t.addedAt)])).get();

  Future<int> countLikes() async {
    final count = userLikes.id.count();
    final row = await (selectOnly(userLikes)..addColumns([count])).getSingle();
    return row.read(count) ?? 0;
  }

  /// Restores like rows. `(songId, platform)` is unique, so re-importing the
  /// same backup is idempotent and never duplicates a favourite.
  Future<void> restoreLikeRows(List<UserLike> rows) async {
    if (rows.isEmpty) return;
    await batch((batch) {
      batch.insertAll(
        userLikes,
        rows.map(
          (r) => UserLikesCompanion.insert(
            songId: r.songId,
            platform: r.platform,
            addedAt: r.addedAt,
          ),
        ),
        mode: InsertMode.insertOrReplace,
      );
    });
  }
}

@DriftAccessor(tables: [LyricsCache])
class LyricsCacheDao extends DatabaseAccessor<AppDatabase> with _$LyricsCacheDaoMixin {
  LyricsCacheDao(super.db);

  Future<String?> getCachedLyrics(String songId, String platform) async {
    final result = await (select(lyricsCache)
          ..where((t) => t.songId.equals(songId) & t.platform.equals(platform))
          ..limit(1))
        .get();
    return result.isNotEmpty ? result.first.content : null;
  }

  Future<({String content, String format})?> getCachedLyricsWithFormat(String songId, String platform) async {
    final result = await (select(lyricsCache)
          ..where((t) => t.songId.equals(songId) & t.platform.equals(platform))
          ..limit(1))
        .get();
    if (result.isEmpty) return null;
    return (content: result.first.content, format: result.first.format);
  }

  Future<void> cacheLyrics(String songId, String platform, String content, String format) async {
    await into(lyricsCache).insert(
      LyricsCacheCompanion.insert(
        songId: songId,
        platform: platform,
        content: content,
        format: format,
        syncedAt: DateTime.now().millisecondsSinceEpoch,
      ),
      mode: InsertMode.insertOrReplace,
    );
  }
}

// --- Statistics ---

/// Accumulator for one `(day, song, platform)` roll-up row.
///
/// Exists so [StatsDao.restorePlayEvents] can write the daily roll-up once per
/// group instead of once per restored event.
class _DailyDelta {
  _DailyDelta(this.day, this.songId, this.platform);

  final String day;
  final String songId;
  final String platform;
  int playCount = 0;
  int listenMs = 0;
}

/// Read/write access to the play-event detail table and its daily roll-up.
///
/// This is the replacement for the old "Hive snapshot of the top 100 songs"
/// statistics store. Aggregates are always computed from the raw detail, so
/// **no song's history can be pushed out and destroyed** by adding a 101st one:
/// the display list is a ranked *view*, never the storage.
@DriftAccessor(tables: [Songs, PlayEvents, DailyStats])
class StatsDao extends DatabaseAccessor<AppDatabase> with _$StatsDaoMixin {
  StatsDao(super.db);

  /// Records the start of a playback stretch and bumps today's roll-up.
  Future<int> recordPlayStart({
    required String songId,
    required String platform,
    required DateTime startedAt,
    PlayEventSource source = PlayEventSource.play,
  }) async {
    final id = await into(playEvents).insert(
      PlayEventsCompanion.insert(
        songId: songId,
        platform: platform,
        startedAt: startedAt.millisecondsSinceEpoch,
        source: Value(source.name),
      ),
    );
    await _bumpDailyStat(
      day: dayKey(startedAt),
      songId: songId,
      platform: platform,
      playDelta: 1,
    );
    return id;
  }

  /// Adds listened time to the newest event of [songId]/[platform].
  ///
  /// [songDurationMs] lets the event carry a completion ratio; pass null when
  /// the platform did not report a duration.
  Future<void> addListenedDuration({
    required String songId,
    required String platform,
    required Duration duration,
    int? songDurationMs,
    DateTime? at,
  }) async {
    if (duration <= Duration.zero) return;
    final now = at ?? DateTime.now();
    final listenMs = duration.inMilliseconds;
    await transaction(() async {
      final newest =
          await (select(playEvents)
                ..where(
                  (t) =>
                      t.songId.equals(songId) & t.platform.equals(platform),
                )
                ..orderBy([(t) => OrderingTerm.desc(t.id)])
                ..limit(1))
              .getSingleOrNull();

      if (newest == null) {
        // A duration without a recorded start (e.g. restored/backfilled data):
        // keep the time instead of dropping it, and mark the source honestly.
        await into(playEvents).insert(
          PlayEventsCompanion.insert(
            songId: songId,
            platform: platform,
            startedAt: now.millisecondsSinceEpoch,
            endedAt: Value(now.millisecondsSinceEpoch),
            durationListened: Value(listenMs),
            source: Value(PlayEventSource.seek.name),
          ),
        );
        await _bumpDailyStat(
          day: dayKey(now),
          songId: songId,
          platform: platform,
          listenMs: listenMs,
        );
        return;
      }

      final totalMs = newest.durationListened + listenMs;
      final ratio = (songDurationMs != null && songDurationMs > 0)
          ? (totalMs / songDurationMs).clamp(0.0, 1.0)
          : newest.completedRatio;
      await (update(playEvents)..where((t) => t.id.equals(newest.id))).write(
        PlayEventsCompanion(
          durationListened: Value(totalMs),
          completedRatio: Value(ratio),
          endedAt: Value(now.millisecondsSinceEpoch),
        ),
      );
      // Roll up against the *event's* day so a stretch crossing midnight still
      // lands in the day it started.
      await _bumpDailyStat(
        day: dayKey(DateTime.fromMillisecondsSinceEpoch(newest.startedAt)),
        songId: songId,
        platform: platform,
        listenMs: listenMs,
      );
    });
  }

  /// `'YYYY-MM-DD'` in local time, matching the [DailyStats.day] contract.
  static String dayKey(DateTime time) {
    final local = time.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '${local.year}-$month-$day';
  }

  /// Adds [playDelta]/[listenMs] to one `(day, songId, platform)` roll-up row.
  ///
  /// Adds [playDelta]/[listenMs] to one `(day, songId, platform)` roll-up row.
  ///
  /// Kept as a read-then-write pair on purpose (W0-D): a single statement would
  /// need drift's expression arithmetic (`old.playCount + Constant(playDelta)`)
  /// or a raw `INSERT ... ON CONFLICT` string, and neither could be verified in
  /// the wave that introduced the v3 schema — the whole package was blocked
  /// while this file did not compile. The `daily_stats` primary key already
  /// makes the upsert shape available whenever someone can run the tests.
  Future<void> _bumpDailyStat({
    required String day,
    required String songId,
    required String platform,
    int playDelta = 0,
    int listenMs = 0,
  }) async {
    final existing =
        await (select(dailyStats)..where(
              (t) =>
                  t.day.equals(day) &
                  t.songId.equals(songId) &
                  t.platform.equals(platform),
            ))
            .getSingleOrNull();
    if (existing == null) {
      await into(dailyStats).insert(
        DailyStatsCompanion.insert(
          day: day,
          songId: songId,
          platform: platform,
          playCount: Value(playDelta),
          listenMs: Value(listenMs),
        ),
      );
      return;
    }
    await (update(dailyStats)..where(
          (t) =>
              t.day.equals(day) &
              t.songId.equals(songId) &
              t.platform.equals(platform),
        ))
        .write(
          DailyStatsCompanion(
            playCount: Value(existing.playCount + playDelta),
            listenMs: Value(existing.listenMs + listenMs),
          ),
        );
  }

  /// Global totals, computed over **every** event row.
  Future<StatsTotals> totals() async {
    final playCount = playEvents.id.count();
    final listenMs = playEvents.durationListened.sum();
    final row =
        await (selectOnly(playEvents)
              ..addColumns([playCount, listenMs]))
            .getSingle();
    final distinct = await customSelect(
      'SELECT COUNT(*) AS c FROM '
      '(SELECT DISTINCT song_id, platform FROM play_events)',
    ).getSingle();
    return (
      playCount: row.read(playCount) ?? 0,
      listenMs: row.read(listenMs) ?? 0,
      distinctSongs: distinct.read<int>('c'),
      eventCount: row.read(playCount) ?? 0,
    );
  }

  /// Per-song aggregates, ranked by listened time.
  Future<List<SongPlayAggregate>> songAggregates({int? limit}) async {
    final playCount = playEvents.id.count();
    final listenMs = playEvents.durationListened.sum();
    final lastPlayedAt = playEvents.startedAt.max();
    final query = selectOnly(playEvents)
      ..addColumns([
        playEvents.songId,
        playEvents.platform,
        playCount,
        listenMs,
        lastPlayedAt,
      ])
      ..groupBy([playEvents.songId, playEvents.platform])
      ..orderBy([
        OrderingTerm.desc(listenMs),
        OrderingTerm.desc(playCount),
        OrderingTerm.desc(lastPlayedAt),
      ]);
    if (limit != null) query.limit(limit);
    final rows = await query.get();
    return rows
        .map(
          (row) => (
            songId: row.read(playEvents.songId)!,
            platform: row.read(playEvents.platform)!,
            playCount: row.read(playCount) ?? 0,
            listenMs: row.read(listenMs) ?? 0,
            lastPlayedAt: row.read(lastPlayedAt) ?? 0,
          ),
        )
        .toList();
  }

  /// One song's aggregate, or null when it has never been played.
  ///
  /// This is the lookup that proves the old top-100 truncation is gone: a song
  /// that is not in the ranked view is still fully retrievable.
  Future<SongPlayAggregate?> songAggregate(String songId, String platform) async {
    final playCount = playEvents.id.count();
    final listenMs = playEvents.durationListened.sum();
    final lastPlayedAt = playEvents.startedAt.max();
    final query = selectOnly(playEvents)
      ..addColumns([playCount, listenMs, lastPlayedAt])
      ..where(playEvents.songId.equals(songId) & playEvents.platform.equals(platform));
    final row = await query.getSingleOrNull();
    if (row == null || (row.read(playCount) ?? 0) == 0) return null;
    return (
      songId: songId,
      platform: platform,
      playCount: row.read(playCount) ?? 0,
      listenMs: row.read(listenMs) ?? 0,
      lastPlayedAt: row.read(lastPlayedAt) ?? 0,
    );
  }

  /// Artists ranked by listened time (joined with the cached song metadata,
  /// because an artist is not a column on [PlayEvents]).
  Future<List<StatsDimensionEntry>> topArtists({int limit = 20}) {
    return _dimension(songs.artists, limit: limit);
  }

  /// Albums ranked by listened time. Songs without an album are skipped.
  Future<List<StatsDimensionEntry>> topAlbums({int limit = 20}) {
    return _dimension(songs.albumName, limit: limit, skipNull: true);
  }

  /// Platforms ranked by listened time; always readable even with no metadata.
  Future<List<StatsDimensionEntry>> platformBreakdown() async {
    final playCount = playEvents.id.count();
    final listenMs = playEvents.durationListened.sum();
    final query = selectOnly(playEvents)
      ..addColumns([playEvents.platform, playCount, listenMs])
      ..groupBy([playEvents.platform])
      ..orderBy([OrderingTerm.desc(listenMs)]);
    final rows = await query.get();
    return rows
        .map(
          (row) => (
            label: row.read(playEvents.platform)!,
            playCount: row.read(playCount) ?? 0,
            listenMs: row.read(listenMs) ?? 0,
          ),
        )
        .toList();
  }

  Future<List<StatsDimensionEntry>> _dimension(
    Column<String> column, {
    required int limit,
    bool skipNull = false,
  }) async {
    final playCount = playEvents.id.count();
    final listenMs = playEvents.durationListened.sum();
    final query = selectOnly(playEvents)
      ..join([
        innerJoin(
          songs,
          songs.id.equalsExp(playEvents.songId) &
              songs.platform.equalsExp(playEvents.platform),
        ),
      ])
      ..addColumns([column, playCount, listenMs])
      ..groupBy([column])
      ..orderBy([OrderingTerm.desc(listenMs)]);
    if (skipNull) query.where(column.isNotNull());
    query.limit(limit);
    final rows = await query.get();
    return rows
        .where((row) => row.read(column) != null)
        .map(
          (row) => (
            label: row.read(column)!,
            playCount: row.read(playCount) ?? 0,
            listenMs: row.read(listenMs) ?? 0,
          ),
        )
        .toList();
  }

  /// `'YYYY-MM-DD'` roll-ups, newest first.
  Future<List<({String day, int playCount, int listenMs})>> dailySeries({
    int limit = 30,
  }) async {
    final playCount = dailyStats.playCount.sum();
    final listenMs = dailyStats.listenMs.sum();
    final query = selectOnly(dailyStats)
      ..addColumns([dailyStats.day, playCount, listenMs])
      ..groupBy([dailyStats.day])
      ..orderBy([OrderingTerm.desc(dailyStats.day)])
      ..limit(limit);
    final rows = await query.get();
    return rows
        .map(
          (row) => (
            day: row.read(dailyStats.day)!,
            playCount: row.read(playCount) ?? 0,
            listenMs: row.read(listenMs) ?? 0,
          ),
        )
        .toList();
  }

  /// Plays bucketed by local hour of day (0–23).
  ///
  /// Aggregated in SQLite. The previous implementation read **every**
  /// `play_events` row into memory and bucketed it in Dart, so opening the
  /// statistics page paid a full-table materialisation on top of the scan — the
  /// one query on that page that grew with the whole history rather than with
  /// the 24 buckets it renders.
  ///
  /// `'localtime'` is deliberate and does not change the result: the Dart it
  /// replaces (`DateTime.fromMillisecondsSinceEpoch(...).toLocal().hour`) reads
  /// the same host time zone, so both follow the host's zone **and** its DST
  /// rules. A fixed UTC offset computed in Dart would be the variant that
  /// disagrees with itself across a DST boundary.
  ///
  /// Table/column names are spelled out, matching the hard-coded SQL in
  /// [totals] and [activeDayCount].
  Future<List<({int hour, int playCount, int listenMs})>> hourHistogram() async {
    final rows = await customSelect(
      "SELECT CAST(strftime('%H', started_at / 1000, 'unixepoch', 'localtime') "
      'AS INTEGER) AS hour_bucket, '
      'COUNT(*) AS plays, '
      'COALESCE(SUM(duration_listened), 0) AS listen_ms '
      'FROM play_events '
      'GROUP BY hour_bucket',
      readsFrom: {playEvents},
    ).get();

    final plays = List<int>.filled(24, 0);
    final listenMs = List<int>.filled(24, 0);
    for (final row in rows) {
      final hour = row.read<int?>('hour_bucket');
      // Defensive: an unparseable timestamp would produce a null bucket, and
      // the caller renders all 24 buckets by index.
      if (hour == null || hour < 0 || hour > 23) continue;
      plays[hour] = row.read<int>('plays');
      listenMs[hour] = row.read<int>('listen_ms');
    }
    return [
      for (var hour = 0; hour < 24; hour++)
        (hour: hour, playCount: plays[hour], listenMs: listenMs[hour]),
    ];
  }

  /// Every event row, oldest first (backup export).
  Future<List<PlayEvent>> allPlayEvents() =>
      (select(playEvents)..orderBy([(t) => OrderingTerm.asc(t.id)])).get();

  /// Restores event rows, skipping `(songId, platform, startedAt)` duplicates so
  /// importing the same backup twice does not double the statistics.
  ///
  /// Batched. The previous version issued one `SELECT` per imported row and one
  /// `INSERT` per insertable row (plus a `SELECT` + `INSERT`/`UPDATE` for the
  /// roll-up of each), so restoring a real backup was thousands of round trips
  /// inside one transaction. Now: one indexed query per 400 distinct timestamps
  /// for the duplicate probe, one batch insert for the survivors, and one
  /// roll-up write per `(day, song, platform)` group.
  Future<int> restorePlayEvents(List<PlayEvent> rows) async {
    if (rows.isEmpty) return 0;
    var inserted = 0;
    await transaction(() async {
      // `Set.add` doubles as the within-import duplicate check: the second copy
      // of an identical row is rejected exactly like one already in the table.
      final seen = await _existingEventKeys(rows);
      final fresh = <PlayEvent>[];
      for (final row in rows) {
        final key = _eventKey(row.songId, row.platform, row.startedAt);
        if (!seen.add(key)) continue;
        fresh.add(row);
      }
      if (fresh.isEmpty) return;

      await batch((b) {
        b.insertAll(playEvents, [
          for (final row in fresh)
            PlayEventsCompanion.insert(
              songId: row.songId,
              platform: row.platform,
              startedAt: row.startedAt,
              endedAt: Value(row.endedAt),
              durationListened: Value(row.durationListened),
              completedRatio: Value(row.completedRatio),
              source: Value(row.source),
            ),
        ]);
      });

      for (final delta in _dailyDeltasOf(fresh).values) {
        await _bumpDailyStat(
          day: delta.day,
          songId: delta.songId,
          platform: delta.platform,
          playDelta: delta.playCount,
          listenMs: delta.listenMs,
        );
      }
      inserted = fresh.length;
    });
    return inserted;
  }

  /// `(songId, platform, startedAt)` keys that already exist **and** could be
  /// hit by [rows].
  ///
  /// Restricted to the import's own `startedAt` values: a duplicate necessarily
  /// shares one of them, so this is exact while staying proportional to the
  /// backup instead of to the whole history. Chunked for SQLite's bound-variable
  /// limit, and served by the `play_events_started_at` index (schema v3).
  Future<Set<String>> _existingEventKeys(List<PlayEvent> rows) async {
    final timestamps = {for (final row in rows) row.startedAt}.toList();
    final keys = <String>{};
    for (var i = 0; i < timestamps.length; i += 400) {
      final chunk = timestamps.skip(i).take(400).toList();
      final found = await customSelect(
        'SELECT song_id, platform, started_at FROM play_events '
        'WHERE started_at IN (${List.filled(chunk.length, '?').join(', ')})',
        variables: [for (final value in chunk) Variable.withInt(value)],
        readsFrom: {playEvents},
      ).get();
      for (final row in found) {
        keys.add(
          _eventKey(
            row.read<String>('song_id'),
            row.read<String>('platform'),
            row.read<int>('started_at'),
          ),
        );
      }
    }
    return keys;
  }

  /// Folds [rows] into one accumulator per `(day, song, platform)`.
  ///
  /// The day comes from each row's own `startedAt`, so a stretch that crosses
  /// midnight still lands in the day it started.
  Map<String, _DailyDelta> _dailyDeltasOf(List<PlayEvent> rows) {
    final byGroup = <String, _DailyDelta>{};
    for (final row in rows) {
      final day = dayKey(DateTime.fromMillisecondsSinceEpoch(row.startedAt));
      final delta = byGroup.putIfAbsent(
        '$day\u0000${row.songId}\u0000${row.platform}',
        () => _DailyDelta(day, row.songId, row.platform),
      );
      delta.playCount += 1;
      delta.listenMs += row.durationListened;
    }
    return byGroup;
  }

  /// One identity key for a play event.
  ///
  /// NUL-joined because none of the three parts can contain a NUL, so no two
  /// distinct triples can produce the same key.
  static String _eventKey(String songId, String platform, int startedAt) =>
      '$songId\u0000$platform\u0000$startedAt';

  Future<int> countPlayEvents() async {
    final count = playEvents.id.count();
    final row = await (selectOnly(playEvents)..addColumns([count])).getSingle();
    return row.read(count) ?? 0;
  }

  /// Distinct days that carry at least one play.
  Future<int> activeDayCount() async {
    final row = await customSelect(
      'SELECT COUNT(*) AS c FROM (SELECT DISTINCT day FROM daily_stats)',
    ).getSingle();
    return row.read<int>('c');
  }

  Future<void> clearAll() async {
    await transaction(() async {
      await delete(playEvents).go();
      await delete(dailyStats).go();
    });
  }
}

// --- Local file cache (DAO only; the scanner lives in WS-J) ---

typedef LocalTrackStamp = ({int mtime, int size});

/// Persistence for the local-file scanner. Deliberately contains **no** scanning
/// or tag-reading logic: that belongs to the local-music feature, which owns the
/// walk and only uses this DAO to skip unchanged files.
@DriftAccessor(tables: [LocalTracks])
class LocalTracksDao extends DatabaseAccessor<AppDatabase> with _$LocalTracksDaoMixin {
  LocalTracksDao(super.db);

  Future<void> upsert(LocalTracksCompanion track) async {
    await into(localTracks).insert(track, mode: InsertMode.insertOrReplace);
  }

  Future<void> upsertAll(List<LocalTracksCompanion> tracks) async {
    if (tracks.isEmpty) return;
    await batch((batch) {
      batch.insertAll(localTracks, tracks, mode: InsertMode.insertOrReplace);
    });
  }

  Future<List<LocalTrack>> all({int? limit}) async {
    final query = select(localTracks)..orderBy([(t) => OrderingTerm.asc(t.path)]);
    if (limit != null) query.limit(limit);
    return query.get();
  }

  Future<LocalTrack?> byPath(String path) {
    return (select(localTracks)..where((t) => t.path.equals(path)))
        .getSingleOrNull();
  }

  /// `path → (mtime, size)` for the incremental-rescan comparison.
  Future<Map<String, LocalTrackStamp>> stamps() async {
    final rows = await (select(localTracks)
          ..orderBy([(t) => OrderingTerm.asc(t.path)]))
        .get();
    return {
      for (final row in rows) row.path: (mtime: row.mtime, size: row.size),
    };
  }

  Future<List<String>> allPaths() async {
    final query = selectOnly(localTracks)..addColumns([localTracks.path]);
    final rows = await query.get();
    return rows.map((row) => row.read(localTracks.path)!).toList();
  }

  Future<int> deleteByPath(String path) {
    return (delete(localTracks)..where((t) => t.path.equals(path))).go();
  }

  /// Deletes exactly [paths], in chunks.
  ///
  /// The local-library reconciler knows the paths that disappeared, and the old
  /// `LocalTrackStore.removePaths` issued one `DELETE` per path inside a single
  /// transaction — a folder rename or a moved library meant thousands of
  /// statements. [deleteMissing] is the complement-shaped variant (keep-list),
  /// so it cannot serve this direction without loading and diffing every path
  /// first.
  Future<int> deletePaths(Iterable<String> paths) =>
      _deletePathChunks(paths.toList(growable: false));

  /// Deletes every row whose path is **not** in [keepPaths].
  ///
  /// Chunked because a music library can hold far more paths than SQLite accepts
  /// variables in one statement.
  Future<int> deleteMissing(Set<String> keepPaths) async {
    final existing = await allPaths();
    final stale = existing.where((path) => !keepPaths.contains(path)).toList();
    return _deletePathChunks(stale);
  }

  /// `DELETE ... WHERE path IN (...)` in batches of 400 bound variables.
  Future<int> _deletePathChunks(List<String> paths) async {
    if (paths.isEmpty) return 0;
    var deleted = 0;
    for (var i = 0; i < paths.length; i += 400) {
      final chunk = paths.skip(i).take(400).toList();
      deleted += await (delete(
        localTracks,
      )..where((t) => t.path.isIn(chunk))).go();
    }
    return deleted;
  }

  Future<int> count() async {
    final count = localTracks.path.count();
    final row = await (selectOnly(localTracks)..addColumns([count])).getSingle();
    return row.read(count) ?? 0;
  }

  Future<int> clear() => delete(localTracks).go();
}

// --- Per-song lyrics offset (schema v3) ---

@DriftAccessor(tables: [LyricsOffsets])
class LyricsOffsetDao extends DatabaseAccessor<AppDatabase>
    with _$LyricsOffsetDaoMixin {
  LyricsOffsetDao(super.db);

  /// The stored offset for [songKey], or `Duration.zero` when none is saved.
  ///
  /// Returning zero instead of null keeps callers free of a "no row yet" branch:
  /// the domain meaning of "no saved offset" and "saved offset of zero" is the
  /// same, and only the UI's "reset" affordance depends on the difference.
  Future<Duration> get(String songKey) async {
    final row = await (select(
      lyricsOffsets,
    )..where((t) => t.songKey.equals(songKey))).getSingleOrNull();
    return Duration(milliseconds: row?.offsetMs ?? 0);
  }

  /// [LyricsOffsetRow] for [songKey], or null when the user never set one.
  Future<LyricsOffsetRow?> row(String songKey) {
    return (select(
      lyricsOffsets,
    )..where((t) => t.songKey.equals(songKey))).getSingleOrNull();
  }

  /// Saves [offset] for [songKey], replacing any previous value.
  ///
  /// A zero offset **deletes** the row rather than storing `offsetMs = 0`: the
  /// table is a "the user changed something" record, so keeping zero rows would
  /// grow it with songs that were merely opened.
  Future<void> set(
    String songKey,
    Duration offset, {
    DateTime? at,
  }) async {
    if (offset == Duration.zero) {
      await clear(songKey);
      return;
    }
    await into(lyricsOffsets).insert(
      LyricsOffsetsCompanion.insert(
        songKey: songKey,
        offsetMs: Value(offset.inMilliseconds),
        updatedAt: (at ?? DateTime.now()).millisecondsSinceEpoch,
      ),
      mode: InsertMode.insertOrReplace,
    );
  }

  Future<int> clear(String songKey) {
    return (delete(
      lyricsOffsets,
    )..where((t) => t.songKey.equals(songKey))).go();
  }

  Future<int> clearAll() => delete(lyricsOffsets).go();
}

// --- Cross-platform source-match cache (schema v3) ---

@DriftAccessor(tables: [SourceMatchCaches])
class SourceMatchCacheDao extends DatabaseAccessor<AppDatabase>
    with _$SourceMatchCacheDaoMixin {
  SourceMatchCacheDao(super.db);

  /// The cached row for one `(song, platform)` pair, expired rows included.
  ///
  /// [targetPlatform] is the persisted `PlatformType.name`, the same shape the
  /// rest of this layer uses (`Songs.platform`, `PlayEvents.platform`).
  ///
  /// Callers decide what an expired row is worth: [get] drops it, while a
  /// "re-resolve this one first" path may still want its [SourceMatchCacheRow.score].
  Future<SourceMatchCacheRow?> row(
    String songKey,
    String targetPlatform,
  ) {
    return (select(sourceMatchCaches)..where(
          (t) =>
              t.songKey.equals(songKey) &
              t.targetPlatform.equals(targetPlatform),
        ))
        .getSingleOrNull();
  }

  /// The cached match, or null when it is absent **or past its expiry**.
  ///
  /// Expiry is enforced here rather than by a sweep so a long-idle library never
  /// hands out a dead stream URL; [purgeExpired] exists only to reclaim space.
  Future<SourceMatchCacheRow?> get(
    String songKey,
    String targetPlatform, {
    DateTime? now,
  }) async {
    final cached = await row(songKey, targetPlatform);
    if (cached == null) return null;
    final at = now ?? DateTime.now();
    if (cached.expiresAt <= at.millisecondsSinceEpoch) return null;
    return cached;
  }

  /// Inserts or replaces one match.
  Future<void> put({
    required String songKey,
    required String targetPlatform,
    required String targetSongId,
    required DateTime expiresAt,
    String? url,
    DateTime? urlFetchedAt,
    double score = 0,
  }) async {
    await into(sourceMatchCaches).insert(
      SourceMatchCachesCompanion.insert(
        songKey: songKey,
        targetPlatform: targetPlatform,
        targetSongId: targetSongId,
        url: Value(url),
        urlFetchedAt: Value(urlFetchedAt?.millisecondsSinceEpoch),
        score: Value(score.clamp(0, 1).toDouble()),
        expiresAt: expiresAt.millisecondsSinceEpoch,
      ),
      mode: InsertMode.insertOrReplace,
    );
  }

  /// Drops every row whose `expiresAt` has passed; returns how many went.
  ///
  /// Spelled out in raw SQL like [StatsDao.totals], so the sweep does not depend
  /// on the spelling of the comparison helper this drift version generates for a
  /// column (they were renamed across the 2.x line).
  Future<int> purgeExpired({DateTime? now}) async {
    final at = (now ?? DateTime.now()).millisecondsSinceEpoch;
    final expired = await customSelect(
      'SELECT COUNT(*) AS expired FROM source_match_caches '
      'WHERE expires_at <= ?',
      variables: [Variable.withInt(at)],
      readsFrom: {sourceMatchCaches},
    ).getSingle();
    final count = expired.read<int>('expired');
    if (count == 0) return 0;
    await customStatement(
      'DELETE FROM source_match_caches WHERE expires_at <= ?',
      [at],
    );
    return count;
  }

  Future<int> clearAll() => delete(sourceMatchCaches).go();
}

// --- Chart cache (DAO only; the hub UI lives in WS-H) ---

@DriftAccessor(tables: [ToplistsCache])
class ToplistsCacheDao extends DatabaseAccessor<AppDatabase> with _$ToplistsCacheDaoMixin {
  ToplistsCacheDao(super.db);

  /// Replaces every cached row of one platform in a single transaction, so a
  /// failed refresh never leaves a half-updated chart list behind.
  Future<void> replaceForPlatform(
    String platform,
    List<ToplistsCacheCompanion> rows,
  ) async {
    await transaction(() async {
      await (delete(toplistsCache)..where((t) => t.platform.equals(platform))).go();
      if (rows.isEmpty) return;
      await batch((batch) {
        batch.insertAll(
          toplistsCache,
          rows,
          mode: InsertMode.insertOrReplace,
        );
      });
    });
  }

  Future<List<ToplistCacheRow>> byPlatform(String platform) {
    return (select(toplistsCache)
          ..where((t) => t.platform.equals(platform))
          ..orderBy([(t) => OrderingTerm.asc(t.fetchedAt)]))
        .get();
  }

  Future<List<ToplistCacheRow>> all() =>
      (select(toplistsCache)..orderBy([(t) => OrderingTerm.asc(t.platform)])).get();

  Future<DateTime?> lastFetchedAt(String platform) async {
    final newest = toplistsCache.fetchedAt.max();
    final row =
        await (selectOnly(toplistsCache)
              ..addColumns([newest])
              ..where(toplistsCache.platform.equals(platform)))
            .getSingleOrNull();
    final value = row?.read(newest);
    return value == null ? null : DateTime.fromMillisecondsSinceEpoch(value);
  }

  Future<int> clearPlatform(String platform) {
    return (delete(toplistsCache)..where((t) => t.platform.equals(platform))).go();
  }

  Future<int> clearAll() => delete(toplistsCache).go();
}

// --- Saved smart-playlist results ---

@DriftAccessor(tables: [SmartPlaylistSnapshots])
class SmartPlaylistSnapshotsDao
    extends DatabaseAccessor<AppDatabase>
    with _$SmartPlaylistSnapshotsDaoMixin {
  SmartPlaylistSnapshotsDao(super.db);

  /// Saves a generated result. Previously the only way to "use" a smart playlist
  /// was to play the preview immediately — the generation was thrown away on
  /// screen exit.
  Future<void> saveSnapshot({
    required String ruleId,
    required List<String> songKeys,
    DateTime? generatedAt,
  }) async {
    final at = generatedAt ?? DateTime.now();
    await into(smartPlaylistSnapshots).insert(
      SmartPlaylistSnapshotsCompanion.insert(
        ruleId: ruleId,
        songKeys: jsonEncode(songKeys),
        generatedAt: at.millisecondsSinceEpoch,
      ),
      mode: InsertMode.insertOrReplace,
    );
  }

  Future<SmartPlaylistSnapshot?> snapshot(String ruleId) {
    return (select(smartPlaylistSnapshots)
          ..where((t) => t.ruleId.equals(ruleId)))
        .getSingleOrNull();
  }

  Future<List<SmartPlaylistSnapshot>> all() =>
      (select(smartPlaylistSnapshots)
            ..orderBy([(t) => OrderingTerm.desc(t.generatedAt)]))
          .get();

  /// Decoded `songKeys` for [ruleId], or an empty list when unsaved/corrupt.
  Future<List<String>> songKeys(String ruleId) async {
    final row = await snapshot(ruleId);
    if (row == null) return const [];
    return decodeSongKeys(row.songKeys);
  }

  static List<String> decodeSongKeys(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded.map((item) => item.toString()).toList();
    } catch (_) {
      return const [];
    }
  }

  /// Drops snapshots whose rule no longer exists.
  Future<int> deleteMissing(Set<String> ruleIds) async {
    final rows = await all();
    final stale = rows
        .where((row) => !ruleIds.contains(row.ruleId))
        .map((row) => row.ruleId)
        .toList();
    if (stale.isEmpty) return 0;
    return (delete(smartPlaylistSnapshots)
          ..where((t) => t.ruleId.isIn(stale)))
        .go();
  }

  Future<int> deleteSnapshot(String ruleId) {
    return (delete(smartPlaylistSnapshots)
          ..where((t) => t.ruleId.equals(ruleId)))
        .go();
  }

  Future<int> clear() => delete(smartPlaylistSnapshots).go();
}

// --- Main Database ---

@DriftDatabase(
  tables: [
    Songs,
    ListeningHistory,
    UserLikes,
    LyricsCache,
    LocalTracks,
    ToplistsCache,
    PlayEvents,
    DailyStats,
    SmartPlaylistSnapshots,
    LyricsOffsets,
    SourceMatchCaches,
  ],
  daos: [
    SongsDao,
    HistoryDao,
    LikesDao,
    LyricsCacheDao,
    StatsDao,
    LocalTracksDao,
    LyricsOffsetDao,
    SourceMatchCacheDao,
    ToplistsCacheDao,
    SmartPlaylistSnapshotsDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.forTesting(super.e);

  /// v1 → v2 adds the album/artist ids on [Songs], the local-library and chart
  /// caches, the play-event statistics tables, and drops the never-populated
  /// `Playlists` table.
  ///
  /// v2 → v3 adds the query indexes the statistics and history pages needed all
  /// along, the local-library lyrics stamp ([LocalTracks.lyricsMtime]), and the
  /// per-song lyrics-offset and source-match caches.
  @override
  int get schemaVersion => 3;

  /// Schema evolution.
  ///
  /// v1 shipped with `onCreate` only. Because drift raises `UnsupportedError`
  /// for an unhandled version bump (it does **not** silently recreate the
  /// database), the very first column added would have crashed every existing
  /// install on upgrade. From v2 onwards an upgrade path exists and is covered
  /// by `test/database_migration_test.dart`.
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      // `createAll()` already creates the `@TableIndex` indexes. Repeating the
      // statements here (`IF NOT EXISTS`, so they are a no-op) is a deliberate
      // belt-and-braces guard: it guarantees a fresh install and an upgraded one
      // end up with the identical index set even if a drift version were to
      // create only tables here.
      await _createV3Indexes(m);
    },
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        // Pre-existing data is preserved: the new columns stay null, and the
        // library falls back to a name-based lookup for records written before
        // the artist/album ids were captured.
        await m.addColumn(songs, songs.albumId);
        await m.addColumn(songs, songs.artistId);
        await m.addColumn(songs, songs.trackNumber);
        await m.createTable(localTracks);
        await m.createTable(toplistsCache);
        await m.createTable(playEvents);
        await m.createTable(dailyStats);
        await m.createTable(smartPlaylistSnapshots);
        // `Playlists` was created in v1 but never written to and has no DAO.
        // Guarded, so installing over a database that somehow lacks it works.
        await m.database.customStatement('DROP TABLE IF EXISTS playlists');
      }
      if (from < 3) {
        // A v1 database created `local_tracks` in the branch above, and
        // `m.createTable` always emits the **current** table definition — which
        // already carries the v3 columns. Re-adding them on that path would
        // abort the entire upgrade with "duplicate column name", so the v1 → v3
        // case deliberately skips this step.
        if (from >= 2) {
          await m.addColumn(localTracks, localTracks.lyricsMtime);
          await m.addColumn(localTracks, localTracks.lyricsSize);
        }
        // New tables: added, never altered, so no data can be lost here. Neither
        // table existed in v1/v2, and neither is dropped by a later branch.
        await m.createTable(lyricsOffsets);
        await m.createTable(sourceMatchCaches);
        // Indexes are created for every pre-v3 database, including the v1 → v3
        // path: `Migrator.createTable` never creates them, only `createAll()`
        // does (a fresh install).
        await _createV3Indexes(m);
      }
    },
  );
}

/// Creates the schema-v3 indexes, idempotently.
Future<void> _createV3Indexes(Migrator m) async {
  for (final statement in _v3IndexStatements) {
    await m.database.customStatement(statement);
  }
}

/// `CREATE INDEX` statements for the schema-v3 indexes.
///
/// Spelled out rather than taken from the generated `Index` objects so that the
/// upgrade path and `Migrator.createAll()` (fresh installs) are guaranteed to
/// produce the same DDL. The names are the ones the `@TableIndex` annotations
/// declare, and `test/database_migration_test.dart` asserts that a fresh
/// database and an upgraded one carry the identical index set.
const List<String> _v3IndexStatements = [
  'CREATE INDEX IF NOT EXISTS listening_history_listened_at '
      'ON listening_history (listened_at)',
  'CREATE INDEX IF NOT EXISTS play_events_song_platform '
      'ON play_events (song_id, platform)',
  'CREATE INDEX IF NOT EXISTS play_events_started_at '
      'ON play_events (started_at)',
  'CREATE INDEX IF NOT EXISTS local_tracks_path ON local_tracks (path)',
];

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'mconnect.sqlite'));
    return NativeDatabase.createInBackground(file, setup: (rawDb) {
      rawDb.execute('PRAGMA journal_mode=WAL;');
      rawDb.execute('PRAGMA busy_timeout=5000;');
    });
  });
}

// --- Singleton ---
AppDatabase? _database;

AppDatabase get database {
  _database ??= AppDatabase();
  return _database!;
}
