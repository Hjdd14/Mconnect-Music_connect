import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/core/network/api_exception.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/recommendation_source.dart';
import 'package:mconnect/platform/kugou/kugou_api.dart';
import 'package:mconnect/platform/kugou/kugou_platform.dart';

/// WS-D: 酷狗官方推荐接口已被服务端下线（探针：5 种签名变体全部返回
/// `Access Deny ! No Actions !`，HTTP 200 + 非 JSON 正文）。这里锁死两件事：
///   1. 接口被拒时必须回落到 `m.kugou.com/?json=true` 的首页推荐；
///   2. 来源必须被标注成 [RecommendationKind.fallbackHomepage] + note，
///      而不是被当成"每日推荐"；失败也不能被静默吞成空列表。
void main() {
  test('refused official endpoint falls back to homepage and is labelled', () async {
    final platform = KugouPlatform(api: _RefusedRecommendApi());

    final result = await platform.getDailyRecommendation();

    // 2 songs from `data` + 2 more from the `special` module (one of its hashes
    // repeats a `data` hash and must not be added twice).
    expect(result.songs, hasLength(4));
    expect(result.songs.first.name, '我们在场');
    expect(result.songs.first.id, 'HASH_HOME_1');
    expect(result.source, isNotNull);
    expect(result.source!.platform, PlatformType.kugou);
    expect(result.source!.kind, RecommendationKind.fallbackHomepage);
    expect(result.source!.label, '酷狗推荐');
    expect(result.source!.note, '官方推荐接口已不可用，来源为首页推荐');
    expect(result.source!.isPersonalized, isFalse);
    expect(result.error, isNull);
  });

  test('the WAF answer is what triggers the fallback (red→green)', () async {
    // The server answers HTTP 200 with `Access Deny ! No Actions !`; the API
    // layer must surface that as an error instead of an empty success.
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.uri.toString().contains('recommend/song')) {
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: 'Access Deny ! No Actions ! ',
              ),
            );
            return;
          }
          handler.resolve(
            Response(
              requestOptions: options,
              statusCode: 200,
              data: _homepagePayload,
            ),
          );
        },
      ),
    );
    final platform = KugouPlatform(api: KugouApi(dio: dio));

    final result = await platform.getDailyRecommendation();

    expect(result.source!.kind, RecommendationKind.fallbackHomepage);
    expect(result.source!.note, '官方推荐接口已不可用，来源为首页推荐');
    expect(result.songs, isNotEmpty);
  });

  test('homepage failure is surfaced, never a silent empty list', () async {
    final platform = KugouPlatform(api: _HomepageFailureApi());

    final result = await platform.getDailyRecommendation();

    expect(result.songs, isEmpty);
    expect(result.error, '酷狗接口拒绝访问');
    expect(result.source!.kind, RecommendationKind.unavailable);
    expect(result.source!.note, '酷狗接口拒绝访问');
  });

  test('an empty homepage module is reported as unavailable', () async {
    final platform = KugouPlatform(api: _EmptyHomepageApi());

    final result = await platform.getDailyRecommendation();

    expect(result.songs, isEmpty);
    expect(result.error, '酷狗推荐暂不可用');
    expect(result.source!.kind, RecommendationKind.unavailable);
  });

  test('homepage data is de-duplicated and the special module is merged in', () async {
    final platform = KugouPlatform(api: _RefusedRecommendApi());

    final songs = await platform.fetchHomepageRecommendations();

    // 2 from `data` + 1 non-duplicate from `special` (the other one repeats a
    // `data` hash) + 1 without a hash but with a distinct title.
    expect(songs.map((s) => s.id), [
      'HASH_HOME_1',
      'HASH_HOME_2',
      'HASH_SPECIAL_1',
      '',
    ]);
    expect(songs.map((s) => s.name), [
      '我们在场',
      '第二首',
      '歌单里的歌',
      '无 hash 的一首',
    ]);
  });

  test('legacy getDailyRecommendations returns the same fallback songs', () async {
    final platform = KugouPlatform(api: _RefusedRecommendApi());

    final songs = await platform.getDailyRecommendations();

    expect(songs, hasLength(4));
    expect(songs.first.id, 'HASH_HOME_1');
  });

  test('a live official endpoint still wins and is labelled personalised', () async {
    final platform = KugouPlatform(api: _LiveOfficialRecommendApi());

    final result = await platform.getDailyRecommendation();

    expect(result.source!.kind, RecommendationKind.personalizedDaily);
    expect(result.songs.single.id, 'HASH_OFFICIAL');
  });

  test('capabilities reflect what is actually implemented', () {
    final platform = KugouPlatform(api: _RefusedRecommendApi());

    expect(platform.supportsDailyRecommendations, isTrue);
    expect(platform.supportsArtistPage, isTrue);
    expect(platform.supportsAlbumPage, isTrue);
    expect(platform.supportsPhoneLogin, isFalse);
    expect(platform.supportsNewSongs, isFalse);
  });

  test('getRecommend surfaces the refused body as an ApiException', () async {
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) => handler.resolve(
          Response(
            requestOptions: options,
            statusCode: 200,
            data: 'Access Deny ! No Actions ! ',
          ),
        ),
      ),
    );

    await expectLater(
      KugouApi(dio: dio).getRecommend(),
      throwsA(
        isA<ApiException>().having(
          (e) => e.message,
          'message',
          '酷狗接口拒绝访问',
        ),
      ),
    );
  });
}

final Map<String, dynamic> _homepagePayload = {
  'data': [
    {
      'hash': 'HASH_HOME_1',
      'filename': '周深、王者荣耀 - 我们在场',
      'songname': '我们在场',
      'singer_name': '周深、王者荣耀',
      'authors': [
        {'author_id': 169967, 'author_name': '周深'},
        {'author_id': 645596, 'author_name': '王者荣耀'},
      ],
      'album_id': '209454115',
      'duration': 200,
      '320hash': 'HASH_HOME_1_320',
      'sqhash': 'HASH_HOME_1_SQ',
      'trans_param': {
        'union_cover': 'http://imge.kugou.com/stdmusic/{size}/cover1.jpg',
      },
    },
    {
      'hash': 'HASH_HOME_2',
      'filename': '某歌手 - 第二首',
      'songname': '第二首',
      'singername': '某歌手',
      'duration': 180,
    },
  ],
  'special': {
    'list': {
      'pagesize': 10,
      'info': [
        {
          'specialname': '歌单 A',
          'songs': [
            // Duplicate of `data[0]` — must be de-duplicated by hash.
            {'hash': 'HASH_HOME_1', 'songname': '我们在场'},
            {'hash': 'HASH_SPECIAL_1', 'songname': '歌单里的歌', 'singername': '甲'},
            {'hash': '', 'songname': '无 hash 的一首', 'singername': '乙'},
          ],
        },
      ],
    },
  },
  'rank': {'total': 55, 'list': []},
};

/// Official endpoint refused (what production does), homepage available.
class _RefusedRecommendApi extends KugouApi {
  @override
  Future<Map<String, dynamic>> getRecommend() async {
    throw ApiException(message: '酷狗接口拒绝访问', details: 'Access Deny ! No Actions ! ');
  }

  @override
  Future<Map<String, dynamic>> getHomepage() async => _homepagePayload;
}

/// Both endpoints refused.
class _HomepageFailureApi extends _RefusedRecommendApi {
  @override
  Future<Map<String, dynamic>> getHomepage() async {
    throw ApiException(message: '酷狗接口拒绝访问', details: 'Access Deny ! No Actions ! ');
  }
}

/// Homepage answers but carries no songs at all.
class _EmptyHomepageApi extends _RefusedRecommendApi {
  @override
  Future<Map<String, dynamic>> getHomepage() async => {
    'data': <dynamic>[],
    'special': {'list': {'info': <dynamic>[]}},
  };
}

/// Forward compatibility: if 酷狗 ever restores the official endpoint.
class _LiveOfficialRecommendApi extends KugouApi {
  @override
  Future<Map<String, dynamic>> getRecommend() async => {
    'status': 1,
    'data': {
      'info': [
        {'hash': 'HASH_OFFICIAL', 'songname': '官方推荐', 'singername': '歌手'},
      ],
    },
  };

  @override
  Future<Map<String, dynamic>> getHomepage() async => _homepagePayload;
}
