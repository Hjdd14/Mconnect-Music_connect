import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/lyrics/models/lyrics_bundle.dart';
import 'package:mconnect/lyrics/models/lyrics_line.dart';
import 'package:mconnect/platform/qq/qq_api.dart';
import 'package:mconnect/platform/qq/qq_platform.dart';

/// W2-A：QQ 的 `qrc`（逐字）参数修复与死路径收口。
///
/// **QQ 的 `.qrc` 响应体是 3DES 加密的，本仓库没有密钥、也不猜密钥**（同源先例见
/// `docs/mconnect-improvement-plan.md` 的 `.qrc` 说明）。所以这里的契约是：
/// 补 `qrc=1` 让服务端真的返回 QRC 轨；**只有明文、能被 `_parseQrc` 认出来的
/// body 才会被采用**；加密或形状不认识 → 静默回退 LRC，不报错、不产生垃圾行。
void main() {
  /// Stub keyed on the `qrc` parameter, so the LRC request and the QRC request
  /// can return different bodies — which is exactly what the platform has to keep
  /// apart.
  ({QqPlatform platform, List<RequestOptions> requests}) build({
    Map<String, dynamic>? lrcBody,
    Map<String, dynamic>? qrcBody,
  }) {
    final requests = <RequestOptions>[];
    final dio = Dio(BaseOptions(baseUrl: 'https://y.qq.com'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requests.add(options);
          final wantsQrc = options.queryParameters['qrc'] == 1;
          final body = wantsQrc ? qrcBody : lrcBody;
          handler.resolve(
            Response(
              requestOptions: options,
              statusCode: 200,
              data: body ?? const <String, dynamic>{},
            ),
          );
        },
      ),
    );
    return (platform: QqPlatform(api: QqApi(dio: dio)), requests: requests);
  }

  String plainQrc() => '<L T="1000" D="500"><P T="0" D="250">你</P>'
      '<P T="250" D="250">好</P></L>';

  test('the qrc request carries qrc=1 (the parameter it was missing)', () async {
    final stub = build(lrcBody: {'lyric': '[00:01.00]Hello'});

    await stub.platform.getLyricsBundle('mid');

    final qrcRequest = stub.requests.firstWhere(
      (options) => options.queryParameters['qrc'] == 1,
    );
    expect(qrcRequest.queryParameters['qrc'], 1);
    expect(qrcRequest.queryParameters['songmid'], 'mid');
    // The plain-LRC request must stay free of `qrc`, so a ciphertext body can
    // never be mistaken for the guaranteed track.
    final lrcRequest = stub.requests.firstWhere(
      (options) => options.queryParameters['qrc'] == null,
    );
    expect(lrcRequest.queryParameters['qrc'], isNull);
  });

  test('adopts a plaintext QRC body and keeps lrc as well', () async {
    final stub = build(
      lrcBody: {'lyric': base64Encode(utf8.encode('[00:01.00]Hello'))},
      qrcBody: {'lyric': base64Encode(utf8.encode(plainQrc()))},
    );

    final bundle = await stub.platform.getLyricsBundle('mid');

    expect(bundle, isNotNull);
    expect(bundle!.lrc, '[00:01.00]Hello');
    expect(bundle.qrc, plainQrc());
    final track = mainLyricsTrack(bundle)!;
    expect(track.format, LyricsFormat.qrc);
    expect(
      LyricsDocument.parse(track.content, track.format).lines.single.words,
      hasLength(2),
    );
  });

  test('an encrypted (unreadable) body falls back to lrc, silently', () async {
    // 3DES 密文的样子：可 base64 解出来一堆不可打印字节，`_parseQrc` 认不出。
    final ciphertext = base64Encode(List<int>.generate(64, (i) => (i * 37) % 256));
    final stub = build(
      lrcBody: {'lyric': base64Encode(utf8.encode('[00:01.00]Hello'))},
      qrcBody: {'lyric': ciphertext},
    );

    final bundle = await stub.platform.getLyricsBundle('mid');

    expect(bundle!.qrc, isNull, reason: '认不出就是认不出，绝不猜');
    expect(bundle.lrc, '[00:01.00]Hello');
    expect(mainLyricsTrack(bundle)!.format, LyricsFormat.lrc);
    expect(
      buildLyricsDocument(bundle).lines.single.text,
      'Hello',
      reason: '回退后不得出现密文垃圾行',
    );
  });

  test('a failed qrc request still delivers the lrc track', () async {
    final stub = build(
      lrcBody: {'lyric': base64Encode(utf8.encode('[00:01.00]Hello'))},
      // no qrcBody → the stub answers `{}` → getQrcLyric returns null
    );

    final bundle = await stub.platform.getLyricsBundle('mid');

    expect(bundle!.qrc, isNull);
    expect(bundle.lrc, '[00:01.00]Hello');
  });

  test('translation is carried separately, not folded into the lrc string', () async {
    final stub = build(
      lrcBody: {
        'lyric': base64Encode(utf8.encode('[00:01.00]Hello')),
        'trans': base64Encode(utf8.encode('[00:01.00]你好')),
      },
    );

    final bundle = await stub.platform.getLyricsBundle('mid');

    expect(bundle!.lrc, '[00:01.00]Hello');
    expect(bundle.translation, '[00:01.00]你好');
    final document = buildLyricsDocument(bundle);
    expect(document.lines.single.translation, '你好');
  });

  test('getLyric still folds lrc and translation into one string', () async {
    // 兼容旧调用方（qq_api_test 守着这一条）。
    final stub = build(
      lrcBody: {
        'lyric': base64Encode(utf8.encode('[00:01.00]Hello')),
        'trans': base64Encode(utf8.encode('[00:01.00]你好')),
      },
    );

    final lyric = await stub.platform.getLyrics('mid');

    expect(lyric, contains('[00:01.00]Hello'));
    expect(lyric, contains('[00:01.00]你好'));
  });

  test('no lyrics at all is reported as no lyrics', () async {
    final stub = build();

    expect(await stub.platform.getLyricsBundle('mid'), isNull);
    expect(
      LyricsBundle(lrc: '  ', qrc: '').isEmpty,
      isTrue,
      reason: '空白轨不算有歌词',
    );
  });

  test('getQrcLyric still degrades to null on a null body', () async {
    // test/qq_api_guard_test.dart:98 的同一条守护。
    final dio = Dio(BaseOptions(baseUrl: 'https://y.qq.com'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) => handler.resolve(
          Response(requestOptions: options, statusCode: 200, data: null),
        ),
      ),
    );

    expect(await QqApi(dio: dio).getQrcLyric('mid'), isNull);
  });

  test('decodeLyricField tolerates both base64 and plain text', () {
    expect(QqApi.decodeLyricField(base64Encode(utf8.encode('词'))), '词');
    expect(QqApi.decodeLyricField('[00:01.00]词'), '[00:01.00]词');
    expect(QqApi.decodeLyricField(null), isNull);
    expect(QqApi.decodeLyricField(''), isNull);
  });
}
