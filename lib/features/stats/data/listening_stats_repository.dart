import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/song_record_mapping.dart';
import '../../../models/artist.dart';
import '../../../models/platform_type.dart';
import '../../../models/song.dart';
import '../domain/listening_stats.dart';

/// Storage boundary for listening statistics.
///
/// The interface is deliberately the same shape it had in v1.3.2
/// (`load` / `recordSongStarted` / `addListenedDuration` / `clear`) so the
/// tracker and the settings page kept working, plus the read-only and migration
/// members the detail-table rewrite needs.
abstract class ListeningStatsRepository {
  Future<ListeningStatsState> load();

  /// Records the start of a play and returns the new `play_events` row id, or
  /// null when this implementation cannot supply one.
  ///
  /// That id is what `scrobble_queue.event_id` stores, which is how the scrobble
  /// outbox de-duplicates "the same stretch of playback" when the tracker
  /// flushes it more than once. A **null** id must make a caller skip the outbox
  /// entirely: falling back to a placeholder would collapse every listen onto
  /// one row.
  Future<int?> recordSongStartedEvent(
    Song song, {
    PlayEventSource source,
    DateTime? at,
  });

  /// Records the start of a play, discarding the row id.
  ///
  /// Stays **abstract** on purpose. A concrete method here would only reach
  /// classes that use `extends`/`with`, while both real implementations say
  /// `implements` — and Dart's `implements` does **not** inherit a member's
  /// body. Declaring it abstract keeps the obligation visible to the compiler
  /// instead of hiding it behind a default that never runs; each implementation
  /// restates it as a one-line delegation to [recordSongStartedEvent].
  Future<ListeningStatsState> recordSongStarted(
    Song song, {
    PlayEventSource source,
    DateTime? at,
  });

  Future<ListeningStatsState> addListenedDuration(
    Song song,
    Duration duration, {
    DateTime? at,
  });

  Future<void> clear();

  /// Multi-dimensional report (artists / albums / platforms / days / hours).
  Future<ListeningStatsReport> loadReport();

  /// Exact statistics for one song, even when it is outside the ranked view.
  Future<ListeningStatsSongEntry?> songStats(String songId, PlatformType platform);

  /// Whether any raw play event exists. Used to decide whether the legacy Hive
  /// snapshot still has to be imported.
  Future<bool> hasEvents();

  /// Writes a legacy (v1.3.2) snapshot into the event table, preserving both the
  /// totals and the per-song detail.
  Future<void> importState(ListeningStatsState legacy, {DateTime? now});
}

/// Statistics backed by the `PlayEvents` / `DailyStats` tables.
///
/// Every number is recomputed from the raw events on load, so **the ranked list
/// is a view and never the storage**: adding song number 101 cannot destroy the
/// statistics of any earlier song.
class DriftListeningStatsRepository implements ListeningStatsRepository {
  DriftListeningStatsRepository(this._db);

  final AppDatabase _db;

  @override
  Future<ListeningStatsState> load() async {
    final totals = await _db.statsDao.totals();
    final aggregates = await _db.statsDao.songAggregates();
    final metadata = await _metadata(aggregates);
    final songs = aggregates
        .map((aggregate) => _entryOf(aggregate, metadata))
        .toList();
    return ListeningStatsState(
      totalPlayCount: totals.playCount,
      totalListenDuration: Duration(milliseconds: totals.listenMs),
      allSongs: songs,
      topSongs: songs.take(listeningStatsTopSongViewLimit).toList(),
      totalSongCount: totals.distinctSongs,
      activeDayCount: await _db.statsDao.activeDayCount(),
    );
  }

  @override
  Future<int?> recordSongStartedEvent(
    Song song, {
    PlayEventSource source = PlayEventSource.play,
    DateTime? at,
  }) async {
    // Cache the song metadata first: the artist/album dimensions join against
    // `songs`, so a played song that was never liked would otherwise have no
    // artist to be grouped under.
    await _db.songsDao.insertSong(_songToCompanion(song));
    // `recordPlayStart` answers with the new row's id, which is exactly the
    // identity the scrobble outbox needs.
    return _db.statsDao.recordPlayStart(
      songId: song.id,
      platform: song.platform.name,
      startedAt: at ?? DateTime.now(),
      source: source,
    );
  }

  /// Delegation is restated because this class `implements` the interface, and
  /// Dart's `implements` does **not** inherit a concrete member's body — only
  /// `extends`/`with` would. Two lines, and the alternative (turning the
  /// interface into a base class) would ripple through every implementation and
  /// test double for no behavioural gain.
  @override
  Future<ListeningStatsState> recordSongStarted(
    Song song, {
    PlayEventSource source = PlayEventSource.play,
    DateTime? at,
  }) async {
    await recordSongStartedEvent(song, source: source, at: at);
    return load();
  }

  @override
  Future<ListeningStatsState> addListenedDuration(
    Song song,
    Duration duration, {
    DateTime? at,
  }) async {
    if (duration <= Duration.zero) return load();
    final songDurationMs = song.duration.inMilliseconds;
    await _db.statsDao.addListenedDuration(
      songId: song.id,
      platform: song.platform.name,
      duration: duration,
      songDurationMs: songDurationMs > 0 ? songDurationMs : null,
      at: at,
    );
    return load();
  }

  @override
  Future<ListeningStatsReport> loadReport() async {
    final artists = await _db.statsDao.topArtists();
    final albums = await _db.statsDao.topAlbums();
    final platforms = await _db.statsDao.platformBreakdown();
    final days = await _db.statsDao.dailySeries();
    final hours = await _db.statsDao.hourHistogram();
    return ListeningStatsReport(
      artists: artists.map(_dimensionOf).toList(),
      albums: albums.map(_dimensionOf).toList(),
      platforms: platforms.map(_dimensionOf).toList(),
      days: days
          .map(
            (row) => ListeningStatsDay(
              day: row.day,
              playCount: row.playCount,
              listenDuration: Duration(milliseconds: row.listenMs),
            ),
          )
          .toList(),
      hours: hours
          .map(
            (row) => ListeningStatsHourBucket(
              hour: row.hour,
              playCount: row.playCount,
              listenDuration: Duration(milliseconds: row.listenMs),
            ),
          )
          .toList(),
    );
  }

  @override
  Future<ListeningStatsSongEntry?> songStats(
    String songId,
    PlatformType platform,
  ) async {
    final aggregate = await _db.statsDao.songAggregate(songId, platform.name);
    if (aggregate == null) return null;
    final metadata = await _metadata([aggregate]);
    return _entryOf(aggregate, metadata);
  }

  @override
  Future<bool> hasEvents() async => (await _db.statsDao.countPlayEvents()) > 0;

  @override
  Future<void> clear() => _db.statsDao.clearAll();

  @override
  Future<void> importState(ListeningStatsState legacy, {DateTime? now}) async {
    if (legacy.allSongs.isEmpty) return;
    final anchor = now ?? DateTime.now();
    await _db.transaction(() async {
      for (final entry in legacy.allSongs) {
        final plays = entry.playCount > 0 ? entry.playCount : 1;
        final totalMs = entry.listenDuration.inMilliseconds;
        final base = totalMs ~/ plays;
        var remainder = totalMs - base * plays;
        // Stagger the events: identical `(songId, platform, startedAt)` triples
        // would be merged on a later backup restore.
        final anchorMs = entry.lastListenedAt.millisecondsSinceEpoch > 0
            ? entry.lastListenedAt.millisecondsSinceEpoch
            : anchor.millisecondsSinceEpoch;
        for (var index = 0; index < plays; index++) {
          final extra = remainder > 0 ? 1 : 0;
          remainder -= extra;
          final startedAt = DateTime.fromMillisecondsSinceEpoch(
            anchorMs - index * 1000,
          );
          await _db.statsDao.recordPlayStart(
            songId: entry.songId,
            platform: entry.platform.name,
            startedAt: startedAt,
            source: PlayEventSource.seek,
          );
          await _db.statsDao.addListenedDuration(
            songId: entry.songId,
            platform: entry.platform.name,
            duration: Duration(milliseconds: base + extra),
            at: startedAt,
          );
        }
      }
    });
  }

  /// `'YYYY-MM-DD'` in local time — the `DailyStats.day` contract.
  static String dayKeyOf(DateTime time) => StatsDao.dayKey(time);

  static ListeningStatsDimension _dimensionOf(StatsDimensionEntry row) {    return ListeningStatsDimension(
      label: row.label,
      playCount: row.playCount,
      listenDuration: Duration(milliseconds: row.listenMs),
    );
  }

  static ListeningStatsSongEntry _entryOf(
    SongPlayAggregate aggregate,
    Map<String, ({String name, String artists})> metadata,
  ) {
    final info = metadata['${aggregate.platform}_${aggregate.songId}'];
    return ListeningStatsSongEntry(
      songId: aggregate.songId,
      platform:
          PlatformType.tryParse(aggregate.platform) ?? PlatformType.netease,
      songName: info?.name ?? '',
      artistNames: info?.artists ?? '',
      playCount: aggregate.playCount,
      listenDuration: Duration(milliseconds: aggregate.listenMs),
      lastListenedAt: DateTime.fromMillisecondsSinceEpoch(
        aggregate.lastPlayedAt,
      ),
    );
  }

  Future<Map<String, ({String name, String artists})>> _metadata(
    List<SongPlayAggregate> aggregates,
  ) async {
    if (aggregates.isEmpty) return const {};
    final records = await _db.songsDao.getSongsByIds(
      aggregates
          .map((item) => (id: item.songId, platform: item.platform))
          .toList(),
    );
    return {
      for (final record in records)
        '${record.platform}_${record.id}': (
          name: record.name,
          artists: record.artists,
        ),
    };
  }

  static SongsCompanion _songToCompanion(Song song) =>
      songsCompanionFromSong(song);
}

/// In-memory statistics with **the same semantics** as
/// [DriftListeningStatsRepository].
///
/// It stores raw events rather than a truncated top-N list, which is what lets
/// the truncation regression test run without a database, and it is the
/// implementation the widget tests use.
class MemoryListeningStatsRepository implements ListeningStatsRepository {
  MemoryListeningStatsRepository({DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  final List<_MemoryEvent> _events = [];

  @override
  Future<ListeningStatsState> load() async => _aggregate(_events);

  @override
  Future<int?> recordSongStartedEvent(
    Song song, {
    PlayEventSource source = PlayEventSource.play,
    DateTime? at,
  }) async {
    _events.add(
      _MemoryEvent(
        song: song,
        startedAt: at ?? _clock(),
        duration: Duration.zero,
        source: source,
      ),
    );
    // 1-based, like the autoIncrement id the drift implementation returns.
    return _events.length;
  }

  /// Same reason as the drift implementation: `implements` does not inherit the
  /// interface's concrete member, so the delegation is repeated here.
  @override
  Future<ListeningStatsState> recordSongStarted(
    Song song, {
    PlayEventSource source = PlayEventSource.play,
    DateTime? at,
  }) async {
    await recordSongStartedEvent(song, source: source, at: at);
    return load();
  }

  @override
  Future<ListeningStatsState> addListenedDuration(
    Song song,
    Duration duration, {
    DateTime? at,
  }) async {
    if (duration <= Duration.zero) return load();
    final timestamp = at ?? _clock();
    for (var index = _events.length - 1; index >= 0; index--) {
      final event = _events[index];
      if (event.song.id == song.id &&
          event.song.platform == song.platform) {
        event.duration += duration;
        event.endedAt = timestamp;
        return load();
      }
    }
    // Duration without a recorded start: keep the time instead of dropping it.
    _events.add(
      _MemoryEvent(
        song: song,
        startedAt: timestamp,
        endedAt: timestamp,
        duration: duration,
        source: PlayEventSource.seek,
      ),
    );
    return load();
  }

  @override
  Future<ListeningStatsReport> loadReport() async {
    final byArtist = <String, _Accumulator>{};
    final byAlbum = <String, _Accumulator>{};
    final byPlatform = <String, _Accumulator>{};
    final byDay = <String, _Accumulator>{};
    final hours = List<_Accumulator>.generate(24, (_) => _Accumulator());
    for (final event in _events) {
      final listenMs = event.duration.inMilliseconds;
      _bump(byPlatform, event.song.platform.displayName, 1, listenMs);
      for (final artist in event.song.artists) {
        _bump(byArtist, artist.name, 1, listenMs);
      }
      final album = event.song.album?.name;
      if (album != null && album.isNotEmpty) {
        _bump(byAlbum, album, 1, listenMs);
      }
      final local = event.startedAt.toLocal();
      _bump(byDay, DriftListeningStatsRepository.dayKeyOf(local), 1, listenMs);
      hours[local.hour].add(1, listenMs);
    }
    return ListeningStatsReport(
      artists: _rank(byArtist),
      albums: _rank(byAlbum),
      platforms: _rank(byPlatform),
      days: [
        for (final entry in byDay.entries)
          ListeningStatsDay(
            day: entry.key,
            playCount: entry.value.playCount,
            listenDuration: Duration(milliseconds: entry.value.listenMs),
          ),
      ]..sort((a, b) => b.day.compareTo(a.day)),
      hours: [
        for (var hour = 0; hour < 24; hour++)
          ListeningStatsHourBucket(
            hour: hour,
            playCount: hours[hour].playCount,
            listenDuration: Duration(milliseconds: hours[hour].listenMs),
          ),
      ],
    );
  }

  @override
  Future<ListeningStatsSongEntry?> songStats(
    String songId,
    PlatformType platform,
  ) async {
    final state = _aggregate(_events);
    return state.songStats(songId, platform);
  }

  @override
  Future<bool> hasEvents() async => _events.isNotEmpty;

  @override
  Future<void> clear() async => _events.clear();

  @override
  Future<void> importState(ListeningStatsState legacy, {DateTime? now}) async {
    final anchor = now ?? _clock();
    for (final entry in legacy.allSongs) {
      final plays = entry.playCount > 0 ? entry.playCount : 1;
      final totalMs = entry.listenDuration.inMilliseconds;
      final base = totalMs ~/ plays;
      var remainder = totalMs - base * plays;
      final anchorMs = entry.lastListenedAt.millisecondsSinceEpoch > 0
          ? entry.lastListenedAt.millisecondsSinceEpoch
          : anchor.millisecondsSinceEpoch;
      for (var index = 0; index < plays; index++) {
        final extra = remainder > 0 ? 1 : 0;
        remainder -= extra;
        _events.add(
          _MemoryEvent(
            song: _songOf(entry),
            startedAt: DateTime.fromMillisecondsSinceEpoch(anchorMs - index * 1000),
            duration: Duration(milliseconds: base + extra),
            source: PlayEventSource.seek,
          ),
        );
      }
    }
  }

  static Song _songOf(ListeningStatsSongEntry entry) {
    return Song(
      id: entry.songId,
      platform: entry.platform,
      name: entry.songName,
      artists: entry.artistNames.isEmpty
          ? const []
          : [Artist(id: '', name: entry.artistNames)],
    );
  }

  static void _bump(
    Map<String, _Accumulator> target,
    String label,
    int playCount,
    int listenMs,
  ) {
    (target[label] ??= _Accumulator()).add(playCount, listenMs);
  }

  static List<ListeningStatsDimension> _rank(Map<String, _Accumulator> source) {
    final rows = source.entries.toList()
      ..sort((a, b) => b.value.listenMs.compareTo(a.value.listenMs));
    return [
      for (final entry in rows.take(20))
        ListeningStatsDimension(
          label: entry.key,
          playCount: entry.value.playCount,
          listenDuration: Duration(milliseconds: entry.value.listenMs),
        ),
    ];
  }

  static ListeningStatsState _aggregate(List<_MemoryEvent> events) {
    final bySong = <String, _MemoryAccumulator>{};
    for (final event in events) {
      final key = '${event.song.platform.name}_${event.song.id}';
      (bySong[key] ??= _MemoryAccumulator(event.song)).add(event);
    }
    final songs = bySong.values.map((item) => item.entry).toList()
      ..sort(compareSongEntries);
    final totalPlayCount = events.length;
    final totalMs = events.fold<int>(0, (sum, event) => sum + event.duration.inMilliseconds);
    final days = <String>{
      for (final event in events)
        DriftListeningStatsRepository.dayKeyOf(event.startedAt.toLocal()),
    };
    return ListeningStatsState(
      totalPlayCount: totalPlayCount,
      totalListenDuration: Duration(milliseconds: totalMs),
      allSongs: songs,
      topSongs: songs.take(listeningStatsTopSongViewLimit).toList(),
      totalSongCount: songs.length,
      activeDayCount: days.length,
    );
  }
}

class _MemoryEvent {
  _MemoryEvent({
    required this.song,
    required this.startedAt,
    required this.duration,
    this.endedAt,
    this.source = PlayEventSource.play,
  });

  final Song song;
  final DateTime startedAt;
  DateTime? endedAt;
  Duration duration;
  final PlayEventSource source;
}

class _MemoryAccumulator {
  _MemoryAccumulator(this.song);

  final Song song;
  int playCount = 0;
  int listenMs = 0;
  int lastPlayedAt = 0;

  void add(_MemoryEvent event) {
    playCount += 1;
    listenMs += event.duration.inMilliseconds;
    final startedAt = event.startedAt.millisecondsSinceEpoch;
    if (startedAt > lastPlayedAt) lastPlayedAt = startedAt;
  }

  ListeningStatsSongEntry get entry => ListeningStatsSongEntry(
    songId: song.id,
    platform: song.platform,
    songName: song.name,
    artistNames: song.artistNames,
    playCount: playCount,
    listenDuration: Duration(milliseconds: listenMs),
    lastListenedAt: DateTime.fromMillisecondsSinceEpoch(lastPlayedAt),
  );
}

class _Accumulator {
  int playCount = 0;
  int listenMs = 0;

  void add(int plays, int ms) {
    playCount += plays;
    listenMs += ms;
  }
}

/// Read-only access to the v1.3.2 Hive statistics snapshot.
///
/// Purely a migration source: v1.4.0 stores statistics in `PlayEvents`. It stays
/// because the upgrade path must not throw away statistics the user already has.
abstract class LegacyStatsSource {
  Future<bool> hasSnapshot();
  Future<ListeningStatsState> read();
}

class LegacyListeningStatsStore implements LegacyStatsSource {
  static const boxName = 'listening_stats';
  static const snapshotKey = 'snapshot';

  const LegacyListeningStatsStore();

  @override
  Future<ListeningStatsState> read() async {
    final box = await Hive.openBox(boxName);
    return ListeningStatsState.fromJson(box.get(snapshotKey));
  }

  @override
  Future<bool> hasSnapshot() async {
    final box = await Hive.openBox(boxName);
    return box.containsKey(snapshotKey);
  }

  Future<void> clear() async {
    final box = await Hive.openBox(boxName);
    await box.delete(snapshotKey);
  }
}

/// Outcome of the legacy-snapshot migration.
enum LegacyStatsMigration {
  skippedNothingToImport,
  skippedAlreadyMigrated,
  imported,
}

/// Moves the v1.3.2 Hive snapshot into the event table exactly once.
class ListeningStatsLegacyMigration {
  const ListeningStatsLegacyMigration({
    required this.legacyStore,
    required this.target,
  });

  final LegacyStatsSource legacyStore;
  final ListeningStatsRepository target;

  Future<LegacyStatsMigration> run({DateTime? now}) async {
    if (await target.hasEvents()) {
      return LegacyStatsMigration.skippedAlreadyMigrated;
    }
    final ListeningStatsState legacy;
    try {
      if (!await legacyStore.hasSnapshot()) {
        return LegacyStatsMigration.skippedNothingToImport;
      }
      legacy = await legacyStore.read();
    } catch (e) {
      debugPrint('ListeningStatsLegacyMigration: legacy snapshot unreadable: $e');
      return LegacyStatsMigration.skippedNothingToImport;
    }
    if (legacy.allSongs.isEmpty && legacy.totalPlayCount == 0) {
      return LegacyStatsMigration.skippedNothingToImport;
    }
    await target.importState(legacy, now: now);
    return LegacyStatsMigration.imported;
  }
}
