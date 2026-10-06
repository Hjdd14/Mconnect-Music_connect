import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';

/// Persisted lyrics for local tracks.
///
/// Reuses the existing `LyricsCache` table with `platform = 'local'` and the
/// **full file path** as `song_id`. Two reasons:
///
/// 1. the old scanner keyed lyrics by *lower-cased base name*
///    (`MainActivity.kt` collected `lyricsByBaseName`), so `Music/A/01.mp3` and
///    `Music/B/01.mp3` shared whichever lyric file was walked last — the wrong
///    lyrics on screen. Keying by the absolute path gives every track exactly
///    one lyric file;
/// 2. storing them means opening the local page is a single SELECT instead of
///    re-reading one `.lrc` per track on every visit.
///
/// Like [LocalTrackStore] this talks to drift through a hand-written accessor.
/// The difference is that here it is not a choice about file ownership: the
/// shared `LyricsCacheDao` (`app_database.dart:459`) only offers single-row
/// `getCachedLyrics` / `cacheLyrics`, and the local page needs "every local
/// lyric row" and "delete rows for these paths" — one SELECT instead of one
/// query per track.
abstract class LocalLyricsStore {
  static const platform = 'local';

  /// `songId (absolute path) -> lyrics content` for the whole local library.
  Future<Map<String, String>> loadAll();

  /// `songId -> stored format` (`lrc` / `qrc` / `krc`), for diagnostics/tests.
  Future<Map<String, String>> loadAllWithFormat();

  Future<void> save(String songId, String content, String format, {int? syncedAt});

  Future<void> removePaths(Iterable<String> songIds);

  Future<void> clear();
}

class DriftLocalLyricsStore extends LocalLyricsStore {
  DriftLocalLyricsStore({AppDatabase? database})
    : _db = database ?? _appDatabase();

  static AppDatabase _appDatabase() => database;

  final AppDatabase _db;

  @override
  Future<Map<String, String>> loadAll() async {
    final rows = await _localRows();
    return {
      for (final row in rows)
        if (row.content.isNotEmpty) row.songId: row.content,
    };
  }

  @override
  Future<Map<String, String>> loadAllWithFormat() async {
    final rows = await _localRows();
    return {for (final row in rows) row.songId: row.format};
  }

  @override
  Future<void> save(
    String songId,
    String content,
    String format, {
    int? syncedAt,
  }) async {
    await _db
        .into(_db.lyricsCache)
        .insert(
          LyricsCacheCompanion.insert(
            songId: songId,
            platform: LocalLyricsStore.platform,
            content: content,
            format: format,
            syncedAt: syncedAt ?? DateTime.now().millisecondsSinceEpoch,
          ),
          mode: InsertMode.insertOrReplace,
        );
  }

  @override
  Future<void> removePaths(Iterable<String> songIds) async {
    final list = songIds.toList(growable: false);
    if (list.isEmpty) return;
    // Chunked: SQLite caps the number of bound variables per statement.
    const chunkSize = 400;
    for (var i = 0; i < list.length; i += chunkSize) {
      final chunk = list.sublist(
        i,
        i + chunkSize > list.length ? list.length : i + chunkSize,
      );
      await (_db.delete(_db.lyricsCache)
            ..where(
              (t) =>
                  t.platform.equals(LocalLyricsStore.platform) &
                  t.songId.isIn(chunk),
            ))
          .go();
    }
  }

  @override
  Future<void> clear() async {
    await (_db.delete(_db.lyricsCache)
          ..where((t) => t.platform.equals(LocalLyricsStore.platform)))
        .go();
  }

  Future<List<LyricsCacheData>> _localRows() {
    return (_db.select(_db.lyricsCache)
          ..where((t) => t.platform.equals(LocalLyricsStore.platform)))
        .get();
  }
}

/// In-memory [LocalLyricsStore] for tests.
class MemoryLocalLyricsStore extends LocalLyricsStore {
  final Map<String, String> _content = {};
  final Map<String, String> _formats = {};

  @override
  Future<Map<String, String>> loadAll() async => Map.of(_content);

  @override
  Future<Map<String, String>> loadAllWithFormat() async => Map.of(_formats);

  @override
  Future<void> save(
    String songId,
    String content,
    String format, {
    int? syncedAt,
  }) async {
    _content[songId] = content;
    _formats[songId] = format;
  }

  @override
  Future<void> removePaths(Iterable<String> songIds) async {
    for (final id in songIds) {
      _content.remove(id);
      _formats.remove(id);
    }
  }

  @override
  Future<void> clear() async {
    _content.clear();
    _formats.clear();
  }
}
