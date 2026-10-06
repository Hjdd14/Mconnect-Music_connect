import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/core/storage/session_storage.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/recommendation_source.dart';
import 'package:mconnect/models/user.dart';
import 'package:mconnect/platform/base/music_platform.dart';
import 'package:mconnect/platform/qq/qq_api.dart';
import 'package:mconnect/platform/qq/qq_platform.dart';
import 'package:mconnect/platform/qq/qq_toplist_ids.dart';

import 'qq_fixtures.dart';

void main() {
  group('QQ 热歌榜（用户点名的缺陷）', () {
    test('getRankingList 使用 topId=26 并解包 toplist_cp 的 data 包裹层', () async {
      final api = _FakeQqApi(toplistCp: kHotToplistCp);

      final songs = await QqPlatform(api: api).getRankingList();

      expect(api.rankedCalls.map((c) => c.topId), [26]);
      expect(songs, hasLength(3));
      expect(songs.first.id, '001fsNdn1zuZnA');
      expect(songs.first.name, '我不难过');
      expect(songs.first.artists.single.name, '孙燕姿');
      expect(songs.first.album?.name, '未完成');
      expect(songs.first.duration, const Duration(seconds: 320));
      expect(songs.first.coverUrl, contains('004VSvF52mQoQp'));
      expect(songs[1].name, 'Proof');
      expect(songs[1].artists.single.name, '檀健次');
    });

    test(
      'getRankedSongs 给出排名、涨跌（old_count-cur_count）、新上榜与 Franking_value',
      () async {
        final api = _FakeQqApi(toplistCp: kHotToplistCp);

        final ranked = await QqPlatform(api: api).getRankedSongs('26');

        expect(ranked.map((r) => r.rank), [1, 2, 3]);
        expect(ranked.map((r) => r.rankChange), [0, 3, 0]);
        expect(ranked.map((r) => r.isNew), [false, false, false]);
        expect(ranked.map((r) => r.rankValue), ['1', '2', '3']);
        expect(ranked[1].song.name, 'Proof');
      },
    );

    test('热歌榜 300 首按 50 一页翻页（端点上限实测 50）', () async {
      final api = _FakeQqApi(cpBuilder: _rankOrderedChart);

      final ranked = await QqPlatform(api: api).getHotSongs();

      expect(ranked, hasLength(300));
      expect(api.rankedCalls.map((c) => c.offset), [0, 50, 100, 150, 200, 250]);
      expect(
        api.rankedCalls.every((c) => c.num <= QqToplistIds.pageSize),
        isTrue,
      );
      expect(ranked.first.rank, 1);
      expect(ranked.last.rank, 300);
      expect(ranked.last.song.id, 'mid-300');
    });

    test('offset 分页从第二页开始保持真实排名', () async {
      final api = _FakeQqApi(cpBuilder: _rankOrderedChart);

      final ranked = await QqPlatform(api: api)
          .getRankedSongs('26', offset: 100, num: 50);

      expect(api.rankedCalls.single.offset, 100);
      expect(ranked.first.rank, 101);
      expect(ranked.last.rank, 150);
    });

    test('指数型榜单的 cur_count 是指数而非排名：排名回退到 offset+i+1，涨跌置空', () async {
      final api = _FakeQqApi(toplistCp: kScoreToplistCp);

      final ranked = await QqPlatform(api: api).getRankedSongs('4');

      expect(ranked.map((r) => r.rank), [1, 2]);
      expect(ranked.map((r) => r.rankChange), [null, null]);
      expect(ranked.map((r) => r.isNew), [null, null]);
      expect(ranked.map((r) => r.rankValue), ['213709', '166026']);
    });
  });

  group('QQ 榜单中心数据', () {
    test('getToplists 解析 GetAll 的 4 组结构', () async {
      final api = _FakeQqApi(toplistCatalogue: kToplistCatalogue);

      final toplists = await QqPlatform(api: api).getToplists();

      expect(toplists.map((t) => t.id), ['62', '26', '5']);
      expect(toplists.map((t) => t.groupName), ['巅峰榜', '巅峰榜', '地区榜']);
      final hot = toplists.firstWhere(
        (t) => t.id == QqToplistIds.hot.toString(),
      );
      expect(hot.name, '热歌榜');
      expect(hot.songCount, 300);
      expect(hot.updateFrequency, '7首歌新上榜');
      expect(hot.period, '2026-10-06');
      expect(hot.coverUrl, contains('001xEeb01e5Jyf'));
      expect(hot.intro, contains('300'));
    });

    test('GetDetail 路径传 period 并解析 rankType（1上/2下/3平/4新/6增长率）', () async {
      final api = _FakeQqApi(toplistDetail: modernChartDetail());

      final ranked = await QqPlatform(api: api)
          .getRankedSongs('58', num: 10, period: '2026_39');

      expect(api.toplistDetailPeriods, ['2026_39']);
      expect(api.rankedCalls, isEmpty);
      expect(ranked.map((r) => r.rank), [1, 2, 3, 8]);
      expect(ranked.map((r) => r.rankChange), [0, 2, -1, null]);
      expect(ranked.map((r) => r.isNew), [false, false, false, true]);
      expect(ranked[3].song.name, '日落以后');
    });

    test('legacy 路径为空时回退到 GetDetail', () async {
      final api = _FakeQqApi(
        toplistCp: const {},
        toplistDetail: modernChartDetail(),
      );

      final ranked = await QqPlatform(api: api).getRankedSongs('58');

      expect(api.rankedCalls.map((c) => c.topId), [58]);
      expect(ranked, hasLength(4));
      expect(ranked.first.song.name, '周旋');
    });

    test('非法榜单 id 与空数字不发起请求', () async {
      final api = _FakeQqApi();

      expect(
        await QqPlatform(api: api).getRankedSongs('not-a-number'),
        isEmpty,
      );
      expect(await QqPlatform(api: api).getRankedSongs('26', num: 0), isEmpty);
      expect(api.rankedCalls, isEmpty);
    });
  });

  group('QQ 艺人页', () {
    test('getArtistDetail 用 legacy 资料 + musicu pmid 头像', () async {
      final api = _FakeQqApi(
        singerDetail: kSingerDetail,
        singerProfile: kSingerProfile,
      );

      final artist = await QqPlatform(api: api)
          .getArtistDetail('003Nz2So3XXYek');

      expect(artist, isNotNull);
      expect(artist!.id, '003Nz2So3XXYek');
      expect(artist.name, '陈奕迅');
      expect(artist.briefDesc, contains('Eason Chan'));
      expect(artist.songCount, 1400);
      expect(artist.albumCount, 103);
      expect(
        artist.avatarUrl,
        contains('T001R300x300M000003Nz2So3XXYek_4.jpg'),
      );
    });

    test('musicu 无 pic 时用 singer_pmid 拼封面模板', () async {
      final api = _FakeQqApi(
        singerDetail: kSingerDetail,
        singerProfile: const {
          'singer': {
            'data': {
              'singer_list': [
                {
                  'basic_info': {'singer_pmid': 'pmid-only'},
                  'pic': <String, dynamic>{},
                },
              ],
            },
          },
        },
      );

      final artist = await QqPlatform(api: api)
          .getArtistDetail('003Nz2So3XXYek');

      expect(artist!.avatarUrl, contains('T001R300x300M000pmid-only.jpg'));
    });

    test('getArtistTopSongs 按播放量排序并截断', () async {
      final api = _FakeQqApi(singerDetail: kSingerDetail);

      final top = await QqPlatform(api: api)
          .getArtistTopSongs('003Nz2So3XXYek', limit: 1);

      expect(top, hasLength(1));
      expect(top.single.name, '十年');
    });

    test('getArtistAlbums 走 AlbumListServer', () async {
      final api = _FakeQqApi(singerAlbums: kSingerAlbumList);

      final albums = await QqPlatform(api: api)
          .getArtistAlbums('003Nz2So3XXYek');

      expect(albums.map((a) => a.name), ['不想放手', '黑白灰']);
      expect(albums.first.coverUrl, contains('000J1pJ50cDCVE'));
      expect(albums.first.releaseDate, DateTime(2008, 6, 30));
      expect(albums.first.artistName, '陈奕迅');
      expect(api.singerAlbumCalls.single.begin, 0);
    });

    test(
      'getArtistAlbums 在 AlbumListServer 无数据时回退 search_type:2 并按歌手过滤',
      () async {
        final api = _FakeQqApi(
          singerDetail: kSingerDetail,
          singerAlbums: const {
            'req_0': {'code': 500003, 'subcode': 860100001},
          },
          albumSearch: kAlbumSearch,
        );

        final albums = await QqPlatform(api: api)
            .getArtistAlbums('003Nz2So3XXYek');

        expect(albums.map((a) => a.name), [
          'Eason Chan Duo Concert 2010',
          'FEAR and DREAMS',
        ]);
        expect(albums.map((a) => a.songCount), [37, 31]);
        expect(albums.first.coverUrl, contains('002gBayj0ZPoR0'));
        expect(albums.any((a) => a.name == '别人的专辑'), isFalse);
      },
    );
  });

  group('QQ 专辑页', () {
    test('getAlbumDetail 解析 legacy album_info_cp 元数据', () async {
      final api = _FakeQqApi(albumInfo: kAlbumInfo);

      final album = await QqPlatform(api: api).getAlbumDetail('004VSvF52mQoQp');

      expect(album, isNotNull);
      expect(album!.id, '004VSvF52mQoQp');
      expect(album.name, '未完成');
      expect(album.artistName, '孙燕姿');
      expect(album.artistId, '001pWERg3vFgg8');
      expect(album.company, '华纳唱片');
      expect(album.genre, 'Pop 流行');
      expect(album.language, '国语');
      expect(album.description, contains('未完成'));
      expect(album.songCount, 2);
      expect(album.releaseDate, DateTime(2003, 1, 10));
      expect(album.coverUrl, contains('004VSvF52mQoQp'));
    });

    test('getAlbumSongs 解析 data.list[] 曲目', () async {
      final api = _FakeQqApi(albumInfo: kAlbumInfo);

      final songs = await QqPlatform(api: api).getAlbumSongs('004VSvF52mQoQp');

      expect(songs.map((s) => s.name), ['神奇', '我不难过']);
      expect(songs.first.duration, const Duration(seconds: 262));
      expect(songs.first.artists.single.name, '孙燕姿');
    });
  });

  group('QQ 新歌速递', () {
    test('NewSongRegion 映射到 QQ type id', () {
      expect(QqPlatform.qqNewSongTypeForTest(NewSongRegion.all), 5);
      expect(QqPlatform.qqNewSongTypeForTest(NewSongRegion.chinese), 1);
      expect(QqPlatform.qqNewSongTypeForTest(NewSongRegion.western), 2);
      expect(QqPlatform.qqNewSongTypeForTest(NewSongRegion.japanese), 3);
      expect(QqPlatform.qqNewSongTypeForTest(NewSongRegion.korean), 4);
      expect(QqPlatform.qqNewSongTypeForTest(NewSongRegion.hongKongTaiwan), 6);
    });

    test('getNewSongs 请求区域 type 并在客户端截断（QQ 忽略 num）', () async {
      final api = _FakeQqApi(newSongs: kNewSongs);

      final songs = await QqPlatform(api: api)
          .getNewSongs(limit: 2, region: NewSongRegion.hongKongTaiwan);

      expect(api.newSongTypes, [6]);
      expect(songs.map((s) => s.name), ['蜚蜚', '新歌二']);
      expect(songs.first.album?.name, contains('煙灰Ash'));
    });
  });

  group('QQ 每日推荐来源标注', () {
    test('未登录时回退新歌榜并标注 fallbackToplist', () async {
      final api = _FakeQqApi(
        cpBuilder: (topId, offset, count) =>
            topId == QqToplistIds.newSongs ? kHotToplistCp : const {},
      );

      final result = await QqPlatform(api: api).getDailyRecommendation();

      expect(result.songs, hasLength(3));
      expect(result.source, isNotNull);
      expect(result.source!.kind, RecommendationKind.fallbackToplist);
      expect(result.source!.label, '新歌榜');
      expect(result.source!.note, '未登录，已回退到新歌榜');
      expect(result.source!.isPersonalized, isFalse);
      expect(api.rankedCalls.single.topId, QqToplistIds.newSongs);
      expect(
        api.dailyPlaylistIdCalls,
        0,
        reason: '匿名调用不该先去抓今日私享页面再等超时',
      );
    });

    test('登录后使用今日私享并标注 personalPrivate', () async {
      final api = _FakeQqApi(
        dailyPlaylistId: '987654',
        playlistDetail: const {
          'req_0': {
            'data': {
              'songlist': [
                {
                  'songInfo': {
                    'mid': 'private-mid',
                    'name': '今日私享曲',
                    'singer': [
                      {'mid': 'artist-1', 'name': '歌手'},
                    ],
                    'interval': 200,
                  },
                },
              ],
            },
          },
        },
      );
      final platform = QqPlatform(api: api);
      await platform.restoreSession(
        _MemorySessionStorage(
          cookie: 'qqmusic_uin=123456; qm_keyst=token',
          user: const User(
            id: '123456',
            nickname: 'QQ User',
            platform: PlatformType.qq,
          ),
        ),
      );

      final result = await platform.getDailyRecommendation();

      expect(result.songs.single.name, '今日私享曲');
      expect(result.source!.kind, RecommendationKind.personalPrivate);
      expect(result.source!.label, '今日私享');
      expect(result.source!.isPersonalized, isTrue);
      expect(api.playlistDetailIds, ['987654']);
    });

    test('登录后今日私享不可用时回退热歌榜并说明原因', () async {
      final api = _FakeQqApi(
        cpBuilder: (topId, offset, count) =>
            topId == QqToplistIds.hot ? kHotToplistCp : const {},
      );
      final platform = QqPlatform(api: api);
      await platform.restoreSession(
        _MemorySessionStorage(
          cookie: 'qqmusic_uin=123456; qm_keyst=token',
          user: const User(
            id: '123456',
            nickname: 'QQ User',
            platform: PlatformType.qq,
          ),
        ),
      );

      final result = await platform.getDailyRecommendation();

      expect(result.source!.kind, RecommendationKind.fallbackToplist);
      expect(result.source!.label, '热歌榜');
      expect(result.source!.note, contains('今日私享暂不可用'));
    });

    test('两条来源都没有时返回 unavailable 与错误说明，而不是混淆为空列表', () async {
      final api = _FakeQqApi();

      final result = await QqPlatform(api: api).getDailyRecommendation();

      expect(result.songs, isEmpty);
      expect(result.source!.kind, RecommendationKind.unavailable);
      expect(result.error, isNotNull);
    });

    test('getDailyRecommendations 与 getDailyRecommendation 保持一致', () async {
      final api = _FakeQqApi(
        cpBuilder: (topId, offset, count) =>
            topId == QqToplistIds.newSongs ? kHotToplistCp : const {},
      );
      final platform = QqPlatform(api: api);

      final songs = await platform.getDailyRecommendations();

      expect(songs.map((s) => s.name), ['我不难过', 'Proof', '神奇']);
      expect(platform.supportsDailyRecommendations, isTrue);
    });
  });

  group('QQ 空响应不再崩溃', () {
    test('全部接口返回空 Map 时逐个降级为空结果', () async {
      final api = _FakeQqApi();
      final platform = QqPlatform(api: api);

      expect(await platform.getToplists(), isEmpty);
      expect(await platform.getRankedSongs('26'), isEmpty);
      expect(await platform.getRankingList(), isEmpty);
      expect(await platform.getArtistDetail('mid'), isNull);
      expect(await platform.getArtistTopSongs('mid'), isEmpty);
      expect(await platform.getArtistAlbums('mid'), isEmpty);
      expect(await platform.getAlbumDetail('mid'), isNull);
      expect(await platform.getAlbumSongs('mid'), isEmpty);
      expect(await platform.getNewSongs(), isEmpty);
    });

    test('能力开关对这些入口全部为 true', () {
      final platform = QqPlatform(api: _FakeQqApi());

      expect(platform.supportsArtistPage, isTrue);
      expect(platform.supportsAlbumPage, isTrue);
      expect(platform.supportsNewSongs, isTrue);
      expect(platform.supportsDailyRecommendations, isTrue);
    });
  });
}

/// 50 rows per page, `cur_count` == rank (rank-ordered chart).
Map<String, dynamic> _rankOrderedChart(int topId, int offset, int count) {
  final rows = <Map<String, dynamic>>[];
  for (var i = 0; i < count; i++) {
    final rank = offset + i + 1;
    rows.add({
      'Franking_value': '$rank',
      'cur_count': '$rank',
      'old_count': '$rank',
      'data': {
        'songmid': 'mid-$rank',
        'songname': 'Song $rank',
        'singer': [
          {'mid': 'singer-$rank', 'name': 'Artist $rank'},
        ],
        'albummid': 'album-$rank',
        'albumname': 'Album $rank',
        'interval': 200,
      },
    });
  }
  return {
    'code': 0,
    'cur_song_num': rows.length,
    'total_song_num': 300,
    'date': '2026-10-06',
    'topinfo': {'ListName': '巅峰榜·热歌', 'topID': topId},
    'songlist': rows,
  };
}

class _MemorySessionStorage extends SessionStorage {
  final User? user;
  final String? cookie;

  _MemorySessionStorage({this.user, this.cookie});

  @override
  Future<String?> loadCookie(PlatformType platform) async => cookie;

  @override
  Future<User?> loadUser(PlatformType platform) async => user;
}

class _FakeQqApi extends QqApi {
  _FakeQqApi({
    this.toplistCatalogue = const {},
    this.toplistCp = const {},
    this.toplistDetail = const {},
    this.singerDetail = const {},
    this.singerProfile = const {},
    this.singerAlbums = const {},
    this.albumSearch = const {},
    this.albumInfo = const {},
    this.newSongs = const {},
    this.playlistDetail = const {},
    this.dailyPlaylistId,
    this.cpBuilder,
  });

  final Map<String, dynamic> toplistCatalogue;
  final Map<String, dynamic> toplistCp;
  final Map<String, dynamic> toplistDetail;
  final Map<String, dynamic> singerDetail;
  final Map<String, dynamic> singerProfile;
  final Map<String, dynamic> singerAlbums;
  final Map<String, dynamic> albumSearch;
  final Map<String, dynamic> albumInfo;
  final Map<String, dynamic> newSongs;
  final Map<String, dynamic> playlistDetail;
  final String? dailyPlaylistId;
  final Map<String, dynamic> Function(int topId, int offset, int count)?
  cpBuilder;

  final rankedCalls = <({int topId, int offset, int num})>[];
  final toplistDetailPeriods = <String?>[];
  final singerAlbumCalls = <({String mid, int begin, int num})>[];
  final newSongTypes = <int>[];
  final playlistDetailIds = <String>[];
  int dailyPlaylistIdCalls = 0;

  @override
  Future<Map<String, dynamic>> getToplistCatalogue() async => toplistCatalogue;

  @override
  Future<Map<String, dynamic>> getToplistCp({
    required int topId,
    int offset = 0,
    int num = QqToplistIds.pageSize,
  }) async {
    rankedCalls.add((topId: topId, offset: offset, num: num));
    final builder = cpBuilder;
    if (builder != null) return builder(topId, offset, num);
    return toplistCp;
  }

  @override
  Future<Map<String, dynamic>> getToplistDetail(
    int topId, {
    int offset = 0,
    int num = 100,
    String? period,
  }) async {
    toplistDetailPeriods.add(period);
    return toplistDetail;
  }

  @override
  Future<Map<String, dynamic>> getSingerDetail(String singerMid) async =>
      singerDetail;

  @override
  Future<Map<String, dynamic>> getSingerProfile(String singerMid) async =>
      singerProfile;

  @override
  Future<Map<String, dynamic>> getSingerAlbums(
    String singerMid, {
    int begin = 0,
    int num = 30,
    int order = 1,
  }) async {
    singerAlbumCalls.add((mid: singerMid, begin: begin, num: num));
    return singerAlbums;
  }

  @override
  Future<Map<String, dynamic>> searchAlbums(
    String keyword, {
    int page = 1,
    int limit = 30,
  }) async => albumSearch;

  @override
  Future<Map<String, dynamic>> getAlbumInfo(String albumMid) async => albumInfo;

  @override
  Future<Map<String, dynamic>> getNewSongs({int type = 5}) async {
    newSongTypes.add(type);
    return newSongs;
  }

  @override
  Future<String?> getDailyPlaylistId() async {
    dailyPlaylistIdCalls++;
    return dailyPlaylistId;
  }

  @override
  Future<Map<String, dynamic>> getPlaylistDetail(
    String disstid, {
    int songBegin = 0,
    int songNum = 200,
  }) async {
    playlistDetailIds.add(disstid);
    return playlistDetail;
  }
}
