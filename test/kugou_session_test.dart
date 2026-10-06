import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/core/storage/session_storage.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/user.dart';
import 'package:mconnect/platform/kugou/kugou_api.dart';
import 'package:mconnect/platform/kugou/kugou_platform.dart';

/// WS-D P0: `logout()` used to clear only `_currentUser`, leaving
/// `token`/`userid`/`vipToken` inside [KugouApi] where `_signedAndroidParams`
/// injected them into every later request until the process restarted.
void main() {
  group('KugouApi.clearSession', () {
    test('clears account fields but keeps device ids by default', () {
      final api = KugouApi()
        ..setSessionFields(
          token: 'tok',
          userid: '10001',
          vipToken: 'vip-tok',
          vipType: '6',
          dfid: 'dfid-1',
          mid: 'mid-1',
          uuid: 'uuid-1',
        );

      api.clearSession();

      expect(api.token, isNull);
      expect(api.userid, isNull);
      expect(api.vipToken, isNull);
      expect(api.vipType, isNull);
      expect(api.hasToken, isFalse);
      expect(api.hasUserId, isFalse);
      expect(api.hasVipToken, isFalse);
      expect(api.hasVipPlaybackSession, isFalse);
      // Device fingerprint is not a credential; rotating it on every logout is
      // what triggers Kugou risk control.
      expect(api.dfid, 'dfid-1');
      expect(api.mid, 'mid-1');
      expect(api.uuid, 'uuid-1');
    });

    test('clearSession(keepDeviceIds: false) also drops the device ids', () {
      final api = KugouApi()
        ..setSessionFields(
          token: 'tok',
          userid: '10001',
          dfid: 'dfid-1',
          mid: 'mid-1',
          uuid: 'uuid-1',
        );

      api.clearSession(keepDeviceIds: false);

      expect(api.token, isNull);
      expect(api.userid, isNull);
      expect(api.dfid, isNull);
      expect(api.mid, isNull);
      expect(api.uuid, isNull);
    });

    test('setSessionFields cannot clear a field (why clearSession exists)', () {
      final api = KugouApi()..setSessionFields(token: 'tok', userid: '10001');

      // The old "clear" attempt: setSessionFields skips empty values on purpose.
      api.setSessionFields(token: '', userid: '   ');

      expect(api.token, 'tok');
      expect(api.userid, '10001');
    });
  });

  group('KugouPlatform.logout', () {
    test('clears both the user and the API session', () async {
      final api = KugouApi()
        ..setSessionFields(
          token: 'tok',
          userid: '10001',
          vipToken: 'vip-tok',
          vipType: '6',
        );
      final platform = KugouPlatform(api: api);
      await platform.restoreSession(
        _MemorySessionStorage(
          user: const User(
            id: '10001',
            nickname: 'Kugou User',
            platform: PlatformType.kugou,
          ),
        ),
      );
      expect(platform.isLoggedIn, isTrue);

      await platform.logout();

      expect(platform.isLoggedIn, isFalse);
      expect(await platform.getUserInfo(), isNull);
      expect(api.token, isNull);
      expect(api.userid, isNull);
      expect(api.vipToken, isNull);
      expect(api.vipType, isNull);
    });

    test('a signed request after logout no longer carries token/userid', () async {
      final dio = Dio();
      final queries = <Map<String, dynamic>>[];
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            queries.add(Map<String, dynamic>.from(options.queryParameters));
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'status': 1,
                  'data': {'lists': []},
                },
              ),
            );
          },
        ),
      );
      final api = KugouApi(dio: dio)
        ..setSessionFields(
          token: 'leaked-token',
          userid: '10001',
          vipToken: 'vip-tok',
          vipType: '6',
          dfid: 'dfid-1',
          mid: 'mid-1',
          uuid: 'uuid-1',
        );
      final platform = KugouPlatform(api: api);
      await platform.restoreSession(
        _MemorySessionStorage(
          user: const User(
            id: '10001',
            nickname: 'Kugou User',
            platform: PlatformType.kugou,
          ),
        ),
      );

      await platform.logout();
      await api.searchPlaylists('anything');

      expect(queries, hasLength(1));
      final query = queries.single;
      expect(
        query.containsKey('token'),
        isFalse,
        reason: 'the stale token is injected by _signedAndroidParams',
      );
      expect(query.containsKey('userid'), isFalse);
      // Device ids survive, so the signature stays stable.
      expect(query['mid'], 'mid-1');
      expect(query['dfid'], 'dfid-1');
      expect(query['uuid'], 'uuid-1');
      expect(query['signature'], isA<String>());
    });

    test('restoreSession still re-hydrates a saved JSON cookie', () async {
      final api = KugouApi();
      final platform = KugouPlatform(api: api);
      await platform.restoreSession(
        _MemorySessionStorage(
          cookie: jsonEncode({
            'token': 'saved-token',
            'userid': '20002',
            'vip_token': 'saved-vip',
            'vip_type': '6',
            'dfid': 'saved-dfid',
            'mid': 'saved-mid',
            'uuid': 'saved-uuid',
            'client': 'lite',
          }),
        ),
      );

      expect(api.token, 'saved-token');
      expect(api.userid, '20002');
      expect(api.vipToken, 'saved-vip');
      expect(api.dfid, 'saved-dfid');
      expect(api.clientMode, KugouPlaybackClient.lite);
    });
  });
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
