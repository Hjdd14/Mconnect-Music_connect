import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/database/app_database.dart';
import '../../../local_music/presentation/providers/local_music_provider.dart';
import '../../../../lyrics/models/lyrics_line.dart';
import '../../../../models/platform_type.dart';
import '../../../../platform/base/platform_registry.dart';
import 'player_provider.dart';

/// Fetches and parses lyrics for the currently playing song, with local cache.
final lyricsProvider = FutureProvider.autoDispose<LyricsDocument?>((ref) async {
  final song = ref.watch(playerProvider.select((s) => s.currentSong));
  if (song == null) return null;

  debugPrint('LyricsProvider: fetching for ${song.name} (${song.platform.name}, id=${song.id})');

  try {
    if (song.platform == PlatformType.local) {
      final raw = ref.watch(
        localMusicProvider.select((s) => s.lyricsFor(song.id)),
      );
      if (raw == null || raw.isEmpty) return null;
      return LyricsDocument.parse(raw, _formatForPlatform(song.platform, raw));
    }

    final db = database;

    // Check local cache first — use stored format to avoid re-detection
    final cached = await db.lyricsCacheDao.getCachedLyricsWithFormat(song.id, song.platform.name);
    if (cached != null) {
      debugPrint('LyricsProvider: cache hit, format=${cached.format}');
      final format = _parseLyricsFormat(cached.format);
      final document = LyricsDocument.parse(cached.content, format);
      if (document.lines.isNotEmpty) {
        return document;
      }
      debugPrint('LyricsProvider: cached lyrics parsed empty, refetching');
    }

    // Fetch from API
    final platform = PlatformRegistry.get(song.platform);
    debugPrint('LyricsProvider: calling ${song.platform.name} getLyrics(${song.id})');
    final raw = await platform.getLyrics(song.id);
    if (raw == null || raw.isEmpty) {
      debugPrint('LyricsProvider: raw lyrics is null or empty');
      return null;
    }
    debugPrint('LyricsProvider: got ${raw.length} chars of lyrics');

    // Cache the result with detected format
    final format = _formatForPlatform(song.platform, raw);
    debugPrint('LyricsProvider: detected format=${format.name}');
    await db.lyricsCacheDao.cacheLyrics(song.id, song.platform.name, raw, format.name);

    return LyricsDocument.parse(raw, format);
  } catch (e, s) {
    debugPrint('LyricsProvider: error: $e');
    debugPrint('LyricsProvider: stack: $s');
    return null;
  }
});

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
