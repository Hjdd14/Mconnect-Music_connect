import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/app.dart';
import 'package:mconnect/core/network/platform_http.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/platform/base/music_platform.dart';
import 'package:mconnect/platform/base/platform_registry.dart';

/// v1.4.1: session expiry is now reported by the network layer itself
/// (`PlatformErrorInterceptor` → [SessionExpiredHandler]) instead of every
/// caller remembering to check for `LoginExpiredException`.
///
/// Before this, exactly one production call site reacted to it
/// (`platform_playlists_provider`), so a dead cookie on any other path
/// (recommendations, charts, downloads, stream-URL resolution) left the app
/// showing the user as logged in while every request failed.
///
/// The failures are produced by replacing the HTTP adapter, so the request goes
/// through Dio's real validation path — a status code only becomes
/// `DioExceptionType.badResponse` (and therefore a translated exception) there.
void main() {
  Dio failingDio(
    void Function(PlatformType)? onExpired, {
    PlatformType? platform = PlatformType.qq,
    int? statusCode = 401,
    DioException? transportError,
  }) {
    final dio = createPlatformDio(
      platform: platform,
      label: 'QQ音乐',
      baseUrl: 'https://example.invalid',
      maxRetries: 0,
      retryBaseDelay: Duration.zero,
      retryMaxDelay: Duration.zero,
      onSessionExpired: onExpired,
    );
    dio.httpClientAdapter = _ScriptedAdapter(
      statusCode: statusCode,
      transportError: transportError,
    );
    return dio;
  }

  Future<DioException> captureError(Future<Response<dynamic>> request) async {
    try {
      await request;
    } on DioException catch (e) {
      return e;
    }
    fail('expected the request to throw a DioException');
  }

  group('network layer reports a dead session', () {
    test('HTTP 401 reports the platform', () async {
      final reported = <PlatformType>[];
      await captureError(failingDio(reported.add).get<dynamic>('/anything'));
      expect(reported, [PlatformType.qq]);
    });

    test('HTTP 403 reports the platform too', () async {
      final reported = <PlatformType>[];
      await captureError(
        failingDio(reported.add, statusCode: 403).get<dynamic>('/anything'),
      );
      expect(reported, [PlatformType.qq]);
    });

    test('other HTTP failures never report', () async {
      for (final code in const [400, 404, 429, 500, 503]) {
        final reported = <PlatformType>[];
        await captureError(
          failingDio(reported.add, statusCode: code).get<dynamic>('/anything'),
        );
        expect(reported, isEmpty, reason: 'HTTP $code is not a session expiry');
      }
    });

    test('a transport failure never reports', () async {
      final reported = <PlatformType>[];
      final dio = failingDio(reported.add, statusCode: null);
      dio.httpClientAdapter = _ScriptedAdapter(
        transportError: DioException.connectionError(
          requestOptions: RequestOptions(path: '/anything'),
          reason: 'no network',
        ),
      );

      await captureError(dio.get<dynamic>('/anything'));
      expect(reported, isEmpty);
    });

    test('a client without a platform does not report (label-only callers)', () async {
      final reported = <PlatformType>[];
      // Callers/tests that only pass a label keep working and stay silent.
      final dio = createPlatformDio(
        label: '测试平台',
        baseUrl: 'https://example.invalid',
        maxRetries: 0,
        retryBaseDelay: Duration.zero,
        retryMaxDelay: Duration.zero,
        onSessionExpired: reported.add,
      );
      dio.httpClientAdapter = _ScriptedAdapter(statusCode: 401);

      await captureError(dio.get<dynamic>('/x'));
      expect(
        reported,
        isEmpty,
        reason: 'without a platform there is nothing to expire',
      );
    });

    test('the injected handler wins over the global sink', () async {
      final injected = <PlatformType>[];
      final global = <PlatformType>[];
      SessionExpiryReporter.handler = global.add;
      addTearDown(SessionExpiryReporter.reset);

      await captureError(failingDio(injected.add).get<dynamic>('/anything'));

      expect(injected, [PlatformType.qq]);
      expect(global, isEmpty, reason: 'tests must not depend on the global sink');
    });

    test('the global sink is used when no handler is injected', () async {
      final global = <PlatformType>[];
      SessionExpiryReporter.handler = global.add;
      addTearDown(SessionExpiryReporter.reset);

      await captureError(failingDio(null).get<dynamic>('/anything'));

      expect(global, [PlatformType.qq]);
    });
  });

  group('an anonymous failure must not log anyone out', () {
    // This is the guard lib/app.dart applies before calling
    // handleSessionExpired: a 403 on an *anonymous* request must not clear a
    // session, and because handleSessionExpired clears the session, the same
    // check is also what makes the burst of 401s after a real expiry report
    // exactly once.
    test('an unregistered platform is never treated as expired', () {
      expect(shouldClearSessionOnExpiry(PlatformType.kugou), isFalse);
    });

    test('a registered but logged-out platform is not expired', () {
      PlatformRegistry.register(
        _FakeLoginStatePlatform(PlatformType.netease, false),
      );
      expect(shouldClearSessionOnExpiry(PlatformType.netease), isFalse);
    });

    test('a registered and logged-in platform is expired', () {
      PlatformRegistry.register(_FakeLoginStatePlatform(PlatformType.qq, true));
      expect(shouldClearSessionOnExpiry(PlatformType.qq), isTrue);
    });

    test('re-registering replaces the previous login state', () {
      PlatformRegistry.register(
        _FakeLoginStatePlatform(PlatformType.netease, false),
      );
      expect(shouldClearSessionOnExpiry(PlatformType.netease), isFalse);
      PlatformRegistry.register(
        _FakeLoginStatePlatform(PlatformType.netease, true),
      );
      expect(shouldClearSessionOnExpiry(PlatformType.netease), isTrue);
    });
  });
}

/// Serves one canned answer, so a status code reaches Dio's validation layer
/// (an interceptor calling `handler.resolve` would bypass it).
class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter({this.statusCode, this.transportError});

  final int? statusCode;
  final DioException? transportError;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final failure = transportError;
    if (failure != null) throw failure;
    return ResponseBody.fromString(
      '{"e":1}',
      statusCode ?? 200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// Only [isLoggedIn] is exercised; every other member is satisfied by
/// `noSuchMethod` (the same trick other tests in this repository use) so a fake
/// platform does not need 20 stub implementations.
class _FakeLoginStatePlatform implements MusicPlatform {
  _FakeLoginStatePlatform(this.platformType, this.isLoggedIn);

  @override
  final PlatformType platformType;

  @override
  final bool isLoggedIn;

  @override
  String get platformName => platformType.displayName;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
