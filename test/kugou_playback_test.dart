import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/core/diagnostics/diagnostics_service.dart';
import 'package:mconnect/models/audio_quality.dart';
import 'package:mconnect/platform/kugou/kugou_api.dart';
import 'package:mconnect/platform/kugou/kugou_platform.dart';

void main() {
  test(
    'Kugou playback uses nested play_url from song info responses',
    () async {
      final platform = KugouPlatform(
        api: _SongInfoApi({
          'status': 1,
          'data': {'play_url': 'https://cdn.example.test/song.mp3'},
        }),
      );

      final url = await platform.getSongUrl('HASH1');

      expect(url, 'https://cdn.example.test/song.mp3');
    },
  );

  test(
    'Kugou playback uses fallback url lists when direct fields are empty',
    () async {
      final platform = KugouPlatform(
        api: _SongInfoApi({
          'status': 1,
          'data': {
            'url': '',
            'play_url': '',
            'backup_url': ['', 'https://backup.example.test/song.flac'],
          },
        }),
      );

      final url = await platform.getSongUrl('HASH2');

      expect(url, 'https://backup.example.test/song.flac');
    },
  );

  test('Kugou playback falls back to the signed v5 url endpoint', () async {
    final api =
        _SongInfoApi({
            'status': 0,
            'hash': 'ORIGINAL_HASH',
            'albumid': 966846,
            'album_audio_id': 32100650,
            'url': '',
            'extra': {'128hash': 'LOW_HASH'},
          })
          ..fallbackResponse = {
            'status': 1,
            'data': {'url': 'https://tracker.example.test/low.mp3'},
          };

    final url = await KugouPlatform(api: api).getSongUrl('ORIGINAL_HASH');

    expect(url, 'https://tracker.example.test/low.mp3');
    expect(api.fallbackRequests, [
      (
        hash: 'LOW_HASH',
        albumId: '966846',
        albumAudioId: '32100650',
        quality: AudioLevel.low,
        client: KugouPlaybackClient.android,
      ),
    ]);
  });

  test(
    'Kugou signed v5 url request includes tracker routing and song ids',
    () async {
      final dio = Dio();
      RequestOptions? capturedOptions;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            capturedOptions = options;
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'status': 1,
                  'data': {'url': 'https://tracker.example.test/song.flac'},
                },
              ),
            );
          },
        ),
      );
      final api = KugouApi(dio: dio)
        ..setToken('token-1')
        ..setUserId('10001');

      await api.getSongPlaybackUrl(
        'ABCDEF',
        albumId: '966846',
        albumAudioId: '32100650',
        quality: AudioLevel.lossless,
      );

      expect(capturedOptions, isNotNull);
      expect(capturedOptions!.method, 'GET');
      expect(capturedOptions!.uri.toString(), contains('/v5/url'));
      expect(capturedOptions!.headers['x-router'], 'trackercdn.kugou.com');
      expect(capturedOptions!.queryParameters['hash'], 'abcdef');
      expect(capturedOptions!.queryParameters['album_id'], 966846);
      expect(capturedOptions!.queryParameters['album_audio_id'], 32100650);
      expect(capturedOptions!.queryParameters['quality'], 'flac');
      expect(capturedOptions!.queryParameters['token'], 'token-1');
      expect(capturedOptions!.queryParameters['userid'], '10001');
      expect(
        capturedOptions!.queryParameters['key'],
        isA<String>().having((value) => value.length, 'length', 32),
      );
      expect(
        capturedOptions!.queryParameters['signature'],
        isA<String>().having((value) => value.length, 'length', 32),
      );
    },
  );

  test(
    'Kugou Lite v5 playback uses Lite identity and stored device fields',
    () async {
      final dio = Dio();
      RequestOptions? capturedOptions;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            capturedOptions = options;
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'status': 1,
                  'data': {'url': 'https://tracker.example.test/lite.flac'},
                },
              ),
            );
          },
        ),
      );
      final api = KugouApi(dio: dio)
        ..setSessionFields(
          token: 'token-1',
          userid: '10001',
          dfid: 'dfid-1',
          mid: 'mid-1',
          uuid: 'uuid-1',
        );

      await api.getSongPlaybackUrl(
        'ABCDEF',
        albumId: '966846',
        albumAudioId: '32100650',
        quality: AudioLevel.lossless,
        client: KugouPlaybackClient.lite,
      );

      expect(capturedOptions, isNotNull);
      expect(capturedOptions!.uri.toString(), contains('/v5/url'));
      expect(capturedOptions!.headers['x-router'], 'trackercdn.kugou.com');
      expect(capturedOptions!.queryParameters['appid'], 3116);
      expect(capturedOptions!.queryParameters['pid'], 411);
      expect(capturedOptions!.queryParameters['page_id'], 967177915);
      expect(
        capturedOptions!.queryParameters['ppage_id'],
        '356753938,823673182,967485191',
      );
      expect(capturedOptions!.queryParameters['dfid'], 'dfid-1');
      expect(capturedOptions!.queryParameters['mid'], 'mid-1');
      expect(capturedOptions!.queryParameters['uuid'], 'uuid-1');
      expect(
        capturedOptions!.queryParameters['key'],
        isA<String>().having((value) => value.length, 'length', 32),
      );
      expect(
        capturedOptions!.queryParameters['signature'],
        isA<String>().having((value) => value.length, 'length', 32),
      );
    },
  );

  test(
    'Kugou playback failure diagnostics include sanitized session booleans',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'mconnect_kugou_diag_flags_',
      );
      await DiagnosticsService.instance.initializeForTest(tempDir);
      try {
        final api = _AllRoutesFailPartialLiteApi();

        await expectLater(
          KugouPlatform(api: api).getSongUrl('VIP_HASH_PARTIAL'),
          throwsException,
        );
        await DiagnosticsService.instance.flush();

        final content = await DiagnosticsService.instance.logFile
            .readAsString();
        expect(content, contains('kugou_client'));
        expect(content, contains('has_token'));
        expect(content, contains('has_userid'));
        expect(content, contains('has_vip_token'));
        expect(content, contains('lite'));
        expect(content, isNot(contains('token-1')));
        expect(content, isNot(contains('10001')));
      } finally {
        await DiagnosticsService.instance.resetForTest();
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      }
    },
  );

  test('Kugou private playback posts VIP token and tracker resource', () async {
    final dio = Dio();
    RequestOptions? capturedOptions;
    Object? capturedBody;
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          capturedOptions = options;
          capturedBody = options.data;
          handler.resolve(
            Response(
              requestOptions: options,
              statusCode: 200,
              data: {
                'status': 1,
                'data': {'url': 'https://tracker.example.test/private.flac'},
              },
            ),
          );
        },
      ),
    );
    final api = KugouApi(dio: dio)
      ..setSessionFields(
        token: 'token-1',
        userid: '10001',
        vipToken: 'vip-token-1',
        vipType: '6',
        dfid: 'dfid-1',
        mid: 'mid-1',
        uuid: 'uuid-1',
      );

    await api.getSongPrivatePlaybackUrl(
      'abcdef',
      albumAudioId: '32100650',
      quality: AudioLevel.lossless,
    );

    expect(capturedOptions, isNotNull);
    expect(capturedOptions!.method, 'POST');
    expect(capturedOptions!.uri.toString(), contains('/v6/priv_url'));
    expect(capturedOptions!.queryParameters['appid'], 3116);
    expect(capturedOptions!.queryParameters['dfid'], 'dfid-1');
    expect(capturedOptions!.queryParameters['mid'], 'mid-1');
    expect(capturedBody, isA<Map>());
    final body = capturedBody as Map;
    expect(body['token'], 'token-1');
    expect(body['userid'], '10001');
    expect(body['vip'], '6');
    expect(body['qualities'], isA<List>());
    expect((body['qualities'] as List).first, 'flac');
    expect(body['qualities'], contains('flac'));
    expect(body['resource'], isA<Map>());
    expect((body['resource'] as Map)['hash'], 'abcdef');
    expect((body['resource'] as Map)['album_audio_id'], 32100650);
    expect(body['tracker_param'], isA<Map>());
    final tracker = body['tracker_param'] as Map;
    expect(tracker['pid'], '411');
    expect(tracker['viptoken'], 'vip-token-1');
    expect(
      tracker['key'],
      isA<String>().having((value) => value.length, 'length', 32),
    );
  });

  test(
    'Kugou VIP playback tries private authenticated URL before ordinary fallback',
    () async {
      final api = _VipFallbackApi();

      final url = await KugouPlatform(api: api).getSongUrl('VIP_HASH');

      expect(url, 'https://tracker.example.test/private.flac');
      expect(api.calls, ['info', 'private']);
    },
  );

  test(
    'Kugou high quality playback ignores ordinary song info url and uses private route',
    () async {
      final api = _VipSongInfoDirectUrlApi();

      final url = await KugouPlatform(
        api: api,
      ).getSongUrl('VIP_HASH', quality: AudioLevel.lossless);

      expect(url, 'https://tracker.example.test/private-lossless.flac');
      expect(api.calls, ['info', 'private']);
    },
  );

  test('Kugou non-VIP playback keeps ordinary v5 fallback behavior', () async {
    final api = _SongInfoApi({'status': 0, 'hash': 'HASH3', 'url': ''})
      ..fallbackResponse = {
        'status': 1,
        'data': {'url': 'https://tracker.example.test/ordinary.mp3'},
      };

    final url = await KugouPlatform(api: api).getSongUrl('HASH3');

    expect(url, 'https://tracker.example.test/ordinary.mp3');
    expect(api.fallbackRequests.single.client, KugouPlaybackClient.android);
  });

  test('Kugou playback failure diagnostics do not leak login tokens', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'mconnect_kugou_diag_',
    );
    await DiagnosticsService.instance.initializeForTest(tempDir);
    try {
      await expectLater(
        KugouPlatform(api: _AllRoutesFailVipApi()).getSongUrl('VIP_HASH_FULL'),
        throwsException,
      );
      await DiagnosticsService.instance.flush();

      final content = await DiagnosticsService.instance.logFile.readAsString();
      expect(content, contains('kugou_playback'));
      expect(content, contains('url_resolution_failed'));
      expect(content, isNot(contains('token-1')));
      expect(content, isNot(contains('vip-token-1')));
      expect(content, isNot(contains('VIP_HASH_FULL')));
    } finally {
      await DiagnosticsService.instance.resetForTest();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    }
  });
}

class _SongInfoApi extends KugouApi {
  final Map<String, dynamic> response;
  Map<String, dynamic>? fallbackResponse;
  final fallbackRequests =
      <
        ({
          String hash,
          String? albumId,
          String? albumAudioId,
          AudioLevel quality,
          KugouPlaybackClient client,
        })
      >[];

  _SongInfoApi(this.response);

  @override
  Future<Map<String, dynamic>> getSongInfo(String hash) async => response;

  @override
  Future<Map<String, dynamic>> getSongPlaybackUrl(
    String hash, {
    String? albumId,
    String? albumAudioId,
    AudioLevel quality = AudioLevel.low,
    KugouPlaybackClient client = KugouPlaybackClient.android,
  }) async {
    fallbackRequests.add((
      hash: hash,
      albumId: albumId,
      albumAudioId: albumAudioId,
      quality: quality,
      client: client,
    ));
    return fallbackResponse ?? {};
  }
}

class _VipFallbackApi extends KugouApi {
  final calls = <String>[];

  _VipFallbackApi() {
    setSessionFields(
      token: 'token-1',
      userid: '10001',
      vipToken: 'vip-token-1',
      vipType: '6',
      mid: 'mid-1',
      dfid: 'dfid-1',
      uuid: 'uuid-1',
    );
  }

  @override
  Future<Map<String, dynamic>> getSongInfo(String hash) async {
    calls.add('info');
    return {'status': 0, 'hash': hash, 'album_audio_id': 32100650, 'url': ''};
  }

  @override
  Future<Map<String, dynamic>> getSongPrivatePlaybackUrl(
    String hash, {
    String? albumAudioId,
    AudioLevel quality = AudioLevel.low,
  }) async {
    calls.add('private');
    return {
      'status': 1,
      'data': {'url': 'https://tracker.example.test/private.flac'},
    };
  }

  @override
  Future<Map<String, dynamic>> getSongPlaybackUrl(
    String hash, {
    String? albumId,
    String? albumAudioId,
    AudioLevel quality = AudioLevel.low,
    KugouPlaybackClient client = KugouPlaybackClient.android,
  }) async {
    calls.add(client == KugouPlaybackClient.lite ? 'lite' : 'android');
    return {};
  }
}

class _VipSongInfoDirectUrlApi extends KugouApi {
  final calls = <String>[];

  _VipSongInfoDirectUrlApi() {
    setSessionFields(
      token: 'token-1',
      userid: '10001',
      vipToken: 'vip-token-1',
      vipType: '6',
      mid: 'mid-1',
      dfid: 'dfid-1',
      uuid: 'uuid-1',
    );
  }

  @override
  Future<Map<String, dynamic>> getSongInfo(String hash) async {
    calls.add('info');
    return {
      'status': 1,
      'hash': hash,
      'album_audio_id': 32100650,
      'url': 'https://ordinary.example.test/128.mp3',
    };
  }

  @override
  Future<Map<String, dynamic>> getSongPrivatePlaybackUrl(
    String hash, {
    String? albumAudioId,
    AudioLevel quality = AudioLevel.low,
  }) async {
    calls.add('private');
    return {
      'status': 1,
      'data': {'url': 'https://tracker.example.test/private-lossless.flac'},
    };
  }

  @override
  Future<Map<String, dynamic>> getSongPlaybackUrl(
    String hash, {
    String? albumId,
    String? albumAudioId,
    AudioLevel quality = AudioLevel.low,
    KugouPlaybackClient client = KugouPlaybackClient.android,
  }) async {
    calls.add(client == KugouPlaybackClient.lite ? 'lite' : 'android');
    return {};
  }
}

class _AllRoutesFailVipApi extends KugouApi {
  _AllRoutesFailVipApi() {
    setSessionFields(
      token: 'token-1',
      userid: '10001',
      vipToken: 'vip-token-1',
      vipType: '6',
      mid: 'mid-1',
      dfid: 'dfid-1',
      uuid: 'uuid-1',
    );
  }

  @override
  Future<Map<String, dynamic>> getSongInfo(String hash) async {
    return {'status': 0, 'hash': hash, 'album_audio_id': 32100650, 'url': ''};
  }

  @override
  Future<Map<String, dynamic>> getSongPrivatePlaybackUrl(
    String hash, {
    String? albumAudioId,
    AudioLevel quality = AudioLevel.low,
  }) async {
    return {
      'status': 1,
      'data': {'url': ''},
    };
  }

  @override
  Future<Map<String, dynamic>> getSongPlaybackUrl(
    String hash, {
    String? albumId,
    String? albumAudioId,
    AudioLevel quality = AudioLevel.low,
    KugouPlaybackClient client = KugouPlaybackClient.android,
  }) async {
    return {};
  }
}

class _AllRoutesFailPartialLiteApi extends KugouApi {
  _AllRoutesFailPartialLiteApi() {
    setClientMode(KugouPlaybackClient.lite);
    setSessionFields(token: 'token-1', userid: '10001');
  }

  @override
  Future<Map<String, dynamic>> getSongInfo(String hash) async {
    return {'status': 0, 'hash': hash, 'album_audio_id': 32100650, 'url': ''};
  }

  @override
  Future<Map<String, dynamic>> getSongPlaybackUrl(
    String hash, {
    String? albumId,
    String? albumAudioId,
    AudioLevel quality = AudioLevel.low,
    KugouPlaybackClient client = KugouPlaybackClient.android,
  }) async {
    return {};
  }
}
