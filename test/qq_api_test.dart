import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/models/audio_quality.dart';
import 'package:mconnect/platform/qq/qq_platform.dart';
import 'package:mconnect/platform/qq/qq_api.dart';

void main() {
  test(
    'QQ daily playlist parser recognizes the real today-private title',
    () async {
      final api = QqApi(
        dio: _plainTextDio('''
<div class="mod_for_u">
  <div class="playlist__item">
    <a class="playlist__link" data-rid="987654"></a>
    <div class="playlist__name">\u4eca\u65e5\u79c1\u4eab</div>
  </div>
</div>
'''),
      );

      final id = await api.getDailyPlaylistId();

      expect(id, '987654');
    },
  );

  test(
    'QQ lyrics include translated lines when the API returns trans text',
    () async {
      final api = QqApi(
        dio: _jsonDio({
          'lyric': '[00:01.00]Hello',
          'trans': '[00:01.00]Ni hao',
        }),
      );

      final lyric = await api.getLyric('songmid');

      expect(lyric, contains('[00:01.00]Hello'));
      expect(lyric, contains('[00:01.00]Ni hao'));
    },
  );

  test(
    'QQ daily recommendations parse songInfo playlist detail rows',
    () async {
      final platform = QqPlatform(api: _FakeDailyQqApi());
      // A cookie is what unlocks 「今日私享」; without one the platform skips the
      // private probe and goes straight to the chart fallback.
      platform.api.setCookie('qqmusic_uin=123456; qm_keyst=token');

      final songs = await platform.getDailyRecommendations();

      expect(songs, hasLength(1));
      expect(songs.single.id, 'mid1');
      expect(songs.single.name, 'Daily Song');
    },
  );

  test(
    'QQ OAuth follows redirects by hand and keeps p_skey from an early hop',
    () async {
      // 真机证据（2026-10-09）：
      //   QQ OAuth: check_sig done, cookies: 452 chars
      //   QQ OAuth: p_skey=null, g_tk=5381        ← 退化成 DJB2 初值
      //   QQ OAuth: failed to extract auth code, location=…oauth2.0/show?…
      // 成因：`_dio.get(redirectUrl)` 用 dio 默认的 followRedirects: true，整条链
      // 被折叠成"最终响应"，而 p_skey 是**中间某一跳**发的 Set-Cookie ⇒ 丢掉。
      // 本用例让第一跳返回 p_skey + Location、第二跳 200，断言：
      //   ① 两跳都被调用（说明手动跟随生效，而不是被 dio 折叠成一次）
      //   ② p_skey 真的进了 cookie
      // 修前必红（旧实现只请求一次、且 p_skey 为空）。
      final called = <String>[];
      final api = QqApi(
        dio: _hopCookieDio(calledUrls: called),
      );

      await api.completeOAuthLogin(
        'https://ssl.ptlogin2.graph.qq.com/check_sig?pttype=1&uin=123',
      );

      expect(
        called.length,
        greaterThanOrEqualTo(2),
        reason: '必须逐跳跟随（旧实现只发一次请求，把中间跳的 Set-Cookie 丢掉了）',
      );
      expect(
        api.cookie,
        contains('p_skey=ABC123'),
        reason: '中间跳发的 p_skey 必须被累积进 cookie —— g_tk 由它推导',
      );
      expect(
        called.last,
        contains('graph.qq.com'),
        reason: '第二跳应该落在 Location 指向的地址上',
      );
    },
  );

  test(
    'merging Set-Cookie lines keeps cookie pairs, NOT attribute segments',
    () {
      // 真机证据（2026-10-10）：登录一直弹回「QQ帐号安全登录」页，而
      // `sending cookie names to graph` 打出：
      //   [Domain, ETK, Expires, HttpOnly, Path, RK, SameSite, Secure,
      //    airkey, p_skey, p_skey_forbid, p_uin, pt2gguin, ...]
      // —— `Domain`/`Path`/`Expires`/`HttpOnly` 根本不是 cookie，是
      // Set-Cookie 的属性片段。旧的 `hopCookies.join('; ')` 把整行塞进 jar，
      // graph.qq.com 收到的 Cookie 头是畸形的，直接判"未登录"。
      // 本用例把真机那条形态原样钉死。
      final merged = QqApi.mergeSetCookiesForTest(
        existing: 'qrsig=OLD',
        setCookieLines: const [
          'p_skey=NEW_PSKEY; Path=/; Domain=.ptlogin2.graph.qq.com; '
              'HttpOnly; Secure; SameSite=None',
          'p_uin=o2443599899; Path=/; Domain=.qq.com; HttpOnly',
          'pt4_token=TOKEN; Path=/; Domain=.ptlogin2.graph.qq.com; HttpOnly',
        ],
      );

      final names = merged.split('; ').map((p) => p.split('=').first).toSet();
      expect(
        names,
        isNot(contains('Path')),
        reason: 'Path 是属性片段，不是 cookie —— 出现即说明 jar 被污染',
      );
      expect(
        names,
        isNot(contains('Domain')),
        reason: 'Domain 是属性片段，不是 cookie',
      );
      expect(
        names,
        isNot(contains('HttpOnly')),
        reason: 'HttpOnly 是属性片段，不是 cookie',
      );
      expect(
        names,
        isNot(contains('Secure')),
        reason: 'Secure 是属性片段，不是 cookie',
      );
      expect(merged, contains('p_skey=NEW_PSKEY'));
      expect(merged, contains('p_uin=o2443599899'));
      expect(merged, contains('qrsig=OLD'), reason: '旧 jar 里的项必须保留');
    },
  );

  test(
    'a Set-Cookie line with FOLDED commas yields every cookie, including p_skey',
    () {
      // 真机证据（2026-10-10）：hop 日志打出
      //   cookieNames=[pt2gguin, pt2gguin, p_uin, p_uin, p_skey, p_skey, ...]
      // 每个名字出现两次 ⇒ dio 的一个 set-cookie 条目里折叠了多个 cookie；
      // 而修复前 merge 之后 `p_skey=false` ⇒ p_skey 被吞。真实形态是
      //   `pt2gguin=oX; Path=/, p_skey=yyy; Path=/; Domain=.qq.com`
      // 逗号才是第二层分隔符。
      final merged = QqApi.mergeSetCookiesForTest(
        existing: '',
        setCookieLines: const [
          'pt2gguin=oX; Path=/, p_skey=YYY; Path=/; Domain=.qq.com',
          'pt4_token=T; Path=/, p_uin=o2443599899; Path=/; Domain=.qq.com',
        ],
      );

      expect(merged, contains('pt2gguin=oX'));
      expect(
        merged,
        contains('p_skey=YYY'),
        reason: 'p_skey 在折叠逗号之后，必须被拆出来 —— 修前它被吞进前一项的值里',
      );
      expect(merged, contains('p_uin=o2443599899'));
      // `Expires=Wed, 21 Oct ...` 的逗号后面是星期/日期，不是 name=，
      // 不得被误拆：
      final withDate = QqApi.mergeSetCookiesForTest(
        existing: '',
        setCookieLines: const [
          'a=B; Expires=Wed, 21 Oct 2026 07:28:00 GMT; Path=/',
        ],
      );
      expect(withDate, contains('a=B'));
      expect(withDate.contains('21 Oct'), isFalse, reason: 'Expires 的值不是 cookie');
    },
  );

  test(
    'an EMPTY Set-Cookie value is a deletion order and must NOT wipe the real one',
    () {
      // 真机证据（2026-10-10）：jar 名单里有 p_skey，值却是 null、g_tk=5381。
      // 参考抓包（QQ 扫码 OAuth2 反向工程）显示 QQ 会发"删除型" Set-Cookie：
      //   ptcz=;Expires=Thu, 01 Jan 1970 00:00:00 GMT;Path=/;Domain=ptlogin2.qq.com;
      // 浏览器按 (名字, 域) 存 cookie，域限定的删除令不影响其他域的同名真值；
      // 本 jar 是扁平的，若照单全收就会把前面刚写入的真值覆盖成空 —— p_skey
      // 就是这样消失的。所以：空值不得进入 jar。
      final merged = QqApi.mergeSetCookiesForTest(
        existing: '',
        setCookieLines: const [
          'p_skey=REAL_PSKEY; Path=/; Domain=.qq.com; HttpOnly; Secure',
          'p_skey=; Expires=Thu, 01 Jan 1970 00:00:00 GMT; Path=/; '
              'Domain=ptlogin2.qq.com',
          'p_uin=o2443599899; Path=/; Domain=.qq.com',
        ],
      );

      expect(
        merged,
        contains('p_skey=REAL_PSKEY'),
        reason: '删除令（空值）出现在真值之后，不得把真值清掉',
      );
      expect(merged, isNot(contains('p_skey=;')));
      expect(merged, contains('p_uin=o2443599899'));
    },
  );

  test('QQ OAuth cookie builder keeps QQ Music login tokens from QQLogin', () {
    final cookie = QqApi.buildMusicLoginCookieForTest(
      existingCookie: 'p_skey=ps-key; skey=s-key',
      loginData: const {
        'uin': '123456',
        'musicid': '654321',
        'musickey': 'music-token',
      },
    );

    expect(cookie, contains('p_skey=ps-key'));
    expect(cookie, contains('skey=s-key'));
    expect(cookie, contains('uin=o123456'));
    expect(cookie, contains('qqmusic_uin=654321'));
    expect(cookie, contains('qqmusic_key=music-token'));
    expect(cookie, contains('qm_keyst=music-token'));
  });

  test('QQ cookie extraction matches exact cookie names', () {
    final value = QqApi.extractCookieForTest(
      'p_skey=ps-key; skey=s-key',
      'skey',
    );

    expect(value, 's-key');
  });

  test('QQ quality filename prefixes follow current QQ Music file types', () {
    expect(QqApi.filenameForTest('mid1', AudioLevel.low), 'M500mid1mid1.mp3');
    expect(
      QqApi.filenameForTest('mid1', AudioLevel.medium),
      'M800mid1mid1.mp3',
    );
    expect(
      QqApi.filenameForTest('mid1', AudioLevel.lossless),
      'F000mid1mid1.flac',
    );
    expect(
      QqApi.filenameForTest('mid1', AudioLevel.hires),
      'RS01mid1mid1.flac',
    );
    expect(
      QqApi.filenameForTest('mid1', AudioLevel.spatial),
      'Q000mid1mid1.flac',
    );
    expect(
      QqApi.filenameForTest('mid1', AudioLevel.dolby),
      'Q001mid1mid1.flac',
    );
    expect(
      QqApi.filenameForTest('mid1', AudioLevel.master),
      'AI00mid1mid1.flac',
    );
  });

  test(
    'QQ VIP playback request uses logged-in uin and cookie tokens',
    () async {
      final dio = Dio();
      Map<String, dynamic>? capturedBody;
      Map<String, dynamic>? capturedHeaders;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            capturedBody = Map<String, dynamic>.from(options.data as Map);
            capturedHeaders = Map<String, dynamic>.from(options.headers);
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'req_1': {
                    'data': {
                      'sip': ['https://dl.stream.qqmusic.qq.com/'],
                      'midurlinfo': [
                        {'purl': 'F000mid1mid1.flac?vkey=abc'},
                      ],
                    },
                  },
                },
              ),
            );
          },
        ),
      );
      final api = QqApi(dio: dio)
        ..setCookie('uin=o123456; qqmusic_uin=123456; qm_keyst=music-token');

      await api.getSongUrl('mid1', quality: AudioLevel.lossless);

      expect(capturedHeaders?['cookie'], contains('qm_keyst=music-token'));
      expect(capturedBody?['loginUin'], '123456');
      expect(capturedBody?['comm']?['uin'], '123456');
      final dispatchParam = capturedBody?['req_0']?['param'] as Map;
      final vkeyParam = capturedBody?['req_1']?['param'] as Map;
      expect(dispatchParam['guid'], isNot('0'));
      expect(vkeyParam['guid'], dispatchParam['guid']);
      expect(vkeyParam['uin'], '123456');
      expect(vkeyParam['filename'], ['F000mid1mid1.flac']);
      expect(vkeyParam['loginflag'], 1);
    },
  );
}

/// A Dio whose first call answers with a 302 carrying `p_skey`, and whose second
/// call answers 200. Used to prove that `completeOAuthLogin` follows the redirect
/// by hand and accumulates EVERY hop's cookies — the bug was that `dio`'s default
/// `followRedirects: true` collapsed the chain, so `p_skey` (issued mid-chain) was
/// lost and `g_tk` fell back to the DJB2 seed 5381.
Dio _hopCookieDio({required List<String> calledUrls}) {
  final dio = Dio();
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        calledUrls.add(options.uri.toString());
        if (calledUrls.length == 1) {
          handler.resolve(
            Response(
              requestOptions: options,
              statusCode: 302,
              data: '',
              headers: Headers.fromMap({
                'set-cookie': ['p_skey=ABC123; path=/; domain=.qq.com'],
                'location': ['https://graph.qq.com/oauth2.0/show?which=Login'],
              }),
            ),
          );
        } else {
          handler.resolve(
            Response(requestOptions: options, statusCode: 200, data: ''),
          );
        }
      },
    ),
  );
  return dio;
}

Dio _plainTextDio(String body) {  final dio = Dio();
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        handler.resolve(
          Response(requestOptions: options, statusCode: 200, data: body),
        );
      },
    ),
  );
  return dio;
}

Dio _jsonDio(Map<String, dynamic> body) {
  final dio = Dio();
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        handler.resolve(
          Response(requestOptions: options, statusCode: 200, data: body),
        );
      },
    ),
  );
  return dio;
}

class _FakeDailyQqApi extends QqApi {
  @override
  Future<String?> getDailyPlaylistId() async => '123456';

  @override
  Future<Map<String, dynamic>> getPlaylistDetail(
    String disstid, {
    int songBegin = 0,
    int songNum = 200,
  }) async {
    return {
      'req_0': {
        'data': {
          'songlist': [
            {
              'songInfo': {
                'mid': 'mid1',
                'name': 'Daily Song',
                'singer': [
                  {'mid': 'artist1', 'name': 'Artist 1'},
                ],
                'interval': 180,
              },
            },
          ],
        },
      },
    };
  }
}
