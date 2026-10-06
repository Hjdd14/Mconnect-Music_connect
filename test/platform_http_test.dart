import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/core/network/api_exception.dart';
import 'package:mconnect/core/network/platform_http.dart';

/// Scripted [HttpClientAdapter]: answers from a callback instead of the network,
/// and counts attempts so retry behaviour is observable.
///
/// This is deliberately the *only* fake here — the production interceptor chain
/// from [createPlatformDio] is exercised as-is, so a regression that drops an
/// interceptor (the pre-Wave-1 state: a bare `Dio` with no interceptors) makes
/// these tests fail.
class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter(this.respond);

  final FutureOr<ResponseBody> Function(RequestOptions options, int attempt)
      respond;

  int attempts = 0;
  final List<String> methods = [];
  final List<String?> urls = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    attempts++;
    methods.add(options.method);
    urls.add(options.uri.toString());
    return respond(options, attempts);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(String body, [int statusCode = 200]) => ResponseBody.fromString(
      body,
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

/// [createPlatformDio] with retry delays flattened, so retry tests do not sleep
/// for the production 1s/2s backoff.
Dio _fastDio({int maxRetries = 2, String label = '测试平台'}) => createPlatformDio(
      label: label,
      baseUrl: 'https://example.invalid',
      maxRetries: maxRetries,
      retryBaseDelay: Duration.zero,
      retryMaxDelay: Duration.zero,
    );

Future<DioException> _captureError(Future<Response<dynamic>> request) async {
  try {
    await request;
  } on DioException catch (e) {
    return e;
  }
  fail('expected the request to throw a DioException');
}

void main() {
  group('createPlatformDio 装配', () {
    test('装上幂等重试守卫与错误翻译拦截器，并应用超时/头部配置', () {
      final dio = createPlatformDio(
        label: '网易云',
        baseUrl: 'https://music.163.com',
        headers: {'Referer': 'https://music.163.com/'},
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 9),
        sendTimeout: const Duration(seconds: 7),
      );

      expect(dio.interceptors.whereType<IdempotentRetryGuard>(), hasLength(1));
      expect(
        dio.interceptors.whereType<PlatformErrorInterceptor>(),
        hasLength(1),
      );
      // The guard must sit in front of the translator: the retry decision is
      // made on the raw DioException (status code still visible).
      expect(
        dio.interceptors.indexOf(
          dio.interceptors.whereType<IdempotentRetryGuard>().first,
        ),
        lessThan(
          dio.interceptors.indexOf(
            dio.interceptors.whereType<PlatformErrorInterceptor>().first,
          ),
        ),
      );
      expect(dio.options.baseUrl, 'https://music.163.com');
      expect(dio.options.connectTimeout, const Duration(seconds: 5));
      expect(dio.options.receiveTimeout, const Duration(seconds: 9));
      expect(dio.options.sendTimeout, const Duration(seconds: 7));
      expect(dio.options.headers['Referer'], 'https://music.163.com/');
    });

    test('默认超时含 sendTimeout，且自定义拦截器追加在内置两个之后', () {
      final custom = InterceptorsWrapper(
        onRequest: (options, handler) => handler.next(options),
      );
      final dio = createPlatformDio(label: '酷狗音乐', interceptors: [custom]);

      expect(dio.options.connectTimeout, const Duration(seconds: 15));
      expect(dio.options.receiveTimeout, const Duration(seconds: 15));
      expect(dio.options.sendTimeout, const Duration(seconds: 15));
      expect(dio.interceptors.whereType<IdempotentRetryGuard>(), hasLength(1));
      expect(
        dio.interceptors.whereType<PlatformErrorInterceptor>(),
        hasLength(1),
      );
      expect(dio.interceptors.last, same(custom));
    });
  });

  group('重试只作用于幂等方法', () {
    test('GET 5xx 重试到 maxRetries 后用尽，并翻译成 ApiException', () async {
      final dio = _fastDio(maxRetries: 2, label: '网易云');
      final adapter = _ScriptedAdapter((_, _) => _json('{"e":1}', 500));
      dio.httpClientAdapter = adapter;

      final err = await _captureError(dio.get<dynamic>('/api/x'));

      expect(adapter.attempts, 3, reason: '1 次原始请求 + maxRetries 次重试');
      expect(adapter.methods, everyElement('GET'));
      final translated = apiExceptionOf(err);
      expect(translated, isA<ApiException>());
      expect(translated.statusCode, 500);
      expect(translated.message, contains('网易云'));
    });

    test('POST 5xx 绝不重放（否则会重复点赞/重复写歌单）', () async {
      final dio = _fastDio(maxRetries: 2, label: 'QQ音乐');
      final adapter = _ScriptedAdapter((_, _) => _json('{"e":1}', 500));
      dio.httpClientAdapter = adapter;

      final err = await _captureError(dio.post<dynamic>('/api/like'));

      expect(adapter.attempts, 1, reason: 'POST 重放会二次触发副作用');
      // …but it must still be translated for the UI.
      expect(apiExceptionOf(err).statusCode, 500);
    });

    test('HEAD 也会重试', () async {
      final dio = _fastDio(maxRetries: 1);
      final adapter = _ScriptedAdapter((_, _) => _json('', 503));
      dio.httpClientAdapter = adapter;

      await _captureError(dio.head<dynamic>('/api/x'));

      expect(adapter.attempts, 2);
      expect(adapter.methods, everyElement('HEAD'));
    });

    test('取消的请求不重试', () async {
      final dio = _fastDio(maxRetries: 2);
      final adapter = _ScriptedAdapter(
        (options, _) => throw DioException.requestCancelled(
          requestOptions: options,
          reason: 'user left the page',
        ),
      );
      dio.httpClientAdapter = adapter;

      final err = await _captureError(dio.get<dynamic>('/api/x'));

      expect(adapter.attempts, 1);
      expect(apiExceptionOf(err), isA<RequestCancelledException>());
    });

    test('GET 第二次成功时返回正常响应', () async {
      final dio = _fastDio(maxRetries: 2);
      final adapter = _ScriptedAdapter(
        (_, attempt) =>
            attempt == 1 ? _json('{"e":1}', 500) : _json('{"ok":true}'),
      );
      dio.httpClientAdapter = adapter;

      final res = await dio.get<dynamic>('/api/x');

      expect(res.statusCode, 200);
      expect(res.data, {'ok': true});
      expect(adapter.attempts, 2);
    });
  });

  group('错误翻译', () {
    Future<ApiException> translate(int statusCode, {String label = '酷狗音乐'}) async {
      final dio = _fastDio(maxRetries: 0, label: label);
      dio.httpClientAdapter = _ScriptedAdapter(
        (_, _) => _json('{"e":1}', statusCode),
      );
      final err = await _captureError(dio.get<dynamic>('/api/x'));
      // The typed exception must be reachable from the DioException…
      expect(err.error, isA<ApiException>());
      // …and identical to what apiExceptionOf hands to platform code.
      return apiExceptionOf(err);
    }

    test('401 → LoginExpiredException', () async {
      final e = await translate(401);
      expect(e, isA<LoginExpiredException>());
      expect(e.message, '登录已过期，请重新登录');
    });

    test('403 → LoginExpiredException', () async {
      expect(await translate(403), isA<LoginExpiredException>());
    });

    test('404 → NotFoundException', () async {
      expect(await translate(404), isA<NotFoundException>());
    });

    test('5xx → ApiException 带状态码与平台名', () async {
      final e = await translate(502);
      expect(e, isA<ApiException>());
      expect(e, isNot(isA<LoginExpiredException>()));
      expect(e.statusCode, 502);
      expect(e.message, '酷狗音乐服务器异常');
    });

    test('其他状态码 → ApiException 带状态码', () async {
      final e = await translate(418);
      expect(e.statusCode, 418);
      expect(e.message, contains('418'));
    });

    test('连接超时 → NetworkException（不是原始 DioException 文案）', () async {
      final dio = _fastDio(maxRetries: 0, label: '网易云');
      dio.httpClientAdapter = _ScriptedAdapter(
        (options, _) => throw DioException.connectionTimeout(
          timeout: const Duration(seconds: 1),
          requestOptions: options,
        ),
      );

      final e = apiExceptionOf(await _captureError(dio.get<dynamic>('/api/x')));

      expect(e, isA<NetworkException>());
      expect(e.message, '网络连接失败，请检查网络后重试');
      expect(e.details, '网易云请求超时');
    });

    test('连接错误 → NetworkException', () async {
      final dio = _fastDio(maxRetries: 0);
      dio.httpClientAdapter = _ScriptedAdapter(
        (options, _) => throw DioException.connectionError(
          requestOptions: options,
          reason: 'Failed host lookup',
        ),
      );

      final e = apiExceptionOf(await _captureError(dio.get<dynamic>('/api/x')));

      expect(e, isA<NetworkException>());
      expect(e.message, '网络连接失败，请检查网络后重试');
    });
  });

  group('apiExceptionOf', () {
    test('ApiException 原样返回（适配器自己抛的不被二次包装）', () {
      final original = UnsupportedActionException('网易云');
      expect(identical(apiExceptionOf(original), original), isTrue);
    });

    test('从 DioException.error 上取回翻译后的类型', () {
      final typed = LoginExpiredException();
      final err = DioException(
        requestOptions: RequestOptions(path: '/api/x'),
        type: DioExceptionType.badResponse,
        error: typed,
      );
      expect(apiExceptionOf(err), same(typed));
    });

    test('未翻译的 DioException 也按类型兜底翻译', () {
      final err = DioException(
        requestOptions: RequestOptions(path: '/api/x'),
        type: DioExceptionType.receiveTimeout,
      );
      expect(apiExceptionOf(err), isA<NetworkException>());
    });

    test('非 Dio 异常（JSON 解析等）包装成 ApiException 而不是裸抛', () {
      final e = apiExceptionOf(const FormatException('bad json'));
      expect(e, isA<ApiException>());
      expect(e, isNot(isA<NetworkException>()));
      expect(e.message, contains('bad json'));
    });
  });

  group('translateDioException 直接调用', () {
    test('cancel → RequestCancelledException（用户取消不等于网络故障）', () {
      final err = DioException(
        requestOptions: RequestOptions(path: '/api/x'),
        type: DioExceptionType.cancel,
      );
      expect(translateDioException(err), isA<RequestCancelledException>());
    });

    test('unknown → NetworkException 且 details 保留底层原因', () {
      final err = DioException(
        requestOptions: RequestOptions(path: '/api/x'),
        type: DioExceptionType.unknown,
        message: 'SocketException: connection reset',
      );
      final e = translateDioException(err);
      expect(e, isA<NetworkException>());
      expect(e.details, 'SocketException: connection reset');
    });

    test('badResponse 无响应体 → 通用 ApiException', () {
      final err = DioException(
        requestOptions: RequestOptions(path: '/api/x'),
        type: DioExceptionType.badResponse,
      );
      final e = translateDioException(err);
      expect(e, isA<ApiException>());
      expect(e.statusCode, isNull);
      expect(e.message, '请求失败');
    });
  });
}
