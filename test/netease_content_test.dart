// WS-B 单测：网易云 艺人 / 专辑 / 新歌 / 榜单
//
// 手法与 `test/netease_api_test.dart:11-33` 一致：真 Dio + `InterceptorsWrapper`
// → `handler.resolve(...)`，既 stub 响应又捕获请求（路径/参数）。
//
// 所有断言基于 `docs/netease-wave-b-probe.md` 实测到的真实返回形状：
//   * 榜单 `list[].{id,name,coverImgUrl,updateFrequency,trackCount}`
//   * 艺人 `head/info/get` → `data.artist`；旧接口 → `artist` + `hotSongs`
//   * 专辑 `v1/album/{id}` → `album{}` + **顶层** `songs[]`（`no` 为 1..N）
//   * 新歌 `v1/discovery/new/songs` → `data[]`（`limit` 被服务端忽略）
//   * 兜底 `personalized/newsong` → `result[].song`，`type` 是 **int 4**
//   * 排名 `v6/playlist/detail` 的 `n` 就是"前 n 首"
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/core/network/api_exception.dart';
import 'package:mconnect/core/network/platform_http.dart';
import 'package:mconnect/platform/base/music_platform.dart';
import 'package:mconnect/platform/netease/netease_api.dart';
import 'package:mconnect/platform/netease/netease_platform.dart';

const _kArtistId = '6452';

void main() {
  // ---------------------------------------------------------------- getToplists

  test('getToplists maps /api/toplist list[] onto Toplist', () async {
    final log = <RequestOptions>[];
    final platform = _platform({
      '/api/toplist': {
        'code': 200,
        'list': [
          {
            'id': 3778678,
            'name': '热歌榜',
            'coverImgUrl': 'https://p1.example/hot.jpg',
            'updateFrequency': '刚刚更新',
            'trackCount': 200,
            // 真实响应里没有 trackNumberUpdate，只有 *UpdateTime 时间戳。
            'trackNumberUpdateTime': 1791247481977,
          },
          {
            'id': 19723756,
            'name': '飙升榜',
            'coverImgUrl': 'https://p2.example/rise.jpg',
            'updateFrequency': '每天更新',
            'trackCount': 100,
          },
        ],
        'artistToplist': {'name': '歌手榜'},
      },
    }, log: log);

    final toplists = await platform.getToplists();

    expect(log.single.path, '/api/toplist');
    expect(toplists, hasLength(2));
    expect(toplists.first.id, '3778678');
    expect(toplists.first.name, '热歌榜');
    expect(toplists.first.coverUrl, 'https://p1.example/hot.jpg');
    expect(toplists.first.updateFrequency, '刚刚更新');
    expect(toplists.first.songCount, 200);
    expect(toplists.last.songCount, 100);
  });

  test('getToplists drops entries without id or name', () async {
    final platform = _platform({
      '/api/toplist': {
        'code': 200,
        'list': [
          {'id': 1, 'name': 'OK'},
          {'name': '没有 id'},
          {'id': 2},
        ],
      },
    });

    final toplists = await platform.getToplists();

    expect(toplists.map((t) => t.name), ['OK']);
  });

  // ------------------------------------------------------------- getArtistDetail

  test('getArtistDetail prefers /api/artist/head/info/get', () async {
    final log = <RequestOptions>[];
    final platform = _platform({
      '/api/artist/head/info/get': {
        'code': 200,
        'message': 'ok',
        'data': {
          'artist': {
            'id': 6452,
            'name': '周杰伦',
            'cover': 'https://p3.example/cover.jpg',
            'avatar': 'https://p4.example/avatar.jpg',
            'briefDesc': '周杰伦（Jay Chou）…',
            'musicSize': 568,
            'albumSize': 44,
          },
        },
      },
    }, log: log);

    final artist = await platform.getArtistDetail(_kArtistId);

    expect(log.single.path, '/api/artist/head/info/get');
    expect(log.single.data, {'id': _kArtistId});
    expect(artist, isNotNull);
    expect(artist!.id, '6452');
    expect(artist.name, '周杰伦');
    expect(artist.avatarUrl, 'https://p3.example/cover.jpg');
    expect(artist.briefDesc, '周杰伦（Jay Chou）…');
    expect(artist.songCount, 568);
    expect(artist.albumCount, 44);
    // 实测两个端点都不返回 fansCount：宁可 null 也不编造。
    expect(artist.fansCount, isNull);
  });

  test('getArtistDetail falls back to legacy /api/artist/{id}', () async {
    final log = <RequestOptions>[];
    final platform = _platform({
      // head/info/get 应答正常但没有 artist（例如该端点被下线/返回空 data）。
      '/api/artist/head/info/get': {'code': 200, 'data': {}},
      '/api/artist/6452': {
        'code': 200,
        'artist': {
          'id': 6452,
          'name': '周杰伦',
          'picUrl': 'https://p4.example/pic.jpg',
          'briefDesc': '',
          'musicSize': 568,
          'albumSize': 44,
        },
        'hotSongs': [],
        'more': true,
      },
    }, log: log);

    final artist = await platform.getArtistDetail(_kArtistId);

    expect(log.map((o) => o.path), [
      '/api/artist/head/info/get',
      '/api/artist/6452',
    ]);
    expect(artist, isNotNull);
    expect(artist!.name, '周杰伦');
    expect(artist.avatarUrl, 'https://p4.example/pic.jpg');
    expect(artist.songCount, 568);
    expect(artist.albumCount, 44);
  });

  test('getArtistDetail returns null when the platform has no such artist', () async {
    final platform = _platform({
      '/api/artist/head/info/get': {'code': 200, 'data': {}},
      '/api/artist/6452': {'code': 200, 'artist': null},
    });

    expect(await platform.getArtistDetail(_kArtistId), isNull);
  });

  test('getArtistDetail surfaces a typed exception when nothing answers', () async {
    // 两个端点都没有 stub → 两次连接错误，必须抛 ApiException（翻译后），
    // 而不是裸 Exception，也不是"没有这个艺人"的 null。
    final platform = _platform(const {});

    await expectLater(
      platform.getArtistDetail(_kArtistId),
      throwsA(isA<ApiException>()),
    );
  });

  // ----------------------------------------------------------- getArtistTopSongs

  test('getArtistTopSongs parses /api/artist/top/song ar/al/dt shape', () async {
    final log = <RequestOptions>[];
    final platform = _platform({
      '/api/artist/top/song': {
        'code': 200,
        'songs': [
          _newShapeSong(210049, '布拉格广场'),
          _newShapeSong(185809, '以父之名'),
          _newShapeSong(185811, '晴天'),
        ],
      },
    }, log: log);

    final songs = await platform.getArtistTopSongs(_kArtistId, limit: 2);

    expect(log.single.path, '/api/artist/top/song');
    expect(log.single.queryParameters['id'], _kArtistId);
    expect(songs, hasLength(2));
    expect(songs.first.name, '布拉格广场');
    expect(songs.first.artists.single.name, '周杰伦');
    expect(songs.first.album?.name, '专辑');
    expect(songs.first.coverUrl, 'https://p.example/cover.jpg');
    expect(songs.first.duration, const Duration(milliseconds: 180000));
  });

  test('getArtistTopSongs falls back to legacy hotSongs (artists/album/duration)', () async {
    final log = <RequestOptions>[];
    final platform = _platform({
      '/api/artist/top/song': {'code': 200, 'songs': <dynamic>[]},
      '/api/artist/6452': {
        'code': 200,
        'artist': {'id': 6452, 'name': '周杰伦'},
        'hotSongs': [
          _legacyShapeSong(1, '旧形状一首'),
          _legacyShapeSong(2, '旧形状二首'),
        ],
      },
    }, log: log);

    final songs = await platform.getArtistTopSongs(_kArtistId);

    expect(log.map((o) => o.path), [
      '/api/artist/top/song',
      '/api/artist/6452',
    ]);
    expect(songs, hasLength(2));
    expect(songs.first.name, '旧形状一首');
    // 旧接口用 artists/album/duration；只认 ar/al/dt 的解析器会把这里读成空。
    expect(songs.first.artists.single.name, '周杰伦');
    expect(songs.first.album?.name, '专辑');
    expect(songs.first.coverUrl, 'https://p.example/legacy.jpg');
    expect(songs.first.duration, const Duration(milliseconds: 200000));
  });

  // ------------------------------------------------------------ getArtistAlbums

  test('getArtistAlbums sends limit/offset and maps hotAlbums fields', () async {
    final log = <RequestOptions>[];
    final platform = _platform({
      '/api/artist/albums/6452': {
        'code': 200,
        'more': true,
        'hotAlbums': [
          {
            'id': 274336916,
            'name': '即兴曲',
            'picUrl': 'https://p3.example/album.jpg',
            'publishTime': 1749139200000,
            'size': 3,
            'company': '杰威尔',
            'description': '置身Beatles录音室',
            'artist': {'id': 6452, 'name': '周杰伦'},
            'tags': ['流行'],
          },
        ],
      },
    }, log: log);

    final albums = await platform.getArtistAlbums(
      _kArtistId,
      page: 3,
      limit: 10,
    );

    expect(log.single.path, '/api/artist/albums/6452');
    // page=3, limit=10 → offset 20
    expect(log.single.queryParameters['limit'], 10);
    expect(log.single.queryParameters['offset'], 20);
    expect(albums, hasLength(1));
    expect(albums.single.id, '274336916');
    expect(albums.single.name, '即兴曲');
    expect(albums.single.coverUrl, 'https://p3.example/album.jpg');
    expect(albums.single.songCount, 3);
    expect(albums.single.company, '杰威尔');
    expect(albums.single.artistName, '周杰伦');
    expect(albums.single.artistId, '6452');
    expect(albums.single.genre, '流行');
    expect(
      albums.single.releaseDate,
      DateTime.fromMillisecondsSinceEpoch(1749139200000),
    );
  });

  // --------------------------------------------------------------- getAlbumDetail

  test('getAlbumDetail maps album{} and leaves unavailable genre null', () async {
    final log = <RequestOptions>[];
    final platform = _platform({
      '/api/v1/album/2489195': {
        'code': 200,
        'songs': <dynamic>[],
        'album': {
          'id': 2489195,
          'name': '天台 电影原声带',
          'picUrl': 'https://p5.example/album.jpg',
          'publishTime': 1370448000000,
          'size': 35,
          'company': '杰威尔',
          'description': '电影原声带',
          'artist': {'id': 6452, 'name': '周杰伦'},
          // 实测没有 genre 字段，tags 为空数组时 genre 必须是 null。
          'tags': <dynamic>[],
        },
      },
    }, log: log);

    final album = await platform.getAlbumDetail('2489195');

    expect(log.single.path, '/api/v1/album/2489195');
    expect(album, isNotNull);
    expect(album!.name, '天台 电影原声带');
    expect(album.songCount, 35);
    expect(album.company, '杰威尔');
    expect(album.artistName, '周杰伦');
    expect(album.artistId, '6452');
    expect(album.genre, isNull);
  });

  test('getAlbumSongs reads top-level songs[] and orders by trackNumber', () async {
    final platform = _platform({
      '/api/v1/album/2489195': {
        'code': 200,
        'album': {
          'id': 2489195,
          'name': '天台 电影原声带',
          // album.songs 在真实响应里是空数组——读它就会得到 0 首。
          'songs': <dynamic>[],
        },
        // 故意乱序，验证按 no 排序而不是照抄服务端顺序。
        'songs': [
          _newShapeSong(3, '第三首', no: 3),
          _newShapeSong(1, '第一首', no: 1),
          _newShapeSong(2, '第二首', no: 2),
        ],
      },
    });

    final songs = await platform.getAlbumSongs('2489195');

    expect(songs.map((s) => s.name), ['第一首', '第二首', '第三首']);
    expect(songs.map((s) => s.trackNumber), [1, 2, 3]);
  });

  // ------------------------------------------------------------------ getNewSongs

  test('getNewSongs slices the fixed 100-item area payload to limit', () async {
    final log = <RequestOptions>[];
    final platform = _platform({
      '/api/v1/discovery/new/songs': {
        'code': 200,
        // 实测：服务端忽略 limit，永远返回 100 条。
        'data': [
          for (var i = 1; i <= 100; i++) _legacyShapeSong(i, '新歌$i'),
        ],
      },
    }, log: log);

    final songs = await platform.getNewSongs(limit: 3);

    expect(log.single.path, '/api/v1/discovery/new/songs');
    expect(log.single.queryParameters['areaId'], 0);
    expect(songs, hasLength(3));
    expect(songs.first.name, '新歌1');
    // 该端点用 artists/album/duration 命名（probe 7f）。
    expect(songs.first.artists.single.name, '周杰伦');
  });

  test('getNewSongs maps each region onto its own areaId', () async {
    final areaIds = <int>[];
    final dio = Dio(BaseOptions(baseUrl: 'https://music.163.com'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          areaIds.add(options.queryParameters['areaId'] as int);
          handler.resolve(
            Response(
              requestOptions: options,
              statusCode: 200,
              data: {
                'code': 200,
                'data': [_legacyShapeSong(1, '歌')],
              },
            ),
          );
        },
      ),
    );
    final platform = NeteasePlatform(api: NeteaseApi(dio: dio));

    await platform.getNewSongs(region: NewSongRegion.all);
    await platform.getNewSongs(region: NewSongRegion.chinese);
    await platform.getNewSongs(region: NewSongRegion.western);
    await platform.getNewSongs(region: NewSongRegion.japanese);
    await platform.getNewSongs(region: NewSongRegion.korean);

    expect(areaIds, [0, 7, 96, 8, 16]);
  });

  test('getNewSongs honestly refuses the unsupported 港台 region', () async {
    final platform = _platform(const {});

    await expectLater(
      platform.getNewSongs(region: NewSongRegion.hongKongTaiwan),
      throwsA(
        isA<UnsupportedActionException>().having(
          (e) => e.message,
          'message',
          contains('暂不支持'),
        ),
      ),
    );
  });

  test(
    'getNewSongs falls back to personalized/newsong and filters type==4 (int), not the string "song"',
    () async {
      final log = <RequestOptions>[];
      final platform = _platform({
        // 地区端点应答但没有 data → 走兜底。
        '/api/v1/discovery/new/songs': {'code': 200},
        '/api/personalized/newsong': {
          'code': 200,
          'category': 5,
          'result': [
            // 实测真实条目的 type 是 int 4（probe 7b）。
            {'id': 1, 'type': 4, 'name': 'A', 'song': _legacyShapeSong(11, 'A')},
            // 非歌曲条目（比如电台/MV）要滤掉。
            {'id': 2, 'type': 1, 'name': 'B', 'song': _legacyShapeSong(12, 'B')},
            // 有 type 但没有 song 子对象也要滤掉。
            {'id': 3, 'type': 4, 'name': 'C'},
            // 极少数历史响应用字符串 'song'，一并接受。
            {'id': 4, 'type': 'song', 'name': 'D', 'song': _legacyShapeSong(14, 'D')},
          ],
        },
      }, log: log);

      final songs = await platform.getNewSongs();

      expect(log.map((o) => o.path), [
        '/api/v1/discovery/new/songs',
        '/api/personalized/newsong',
      ]);
      expect(songs.map((s) => s.name), ['A', 'D']);
      // 按任务书写的 `type == 'song'` 过滤会得到 0 首——这里钉住正确行为。
      expect(songs, isNotEmpty);
      expect(songs.first.id, '11');
    },
  );

  test('getNewSongs does not fake a region list when the area call fails', () async {
    final platform = _platform({
      // 只有兜底端点有 stub；华语请求失败时不许用"全部新歌"冒充华语新歌。
      '/api/personalized/newsong': {
        'code': 200,
        'result': [
          {'id': 1, 'type': 4, 'name': 'A', 'song': _legacyShapeSong(11, 'A')},
        ],
      },
    });

    await expectLater(
      platform.getNewSongs(region: NewSongRegion.chinese),
      throwsA(isA<ApiException>()),
    );
  });

  // ----------------------------------------------------------------- getRankedSongs

  test('getRankedSongs ranks by global index and honours offset/num', () async {
    final log = <RequestOptions>[];
    final platform = _platform({
      '/api/v6/playlist/detail': {
        'code': 200,
        'playlist': {
          'id': 3778678,
          'name': '热歌榜',
          'trackCount': 5,
          'tracks': [
            _newShapeSong(101, '第一首'),
            _newShapeSong(102, '第二首'),
            _newShapeSong(103, '第三首'),
            _newShapeSong(104, '第四首'),
          ],
          'trackIds': [
            {'id': 101},
            {'id': 102},
            {'id': 103},
            {'id': 104},
          ],
        },
      },
    }, log: log);

    final ranked = await platform.getRankedSongs('3778678', offset: 1, num: 2);

    // `n` 实测就是"前 n 首"，所以 offset+num 一次取回再本地切片。
    expect(log.single.path, '/api/v6/playlist/detail');
    expect(log.single.data, {'id': '3778678', 'n': 3});
    expect(ranked.map((r) => r.rank), [2, 3]);
    expect(ranked.map((r) => r.song.name), ['第二首', '第三首']);
    expect(ranked.first.song.id, '102');
  });

  test('getRankedSongs fills the window through trackIds + song detail', () async {
    final log = <RequestOptions>[];
    final platform = _platform({
      '/api/v6/playlist/detail': {
        'code': 200,
        'playlist': {
          'id': 3778678,
          // 服务端只给了前 2 首，trackIds 是完整的 5 个。
          'tracks': [
            _newShapeSong(201, '第一首'),
            _newShapeSong(202, '第二首'),
          ],
          'trackIds': [
            {'id': 201},
            {'id': 202},
            {'id': 203},
            {'id': 204},
            {'id': 205},
          ],
        },
      },
      '/api/v3/song/detail': {
        'code': 200,
        'songs': [
          _newShapeSong(203, '第三首'),
          _newShapeSong(204, '第四首'),
        ],
      },
    }, log: log);

    final ranked = await platform.getRankedSongs('3778678', offset: 2, num: 2);

    expect(log.map((o) => o.path), [
      '/api/v6/playlist/detail',
      '/api/v3/song/detail',
    ]);
    expect(log.first.data, {'id': '3778678', 'n': 4});
    // 缺口只请求窗口内的 id，且只发一次（不再重复已加载的 1/2）。
    expect(log.last.data?['ids'], '[203,204]');
    expect(ranked.map((r) => r.rank), [3, 4]);
    expect(ranked.map((r) => r.song.name), ['第三首', '第四首']);
  });

  test('getRankedSongs returns empty when the offset is past the chart', () async {
    final platform = _platform({
      '/api/v6/playlist/detail': {
        'code': 200,
        'playlist': {
          'tracks': [_newShapeSong(1, '唯一一首')],
          'trackIds': [
            {'id': 1},
          ],
        },
      },
    });

    expect(await platform.getRankedSongs('1', offset: 5, num: 10), isEmpty);
  });

  test('getRankingList now goes through the ranked chart path', () async {
    final log = <RequestOptions>[];
    final platform = _platform({
      '/api/v6/playlist/detail': {
        'code': 200,
        'playlist': {
          'name': '热歌榜',
          'tracks': [
            for (var i = 1; i <= 30; i++) _newShapeSong(i, '热歌$i'),
          ],
          'trackIds': [for (var i = 1; i <= 30; i++) {'id': i}],
        },
      },
    }, log: log);

    final songs = await platform.getRankingList();

    expect(log.single.data, {'id': '3778678', 'n': 30});
    expect(songs, hasLength(30));
    expect(songs.last.name, '热歌30');
  });

  // ------------------------------------------------------- Dio factory wiring

  test('a cancelled artist query is not answered from the legacy fallback', () async {
    final log = <RequestOptions>[];
    final platform = _platform({
      // 兜底端点有数据，但请求是被取消的 —— 不许拿它当"成功"。
      '/api/artist/6452': {
        'code': 200,
        'artist': {'id': 6452, 'name': '周杰伦'},
      },
    }, log: log, cancelPaths: {'/api/artist/head/info/get'});

    await expectLater(
      platform.getArtistDetail(_kArtistId),
      throwsA(isA<RequestCancelledException>()),
    );
    expect(log.map((o) => o.path), ['/api/artist/head/info/get']);
  });

  test('a cancelled 华语 new-song query is not answered from the fallback', () async {
    final log = <RequestOptions>[];
    final platform = _platform({
      '/api/personalized/newsong': {
        'code': 200,
        'result': [
          {'id': 1, 'type': 4, 'name': 'A', 'song': _legacyShapeSong(11, 'A')},
        ],
      },
    }, log: log, cancelPaths: {'/api/v1/discovery/new/songs'});

    await expectLater(
      platform.getNewSongs(region: NewSongRegion.chinese),
      throwsA(isA<RequestCancelledException>()),
    );
    expect(log.map((o) => o.path), ['/api/v1/discovery/new/songs']);
  });

  test('NeteaseApi default Dio comes from createPlatformDio', () {
    final api = NeteaseApi();

    expect(api.dio.options.baseUrl, 'https://music.163.com');
    // 此前适配器自建裸 Dio → RetryInterceptor / 错误翻译全是死代码。
    expect(api.dio.interceptors.whereType<IdempotentRetryGuard>(), isNotEmpty);
    expect(api.dio.interceptors.whereType<PlatformErrorInterceptor>(), isNotEmpty);
    expect(api.dio.options.sendTimeout, isNotNull);
    expect(api.dio.options.headers['cookie'], contains('os=pc'));
  });

  test('HTTP failures are translated into typed ApiExceptions', () async {
    final dio = createPlatformDio(
      label: '网易云音乐',
      baseUrl: 'https://music.163.com',
      maxRetries: 0,
    )..httpClientAdapter = _JsonStatusAdapter(404, '{"code":404}');
    final platform = NeteasePlatform(api: NeteaseApi(dio: dio));

    await expectLater(platform.getToplists(), throwsA(isA<NotFoundException>()));
  });

  // --------------------------------------------------------- typed playback errors

  test('Netease playback exposes typed errors instead of raw Exception', () async {
    final platform = NeteasePlatform(api: _FakePlaybackApi('trial'));
    await expectLater(
      platform.getSongUrl('1'),
      throwsA(isA<NoVipMembershipException>()),
    );

    final vipOnly = NeteasePlatform(api: _FakePlaybackApi('vip'));
    await expectLater(
      vipOnly.getSongUrl('1'),
      throwsA(isA<NoVipMembershipException>()),
    );

    final gone = NeteasePlatform(api: _FakePlaybackApi('gone'));
    await expectLater(
      gone.getSongUrl('1'),
      throwsA(isA<SongNotAvailableException>()),
    );
  });
}

// ---------------------------------------------------------------------- helpers

/// Builds a [NeteasePlatform] whose [NeteaseApi] answers from [responses] keyed by
/// request path; a path with no entry is a connection error (so the platform's
/// graceful-degradation / fallback branches can be exercised).
NeteasePlatform _platform(
  Map<String, Object?> responses, {
  List<RequestOptions>? log,
  Set<String> cancelPaths = const {},
}) {
  final dio = Dio(BaseOptions(baseUrl: 'https://music.163.com'));
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        log?.add(options);
        if (cancelPaths.contains(options.path)) {
          handler.reject(
            DioException(
              requestOptions: options,
              type: DioExceptionType.cancel,
              message: 'cancelled',
            ),
          );
          return;
        }
        if (!responses.containsKey(options.path)) {
          handler.reject(
            DioException(
              requestOptions: options,
              type: DioExceptionType.connectionError,
              message: 'no stub for ${options.path}',
            ),
          );
          return;
        }
        handler.resolve(
          Response(
            requestOptions: options,
            statusCode: 200,
            data: responses[options.path],
          ),
        );
      },
    ),
  );
  return NeteasePlatform(api: NeteaseApi(dio: dio));
}

/// 新接口形状：`ar` / `al` / `dt`。
Map<String, dynamic> _newShapeSong(int id, String name, {int? no, int dt = 180000}) {
  return {
    'id': id,
    'name': name,
    'no': no,
    'dt': dt,
    'fee': 0,
    'ar': [
      {'id': 6452, 'name': '周杰伦'},
    ],
    'al': {'id': 21349, 'name': '专辑', 'picUrl': 'https://p.example/cover.jpg'},
  };
}

/// 旧接口形状：`artists` / `album` / `duration`。
Map<String, dynamic> _legacyShapeSong(
  int id,
  String name, {
  int no = 1,
  int duration = 200000,
}) {
  return {
    'id': id,
    'name': name,
    'no': no,
    'duration': duration,
    'fee': 0,
    'artists': [
      {'id': 6452, 'name': '周杰伦'},
    ],
    'album': {
      'id': 21349,
      'name': '专辑',
      'picUrl': 'https://p.example/legacy.jpg',
    },
  };
}

/// 直接按状态码回一个 JSON 体的适配器，用来验证错误翻译（不需要网络）。
class _JsonStatusAdapter implements HttpClientAdapter {
  _JsonStatusAdapter(this.statusCode, this.body);

  final int statusCode;
  final String body;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      body,
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _FakePlaybackApi extends NeteaseApi {
  _FakePlaybackApi(this.mode);

  final String mode;

  @override
  Future<Map<String, dynamic>> getSongUrl(
    String songId, {
    String level = 'exhigh',
  }) async {
    switch (mode) {
      case 'trial':
        return {
          'data': [
            {
              'url': 'https://m701.example/trial.mp3',
              'level': 'standard',
              'br': 128000,
              'freeTrialInfo': {'start': 0, 'end': 30000},
            },
          ],
        };
      case 'vip':
        return {
          'data': [
            {'url': null, 'level': 'none', 'fee': 1},
          ],
        };
      default:
        return {
          'data': <dynamic>[],
        };
    }
  }
}
