import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/core/storage/session_storage.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/user.dart';
import 'package:mconnect/platform/base/music_platform.dart';
import 'package:mconnect/platform/kugou/kugou_api.dart';
import 'package:mconnect/platform/kugou/kugou_platform.dart';

void main() {
  test('Kugou QR key requests include default signed web parameters', () async {
    final dio = Dio();
    Map<String, dynamic>? capturedQuery;
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          capturedQuery = Map<String, dynamic>.from(options.queryParameters);
          handler.resolve(
            Response(
              requestOptions: options,
              statusCode: 200,
              data: {
                'status': 1,
                'error_code': 0,
                'data': {'qrcode': 'abc'},
              },
            ),
          );
        },
      ),
    );

    await KugouApi(dio: dio).getQrLoginKey();

    expect(capturedQuery, isNotNull);
    expect(capturedQuery!['dfid'], '-');
    expect(capturedQuery!['mid'], 'mid');
    expect(capturedQuery!['uuid'], '-');
    expect(capturedQuery!['clientver'], 20489);
    expect(capturedQuery!['clienttime'], isA<int>());
    expect(
      capturedQuery!['signature'],
      isA<String>().having((s) => s.length, 'length', 32),
    );
  });

  test('Kugou Lite QR key requests bind QR text to concept appid', () async {
    final dio = Dio();
    Map<String, dynamic>? capturedQuery;
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          capturedQuery = Map<String, dynamic>.from(options.queryParameters);
          handler.resolve(
            Response(
              requestOptions: options,
              statusCode: 200,
              data: {
                'status': 1,
                'error_code': 0,
                'data': {'qrcode': 'abc'},
              },
            ),
          );
        },
      ),
    );

    await (KugouApi(
      dio: dio,
    )..setClientMode(KugouPlaybackClient.lite)).getQrLoginKey();

    expect(capturedQuery, isNotNull);
    expect(capturedQuery!['clientver'], 11440);
    expect(
      capturedQuery!['qrcode_txt'],
      'https://h5.kugou.com/apps/loginQRCode/html/index.html?appid=3116&',
    );
    expect(
      capturedQuery!['signature'],
      isA<String>().having((s) => s.length, 'length', 32),
    );
  });

  test('Kugou Lite QR polling uses concept appid and client version', () async {
    final dio = Dio();
    Map<String, dynamic>? capturedQuery;
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          capturedQuery = Map<String, dynamic>.from(options.queryParameters);
          handler.resolve(
            Response(
              requestOptions: options,
              statusCode: 200,
              data: {
                'status': 1,
                'error_code': 0,
                'data': {'status': 1},
              },
            ),
          );
        },
      ),
    );

    await (KugouApi(
      dio: dio,
    )..setClientMode(KugouPlaybackClient.lite)).checkQrLogin('abc123');

    expect(capturedQuery, isNotNull);
    expect(capturedQuery!['appid'], 3116);
    expect(capturedQuery!['clientver'], 11440);
    expect(capturedQuery!['qrcode'], 'abc123');
  });

  test(
    'Kugou QR display URL keeps the appid bound to the generated key',
    () async {
      final platform = KugouPlatform(api: _FakeKugouApi());

      final qr = await platform.getQrCode();

      expect(qr.key, 'abc123');
      expect(qr.qrUrl, contains('appid=1005'));
      expect(qr.qrUrl, contains('qrcode=abc123'));
    },
  );

  test(
    'Kugou concept QR display URL uses concept appid for scanner compatibility',
    () async {
      final platform = KugouPlatform(api: _FakeKugouApi())
        ..setClientVariant('lite');

      final qr = await platform.getQrCode();

      expect(qr.key, 'abc123');
      expect(qr.qrUrl, contains('appid=3116'));
      expect(qr.qrUrl, contains('qrcode=abc123'));
    },
  );

  test(
    'Kugou QR success keeps the account logged in when profile fetch fails',
    () async {
      final platform = KugouPlatform(api: _QrSuccessWithoutProfileKugouApi());

      final status = await platform
          .pollQrStatus('abc123')
          .firstWhere((status) => status == QrLoginStatus.success);
      final user = await platform.getUserInfo();

      expect(status, QrLoginStatus.success);
      expect(user, isNotNull);
      expect(user!.id, '10001');
      expect(user.nickname, isNotEmpty);
      expect(platform.isLoggedIn, isTrue);
    },
  );

  test(
    'Kugou user playlists use the authenticated cloud list endpoint',
    () async {
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
                  'data': {'list_create_list': []},
                },
              ),
            );
          },
        ),
      );

      final api = KugouApi(dio: dio)
        ..setToken('token-1')
        ..setUserId('10001');

      await api.getUserPlaylists(page: 2, limit: 30);

      expect(capturedOptions, isNotNull);
      expect(capturedOptions!.method, 'POST');
      expect(capturedOptions!.uri.toString(), contains('/v7/get_all_list'));
      expect(
        capturedOptions!.headers['x-router'],
        'cloudlist.service.kugou.com',
      );
      expect(capturedOptions!.queryParameters['userid'], 10001);
      expect(capturedOptions!.queryParameters['token'], 'token-1');
      expect(capturedOptions!.queryParameters['plat'], 1);
      expect(
        capturedOptions!.queryParameters['signature'],
        isA<String>().having((value) => value.length, 'length', 32),
      );
      expect(capturedBody, isA<Map>());
      final body = capturedBody as Map;
      expect(body['userid'], '10001');
      expect(body['token'], 'token-1');
      expect(body['type'], 2);
      expect(body['page'], 2);
      expect(body['pagesize'], 30);
    },
  );

  test(
    'Kugou concept user playlists keep the concept client identity',
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
                  'data': {'list_create_list': []},
                },
              ),
            );
          },
        ),
      );

      final api = KugouApi(dio: dio)
        ..setClientMode(KugouPlaybackClient.lite)
        ..setToken('token-1')
        ..setUserId('10001');

      await api.getUserPlaylists();

      expect(capturedOptions, isNotNull);
      expect(capturedOptions!.queryParameters['appid'], 3116);
      expect(capturedOptions!.queryParameters['clientver'], 11440);
      expect(capturedOptions!.queryParameters['userid'], 10001);
      expect(capturedOptions!.queryParameters['token'], 'token-1');
    },
  );

  test('Kugou user playlist songs use the editable listid endpoint', () async {
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
                'data': {'list': []},
              },
            ),
          );
        },
      ),
    );

    final api = KugouApi(dio: dio)
      ..setToken('token-1')
      ..setUserId('10001');

    await api.getUserPlaylistSongs('list-456', page: 3, limit: 40);

    expect(capturedOptions, isNotNull);
    expect(capturedOptions!.method, 'POST');
    expect(capturedOptions!.uri.toString(), contains('/v4/get_list_all_file'));
    expect(capturedOptions!.headers['x-router'], 'cloudlist.service.kugou.com');
    expect(
      capturedOptions!.queryParameters['signature'],
      isA<String>().having((value) => value.length, 'length', 32),
    );
    expect(capturedBody, isA<Map>());
    final body = capturedBody as Map;
    expect(body['listid'], 'list-456');
    expect(body['userid'], '10001');
    expect(body['token'], 'token-1');
    expect(body['page'], 3);
    expect(body['pagesize'], 40);
  });

  test(
    'Kugou concept user playlist songs keep the concept client identity',
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
                  'data': {'list': []},
                },
              ),
            );
          },
        ),
      );

      final api = KugouApi(dio: dio)
        ..setClientMode(KugouPlaybackClient.lite)
        ..setToken('token-1')
        ..setUserId('10001');

      await api.getUserPlaylistSongs('list-456');

      expect(capturedOptions, isNotNull);
      expect(capturedOptions!.queryParameters['appid'], 3116);
      expect(capturedOptions!.queryParameters['clientver'], 11440);
      expect(
        capturedOptions!.headers['x-router'],
        'cloudlist.service.kugou.com',
      );
    },
  );

  test(
    'Kugou create playlist uses cloudlist router and current client identity',
    () async {
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
                data: {'status': 1},
              ),
            );
          },
        ),
      );

      final api = KugouApi(dio: dio)
        ..setClientMode(KugouPlaybackClient.lite)
        ..setToken('token-1')
        ..setUserId('10001');

      await api.createPlaylist('新歌单');

      expect(capturedOptions, isNotNull);
      expect(capturedOptions!.method, 'POST');
      expect(
        capturedOptions!.uri.toString(),
        contains('/cloudlist.service/v5/add_list'),
      );
      expect(
        capturedOptions!.headers['x-router'],
        'cloudlist.service.kugou.com',
      );
      expect(capturedOptions!.queryParameters['appid'], 3116);
      expect(capturedOptions!.queryParameters['clientver'], 11440);
      expect(capturedOptions!.queryParameters['userid'], '10001');
      expect(capturedOptions!.queryParameters['token'], 'token-1');
      expect(capturedBody, isA<Map>());
      expect((capturedBody as Map)['name'], '新歌单');
    },
  );

  test(
    'Kugou QR success stores userid from fetched profile for later APIs',
    () async {
      final api = _QrSuccessProfileOnlyKugouApi();
      final platform = KugouPlatform(api: api);

      await platform
          .pollQrStatus('abc123')
          .firstWhere((status) => status == QrLoginStatus.success);
      final user = await platform.getUserInfo();

      expect(api.token, 'token-2');
      expect(api.userid, '20002');
      expect(user, isNotNull);
      expect(user!.id, '20002');
    },
  );

  test('Kugou phone login stores token and userid for playlist APIs', () async {
    final api = _PhoneLoginKugouApi();
    final platform = KugouPlatform(api: api);

    final result = await platform.loginByPhone('13800138000', '123456');

    expect(result.success, isTrue);
    expect(api.token, 'phone-token');
    expect(api.userid, '30003');
    expect(result.user, isNotNull);
    expect(result.user!.id, '30003');
  });

  test('Kugou concept phone login asks the user to use QR login', () async {
    final api = _PhoneLoginKugouApi();
    final platform = KugouPlatform(api: api)..setClientVariant('lite');

    final codeResult = await platform.sendPhoneCode('13800138000');
    final loginResult = await platform.loginByPhone('13800138000', '123456');

    expect(codeResult.success, isFalse);
    expect(codeResult.error, contains('二维码'));
    expect(loginResult.success, isFalse);
    expect(loginResult.error, contains('二维码'));
  });

  test(
    'Kugou QR success stores extended VIP and device session fields',
    () async {
      final api = _QrSuccessWithVipSessionKugouApi();
      final platform = KugouPlatform(api: api);

      await platform
          .pollQrStatus('abc123')
          .firstWhere((status) => status == QrLoginStatus.success);

      expect(api.token, 'token-vip');
      expect(api.userid, '40004');
      expect(api.vipToken, 'vip-token-1');
      expect(api.vipType, '6');
      expect(api.dfid, 'dfid-1');
      expect(api.mid, 'mid-1');
      expect(api.uuid, 'uuid-1');
    },
  );

  test('Kugou session saves JSON and restores old pipe format', () async {
    final api = KugouApi()
      ..setClientMode(KugouPlaybackClient.lite)
      ..setSessionFields(
        token: 'token-json',
        userid: '50005',
        vipToken: 'vip-token-json',
        vipType: '6',
        dfid: 'dfid-json',
        mid: 'mid-json',
        uuid: 'uuid-json',
      );
    final platform = KugouPlatform(api: api);
    final storage = _MemorySessionStorage(
      user: const User(
        id: '50005',
        nickname: 'Json User',
        platform: PlatformType.kugou,
      ),
    );

    await platform.restoreSession(storage);
    await platform.saveSession(storage);

    expect(storage.cookie, isNotNull);
    expect(storage.cookie, startsWith('{'));
    final saved = jsonDecode(storage.cookie!) as Map<String, dynamic>;
    expect(saved['token'], 'token-json');
    expect(saved['userid'], '50005');
    expect(saved['vip_token'], 'vip-token-json');
    expect(saved['vip_type'], '6');
    expect(saved['dfid'], 'dfid-json');
    expect(saved['mid'], 'mid-json');
    expect(saved['uuid'], 'uuid-json');
    expect(saved['client'], 'lite');

    final oldApi = KugouApi();
    await KugouPlatform(
      api: oldApi,
    ).restoreSession(_MemorySessionStorage(cookie: 'old-token|60006'));
    expect(oldApi.token, 'old-token');
    expect(oldApi.userid, '60006');
    expect(oldApi.clientMode, KugouPlaybackClient.android);

    final restoredApi = KugouApi();
    await KugouPlatform(
      api: restoredApi,
    ).restoreSession(_MemorySessionStorage(cookie: storage.cookie));
    expect(restoredApi.clientMode, KugouPlaybackClient.lite);
    expect(restoredApi.hasVipPlaybackSession, isTrue);
  });

  test(
    'Kugou concept VIP session is trusted before ordinary VIP endpoint data',
    () async {
      final api = _ConceptVipSessionWithFreeVipInfoApi();
      final platform = KugouPlatform(api: api);

      final vipLevel = await platform.getVipStatus();

      expect(vipLevel, VipLevel.svip);
    },
  );
}

class _FakeKugouApi extends KugouApi {
  @override
  Future<Map<String, dynamic>> getQrLoginKey() async {
    return {
      'status': 1,
      'error_code': 0,
      'data': {'qrcode': 'abc123'},
    };
  }
}

class _QrSuccessWithoutProfileKugouApi extends KugouApi {
  @override
  Future<Map<String, dynamic>> checkQrLogin(String key) async {
    return {
      'status': 1,
      'error_code': 0,
      'data': {'status': 4, 'token': 'token-1', 'userid': '10001'},
    };
  }

  @override
  Future<Map<String, dynamic>> getUserInfoFromToken() async {
    throw StateError('profile unavailable');
  }
}

class _QrSuccessProfileOnlyKugouApi extends KugouApi {
  @override
  Future<Map<String, dynamic>> checkQrLogin(String key) async {
    return {
      'status': 1,
      'error_code': 0,
      'data': {'status': 4, 'token': 'token-2'},
    };
  }

  @override
  Future<Map<String, dynamic>> getUserInfoFromToken() async {
    return {
      'status': 1,
      'data': {'userid': '20002', 'nickname': 'Profile User'},
    };
  }
}

class _PhoneLoginKugouApi extends KugouApi {
  @override
  Future<Map<String, dynamic>> login(String phone, String code) async {
    return {
      'status': 1,
      'data': {
        'user_id': '30003',
        'nick_name': 'Phone User',
        'token': 'phone-token',
      },
    };
  }
}

class _QrSuccessWithVipSessionKugouApi extends KugouApi {
  @override
  Future<Map<String, dynamic>> checkQrLogin(String key) async {
    return {
      'status': 1,
      'error_code': 0,
      'data': {
        'status': 4,
        'token': 'token-vip',
        'userid': '40004',
        'vip_token': 'vip-token-1',
        'vip_type': 6,
        'dfid': 'dfid-1',
        'mid': 'mid-1',
        'uuid': 'uuid-1',
      },
    };
  }

  @override
  Future<Map<String, dynamic>> getUserInfoFromToken() async {
    return {
      'status': 1,
      'data': {'userid': '40004', 'nickname': 'Vip User'},
    };
  }
}

class _ConceptVipSessionWithFreeVipInfoApi extends KugouApi {
  _ConceptVipSessionWithFreeVipInfoApi() {
    setClientMode(KugouPlaybackClient.lite);
    setSessionFields(
      token: 'token-1',
      userid: '10001',
      vipToken: 'vip-token-1',
      vipType: '6',
    );
  }

  @override
  Future<Map<String, dynamic>> getVipInfo() async {
    return {
      'status': 1,
      'data': {'vip_type': 0},
    };
  }
}

class _MemorySessionStorage extends SessionStorage {
  String? cookie;
  User? user;

  _MemorySessionStorage({this.cookie, this.user});

  @override
  Future<void> saveCookie(PlatformType platform, String cookie) async {
    this.cookie = cookie;
  }

  @override
  Future<String?> loadCookie(PlatformType platform) async => cookie;

  @override
  Future<void> saveUser(PlatformType platform, User user) async {
    this.user = user;
  }

  @override
  Future<User?> loadUser(PlatformType platform) async => user;
}
