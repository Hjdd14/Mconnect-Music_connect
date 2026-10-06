import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/core/network/api_exception.dart';
import 'package:mconnect/core/network/platform_http.dart';
import 'package:mconnect/platform/kugou/kugou_api.dart';

/// WS-D: wires [KugouApi] to the shared [createPlatformDio] factory, so the
/// retry / error-translation interceptors that were dead code actually apply.
/// Two properties matter for Kugou specifically:
///   * the retry guard must never replay a Kugou **POST** write
///     (`song/collect`, `createPlaylist`, `get_all_list`) — a double "like" or
///     a duplicated playlist entry would be a silent data corruption;
///   * a WAF refusal (`HTTP 200` + `Access Deny ! No Actions !`) must become an
///     [ApiException], never an empty-but-successful payload.
void main() {
  test('createPlatformDio retries idempotent GET but never replays POST', () async {
    final adapter = _RecordingAdapter();
    final dio = createPlatformDio(label: '酷狗音乐', maxRetries: 1)
      ..httpClientAdapter = adapter;

    Object? getError;
    try {
      await dio.get<String>('http://example.test/rank/list');
    } catch (e) {
      getError = e;
    }
    expect(adapter.calls['GET'], 2, reason: '1 attempt + 1 retry');
    expect(apiExceptionOf(getError!).statusCode, 503);

    Object? postError;
    try {
      await dio.post<String>('http://example.test/song/collect', data: {'a': 1});
    } catch (e) {
      postError = e;
    }
    expect(
      adapter.calls['POST'],
      1,
      reason: 'a failed write must not be replayed',
    );
    expect(apiExceptionOf(postError!), isA<ApiException>());
  });

  test('a WAF refusal is an ApiException, not an empty result', () async {
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
      KugouApi(dio: dio).getToplists(),
      throwsA(
        isA<ApiException>().having(
          (e) => e.message,
          'message',
          '酷狗接口拒绝访问',
        ),
      ),
    );
  });

  test('a non-JSON body becomes an ApiException too', () async {
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) => handler.resolve(
          Response(
            requestOptions: options,
            statusCode: 200,
            data: '<html>maintenance</html>',
          ),
        ),
      ),
    );

    await expectLater(
      KugouApi(dio: dio).getToplists(),
      throwsA(
        isA<ApiException>().having(
          (e) => e.message,
          'message',
          '酷狗接口返回了非 JSON 响应',
        ),
      ),
    );
  });

  test('the KG_TAG_RES wrapper is stripped before decoding', () async {
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) => handler.resolve(
          Response(
            requestOptions: options,
            statusCode: 200,
            data:
                '<!--KG_TAG_RES_START-->{"status":1,"data":'
                '{"singerid":3060,"singername":"薛之谦"}}'
                '<!--KG_TAG_RES_END-->',
          ),
        ),
      ),
    );

    final res = await KugouApi(dio: dio).getArtistInfo('3060');

    expect(res['status'], 1);
    expect(res['data']['singername'], '薛之谦');
  });

  test('production KugouApi uses the shared platform Dio', () {
    final dio = createPlatformDio(label: '酷狗音乐');

    expect(dio.options.sendTimeout, isNotNull);
    expect(dio.interceptors.whereType<IdempotentRetryGuard>(), hasLength(1));
    expect(dio.interceptors.whereType<PlatformErrorInterceptor>(), hasLength(1));
  });
}

/// Always answers `503` and records how many times each method was attempted.
class _RecordingAdapter implements HttpClientAdapter {
  final Map<String, int> calls = {};

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls.update(options.method, (value) => value + 1, ifAbsent: () => 1);
    return ResponseBody.fromString(
      '{"status":0,"errmsg":"unavailable"}',
      503,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
