import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/core/network/api_exception.dart';
import 'package:mconnect/platform/kugou/kugou_api.dart';
import 'package:mconnect/platform/kugou/kugou_platform.dart';

/// WS-D: 榜单 / 艺人 / 专辑 interfaces, driven by payloads captured from the
/// live endpoints (see `scripts/test_kugou_wave1_probe*.dart`).
void main() {
  group('getToplists', () {
    test('parses rank/list rows including the extra.resp.all_total count', () async {
      final platform = KugouPlatform(api: _ContentApi());

      final toplists = await platform.getToplists();

      expect(toplists, hasLength(2));
      final top500 = toplists.first;
      expect(top500.id, '8888');
      expect(top500.name, 'TOP500');
      expect(top500.coverUrl, contains('imge.kugou.com'));
      expect(top500.coverUrl, isNot(contains('{size}')));
      expect(top500.updateFrequency, '每天');
      expect(top500.songCount, 500);
      expect(top500.period, '2026-10-06 08:30:01');
      expect(top500.intro, contains('更新频率：每天'));

      final weekly = toplists[1];
      expect(weekly.id, '85897');
      expect(weekly.updateFrequency, '周五凌晨更新周榜');
      expect(weekly.songCount, 100);
    });

    test('drops rows without a rankid', () async {
      final platform = KugouPlatform(api: _ContentApi());

      final toplists = await platform.getToplists();

      expect(toplists.every((t) => t.id.isNotEmpty), isTrue);
    });
  });

  group('getRankedSongs', () {
    test('uses the reported sort/rank_count and maps movement to rankChange', () async {
      final platform = KugouPlatform(api: _ContentApi());

      final ranked = await platform.getRankedSongs('8888', num: 3);

      expect(ranked, hasLength(3));
      expect(ranked.map((r) => r.rank), [1, 2, 5]);
      // rank_count is the previous position: 1 -> 1 = 0, 5 -> 2 = +3, 9 -> 5 = +4
      expect(ranked.map((r) => r.rankChange), [0, 3, 4]);
      expect(ranked.map((r) => r.rankValue), ['1', '5', '9']);
      expect(ranked.map((r) => r.isNew), [null, true, null]);
      expect(ranked.first.song.name, '茶汤');
      expect(ranked.first.song.id, 'HASH_RANK_1');
    });

    test('falls back to the page index when sort is missing', () async {
      final platform = KugouPlatform(api: _ContentApi());

      final ranked = await platform.getRankedSongs('9999', num: 2);

      expect(ranked.map((r) => r.rank), [1, 2]);
      expect(ranked.map((r) => r.rankChange), [null, null]);
      expect(ranked.map((r) => r.song.id), ['HASH_NO_SORT_1', 'HASH_NO_SORT_2']);
    });

    test('artist names come from the authors list', () async {
      final platform = KugouPlatform(api: _ContentApi());

      final ranked = await platform.getRankedSongs('8888', num: 1);

      expect(ranked.single.song.artists.map((a) => a.name), ['郁可唯']);
      expect(ranked.single.song.artists.single.id, '6539');
    });

    test('rejects a non-numeric chart id instead of guessing', () async {
      final platform = KugouPlatform(api: _ContentApi());

      await expectLater(
        platform.getRankedSongs('not-a-rank-id'),
        throwsA(isA<ApiException>()),
      );
    });
  });

  group('artist pages', () {
    test('getArtistDetail maps singer/info fields', () async {
      final platform = KugouPlatform(api: _ContentApi());

      final artist = await platform.getArtistDetail('3060');

      expect(artist, isNotNull);
      expect(artist!.id, '3060');
      expect(artist.name, '薛之谦');
      expect(artist.avatarUrl, isNot(contains('{size}')));
      expect(artist.briefDesc, startsWith('薛之谦，1983年7月17日'));
      expect(artist.songCount, 962);
      expect(artist.albumCount, 41);
      expect(artist.fansCount, 1234567);
    });

    test('getArtistDetail returns null when the payload has no artist', () async {
      final platform = KugouPlatform(api: _ContentApi());

      expect(await platform.getArtistDetail('0'), isNull);
    });

    test('getArtistTopSongs honours the limit', () async {
      final platform = KugouPlatform(api: _ContentApi());

      final all = await platform.getArtistTopSongs('3060');
      final limited = await platform.getArtistTopSongs('3060', limit: 1);

      expect(all, hasLength(3));
      expect(limited, hasLength(1));
      expect(limited.single.name, '演员');
      expect(limited.single.album?.name, '绅士');
    });

    test('getArtistAlbums parses singer/album rows', () async {
      final platform = KugouPlatform(api: _ContentApi());

      final albums = await platform.getArtistAlbums('3060');

      expect(albums, hasLength(1));
      final album = albums.single;
      expect(album.id, '199628146');
      expect(album.name, '媚人');
      expect(album.artistName, '薛之谦');
      expect(album.artistId, '3060');
      expect(album.songCount, 1);
      expect(album.coverUrl, isNot(contains('{size}')));
      expect(album.releaseDate, DateTime.parse('2026-07-17T00:00:00'));
    });
  });

  group('album pages', () {
    test('getAlbumDetail maps album/info fields', () async {
      final platform = KugouPlatform(api: _ContentApi());

      final album = await platform.getAlbumDetail('14456909');

      expect(album, isNotNull);
      expect(album!.id, '14456909');
      expect(album.name, '绅士');
      expect(album.artistName, '薛之谦');
      expect(album.artistId, '3060');
      expect(album.description, startsWith('从戴上面具的《丑八怪》'));
      expect(album.releaseDate, DateTime.parse('2015-06-05T00:00:00'));
      expect(album.coverUrl, isNot(contains('{size}')));
    });

    test('getAlbumSongs parses album/song rows', () async {
      final platform = KugouPlatform(api: _ContentApi());

      final songs = await platform.getAlbumSongs('1020619');

      expect(songs, hasLength(1));
      expect(songs.single.id, 'AB9F4F0054263A3521E83D50CB9DF818');
      expect(songs.single.name, 'Petals');
      expect(songs.single.artists.single.name, 'beck hansen、Scenic');
      expect(songs.single.duration, const Duration(seconds: 206));
      expect(songs.single.coverUrl, isNot(contains('{size}')));
    });
  });

  group('getNewSongs', () {
    test('degrades honestly instead of returning an empty list', () async {
      final platform = KugouPlatform(api: _ContentApi());

      await expectLater(
        platform.getNewSongs(),
        throwsA(
          isA<UnsupportedActionException>().having(
            (e) => e.message,
            'message',
            '酷狗音乐暂不支持该功能',
          ),
        ),
      );
      expect(platform.supportsNewSongs, isFalse);
    });
  });
}

/// Payloads copied from the live probes (2026-10-06).
class _ContentApi extends KugouApi {
  @override
  Future<Map<String, dynamic>> getToplists({
    int page = 1,
    int pagesize = 100,
  }) async {
    return {
      'status': 1,
      'data': {
        'total': 25,
        'info': [
          {
            'rankid': 8888,
            'rankname': 'TOP500',
            'imgurl': 'http://imge.kugou.com/mcommon/{size}/top500.png',
            'update_frequency': '每天',
            'rank_id_publish_date': '2026-10-06 08:30:01',
            'intro': '数据来源：全曲库歌曲\n更新频率：每天',
            'extra': {
              'resp': {'all_total': 500, 'new_total': 1},
            },
          },
          {
            'rankid': 85897,
            'rankname': '国潮音乐榜',
            'imgurl': 'http://imge.kugou.com/mcommon/{size}/gc.jpg',
            'update_frequency': '周五凌晨更新周榜',
            'extra': {
              'resp': {'all_total': 100},
            },
          },
          {
            'rankname': '没有 rankid 的行',
            'imgurl': 'http://imge.kugou.com/mcommon/{size}/x.jpg',
          },
        ],
      },
    };
  }

  @override
  Future<Map<String, dynamic>> getRankList({
    int rankId = 8888,
    int page = 1,
    int pagesize = 100,
  }) async {
    final sorted = <Map<String, dynamic>>[
      {
        'hash': 'HASH_RANK_1',
        'songname': '茶汤',
        'filename': '郁可唯 - 茶汤',
        'authors': [
          {'author_id': 6539, 'author_name': '郁可唯'},
        ],
        'album_id': '4012536',
        'duration': 306,
        'sort': 1,
        'rank_count': 1,
        'isfirst': 0,
        'trans_param': {
          'union_cover': 'http://imge.kugou.com/stdmusic/{size}/cover.jpg',
        },
      },
      {
        'hash': 'HASH_RANK_2',
        'songname': '第二首',
        'filename': '歌手 - 第二首',
        'duration': 200,
        'sort': 2,
        'rank_count': 5,
        'isfirst': 1,
      },
      {
        'hash': 'HASH_RANK_3',
        'songname': '第五首',
        'filename': '歌手 - 第五首',
        'duration': 210,
        'sort': 5,
        'rank_count': 9,
        'isfirst': 0,
      },
    ];
    final unsorted = <Map<String, dynamic>>[
      {'hash': 'HASH_NO_SORT_1', 'songname': '无位次一', 'filename': '甲 - 无位次一'},
      {'hash': 'HASH_NO_SORT_2', 'songname': '无位次二', 'filename': '乙 - 无位次二'},
    ];
    // rankid 8888 reports `sort`/`rank_count`; 9999 does not.
    final source = rankId == 8888 ? sorted : unsorted;
    return {
      'status': 1,
      'data': {
        'total': 500,
        'info': source.take(pagesize).toList(),
      },
    };
  }

  @override
  Future<Map<String, dynamic>> getArtistInfo(String singerId) async {
    if (singerId == '0') {
      return {
        'status': 1,
        'data': {'singername': '', 'singerid': 0},
      };
    }
    return {
      'status': 1,
      'data': {
        'singerid': 3060,
        'singername': '薛之谦',
        'avatar': 'http://singerimg.kugou.com/uploadpic/softhead/{size}/a.jpg',
        'profile': '薛之谦，1983年7月17日出生于上海市，中国内地流行乐男歌手。',
        'songcount': 962,
        'albumcount': 41,
        'fansnums': 1234567,
      },
    };
  }

  @override
  Future<Map<String, dynamic>> getArtistSongs(
    String singerId, {
    int page = 1,
    int pagesize = 100,
    int sortType = 2,
  }) async {
    return {
      'status': 1,
      'data': {
        'info': [
          {
            'hash': 'HASH_ARTIST_1',
            'filename': '薛之谦 - 演员',
            'album_name': '绅士',
            'album_id': '14456909',
            'duration': 261,
            'trans_param': {
              'union_cover': 'http://imge.kugou.com/stdmusic/{size}/s.jpg',
            },
          },
          {'hash': 'HASH_ARTIST_2', 'filename': '薛之谦 - 绅士', 'duration': 267},
          {'hash': 'HASH_ARTIST_3', 'filename': '薛之谦 - 丑八怪', 'duration': 261},
        ].take(pagesize).toList(),
      },
    };
  }

  @override
  Future<Map<String, dynamic>> getArtistAlbums(
    String singerId, {
    int page = 1,
    int pagesize = 100,
  }) async {
    return {
      'status': 1,
      'data': {
        'info': [
          {
            'albumid': 199628146,
            'albumname': '媚人',
            'singername': '薛之谦',
            'singerid': 3060,
            'songcount': 1,
            'publishtime': '2026-07-17 00:00:00',
            'imgurl': 'http://imge.kugou.com/stdmusic/{size}/mr.jpg',
            'intro': '你心所想 即是模样',
          },
        ].take(pagesize).toList(),
      },
    };
  }

  @override
  Future<Map<String, dynamic>> getAlbumInfo(String albumId) async {
    return {
      'status': 1,
      'errcode': 0,
      'data': {
        'albumid': 14456909,
        'albumname': '绅士',
        'singername': '薛之谦',
        'singerid': 3060,
        'songcount': 3,
        'publishtime': '2015-06-05 00:00:00',
        'imgurl': 'http://imge.kugou.com/stdmusic/{size}/ss.jpg',
        'intro': '从戴上面具的《丑八怪》到摘下礼帽的《绅士》',
      },
    };
  }

  @override
  Future<Map<String, dynamic>> getAlbumSongs(
    String albumId, {
    int page = 1,
    int pagesize = 100,
  }) async {
    return {
      'status': 1,
      'errcode': 0,
      'data': {
        'info': [
          {
            'hash': 'AB9F4F0054263A3521E83D50CB9DF818',
            'filename': 'beck hansen、Scenic - Petals',
            'album_id': '1020619',
            'duration': 206,
            'trans_param': {
              'union_cover': 'http://imge.kugou.com/stdmusic/{size}/p.jpg',
            },
          },
        ],
      },
    };
  }
}
