import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/models/audio_quality.dart';
import 'package:mconnect/platform/qq/qq_platform.dart';
import 'package:mconnect/platform/qq/qq_api.dart';

void main() {
  test(
    'QQ daily playlist parser recognizes the real today-private title',
    () async {
      final api = QqApi(
        dio: _plainTextDio('''
<div class="mod_for_u">
  <div class="playlist__item">
    <a class="playlist__link" data-rid="987654"></a>
    <div class="playlist__name">\u4eca\u65e5\u79c1\u4eab</div>
  </div>
</div>
'''),
      );

      final id = await api.getDailyPlaylistId();

      expect(id, '987654');
    },
  );

  test(
    'QQ lyrics include translated lines when the API returns trans text',
    () async {
      final api = QqApi(
        dio: _jsonDio({
          'lyric': '[00:01.00]Hello',
          'trans': '[00:01.00]Ni hao',
        }),
      );

      final lyric = await api.getLyric('songmid');

      expect(lyric, contains('[00:01.00]Hello'));
      expect(lyric, contains('[00:01.00]Ni hao'));
    },
  );

  test(
    'QQ daily recommendations parse songInfo playlist detail rows',
    () async {
      final platform = QqPlatform(api: _FakeDailyQqApi());

      final songs = await platform.getDailyRecommendations();

      expect(songs, hasLength(1));
      expect(songs.single.id, 'mid1');
      expect(songs.single.name, 'Daily Song');
    },
  );

  test('QQ OAuth cookie builder keeps QQ Music login tokens from QQLogin', () {
    final cookie = QqApi.buildMusicLoginCookieForTest(
      existingCookie: 'p_skey=ps-key; skey=s-key',
      loginData: const {
        'uin': '123456',
        'musicid': '654321',
        'musickey': 'music-token',
      },
    );

    expect(cookie, contains('p_skey=ps-key'));
    expect(cookie, contains('skey=s-key'));
    expect(cookie, contains('uin=o123456'));
    expect(cookie, contains('qqmusic_uin=654321'));
    expect(cookie, contains('qqmusic_key=music-token'));
    expect(cookie, contains('qm_keyst=music-token'));
  });

  test('QQ cookie extraction matches exact cookie names', () {
    final value = QqApi.extractCookieForTest(
      'p_skey=ps-key; skey=s-key',
      'skey',
    );

    expect(value, 's-key');
  });

  test('QQ quality filename prefixes follow current QQ Music file types', () {
    expect(QqApi.filenameForTest('mid1', AudioLevel.low), 'M500mid1mid1.mp3');
    expect(
      QqApi.filenameForTest('mid1', AudioLevel.medium),
      'M800mid1mid1.mp3',
    );
    expect(
      QqApi.filenameForTest('mid1', AudioLevel.lossless),
      'F000mid1mid1.flac',
    );
    expect(
      QqApi.filenameForTest('mid1', AudioLevel.hires),
      'RS01mid1mid1.flac',
    );
    expect(
      QqApi.filenameForTest('mid1', AudioLevel.spatial),
      'Q000mid1mid1.flac',
    );
    expect(
      QqApi.filenameForTest('mid1', AudioLevel.dolby),
      'Q001mid1mid1.flac',
    );
    expect(
      QqApi.filenameForTest('mid1', AudioLevel.master),
      'AI00mid1mid1.flac',
    );
  });

  test(
    'QQ VIP playback request uses logged-in uin and cookie tokens',
    () async {
      final dio = Dio();
      Map<String, dynamic>? capturedBody;
      Map<String, dynamic>? capturedHeaders;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            capturedBody = Map<String, dynamic>.from(options.data as Map);
            capturedHeaders = Map<String, dynamic>.from(options.headers);
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'req_1': {
                    'data': {
                      'sip': ['https://dl.stream.qqmusic.qq.com/'],
                      'midurlinfo': [
                        {'purl': 'F000mid1mid1.flac?vkey=abc'},
                      ],
                    },
                  },
                },
              ),
            );
          },
        ),
      );
      final api = QqApi(dio: dio)
        ..setCookie('uin=o123456; qqmusic_uin=123456; qm_keyst=music-token');

      await api.getSongUrl('mid1', quality: AudioLevel.lossless);

      expect(capturedHeaders?['cookie'], contains('qm_keyst=music-token'));
      expect(capturedBody?['loginUin'], '123456');
      expect(capturedBody?['comm']?['uin'], '123456');
      final dispatchParam = capturedBody?['req_0']?['param'] as Map;
      final vkeyParam = capturedBody?['req_1']?['param'] as Map;
      expect(dispatchParam['guid'], isNot('0'));
      expect(vkeyParam['guid'], dispatchParam['guid']);
      expect(vkeyParam['uin'], '123456');
      expect(vkeyParam['filename'], ['F000mid1mid1.flac']);
      expect(vkeyParam['loginflag'], 1);
    },
  );
}

Dio _plainTextDio(String body) {
  final dio = Dio();
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        handler.resolve(
          Response(requestOptions: options, statusCode: 200, data: body),
        );
      },
    ),
  );
  return dio;
}

Dio _jsonDio(Map<String, dynamic> body) {
  final dio = Dio();
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        handler.resolve(
          Response(requestOptions: options, statusCode: 200, data: body),
        );
      },
    ),
  );
  return dio;
}

class _FakeDailyQqApi extends QqApi {
  @override
  Future<String?> getDailyPlaylistId() async => '123456';

  @override
  Future<Map<String, dynamic>> getPlaylistDetail(
    String disstid, {
    int songBegin = 0,
    int songNum = 200,
  }) async {
    return {
      'req_0': {
        'data': {
          'songlist': [
            {
              'songInfo': {
                'mid': 'mid1',
                'name': 'Daily Song',
                'singer': [
                  {'mid': 'artist1', 'name': 'Artist 1'},
                ],
                'interval': 180,
              },
            },
          ],
        },
      },
    };
  }

  @override
  Future<Map<String, dynamic>> getDailyRecommend() async => const {};
}
