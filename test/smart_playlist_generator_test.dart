import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/features/smart_playlists/domain/smart_playlist_generator.dart';
import 'package:mconnect/features/smart_playlists/domain/smart_playlist_rule.dart';
import 'package:mconnect/features/stats/domain/listening_stats.dart';
import 'package:mconnect/models/artist.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/song.dart';

void main() {
  test('smart playlist generator combines filters without network calls', () {
    final now = DateTime(2026, 5, 30);
    final neteaseMatch = _song('n1', PlatformType.netease, 'Live Song', '歌手A');
    final qqUncached = _song('q1', PlatformType.qq, 'Live Song', '歌手B');
    final kugouWrongPlatform = _song(
      'k1',
      PlatformType.kugou,
      'Live Song',
      '歌手C',
    );
    final oldSong = _song('n2', PlatformType.netease, 'Live Song', '歌手D');
    final keywordMiss = _song('n3', PlatformType.netease, 'Studio Song', '歌手A');

    final context = SmartPlaylistSourceContext(
      songs: [
        neteaseMatch,
        qqUncached,
        kugouWrongPlatform,
        oldSong,
        keywordMiss,
      ],
      likedSongKeys: {
        SmartPlaylistGenerator.songKey(neteaseMatch),
        SmartPlaylistGenerator.songKey(qqUncached),
        SmartPlaylistGenerator.songKey(oldSong),
        SmartPlaylistGenerator.songKey(keywordMiss),
      },
      cachedSongKeys: {
        SmartPlaylistGenerator.songKey(neteaseMatch),
        SmartPlaylistGenerator.songKey(kugouWrongPlatform),
        SmartPlaylistGenerator.songKey(oldSong),
        SmartPlaylistGenerator.songKey(keywordMiss),
      },
      statsBySongKey: {
        SmartPlaylistGenerator.songKey(neteaseMatch): _stats(
          neteaseMatch,
          playCount: 5,
          lastListenedAt: now.subtract(const Duration(days: 2)),
        ),
        SmartPlaylistGenerator.songKey(qqUncached): _stats(
          qqUncached,
          playCount: 6,
          lastListenedAt: now.subtract(const Duration(days: 1)),
        ),
        SmartPlaylistGenerator.songKey(kugouWrongPlatform): _stats(
          kugouWrongPlatform,
          playCount: 8,
          lastListenedAt: now.subtract(const Duration(days: 1)),
        ),
        SmartPlaylistGenerator.songKey(oldSong): _stats(
          oldSong,
          playCount: 9,
          lastListenedAt: now.subtract(const Duration(days: 40)),
        ),
        SmartPlaylistGenerator.songKey(keywordMiss): _stats(
          keywordMiss,
          playCount: 10,
          lastListenedAt: now.subtract(const Duration(days: 1)),
        ),
      },
      now: now,
    );
    final rule = SmartPlaylistRule.create(
      name: '规则',
      platforms: const {PlatformType.netease, PlatformType.qq},
      keyword: 'live',
      minPlayCount: 3,
      recentlyPlayedDays: 7,
      likedOnly: true,
      cachedOnly: true,
    );

    final result = SmartPlaylistGenerator.generate(rule, context);

    expect(result, [neteaseMatch]);
  });

  group('extended filters', () {
    final now = DateTime(2026, 5, 30);

    test('artist and album ids select the owning platform ids', () {
      final targeted = _song(
        'a1',
        PlatformType.netease,
        '目标曲',
        '歌手A',
        artistId: 'artist-1',
        albumId: 'album-1',
      );
      final other = _song(
        'a2',
        PlatformType.netease,
        '其他曲',
        '歌手B',
        artistId: 'artist-2',
        albumId: 'album-2',
      );
      final context = SmartPlaylistSourceContext(
        songs: [targeted, other],
        now: now,
      );

      expect(
        SmartPlaylistGenerator.generate(
          SmartPlaylistRule.create(name: 'r', artistIds: const {'artist-1'}),
          context,
        ),
        [targeted],
      );
      expect(
        SmartPlaylistGenerator.generate(
          SmartPlaylistRule.create(name: 'r', albumIds: const {'album-2'}),
          context,
        ),
        [other],
      );
      // Songs without ids must not be swept in by an id filter.
      expect(
        SmartPlaylistGenerator.generate(
          SmartPlaylistRule.create(name: 'r', artistIds: const {'missing'}),
          context,
        ),
        isEmpty,
      );
    });

    test('duration range keeps only the requested length', () {
      final short = _song(
        's',
        PlatformType.netease,
        '短曲',
        '歌手A',
        duration: const Duration(seconds: 90),
      );
      final medium = _song(
        'm',
        PlatformType.netease,
        '中曲',
        '歌手A',
        duration: const Duration(minutes: 4),
      );
      final long = _song(
        'l',
        PlatformType.netease,
        '长曲',
        '歌手A',
        duration: const Duration(minutes: 12),
      );
      final context = SmartPlaylistSourceContext(
        songs: [short, medium, long],
        now: now,
      );

      final result = SmartPlaylistGenerator.generate(
        SmartPlaylistRule.create(
          name: 'r',
          minDurationMs: const Duration(minutes: 2).inMilliseconds,
          maxDurationMs: const Duration(minutes: 6).inMilliseconds,
        ),
        context,
      );

      expect(result, [medium]);
    });

    test('play count bounds and recency filters use the statistics', () {
      final neverPlayed = _song('n', PlatformType.netease, '没听过', '歌手A');
      final rare = _song('r', PlatformType.netease, '偶尔听', '歌手A');
      final heavy = _song('h', PlatformType.netease, '常听', '歌手A');
      final old = _song('o', PlatformType.netease, '很久没听', '歌手A');
      final context = SmartPlaylistSourceContext(
        songs: [neverPlayed, rare, heavy, old],
        statsBySongKey: {
          SmartPlaylistGenerator.songKey(rare): _stats(
            rare,
            playCount: 2,
            lastListenedAt: now.subtract(const Duration(days: 2)),
          ),
          SmartPlaylistGenerator.songKey(heavy): _stats(
            heavy,
            playCount: 40,
            lastListenedAt: now.subtract(const Duration(days: 1)),
          ),
          SmartPlaylistGenerator.songKey(old): _stats(
            old,
            playCount: 5,
            lastListenedAt: now.subtract(const Duration(days: 200)),
          ),
        },
        now: now,
      );

      expect(
        SmartPlaylistGenerator.generate(
          SmartPlaylistRule.create(name: 'r', maxPlayCount: 5),
          context,
        ).map((song) => song.id),
        // Never-played songs count as 0 plays, which is the point of the filter.
        ['o', 'r', 'n'],
      );

      expect(
        SmartPlaylistGenerator.generate(
          SmartPlaylistRule.create(name: 'r', notPlayedSinceDays: 100),
          context,
        ).map((song) => song.id),
        ['o', 'n'],
      );
    });

    test('local-only and downloaded-only use the platform and download sets', () {
      final local = _song('l', PlatformType.local, '本地曲', '歌手A');
      final streamed = _song('s', PlatformType.netease, '在线曲', '歌手A');
      final downloaded = _song('d', PlatformType.qq, '已下载', '歌手A');
      final context = SmartPlaylistSourceContext(
        songs: [local, streamed, downloaded],
        downloadedSongKeys: {SmartPlaylistGenerator.songKey(downloaded)},
        now: now,
      );

      expect(
        SmartPlaylistGenerator.generate(
          SmartPlaylistRule.create(name: 'r', localOnly: true),
          context,
        ),
        [local],
      );
      expect(
        SmartPlaylistGenerator.generate(
          SmartPlaylistRule.create(name: 'r', downloadedOnly: true),
          context,
        ),
        [downloaded],
      );
    });

    test('excludeLiked is the counterpart of likedOnly', () {
      final liked = _song('l', PlatformType.netease, '红心', '歌手A');
      final unliked = _song('u', PlatformType.netease, '未红心', '歌手A');
      final context = SmartPlaylistSourceContext(
        songs: [liked, unliked],
        likedSongKeys: {SmartPlaylistGenerator.songKey(liked)},
        now: now,
      );

      expect(
        SmartPlaylistGenerator.generate(
          SmartPlaylistRule.create(name: 'r', excludeLiked: true),
          context,
        ),
        [unliked],
      );
    });

    test('match any is an OR over the condition group but not over platforms', () {
      final neteaseLiked = _song('nl', PlatformType.netease, '红心', '歌手A');
      final neteasePlayed = _song('np', PlatformType.netease, '常听', '歌手A');
      final qqLiked = _song('ql', PlatformType.qq, '红心', '歌手A');
      final context = SmartPlaylistSourceContext(
        songs: [neteaseLiked, neteasePlayed, qqLiked],
        likedSongKeys: {
          SmartPlaylistGenerator.songKey(neteaseLiked),
          SmartPlaylistGenerator.songKey(qqLiked),
        },
        statsBySongKey: {
          SmartPlaylistGenerator.songKey(neteasePlayed): _stats(
            neteasePlayed,
            playCount: 9,
            lastListenedAt: now,
          ),
        },
        now: now,
      );

      final any = SmartPlaylistGenerator.generate(
        SmartPlaylistRule.create(
          name: 'r',
          platforms: const {PlatformType.netease},
          likedOnly: true,
          minPlayCount: 5,
          match: SmartPlaylistMatch.any,
        ),
        context,
      );
      expect(
        any.map((song) => song.id).toSet(),
        {'nl', 'np'},
        reason: 'either condition may match…',
      );
      expect(
        any.any((song) => song.platform == PlatformType.qq),
        isFalse,
        reason: '…but the platform scope stays an AND',
      );

      final all = SmartPlaylistGenerator.generate(
        SmartPlaylistRule.create(
          name: 'r',
          platforms: const {PlatformType.netease},
          likedOnly: true,
          minPlayCount: 5,
        ),
        context,
      );
      expect(all, isEmpty);
    });

    test('sort orders are deterministic', () {
      final a = _song('a', PlatformType.netease, 'Zeta', '歌手A');
      final b = _song('b', PlatformType.netease, 'Alpha', '歌手A');
      final context = SmartPlaylistSourceContext(
        songs: [a, b],
        statsBySongKey: {
          SmartPlaylistGenerator.songKey(a): _stats(
            a,
            playCount: 1,
            lastListenedAt: now.subtract(const Duration(days: 5)),
          ),
          SmartPlaylistGenerator.songKey(b): _stats(
            b,
            playCount: 10,
            lastListenedAt: now,
          ),
        },
        now: now,
      );

      expect(
        SmartPlaylistGenerator.generate(
          SmartPlaylistRule.create(
            name: 'r',
            sortBy: SmartPlaylistSortOrder.mostPlayed,
          ),
          context,
        ).map((song) => song.id),
        ['b', 'a'],
      );
      expect(
        SmartPlaylistGenerator.generate(
          SmartPlaylistRule.create(
            name: 'r',
            sortBy: SmartPlaylistSortOrder.recentlyPlayed,
          ),
          context,
        ).map((song) => song.id),
        ['b', 'a'],
      );
      expect(
        SmartPlaylistGenerator.generate(
          SmartPlaylistRule.create(
            name: 'r',
            sortBy: SmartPlaylistSortOrder.titleAsc,
          ),
          context,
        ).map((song) => song.id),
        ['b', 'a'],
      );

      // Without statistics the order must still be stable, not "whatever the
      // source list happened to be".
      final noStats = SmartPlaylistSourceContext(songs: [a, b], now: now);
      final first = SmartPlaylistGenerator.generate(
        SmartPlaylistRule.create(
          name: 'r',
          sortBy: SmartPlaylistSortOrder.mostListened,
        ),
        noStats,
      );
      final second = SmartPlaylistGenerator.generate(
        SmartPlaylistRule.create(
          name: 'r',
          sortBy: SmartPlaylistSortOrder.mostListened,
        ),
        SmartPlaylistSourceContext(songs: [b, a], now: now),
      );
      expect(first.map((song) => song.id), second.map((song) => song.id));
    });
  });
}

Song _song(
  String id,
  PlatformType platform,
  String name,
  String artist, {
  String? artistId,
  String? albumId,
  Duration duration = const Duration(minutes: 4),
}) {
  return Song(
    id: id,
    platform: platform,
    name: name,
    artists: [Artist(id: artistId ?? 'artist_$id', name: artist)],
    duration: duration,
    artistId: artistId,
    albumId: albumId,
  );
}

ListeningStatsSongEntry _stats(
  Song song, {
  required int playCount,
  required DateTime lastListenedAt,
}) {
  return ListeningStatsSongEntry(
    songId: song.id,
    platform: song.platform,
    songName: song.name,
    artistNames: song.artistNames,
    playCount: playCount,
    listenDuration: Duration(minutes: playCount),
    lastListenedAt: lastListenedAt,
  );
}
