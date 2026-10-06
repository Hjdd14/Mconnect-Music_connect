import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/core/network/api_exception.dart';
import 'package:mconnect/core/network/platform_http.dart';
import 'package:mconnect/platform/qq/qq_api.dart';

/// Scripted [HttpClientAdapter]: answers from a callback instead of the network
/// and counts attempts, so retry behaviour of the **QQ adapter itself** is
/// observable.
class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter(this.respond);

  final FutureOr<ResponseBody> Function(RequestOptions options, int attempt)
  respond;

  int attempts = 0;
  final List<String> methods = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    attempts++;
    methods.add(options.method);
    return respond(options, attempts);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _errorBody([int status = 500]) => ResponseBody.fromString(
  '{"code":$status}',
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

/// A [Dio] whose adapter always answers with [data] — used to replay the
/// "empty/failed body" cases that used to crash the adapter.
Dio _stubDio(dynamic data) {
  final dio = Dio();
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        handler.resolve(
          Response(requestOptions: options, statusCode: 200, data: data),
        );
      },
    ),
  );
  return dio;
}

Dio _fastPlatformDio() => createPlatformDio(
  label: 'QQ音乐',
  maxRetries: 2,
  retryBaseDelay: Duration.zero,
  retryMaxDelay: Duration.zero,
);

void main() {
  group('QQ 空/异常响应守卫', () {
    test('responseMapOf 处理 null、空串、HTML、双重编码 JSON', () {
      expect(QqApi.responseMapOf(null), isEmpty);
      expect(QqApi.responseMapOf(''), isEmpty);
      expect(QqApi.responseMapOf('   '), isEmpty);
      expect(QqApi.responseMapOf('<html>登录</html>'), isEmpty);
      expect(QqApi.responseMapOf(const [1, 2, 3]), isEmpty);
      expect(QqApi.responseMapOf('{"code":0}'), {'code': 0});
      // QQ sometimes answers with a JSON document that is itself a JSON string.
      expect(QqApi.responseMapOf('"{\\"code\\":0}"'), {'code': 0});
    });

    test('null body 不再抛 TypeError：12 个入口全部降级', () async {
      final api = QqApi(dio: _stubDio(null));

      expect(await api.musicu({'comm': <String, dynamic>{}}), isEmpty);
      expect(await api.searchPlaylists('周杰伦'), isEmpty);
      expect(await api.getUserInfo('123456'), isEmpty);
      expect(await api.getUserPlaylists('123456'), isEmpty);
      expect(await api.getLegacyPlaylistDetail('888888'), isEmpty);
      expect(await api.addSongToPlaylist('34', 'mid'), isEmpty);
      expect(await api.createPlaylist('新歌单'), isEmpty);
      expect(await api.collectPlaylist('888888'), isEmpty);
      expect(await api.getToplistCatalogue(), isEmpty);
      expect(await api.getToplistCp(topId: 26), isEmpty);
      expect(await api.getSingerDetail('mid'), isEmpty);
      expect(await api.getAlbumInfo('mid'), isEmpty);
      expect(await api.getNewSongs(), isEmpty);
      expect(await api.getQrcLyric('mid'), isNull);
    });

    test('空字符串 body 同样降级（曾是 res.data as Map 的直接崩溃点）', () async {
      final api = QqApi(dio: _stubDio(''));

      expect(await api.getUserInfo('123456'), isEmpty);
      expect(await api.getUserPlaylists('123456'), isEmpty);
      expect(await api.getLegacyPlaylistDetail('888888'), isEmpty);
      expect(await api.createPlaylist('x'), isEmpty);
      expect(await api.collectPlaylist('1'), isEmpty);
      expect(await api.addSongToPlaylist('1', 'mid'), isEmpty);
      expect(await api.searchPlaylists('x'), isEmpty);
      expect(await api.getAlbumInfo('mid'), isEmpty);
    });

    test('双重编码的音乐库响应仍能解析出内容', () async {
      final api = QqApi(
        dio: _stubDio(jsonEncode(jsonEncode({'code': 0, 'dirid': 34}))),
      );

      final res = await api.createPlaylist('x');

      expect(res['dirid'], 34);
    });
  });

  group('QQ 请求走冻结的 createPlatformDio（重试/错误翻译真正生效）', () {
    test('默认 Dio 装有幂等重试守卫与错误翻译拦截器', () {
      final api = QqApi();

      expect(
        api.dioForTest.interceptors.whereType<IdempotentRetryGuard>(),
        hasLength(1),
      );
      expect(
        api.dioForTest.interceptors.whereType<PlatformErrorInterceptor>(),
        isNotEmpty,
      );
      expect(api.dioForTest.options.sendTimeout, isNotNull);
    });

    test('POST（musicu：点赞/歌单写）5xx 绝不重放', () async {
      final adapter = _ScriptedAdapter((_, _) => _errorBody());
      final api = QqApi(dio: _fastPlatformDio());
      api.dioForTest.httpClientAdapter = adapter;

      Object? caught;
      try {
        await api.musicu({
          'comm': {'ct': 19, 'cv': 1845},
          'req_0': {'module': 'x', 'method': 'y', 'param': <String, dynamic>{}},
        });
      } on Object catch (e) {
        caught = e;
      }

      expect(caught, isNotNull);
      expect(adapter.attempts, 1, reason: '重放 POST 会重复点赞/重复写歌单');
      expect(adapter.methods, ['POST']);
      expect(apiExceptionOf(caught!).message, contains('服务器异常'));
    });

    test('GET（toplist_cp：榜单读取）5xx 会重试到上限', () async {
      final adapter = _ScriptedAdapter((_, _) => _errorBody());
      final api = QqApi(dio: _fastPlatformDio());
      api.dioForTest.httpClientAdapter = adapter;

      Object? caught;
      try {
        await api.getToplistCp(topId: 26);
      } on Object catch (e) {
        caught = e;
      }

      // 1 次原始请求 + maxRetries(2) 次重试 —— 若 QqApi 退回裸 Dio，这里只有 1。
      expect(adapter.attempts, 3);
      expect(adapter.methods, everyElement('GET'));
      expect(apiExceptionOf(caught!), isA<ApiException>());
    });
  });
}
