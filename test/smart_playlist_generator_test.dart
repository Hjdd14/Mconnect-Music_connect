import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/features/smart_playlists/domain/smart_playlist_generator.dart';
import 'package:mconnect/features/smart_playlists/domain/smart_playlist_rule.dart';
import 'package:mconnect/features/stats/presentation/providers/listening_stats_provider.dart';
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
}

Song _song(String id, PlatformType platform, String name, String artist) {
  return Song(
    id: id,
    platform: platform,
    name: name,
    artists: [Artist(id: 'artist_$id', name: artist)],
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
