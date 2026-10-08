import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/lyrics/models/lyrics_line.dart';
import 'package:mconnect/platform/netease/netease_api.dart';
import 'package:mconnect/platform/netease/netease_platform.dart';

/// W2-A：网易云多轨歌词（`yrc` 逐字 / `romalrc` 罗马音 / `tlyric` 翻译）。
///
/// 形状与参数集来自真机观测，见 `docs/netease-lyric-shapes.md`：`rv=-1` 才是解锁
/// 罗马音的开关，而 `yrc`/`romalrc` 都是**按歌可选**的。样本用自建文本。
void main() {
  ({NeteasePlatform platform, List<RequestOptions> requests}) build(
    Map<String, dynamic> data,
  ) {
    final requests = <RequestOptions>[];
    final dio = Dio(BaseOptions(baseUrl: 'https://music.163.com'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requests.add(options);
          handler.resolve(
            Response(requestOptions: options, statusCode: 200, data: data),
          );
        },
      ),
    );
    return (platform: NeteasePlatform(api: NeteaseApi(dio: dio)), requests: requests);
  }

  test('requests every lyric track the endpoint can return', () async {
    // 这是本条的根因：只发 lv/tv 时 yrc/romalrc 永远不会出现在响应里。
    final stub = build({
      'lrc': {'lyric': '[00:01.00]Hello'},
    });

    await stub.platform.getLyricsBundle('1');

    final query = stub.requests.single.queryParameters;
    expect(query['lv'], -1);
    expect(query['tv'], -1);
    expect(query['yv'], -1, reason: 'yv 解锁 yrc（逐字）');
    expect(query['yrv'], -1, reason: 'yrv 解锁 yrc 的翻译轨');
    expect(query['rv'], -1, reason: 'rv 才是解锁 romalrc 的那个参数');
  });

  test('carries lrc, translation, yrc and romaji as separate tracks', () async {
    final stub = build({
      'lrc': {'lyric': '[00:01.00]Hello'},
      'tlyric': {'lyric': '[00:01.00]你好'},
      'yrc': {'lyric': '[1000,1000](0,500,0)Hello'},
      'romalrc': {'lyric': '[00:01.000]Hello'},
    });

    final bundle = await stub.platform.getLyricsBundle('1');

    expect(bundle, isNotNull);
    expect(bundle!.lrc, '[00:01.00]Hello');
    expect(bundle.translation, '[00:01.00]你好');
    expect(bundle.yrc, '[1000,1000](0,500,0)Hello');
    expect(bundle.romaji, '[00:01.000]Hello');
    expect(bundle.isEmpty, isFalse);
  });

  test('a song without yrc/romalrc is normal, not an error', () async {
    final stub = build({
      'lrc': {'lyric': '[00:01.00]Hello'},
      'tlyric': {'lyric': '[00:01.00]你好'},
    });

    final bundle = await stub.platform.getLyricsBundle('1');

    expect(bundle!.lrc, isNotNull);
    expect(bundle.yrc, isNull);
    expect(bundle.romaji, isNull);
    expect(bundle.isEmpty, isFalse);
  });

  test('a blank track is treated as absent', () async {
    final stub = build({
      'lrc': {'lyric': '[00:01.00]Hello'},
      'yrc': {'lyric': '   '},
      'romalrc': <String, dynamic>{},
    });

    final bundle = await stub.platform.getLyricsBundle('1');

    expect(bundle!.yrc, isNull);
    expect(bundle.romaji, isNull);
  });

  test('reports no lyrics when the response carries no track at all', () async {
    final stub = build(const <String, dynamic>{});

    expect(await stub.platform.getLyricsBundle('1'), isNull);
  });

  test('yromalrc is accepted when romalrc is missing', () async {
    final stub = build({
      'lrc': {'lyric': '[00:01.00]Hello'},
      'yromalrc': {'lyric': '[00:01.000]Hello'},
    });

    final bundle = await stub.platform.getLyricsBundle('1');

    expect(bundle!.romaji, '[00:01.000]Hello');
  });

  test('getLyrics still folds the two LRC tracks into one string', () async {
    // 兼容旧调用方（以及既有的 netease_api_test）：单字符串接口的行为不变。
    final stub = build({
      'lrc': {'lyric': '[00:01.00]Hello'},
      'tlyric': {'lyric': '[00:01.00]Ni hao'},
    });

    final lyric = await stub.platform.getLyrics('1');

    expect(lyric, contains('[00:01.00]Hello'));
    expect(lyric, contains('[00:01.00]Ni hao'));
  });

  test('the word-by-word track reaches a parsed document', () async {
    final stub = build({
      'lrc': {'lyric': '[00:01.00]Hello'},
      'yrc': {'lyric': '[1000,1000](0,500,0)Hel(500,500,0)lo'},
    });

    final bundle = await stub.platform.getLyricsBundle('1');
    final document = LyricsDocument.parse(
      bundle!.yrc!,
      LyricsFormat.yrc,
      source: LyricsSource.netease,
    );

    expect(document.lines.single.text, 'Hello');
    expect(document.lines.single.words, hasLength(2));
    expect(document.source, LyricsSource.netease);
  });
}
