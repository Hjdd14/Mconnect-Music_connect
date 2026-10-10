import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/network/platform_http.dart';
import '../../../../lyrics/lrclib_client.dart';
import '../../../../lyrics/models/lyrics_bundle.dart';
import '../../../../lyrics/models/lyrics_line.dart';
import '../../../../models/platform_type.dart';
import '../../../../models/song.dart';
import '../../../../platform/base/music_platform.dart';
import '../../../../platform/base/platform_registry.dart';
import '../../../local_music/presentation/providers/local_music_provider.dart';
import 'player_provider.dart';

/// Timeout for every lyrics request.
///
/// Lyrics used to be the only critical request in the app without one: a
/// platform that accepted the connection but never answered left the lyrics
/// panel on a spinner forever (the panel has no other way to observe failure).
const Duration lyricsRequestTimeout = Duration(seconds: 8);

/// Raised when lyrics could not be loaded from **any** source.
///
/// Deliberately distinct from "the platforms answered, there are no lyrics"
/// (which returns `null`), because only the former may render
/// `lyrics_display.dart`'s "歌词加载失败" branch — and that branch used to be
/// unreachable because the provider swallowed every exception into `null`.
class LyricsUnavailableException implements Exception {
  final String message;
  final List<Object> causes;

  const LyricsUnavailableException(this.message, {this.causes = const []});

  @override
  String toString() => 'LyricsUnavailableException: $message';
}

/// Raw lyric tracks for a song, plus which source supplied them.
@immutable
class RawLyrics {
  final LyricsBundle bundle;
  final LyricsSource source;

  const RawLyrics({
    required this.bundle,
    this.source = LyricsSource.unknown,
  });
}

/// How long a cached lyrics row stays trustworthy before it is refetched.
///
/// `LyricsCache.syncedAt` used to be a **write-only** field: a cached row was
/// served forever, so a platform correcting its own lyrics (typos, fixed
/// timings) could never surface on a device that had already cached them.
const Duration lyricsCacheTtl = Duration(days: 14);

/// True when a row written at [syncedAtMs] is older than [ttl].
///
/// A timestamp in the future (clock skew, or a device whose time was corrected
/// backwards) counts as **fresh**: calling it expired would make every play
/// refetch and re-cache, forever.
bool isLyricsCacheExpired(
  int syncedAtMs, {
  required DateTime now,
  Duration ttl = lyricsCacheTtl,
}) {
  return now.millisecondsSinceEpoch - syncedAtMs >= ttl.inMilliseconds;
}

/// The cached lyrics row for [songId]/[platform], `syncedAt` included, or null.
///
/// A direct table read because `LyricsCacheDao` exposes neither the timestamp
/// nor a TTL, and the database layer belongs to another workstream (`local` rows
/// are excluded by construction: this only ever runs for streamed platforms).
Future<({String content, String format, int syncedAt})?> readCachedLyrics(
  String songId,
  String platform, {
  AppDatabase? db,
}) async {
  final target = db ?? database;
  final row = await (target.select(target.lyricsCache)
        ..where((t) => t.songId.equals(songId) & t.platform.equals(platform))
        ..limit(1))
      .getSingleOrNull();
  if (row == null || row.content.isEmpty) return null;
  return (content: row.content, format: row.format, syncedAt: row.syncedAt);
}

/// Drops every cached lyrics row older than [ttl]; returns how many went.
///
/// Spelled out in raw SQL like `SourceMatchCacheDao.purgeExpired`, so the sweep
/// does not depend on the spelling of the comparison helper this drift version
/// generates for an integer column (they were renamed across the 2.x line).
Future<int> purgeExpiredLyricsCache({
  AppDatabase? db,
  DateTime? now,
  Duration ttl = lyricsCacheTtl,
}) async {
  final target = db ?? database;
  final cutoff = (now ?? DateTime.now()).subtract(ttl).millisecondsSinceEpoch;
  final expired = await target
      .customSelect(
        'SELECT COUNT(*) AS expired FROM lyrics_cache WHERE synced_at <= ?',
        variables: [Variable.withInt(cutoff)],
        readsFrom: {target.lyricsCache},
      )
      .getSingle();
  final count = expired.read<int>('expired');
  if (count == 0) return 0;
  await target.customStatement(
    'DELETE FROM lyrics_cache WHERE synced_at <= ?',
    [cutoff],
  );
  return count;
}

/// The badge source for [type].
///
/// Exhaustive on purpose: a platform added later has to decide what its badge
/// says instead of silently reusing someone else's name.
LyricsSource lyricsSourceForPlatform(PlatformType type) => switch (type) {
  PlatformType.netease => LyricsSource.netease,
  PlatformType.qq => LyricsSource.qq,
  PlatformType.kugou => LyricsSource.kugou,
  PlatformType.local => LyricsSource.local,
};

/// Fetches and parses lyrics for the currently playing song, with local cache.
///
/// Failure semantics:
/// * every attempted source **threw** → [LyricsUnavailableException] (load error);
/// * at least one source answered "no lyrics" → `null` ("暂无歌词").
final lyricsProvider = FutureProvider.autoDispose<LyricsDocument?>((ref) async {
  final song = ref.watch(playerProvider.select((s) => s.currentSong));
  if (song == null) return null;

  debugPrint('LyricsProvider: fetching for ${song.name} (${song.platform.name}, id=${song.id})');

  final localRawLyrics = song.platform == PlatformType.local
      ? ref.watch(localMusicProvider.select((s) => s.lyricsFor(song.id)))
      : null;

  ({String content, String format})? cachedLyrics;
  int? cachedSyncedAt;
  if (song.platform != PlatformType.local) {
    try {
      final cached = await readCachedLyrics(song.id, song.platform.name);
      if (cached != null) {
        debugPrint(
          'LyricsProvider: cache hit, format=${cached.format}, '
          'syncedAt=${cached.syncedAt}',
        );
        cachedLyrics = (content: cached.content, format: cached.format);
        cachedSyncedAt = cached.syncedAt;
      }
    } catch (e) {
      // A cache read failure must never block fetching fresh lyrics.
      debugPrint('LyricsProvider: cache read failed: $e');
    }
  }

  return resolveLyricsForSong(
    song: song,
    localRawLyrics: localRawLyrics,
    cachedLyrics: cachedLyrics,
    cachedSyncedAt: cachedSyncedAt,
    platforms: PlatformRegistry.all,
    writeCache: song.platform == PlatformType.local
        ? null
        : (raw, format) => database.lyricsCacheDao.cacheLyrics(
            song.id,
            song.platform.name,
            raw,
            format.name,
          ),
    lrclib: (queried) =>
        ref.read(lrclibClientProvider).fetchSyncedLyrics(queried),
    timeout: lyricsRequestTimeout,
  );
});

/// Resolves lyrics for [song] without any Riverpod/DB dependency, so the
/// timeout, cross-platform fallback and cache-isolation rules are unit
/// testable with fake platforms.
///
/// [writeCache] is best effort: a cache write failure must not discard lyrics
/// that were already fetched (the previous implementation awaited it inside
/// the same `try` and returned `null` on failure).
@visibleForTesting
Future<LyricsDocument?> resolveLyricsForSong({
  required Song song,
  String? localRawLyrics,
  ({String content, String format})? cachedLyrics,
  int? cachedSyncedAt,
  List<MusicPlatform> platforms = const [],
  Future<void> Function(String raw, LyricsFormat format)? writeCache,
  Duration timeout = lyricsRequestTimeout,
  Duration cacheTtl = lyricsCacheTtl,
  DateTime Function()? now,
  Future<String?> Function(Song song)? lrclib,
}) async {
  if (song.platform == PlatformType.local) {
    final raw = localRawLyrics;
    if (raw != null && raw.isNotEmpty) {
      final document = LyricsDocument.parse(
        raw,
        _localLyricsFormat(raw),
        source: lyricsSourceForPlatform(song.platform),
      );
      if (document.lines.isNotEmpty) return document;
    }
    // 本地没有可用歌词（没有 .lrc / 内嵌歌词，或解析不出时间轴）时才兜底：
    // 用户自己的文件常常一个歌词文件都没有，这里正是 LRCLIB 该上场的地方。
    return _lrclibFallback(lrclib, song, null);
  }

  final cached = cachedLyrics;
  if (cached != null) {
    final syncedAt = cachedSyncedAt;
    final expired =
        syncedAt != null &&
        isLyricsCacheExpired(
          syncedAt,
          now: (now ?? DateTime.now)(),
          ttl: cacheTtl,
        );
    if (expired) {
      debugPrint('LyricsProvider: cached lyrics older than $cacheTtl');
    } else {
      final format = _parseLyricsFormat(cached.format);
      final document = LyricsDocument.parse(
        cached.content,
        format,
        // The row is keyed by the *owning* platform, so a cross-source fallback
        // that was cached under it still reports the owning platform here.
        source: lyricsSourceForPlatform(song.platform),
      );
      if (document.lines.isNotEmpty) {
        return document;
      }
      debugPrint('LyricsProvider: cached lyrics parsed empty, refetching');
    }
  }

  final outcome = await _fetchLyricsWithFallback(
    song: song,
    platforms: platforms,
    timeout: timeout,
  );
  final raw = outcome.raw;
  LyricsDocument? document;
  if (raw != null) {
    final built = buildLyricsDocument(raw.bundle, source: raw.source);
    // Content with no timed lines is "no lyrics", not a load failure.
    document = built.lines.isEmpty ? null : built;
  }

  // LRCLIB 兜底：平台没给出可用歌词、或时间轴明显不对时才问一次。
  // 它在 **抛错之前** 有一次机会：三个平台都失败时，能从 LRCLIB 拿到词就
  // 不该给用户看"歌词加载失败"。
  final fallbackDocument = await _lrclibFallback(lrclib, song, document);
  if (fallbackDocument != null) return fallbackDocument;

  if (document == null) {
    if (raw == null && !outcome.answered && outcome.errors.isNotEmpty) {
      throw LyricsUnavailableException(
        outcome.errorMessage(),
        causes: outcome.errors,
      );
    }
    return null;
  }

  final track = mainLyricsTrack(raw!.bundle);
  if (writeCache != null && track != null) {
    // The cache holds one string per song, so the translation is folded into it
    // to survive a cache hit. The track folded in must share the main track's
    // timeline: lrc pairs with `tlyric`, and a word-by-word row pairs with
    // `ytlrc` — the device bug had the yrc row cached VERBATIM (its translation
    // dropped here), so every cache hit of a yrc song rendered without any
    // translation even after the pairing was fixed.
    final translation = track.format == LyricsFormat.lrc
        ? raw.bundle.translation
        : raw.bundle.yrcTranslation;
    final cachedContent =
        translation != null && translation.trim().isNotEmpty
            ? '${track.content}\n$translation'
            : track.content;
    unawaited(
      _writeCacheBestEffort(writeCache, cachedContent, track.format),
    );
  }
  return document;
}

/// Asks the fallback source, swallowing everything it throws.
///
/// A fallback that is down (or times out) must never turn into "歌词加载失败"
/// when the platform path already has an answer — and never hide the platform's
/// own error when it does not.
///
/// The result is deliberately **not** cached: the cache row is keyed by the
/// owning platform, so storing a fallback under it would both mislabel the next
/// "来源" badge and stop the platform from being retried on the next run.
Future<LyricsDocument?> _lrclibFallback(
  Future<String?> Function(Song song)? lrclib,
  Song song,
  LyricsDocument? current,
) async {
  if (lrclib == null) return null;
  if (!shouldAskLrclib(current, songDuration: song.duration)) return null;
  try {
    final lyrics = await lrclib(song);
    if (lyrics == null || lyrics.trim().isEmpty) return null;
    final document = LyricsDocument.parse(
      lyrics,
      LyricsFormat.lrc,
      source: LyricsSource.lrclib,
    );
    return document.lines.isEmpty ? null : document;
  } catch (e) {
    debugPrint('LyricsProvider: LRCLIB fallback failed: $e');
    return null;
  }
}

Future<void> _writeCacheBestEffort(
  Future<void> Function(String raw, LyricsFormat format) writeCache,
  String raw,
  LyricsFormat format,
) async {
  try {
    await writeCache(raw, format);
  } catch (e, s) {
    // Cache write failures are reported but never propagate: the lyrics were
    // already fetched and must still be shown.
    debugPrint('LyricsProvider: cache write failed: $e');
    debugPrint('$s');
  }
}

@immutable
class _LyricsFetchOutcome {
  final RawLyrics? raw;
  final List<Object> errors;
  final bool answered;

  const _LyricsFetchOutcome({
    this.raw,
    this.errors = const [],
    this.answered = false,
  });

  String errorMessage() {
    final first = errors.isEmpty ? null : apiExceptionOf(errors.first);
    return first?.message ?? '歌词加载失败';
  }
}

Future<_LyricsFetchOutcome> _fetchLyricsWithFallback({
  required Song song,
  required List<MusicPlatform> platforms,
  required Duration timeout,
}) async {
  final errors = <Object>[];
  var answered = false;

  final own = _platformFor(song.platform, platforms);
  if (own != null) {
    final result = await _requestLyrics(own, song.id, timeout, errors);
    if (result.raw != null) return result;
    answered |= result.answered;
  } else {
    // Without a registered platform for this song, nothing answered.
    debugPrint(
      'LyricsProvider: no registered platform for ${song.platform.name}',
    );
  }

  // Cross-source fallback: another platform may still have the same recording
  // (the same song exists on several services under different ids).
  for (final platform in platforms) {
    if (platform.platformType == song.platform ||
        platform.platformType == PlatformType.local) {
      continue;
    }
    final match = await _searchEquivalentSong(platform, song, timeout, errors);
    if (match == null) continue;
    final result = await _requestLyrics(platform, match.id, timeout, errors);
    if (result.raw != null) return result;
    answered |= result.answered;
  }

  return _LyricsFetchOutcome(errors: errors, answered: answered);
}

MusicPlatform? _platformFor(
  PlatformType type,
  List<MusicPlatform> platforms,
) {
  for (final platform in platforms) {
    if (platform.platformType == type) return platform;
  }
  return null;
}

Future<_LyricsFetchOutcome> _requestLyrics(
  MusicPlatform platform,
  String songId,
  Duration timeout,
  List<Object> errors,
) async {
  debugPrint(
    'LyricsProvider: calling ${platform.platformType.name} getLyricsBundle($songId)',
  );
  try {
    final bundle = await platform.getLyricsBundle(songId).timeout(timeout);
    if (bundle == null || bundle.isEmpty) {
      debugPrint('LyricsProvider: raw lyrics is null or empty');
      return const _LyricsFetchOutcome(answered: true);
    }
    debugPrint(
      'LyricsProvider: got lrc=${bundle.lrc?.length ?? 0} '
      'translation=${bundle.translation?.length ?? 0} '
      'yrc=${bundle.yrc?.length ?? 0} romaji=${bundle.romaji?.length ?? 0}',
    );
    return _LyricsFetchOutcome(
      raw: RawLyrics(
        bundle: bundle,
        source: lyricsSourceForPlatform(platform.platformType),
      ),
      answered: true,
    );
  } catch (e) {
    debugPrint('LyricsProvider: ${platform.platformType.name} failed: $e');
    errors.add(e);
    return const _LyricsFetchOutcome();
  }
}

Future<Song?> _searchEquivalentSong(
  MusicPlatform platform,
  Song song,
  Duration timeout,
  List<Object> errors,
) async {
  try {
    final keyword = '${song.name} ${song.artists.map((a) => a.name).join(' ')}'
        .trim();
    if (keyword.isEmpty) return null;
    final candidates = await platform.search(keyword, limit: 10).timeout(timeout);
    final key = song.dedupeKey;
    for (final candidate in candidates) {
      if (candidate.dedupeKey == key) return candidate;
    }
    return null;
  } catch (e) {
    debugPrint('LyricsProvider: ${platform.platformType.name} search failed: $e');
    errors.add(e);
    return null;
  }
}

LyricsFormat _parseLyricsFormat(String formatStr) {
  return LyricsFormat.values.firstWhere(
    (f) => f.name == formatStr,
    orElse: () => LyricsFormat.lrc,
  );
}

/// Format of a **local** lyric payload: a `.lrc`/`.krc`/`.qrc` sidecar or an
/// embedded tag.
///
/// Guesses, most specific first, and a candidate only wins when it really parses
/// into at least one timed line: sniffing on `[` + `<` + `,` alone sent an
/// ordinary LRC (a smiley, a comma in the lyrics) to the KRC parser, which found
/// nothing and blanked the whole song — "暂无歌词" for a file that was fine.
///
/// Streamed platforms do not come through here: `LyricsBundle` carries the
/// format, and `mainLyricsTrack` sniffs a single-payload platform's track.
LyricsFormat _localLyricsFormat(String raw) {
  return LyricsDocument.sniffFormat(raw, const [
    LyricsFormat.qrc,
    LyricsFormat.krc,
    LyricsFormat.lrc,
  ]);
}
