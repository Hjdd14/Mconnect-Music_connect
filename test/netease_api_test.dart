import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/models/audio_quality.dart';
import 'package:mconnect/platform/netease/netease_api.dart';
import 'package:mconnect/platform/netease/netease_platform.dart';

void main() {
  test(
    'Netease playlist detail caps requested track count to avoid UI stalls',
    () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://music.163.com'));
      Map<String, dynamic>? capturedData;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            capturedData = Map<String, dynamic>.from(options.data as Map);
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'playlist': {'tracks': []},
                },
              ),
            );
          },
        ),
      );

      await NeteaseApi(dio: dio).getPlaylistDetail('123');

      expect(capturedData, isNotNull);
      expect(capturedData!['n'], lessThanOrEqualTo(1000));
    },
  );

  test(
    'Netease lyrics include translated lines when tlyric is available',
    () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://music.163.com'));
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'lrc': {'lyric': '[00:01.00]Hello'},
                  'tlyric': {'lyric': '[00:01.00]Ni hao'},
                },
              ),
            );
          },
        ),
      );

      final lyric = await NeteasePlatform(
        api: NeteaseApi(dio: dio),
      ).getLyrics('1');

      expect(lyric, contains('[00:01.00]Hello'));
      expect(lyric, contains('[00:01.00]Ni hao'));
    },
  );

  test('Netease quality levels map to current song url v1 level names', () {
    expect(NeteasePlatform.levelNameForTest(AudioLevel.low), 'standard');
    expect(NeteasePlatform.levelNameForTest(AudioLevel.medium), 'higher');
    expect(NeteasePlatform.levelNameForTest(AudioLevel.high), 'exhigh');
    expect(NeteasePlatform.levelNameForTest(AudioLevel.lossless), 'lossless');
    expect(NeteasePlatform.levelNameForTest(AudioLevel.hires), 'hires');
    expect(NeteasePlatform.levelNameForTest(AudioLevel.spatial), 'jyeffect');
    expect(NeteasePlatform.levelNameForTest(AudioLevel.dolby), 'sky');
    expect(NeteasePlatform.levelNameForTest(AudioLevel.master), 'jymaster');
  });

  test(
    'Netease VIP playback request keeps login cookie and requested level',
    () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://music.163.com'));
      RequestOptions? capturedOptions;
      Map<String, dynamic>? capturedData;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            capturedOptions = options;
            capturedData = Map<String, dynamic>.from(options.data as Map);
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'data': [
                    {
                      'url': 'https://m701.music.126.net/song.flac',
                      'level': 'jymaster',
                      'br': 999000,
                    },
                  ],
                },
              ),
            );
          },
        ),
      );
      final api = NeteaseApi(dio: dio)
        ..restoreCookie('MUSIC_U=vip-cookie; __csrf=csrf-1');

      await api.getSongUrl('123', level: 'jymaster');

      expect(capturedOptions, isNotNull);
      expect(capturedOptions!.path, '/api/song/enhance/player/url/v1');
      expect(
        capturedOptions!.headers['cookie'],
        contains('MUSIC_U=vip-cookie'),
      );
      expect(capturedData?['ids'], '["123"]');
      expect(capturedData?['level'], 'jymaster');
      expect(capturedData?['csrf'], 'csrf-1');
    },
  );

  test('Netease playback rejects trial-only urls', () async {
    final platform = NeteasePlatform(api: _NeteaseTrialPlaybackApi());

    await expectLater(
      platform.getSongUrl('trial-song'),
      throwsA(isA<Exception>()),
    );
  });

  test('Netease import recognizes mobile playlist share links', () async {
    final api = _NeteaseShareApi();
    final playlist = await NeteasePlatform(api: api).parseShareLink(
      'https://music.163.com/m/playlist?id=863541621&creatorId=556315981',
    );

    expect(api.requestedId, '863541621');
    expect(playlist, isNotNull);
    expect(playlist!.id, '863541621');
    expect(playlist.name, 'Imported Netease Playlist');
    expect(playlist.songCount, 42);
  });

  test(
    'Netease playlist detail keeps songs beyond the first 1000 tracks',
    () async {
      final api = _NeteaseLargePlaylistApi();
      final songs = await NeteasePlatform(api: api).getPlaylistDetail('large');

      expect(songs, hasLength(1200));
      expect(songs.first.id, '1');
      expect(songs.last.id, '1200');
      expect(api.detailBatchRequests, [
        List.generate(200, (index) => '${index + 1001}'),
      ]);
    },
  );
}

class _NeteaseTrialPlaybackApi extends NeteaseApi {
  @override
  Future<Map<String, dynamic>> getSongUrl(
    String songId, {
    String level = 'exhigh',
  }) async {
    return {
      'data': [
        {
          'url': 'https://m701.music.126.net/trial.mp3',
          'level': 'standard',
          'br': 128000,
          'freeTrialInfo': {'start': 0, 'end': 30000},
        },
      ],
    };
  }
}

class _NeteaseShareApi extends NeteaseApi {
  String? requestedId;

  @override
  Future<Map<String, dynamic>> getPlaylistDetail(
    String id, {
    int n = 1000,
  }) async {
    requestedId = id;
    return {
      'playlist': {
        'id': int.parse(id),
        'name': 'Imported Netease Playlist',
        'trackCount': 42,
        'coverImgUrl': 'https://example.test/cover.jpg',
      },
    };
  }
}

class _NeteaseLargePlaylistApi extends NeteaseApi {
  final detailBatchRequests = <List<String>>[];

  @override
  Future<Map<String, dynamic>> getPlaylistDetail(
    String id, {
    int n = 1000,
  }) async {
    return {
      'playlist': {
        'id': id,
        'name': 'Large Playlist',
        'trackCount': 1200,
        'trackIds': List.generate(1200, (index) => {'id': index + 1}),
        'tracks': List.generate(1000, (index) => _song(index + 1)),
      },
    };
  }

  @override
  Future<Map<String, dynamic>> getSongDetails(List<String> ids) async {
    detailBatchRequests.add(List<String>.from(ids));
    return {'songs': ids.map((id) => _song(int.parse(id))).toList()};
  }

  Map<String, dynamic> _song(int id) {
    return {
      'id': id,
      'name': 'Song $id',
      'ar': [
        {'id': 1, 'name': 'Artist'},
      ],
      'dt': 180000,
    };
  }
}
