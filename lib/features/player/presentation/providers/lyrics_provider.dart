import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/network/platform_http.dart';
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

/// Raw lyrics text plus the format it should be parsed with.
@immutable
class RawLyrics {
  final String content;
  final LyricsFormat format;
  final PlatformType? source;

  const RawLyrics({
    required this.content,
    required this.format,
    this.source,
  });
}

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
  if (song.platform != PlatformType.local) {
    try {
      final cached = await database.lyricsCacheDao.getCachedLyricsWithFormat(
        song.id,
        song.platform.name,
      );
      if (cached != null) {
        debugPrint('LyricsProvider: cache hit, format=${cached.format}');
        cachedLyrics = (content: cached.content, format: cached.format);
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
    platforms: PlatformRegistry.all,
    writeCache: song.platform == PlatformType.local
        ? null
        : (raw, format) => database.lyricsCacheDao.cacheLyrics(
            song.id,
            song.platform.name,
            raw,
            format.name,
          ),
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
  List<MusicPlatform> platforms = const [],
  Future<void> Function(String raw, LyricsFormat format)? writeCache,
  Duration timeout = lyricsRequestTimeout,
}) async {
  if (song.platform == PlatformType.local) {
    final raw = localRawLyrics;
    if (raw == null || raw.isEmpty) return null;
    final document = LyricsDocument.parse(
      raw,
      _formatForPlatform(song.platform, raw),
    );
    return document.lines.isEmpty ? null : document;
  }

  final cached = cachedLyrics;
  if (cached != null) {
    final format = _parseLyricsFormat(cached.format);
    final document = LyricsDocument.parse(cached.content, format);
    if (document.lines.isNotEmpty) {
      return document;
    }
    debugPrint('LyricsProvider: cached lyrics parsed empty, refetching');
  }

  final outcome = await _fetchLyricsWithFallback(
    song: song,
    platforms: platforms,
    timeout: timeout,
  );
  final raw = outcome.raw;
  if (raw == null) {
    if (!outcome.answered && outcome.errors.isNotEmpty) {
      throw LyricsUnavailableException(
        outcome.errorMessage(),
        causes: outcome.errors,
      );
    }
    return null;
  }

  final document = LyricsDocument.parse(raw.content, raw.format);
  if (document.lines.isEmpty) {
    // The platform answered with content that carries no timed lines; treat it
    // as "no lyrics" rather than as a load failure.
    return null;
  }

  if (writeCache != null) {
    unawaited(
      _writeCacheBestEffort(writeCache, raw.content, raw.format),
    );
  }
  return document;
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
  debugPrint('LyricsProvider: calling ${platform.platformType.name} getLyrics($songId)');
  try {
    final raw = await platform.getLyrics(songId).timeout(timeout);
    if (raw == null || raw.isEmpty) {
      debugPrint('LyricsProvider: raw lyrics is null or empty');
      return const _LyricsFetchOutcome(answered: true);
    }
    debugPrint('LyricsProvider: got ${raw.length} chars of lyrics');
    return _LyricsFetchOutcome(
      raw: RawLyrics(
        content: raw,
        format: _formatForPlatform(platform.platformType, raw),
        source: platform.platformType,
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

LyricsFormat _formatForPlatform(PlatformType platformType, String raw) {
  switch (platformType) {
    case PlatformType.qq:
      if (raw.contains('<L ') && raw.contains('<P ')) {
        return LyricsFormat.qrc;
      }
      return LyricsFormat.lrc;
    case PlatformType.kugou:
      if (raw.contains('[') && raw.contains('<') && raw.contains(',')) {
        return LyricsFormat.krc;
      }
      return LyricsFormat.lrc;
    case PlatformType.local:
      if (raw.contains('<L ') && raw.contains('<P ')) {
        return LyricsFormat.qrc;
      }
      if (raw.contains('[') && raw.contains('<') && raw.contains(',')) {
        return LyricsFormat.krc;
      }
      return LyricsFormat.lrc;
    case PlatformType.netease:
      return LyricsFormat.lrc;
  }
}
