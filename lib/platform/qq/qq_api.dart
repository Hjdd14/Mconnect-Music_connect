import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../core/network/platform_http.dart';
import '../../models/audio_quality.dart';
import '../../models/platform_type.dart';
import 'qq_endpoints.dart';
import 'qq_toplist_ids.dart';

class QqApi {
  final Dio _dio;
  String? _cookie;
  String? _playbackGuid;

  /// QQ's `g_tk` ("bkn"): the DJB2 hash of `p_skey`, masked to 31 bits.
  ///
  /// Five playlist endpoints used to hardcode `5381` — which is merely the DJB2
  /// *seed*, i.e. the value you get when you hash nothing. The correctly computed
  /// value was already being produced at login (see the OAuth step that stores
  /// it) and used for the OAuth-authorize call, but the playlist reads/writes
  /// never picked it up. It is a field now so every call site shares one value.
  int _gTk = 5381;

  /// Builds the QQ adapter.
  ///
  /// The default [Dio] comes from [createPlatformDio], so QQ requests get the
  /// shared interceptor chain: idempotent-only retry, `sendTimeout`, and typed
  /// error translation. That guard is what keeps the many **POST** calls here
  /// (`musicu.fcg`, like/playlist writes) from being replayed — a retried
  /// "add song to playlist" would add it twice — while GETs still retry.
  QqApi({Dio? dio})
    : _dio =
          dio ??
          createPlatformDio(
            // Enables central session-expiry reporting (see platform_http).
            platform: PlatformType.qq,
            label: 'QQ音乐',
            headers: {
              'User-Agent':
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
              'Referer': 'https://y.qq.com/',
              'Origin': 'https://y.qq.com',
            },
          );

  /// The Dio this adapter actually uses.
  ///
  /// Exposed so tests can prove the shared interceptor chain is installed (a
  /// bare, interceptor-less `Dio` is the pre-v1.4.0 state that made retry and
  /// error translation dead code) and so a scripted adapter can be attached to
  /// observe retry behaviour.
  @visibleForTesting
  Dio get dioForTest => _dio;

  void setCookie(String cookie) {
    if (cookie.isEmpty) {
      _cookie = '';
      _dio.options.headers['cookie'] = '';
      return;
    }
    if (_cookie == null || _cookie!.isEmpty) {
      _cookie = cookie;
    } else {
      final existing = _parseCookieMap(_cookie!);
      existing.addAll(_parseCookieMap(cookie));
      _cookie = existing.entries.map((e) => '${e.key}=${e.value}').join('; ');
    }
    _dio.options.headers['cookie'] = _cookie;
  }

  static Map<String, String> _parseCookieMap(String cookieStr) {
    final map = <String, String>{};
    for (final part in cookieStr.split(';')) {
      final trimmed = part.trim();
      final eqIndex = trimmed.indexOf('=');
      if (eqIndex > 0) {
        final name = trimmed.substring(0, eqIndex).trim();
        final lowerName = name.toLowerCase();
        if (const {
          'path',
          'domain',
          'expires',
          'max-age',
          'secure',
          'httponly',
          'samesite',
        }.contains(lowerName)) {
          continue;
        }
        map[name] = trimmed.substring(eqIndex + 1);
      }
    }
    return map;
  }

  static String _cookieStringFromMap(Map<String, String> cookies) {
    return cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');
  }

  @visibleForTesting
  static String buildMusicLoginCookieForTest({
    required String existingCookie,
    required Map<String, dynamic> loginData,
  }) {
    return _buildMusicLoginCookie(
      existingCookie: existingCookie,
      loginData: loginData,
    );
  }

  @visibleForTesting
  static String? extractCookieForTest(String cookie, String name) {
    return _extractCookieValue(cookie, name);
  }

  static String _buildMusicLoginCookie({
    required String existingCookie,
    required Map<dynamic, dynamic>? loginData,
  }) {
    final cookies = _parseCookieMap(existingCookie);
    final data = loginData ?? const {};

    void put(String name, dynamic value) {
      final text = value?.toString();
      if (text != null && text.isNotEmpty && text != 'null') {
        cookies[name] = text;
      }
    }

    String? firstText(List<String> names) {
      for (final name in names) {
        final value = data[name];
        final text = value?.toString();
        if (text != null && text.isNotEmpty && text != '0') return text;
      }
      return null;
    }

    String? digitsOnly(String? value) {
      if (value == null || value.isEmpty) return null;
      final match = RegExp(r'\d+').firstMatch(value);
      return match?.group(0);
    }

    final uin = digitsOnly(
      firstText(['uin', 'loginUin', 'qqmusic_uin', 'musicid', 'music_id']),
    );
    final musicUin = digitsOnly(
      firstText(['musicid', 'music_id', 'musicuin', 'qqmusic_uin', 'uin']),
    );
    final musicKey = firstText([
      'musickey',
      'music_key',
      'qqmusic_key',
      'qm_keyst',
    ]);

    if (uin != null) {
      put('uin', 'o$uin');
      put('loginUin', uin);
    }
    if (musicUin != null) {
      put('qqmusic_uin', musicUin);
    }
    if (musicKey != null) {
      put('qqmusic_key', musicKey);
      put('qm_keyst', musicKey);
      put('musickey', musicKey);
    }
    put('openid', firstText(['openid', 'openId']));
    put('access_token', firstText(['access_token', 'accessToken']));
    put('refresh_key', firstText(['refresh_key', 'refreshKey']));

    return _cookieStringFromMap(cookies);
  }

  String? get cookie => _cookie;

  void restoreCookie(String cookie) {
    _cookie = cookie;
    _dio.options.headers['cookie'] = cookie;
  }

  /// Normalises a QQ response body into a map.
  ///
  /// QQ answers some JSON endpoints with a JSON *string* (and occasionally with
  /// a double-encoded one), and a failed/empty body can arrive as `null` or an
  /// empty string. The pre-v1.4.0 code did `res.data as Map<String, dynamic>`,
  /// which threw a raw `TypeError` on every one of those cases and crashed the
  /// caller instead of degrading to "no data". Callers now always get a map.
  static Map<String, dynamic> responseMapOf(dynamic data) {
    if (data == null) return <String, dynamic>{};
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    if (data is List) return <String, dynamic>{};
    if (data is String) {
      final text = data.trim();
      if (text.isEmpty) return <String, dynamic>{};
      try {
        return responseMapOf(jsonDecode(text));
      } catch (_) {
        return <String, dynamic>{};
      }
    }
    return <String, dynamic>{};
  }

  /// Generic musicu request
  Future<Map<String, dynamic>> musicu(Map<String, dynamic> data) async {
    final res = await _dio.post(
      QqEndpoints.musicu,
      data: data,
      options: Options(
        contentType: Headers.jsonContentType,
        responseType: ResponseType.json,
      ),
    );
    return responseMapOf(res.data);
  }

  /// Content of one musicu module response (`res[key]`).
  ///
  /// The response key always equals the request key (`toplist`, `singer`,
  /// `newsong`, `req_0`, …), so the caller must pass the key it sent.
  static Map<String, dynamic> moduleOf(
    Map<String, dynamic> response,
    String key,
  ) {
    final module = response[key];
    return module is Map ? Map<String, dynamic>.from(module) : <String, dynamic>{};
  }

  /// Search songs
  Future<Map<String, dynamic>> search(
    String keyword, {
    int page = 1,
    int limit = 30,
  }) async {
    return musicu({
      'comm': {'ct': 19, 'cv': 1845},
      'req_0': {
        'method': 'DoSearchForQQMusicDesktop',
        'module': 'music.search.SearchCgiService',
        'param': {
          'num_per_page': limit,
          'page_num': page,
          'query': keyword,
          'search_type': 0,
        },
      },
    });
  }

  /// Search public playlists.
  Future<Map<String, dynamic>> searchPlaylists(
    String keyword, {
    int page = 1,
    int limit = 30,
  }) async {
    final res = await _dio.get(
      QqEndpoints.searchPlaylist,
      queryParameters: {
        'remoteplace': 'txt.yqq.playlist',
        'page_no': page - 1,
        'num_per_page': limit,
        'query': keyword,
        'format': 'json',
      },
      options: Options(
        responseType: ResponseType.json,
        headers: {'Referer': 'https://y.qq.com'},
      ),
    );
    return responseMapOf(res.data);
  }

  /// Get song URL via CDN dispatch
  Future<Map<String, dynamic>> getSongUrl(
    String songMid, {
    AudioLevel quality = AudioLevel.low,
  }) async {
    final filename = _filenameFor(songMid, quality);
    final uin = _loggedInUin();
    final guid = _getPlaybackGuid();
    return musicu({
      'comm': {'ct': 19, 'cv': 1845, 'uin': uin},
      'loginUin': uin,
      'req_0': {
        'module': 'CDN.SrfCdnDispatchServer',
        'method': 'GetCdnDispatch',
        'param': {'guid': guid, 'calltype': 0, 'userip': ''},
      },
      'req_1': {
        'module': 'vkey.GetVkeyServer',
        'method': 'CgiGetVkey',
        'param': {
          'guid': guid,
          'songmid': [songMid],
          'songtype': [0],
          'uin': uin,
          'loginflag': 1,
          'platform': '20',
          'filename': [filename],
        },
      },
    });
  }

  String _loggedInUin() {
    return _extractCookie('qqmusic_uin')?.replaceAll(RegExp(r'\D'), '') ??
        _extractCookie('uin')?.replaceAll(RegExp(r'\D'), '') ??
        _extractCookie('loginUin')?.replaceAll(RegExp(r'\D'), '') ??
        '0';
  }

  String _getPlaybackGuid() {
    final existing = _playbackGuid;
    if (existing != null && existing.isNotEmpty && existing != '0') {
      return existing;
    }
    final micros = DateTime.now().microsecondsSinceEpoch;
    final value = (micros % 9000000000) + 1000000000;
    _playbackGuid = value.toString();
    return _playbackGuid!;
  }

  @visibleForTesting
  static String filenameForTest(String songMid, AudioLevel quality) {
    return _filenameFor(songMid, quality);
  }

  static String _filenameFor(String songMid, AudioLevel quality) {
    final spec = switch (quality) {
      AudioLevel.low => (prefix: 'M500', extension: 'mp3'),
      AudioLevel.medium => (prefix: 'M800', extension: 'mp3'),
      AudioLevel.high => (prefix: 'M800', extension: 'mp3'),
      AudioLevel.lossless => (prefix: 'F000', extension: 'flac'),
      AudioLevel.hires => (prefix: 'RS01', extension: 'flac'),
      AudioLevel.spatial => (prefix: 'Q000', extension: 'flac'),
      AudioLevel.dolby => (prefix: 'Q001', extension: 'flac'),
      AudioLevel.master => (prefix: 'AI00', extension: 'flac'),
    };
    return '${spec.prefix}$songMid$songMid.${spec.extension}';
  }

  /// Get lyrics
  Future<String?> getLyric(String songMid) async {
    final tracks = await getLyricTracks(songMid);
    final lyric = tracks.lyric;
    if (lyric == null || lyric.isEmpty) return null;
    final translation = tracks.translation;
    if (translation == null || translation.isEmpty) return lyric;
    return '$lyric\n$translation';
  }

  /// The plain lyric endpoint's two LRC tracks, still **separate**.
  ///
  /// [getLyric] folds them into one string for callers that only understand one
  /// string; the platform's `getLyricsBundle` needs them apart so the
  /// translation stays in its own field, and so a `qrc=1` request can never mix
  /// ciphertext into the LRC track.
  Future<({String? lyric, String? translation})> getLyricTracks(
    String songMid,
  ) async {
    try {
      final res = await _dio.get(
        QqEndpoints.lyricBase,
        queryParameters: {'songmid': songMid, 'format': 'json', 'nobase64': 1},
      );
      // Response may be a JSON string or already parsed Map
      dynamic data = res.data;
      if (data is String) {
        data = jsonDecode(data);
      }
      if (data is! Map || data['lyric'] == null) {
        return (lyric: null, translation: null);
      }
      return (
        lyric: decodeLyricField(data['lyric']),
        translation: decodeLyricField(
          data['trans'] ?? data['translation'] ?? data['transLyric'],
        ),
      );
    } catch (_) {
      return (lyric: null, translation: null);
    }
  }

  /// Decodes one lyric field: base64 when it is base64, the text otherwise.
  ///
  /// Public because the QRC path has to inspect the body before deciding whether
  /// it is readable QRC or encrypted bytes.
  static String? decodeLyricField(dynamic value) {
    if (value == null) return null;
    final text = value.toString();
    if (text.isEmpty) return null;
    try {
      return utf8.decode(base64Decode(text));
    } catch (_) {
      return text;
    }
  }

  /// Get QRC lyrics (encrypted, word-by-word).
  ///
  /// **`qrc=1` is the parameter that makes the endpoint return the QRC track** —
  /// without it this method could never return QRC, which is why it was dead code
  /// with no caller.
  ///
  /// The body is **3DES-encrypted** and this repository has no key, and does not
  /// guess keys (see the `.qrc` note in `docs/mconnect-improvement-plan.md`).
  /// Callers must treat the result as "maybe readable, maybe not" and keep the
  /// plain LRC path as the guaranteed one.
  Future<Map<String, dynamic>?> getQrcLyric(String songMid) async {
    try {
      final res = await _dio.get(
        QqEndpoints.lyricBase,
        queryParameters: {
          'songmid': songMid,
          'format': 'json',
          'nobase64': 1,
          'qrc': 1,
        },
      );
      dynamic data = res.data;
      if (data is String) {
        data = jsonDecode(data);
      }
      final map = data is Map ? data : const <String, dynamic>{};
      return map.isEmpty ? null : responseMapOf(map);
    } catch (_) {
      return null;
    }
  }

  /// QR code login - get ptqrshow
  Future<List<int>?> getQrImage() async {
    try {
      final res = await _dio.get(
        QqEndpoints.qrShow,
        queryParameters: {
          'appid': 716027609,
          'e': 2,
          'l': 'M',
          's': '3',
          'd': 72,
          'v': 4,
          't': DateTime.now().millisecondsSinceEpoch ~/ 1000,
          'daid': 383,
          'pt_3rd_aid': 100497308,
        },
        options: Options(responseType: ResponseType.bytes),
      );
      // Store qrsig cookie (attribute segments stripped — see [_mergeSetCookies]).
      final cookies = res.headers['set-cookie'];
      if (cookies != null && cookies.isNotEmpty) {
        setCookie(_mergeSetCookies(existing: _cookie ?? '', setCookieLines: cookies));
      }
      return res.data as List<int>?;
    } catch (_) {
      return null;
    }
  }

  /// QR code login - poll status
  Future<Map<String, dynamic>> checkQr() async {
    try {
      final res = await _dio.get(
        QqEndpoints.qrLogin,
        queryParameters: {
          'u1': QqEndpoints.graphLoginJump,
          'ptqrtoken': _getQrHash(_extractCookie('qrsig') ?? ''),
          'ptredirect': 1,
          'h': 1,
          't': 1,
          'g': 1,
          'from_ui': 1,
          'ptlang': 2052,
          'action': '0-0-${DateTime.now().millisecondsSinceEpoch ~/ 1000}',
          'js_ver': 24060411,
          'js_type': 1,
          'login_sig': '',
          'pt_uistyle': 40,
          'aid': 716027609,
          'daid': 383,
          'pt_3rd_aid': 100497308,
        },
        options: Options(
          responseType: ResponseType.plain,
          headers: {'cookie': _cookie ?? ''},
        ),
      );
      final text = res.data.toString();
      final cookieHeaders = res.headers['set-cookie'];
      // Raw lines are returned so the caller can merge them with
      // [_mergeSetCookies]; joining here would leak attribute segments into the
      // jar, which is precisely the bug that made graph.qq.com reject the session.
      final cookieStr = cookieHeaders == null
          ? null
          : _mergeSetCookies(existing: _cookie ?? '', setCookieLines: cookieHeaders);
      return {'raw': text, 'cookies': cookieStr};
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  /// Follow check_sig redirect to graph.qq.com, then OAuth authorize, then exchange code
  Future<String?> completeOAuthLogin(String redirectUrl) async {
    try {
      // Step 3: Follow check_sig URL → sets cookies on graph.qq.com.
      //
      // **Hop by hop, following redirects manually.** `dio` defaults to
      // `followRedirects: true`, which collapses this chain into the FINAL
      // response — and `res.headers['set-cookie']` then only carries the last
      // hop's cookies. `p_skey` is issued on one of the intermediate hops, so it
      // was being dropped, and the device log showed the consequence:
      //
      //   QQ OAuth: check_sig done, cookies: 452 chars
      //   QQ OAuth: p_skey=null, g_tk=5381        <- g_tk fell back to the DJB2 seed
      //   QQ OAuth: failed to extract auth code, location=https://graph.qq.com/oauth2.0/show?...
      //
      // Without p_skey the `g_tk` sent to `oauth2.0/authorize` is wrong, so the
      // platform answers by bouncing the user back to `oauth2.0/show` instead of
      // returning `Location: ...?code=...`, and no auth code can ever be read.
      // Following manually lets every hop's Set-Cookie be accumulated.
      var currentUrl = redirectUrl;
      const maxHops = 10;
      for (var hop = 0; hop < maxHops; hop++) {
        final res = await _dio.get(
          currentUrl,
          options: Options(
            responseType: ResponseType.plain,
            followRedirects: false,
            validateStatus: (status) => status != null && status < 400,
            headers: {
              'Referer': 'https://xui.ptlogin2.qq.com/',
              'cookie': _cookie ?? '',
            },
          ),
        );

        final hopCookies = res.headers['set-cookie'];
        if (hopCookies != null && hopCookies.isNotEmpty) {
          // Merge REAL cookie pairs. `hopCookies.join('; ')` pasted the attribute
          // segments (Path=/, Domain=..., HttpOnly...) into the jar as if they
          // were cookies, which is what made graph.qq.com return the
          // "QQ帐号安全登录" page — see [_mergeSetCookies].
          _cookie = _mergeSetCookies(
            existing: _cookie ?? '',
            setCookieLines: hopCookies,
          );
        }

        // Which cookie NAMES came in on this hop, and from which host. The
        // "QQ帐号安全登录" page returned by `oauth2.0/show` proves graph.qq.com
        // does NOT accept this session even though p_skey is present — the usual
        // reason is that the session cookies were issued for
        // `ptlogin2.graph.qq.com` rather than for `.qq.com`, so the names exist in
        // our jar but are not valid for the host we send them to. Logging the
        // names + the request host answers that without exposing values.
        final hopHost = Uri.tryParse(currentUrl)?.host ?? '?';
        final names = (hopCookies ?? const <String>[])
            .map((c) => c.split('=').first.trim())
            .join(',');
        debugPrint(
          'QQ OAuth: hop=$hop host=$hopHost cookieNames=[$names]',
        );

        final location = res.headers.value('location');
        debugPrint(
          'QQ OAuth: check_sig hop=$hop status=${res.statusCode} '
          'setCookie=${hopCookies?.length ?? 0} '
          'p_skey=${_extractCookie('p_skey') != null} '
          'location=${location != null}',
        );

        if (location == null || location.isEmpty) break;
        // Resolve relative redirects against the URL we just called.
        currentUrl = Uri.parse(currentUrl).resolve(location).toString();
      }
      debugPrint(
        'QQ OAuth: check_sig done, cookies: ${_cookie != null ? _cookie!.length : 0} chars',
      );

      // Extract p_skey for g_tk hash
      final pSkey = _extractCookie('p_skey');
      final gTk = pSkey != null ? _hash5381(pSkey) : 5381;
      // Remember it for every request that needs a `g_tk` (playlist reads and
      // writes), so those call sites stop sending the bare DJB2 seed.
      _gTk = gTk;
      debugPrint(
        'QQ OAuth: p_skey=${pSkey != null ? "found" : "null"}, g_tk=$gTk',
      );

      // Step 4: OAuth authorize
      final uri = Uri.parse(redirectUrl);
      final surl =
          uri.queryParameters['surl'] ?? uri.queryParameters['uin'] ?? '';
      // Record what we actually parsed out of check_sig. `surl` falls back to the
      // raw `uin` (a bare number) when the callback carries no `surl`, and whether
      // oauth2.0/show accepts that is unverified — so log the value rather than
      // assume. Non-secret: it is a public account number, not a token.
      debugPrint(
        'QQ OAuth: calling oauth2.0/show, surl=$surl '
        '(fromRedirect=${uri.queryParameters.containsKey('surl')})',
      );
      // The names we are ABOUT to send to graph.qq.com. Comparing this list with
      // the "QQ帐号安全登录" outcome is what separates "cookie lost" (a name
      // missing) from "cookie not valid for this host" (name present, domain
      // wrong) — the two have different fixes.
      final sentNames = (_cookie ?? '')
          .split(';')
          .map((p) => p.split('=').first.trim())
          .where((n) => n.isNotEmpty)
          .toSet()
          .toList()
        ..sort();
      debugPrint('QQ OAuth: sending cookie names to graph: $sentNames');
      final authRes = await _dio.get(
        QqEndpoints.graphShow,
        queryParameters: {
          'which': 'Login',
          'display': 'pc',
          'response_type': 'code',
          'client_id': 100497308,
          'redirect_uri': QqEndpoints.oauthRedirectUri,
          'surl': surl,
          'state': DateTime.now().millisecondsSinceEpoch ~/ 1000,
          'scope': 'get_user_info',
        },
        options: Options(
          responseType: ResponseType.plain,
          followRedirects: false,
          validateStatus: (status) => status != null && status < 400,
          headers: {
            'Referer': 'https://xui.ptlogin2.qq.com/',
            'cookie': _cookie ?? '',
          },
        ),
      );
      // Capture more cookies
      final cookies2 = authRes.headers['set-cookie'];
      if (cookies2 != null && cookies2.isNotEmpty) {
        // Same defect as the check_sig merge: these lines carry attribute
        // segments that must not enter the jar.
        _cookie = _mergeSetCookies(
          existing: _cookie ?? '',
          setCookieLines: cookies2,
        );
      }
      // `oauth2.0/show` normally answers 200 with an HTML page that EMBEDS the
      // authorization form (hidden fields such as `state`/`scope`/`s_url`). If it
      // instead redirects, the Location is the shortcut carrying `?code=...`.
      // Log enough of the page to see which shape came back — the device log only
      // said status=200, which told us nothing about whether the form was there.
      final showLocation = authRes.headers.value('location');
      debugPrint(
        'QQ OAuth: show status=${authRes.statusCode} '
        'location=${showLocation != null} setCookie=${cookies2?.length ?? 0}',
      );
      if (showLocation != null && showLocation.isNotEmpty) {
        debugPrint('QQ OAuth: show location=$showLocation');
      }
      if (authRes.data != null) {
        final body = authRes.data.toString();
        // Name the decisive markers instead of dumping the page: a 200 that
        // contains these inputs means "we served the authorize form" (the session
        // was NOT accepted); a page that instead embeds a redirect target means
        // the session WAS accepted and we must submit the form.
        final hasForm = body.contains('authorize') || body.contains('<form');
        final hasLoginUi = body.contains('pt_login') || body.contains('loginbtn');
        debugPrint(
          'QQ OAuth: show body len=${body.length} authorizeForm=$hasForm '
          'loginUi=$hasLoginUi',
        );
        final head = body.length > 400 ? body.substring(0, 400) : body;
        debugPrint('QQ OAuth: show body(head)=$head');
      }
      if (showLocation != null) {
        final showCode = RegExp(r'code=([^&]+)').firstMatch(showLocation);
        if (showCode != null) {
          debugPrint('QQ OAuth: got auth code directly from oauth2.0/show');
          return await _exchangeAuthCodeForCookies(showCode.group(1)!, gTk);
        }
      }

      // POST to authorize endpoint to get the auth code
      debugPrint('QQ OAuth: calling oauth2.0/authorize');
      final authCodeRes = await _dio.post(
        QqEndpoints.graphAuthorize,
        data:
            'response_type=code&client_id=100497308'
            '&redirect_uri=${Uri.encodeComponent(QqEndpoints.oauthRedirectUri)}'
            '&scope=get_user_info&state=${DateTime.now().millisecondsSinceEpoch ~/ 1000}'
            '&g_tk=$gTk&from_ptlogin=1&src=1&update_auth=1&openapi=1010'
            '&q_login_code=&q_state=&from=login',
        options: Options(
          contentType: 'application/x-www-form-urlencoded',
          responseType: ResponseType.plain,
          followRedirects: false,
          validateStatus: (s) => s != null && s < 400,
          headers: {
            // The browser reached `authorize` FROM the `show` page, so QQ expects
            // both headers; their absence is one plausible reason the endpoint
            // treats the request as not part of a login flow and bounces it back
            // to `show`. `redirect_uri`/`scope`/`state` are now also sent
            // properly encoded (they were missing from the body entirely, and an
            // authorize request without them cannot name a client).
            'Referer': QqEndpoints.graphShow,
            'Origin': 'https://graph.qq.com',
            'cookie': _cookie ?? '',
          },
        ),
      );

      // Extract auth code from Location header
      final authLocation = authCodeRes.headers.value('location');
      String? authCode;
      // Record what authorize actually answered. The device log shows it bouncing
      // back to `oauth2.0/show` (the login page) instead of returning
      // `Location: ...?code=...`, which means the request was not accepted as an
      // authenticated authorization — so the status and the response body matter
      // as much as the Location.
      debugPrint(
        'QQ OAuth: authorize status=${authCodeRes.statusCode} '
        'location=${authLocation != null}',
      );
      if (authLocation != null && authLocation.isNotEmpty) {
        debugPrint('QQ OAuth: authorize location=$authLocation');
      }
      if (authCodeRes.data != null) {
        final body = authCodeRes.data.toString();
        debugPrint(
          'QQ OAuth: authorize body(head)='
          '${body.length > 300 ? body.substring(0, 300) : body}',
        );
      }
      if (authLocation != null) {
        final codeMatch = RegExp(r'code=([^&]+)').firstMatch(authLocation);
        authCode = codeMatch?.group(1);
      }
      if (authCode == null || authCode.isEmpty) {
        // Try parsing from body
        final bodyMatch = RegExp(
          r'code=([^&\s]+)',
        ).firstMatch(authCodeRes.data.toString());
        authCode = bodyMatch?.group(1);
      }
      if (authCode == null || authCode.isEmpty) {
        debugPrint(
          'QQ OAuth: failed to extract auth code, location=$authLocation',
        );
        return null;
      }
      debugPrint('QQ OAuth: got auth code, exchanging...');
      return await _exchangeAuthCodeForCookies(authCode, gTk);
    } catch (e) {
      debugPrint('QQ OAuth: exception: $e');
      return null;
    }
  }

  /// Merges raw `Set-Cookie` lines into a cookie header, correctly.
  ///
  /// ⚠️ This exists because the previous merge was wrong in a way that broke the
  /// whole login. A `Set-Cookie` header line is NOT a cookie — it is a cookie
  /// PLUS attributes:
  ///
  /// ```
  /// p_skey=xxx; Path=/; Domain=.ptlogin2.graph.qq.com; HttpOnly; Secure
  /// ```
  ///
  /// The old code did `hopCookies.join('; ')`, i.e. it pasted whole lines into the
  /// jar, so `Path=/`, `Domain=...`, `HttpOnly`... all entered the jar as if they
  /// were cookies named `Path`/`Domain`/`HttpOnly`. The device log caught it
  /// exactly:
  ///
  /// ```
  /// QQ OAuth: sending cookie names to graph: [Domain, ETK, Expires, HttpOnly,
  ///   Path, RK, SameSite, Secure, airkey, p_skey, p_skey_forbid, ...]
  /// ```
  ///
  /// graph.qq.com then saw a malformed `Cookie` header and answered every request
  /// with the "QQ帐号安全登录" page even though `p_skey` was present — the cookie
  /// NAMES existed, but the header itself was garbage.
  ///
  /// This function keeps only real `name=value` pairs (the first segment of each
  /// line), later values winning, so the jar stays a valid cookie header.
  @visibleForTesting
  static String mergeSetCookiesForTest({
    required String existing,
    required List<String> setCookieLines,
  }) {
    return _mergeSetCookies(existing: existing, setCookieLines: setCookieLines);
  }

  static String _mergeSetCookies({
    required String existing,
    required List<String> setCookieLines,
  }) {
    // name=value only, in order; later duplicates replace earlier ones.
    final jar = <String, String>{};
    void absorb(String line) {
      final firstPair = line.split(';').first.trim();
      final eq = firstPair.indexOf('=');
      if (eq <= 0) return; // no "=", or empty name — not a cookie
      final name = firstPair.substring(0, eq).trim();
      final value = firstPair.substring(eq + 1).trim();
      if (name.isEmpty) return;
      jar[name] = value;
    }

    // Existing jar: parse the pairs we already hold.
    for (final pair in existing.split(';')) {
      absorb(pair);
    }
    for (final line in setCookieLines) {
      absorb(line);
    }
    return jar.entries.map((e) => '${e.key}=${e.value}').join('; ');
  }

  /// Steps 5–6 of the login flow: exchange an OAuth `code` for QQ Music cookies.  ///
  /// Split out so the code can arrive from either place it legitimately appears:
  /// the `Location` of `oauth2.0/show` (the normal path), or the `Location` of
  /// `oauth2.0/authorize`. Both callers pass the `g_tk` derived from the `p_skey`
  /// obtained when following `check_sig` hop by hop.
  Future<String?> _exchangeAuthCodeForCookies(String authCode, int gTk) async {
    try {
      // Step 5: Exchange code for QQ Music login
      final loginRes = await musicu({
        'comm': {'g_tk': gTk, 'platform': 'yqq', 'ct': 24, 'cv': 0},
        'req': {
          'module': 'QQConnectLogin.LoginServer',
          'method': 'QQLogin',
          'param': {'code': authCode},
        },
      });

      // Step 6: Extract final cookies
      final req = loginRes['req'];
      final code = req?['code'];
      debugPrint('QQ OAuth: QQLogin response code=$code');
      if (code == 0 || code == '0') {
        final loginData = req?['data'];
        if (loginData is Map) {
          restoreCookie(
            _buildMusicLoginCookie(
              existingCookie: _cookie ?? '',
              loginData: loginData,
            ),
          );
        } else {
          final cookies3 = <String>[];
          final pskey = _extractCookie('p_skey');
          if (pskey != null) cookies3.add('p_skey=$pskey');
          final skey = _extractCookie('skey');
          if (skey != null) cookies3.add('skey=$skey');
          if (cookies3.isNotEmpty) {
            setCookie(cookies3.join('; '));
          }
        }
        debugPrint('QQ OAuth: login successful');
        return _cookie;
      }
      debugPrint('QQ OAuth: QQLogin failed, code=$code');
      return null;
    } catch (e) {
      debugPrint('QQ OAuth: exchange exception: $e');
      return null;
    }
  }

  static String? _extractCookieValue(String? cookie, String name) {
    if (cookie == null) return null;
    final escapedName = RegExp.escape(name);
    final match = RegExp('(?:^|;\\s*)$escapedName=([^;]+)').firstMatch(cookie);
    return match?.group(1);
  }

  String? _extractCookie(String name) => _extractCookieValue(_cookie, name);

  int _hash5381(String str) {
    int hash = 0;
    for (var i = 0; i < str.length; i++) {
      hash = ((hash << 5) + hash) + str.codeUnitAt(i);
      hash = hash & 0xFFFFFFFF;
    }
    return hash & 0x7FFFFFFF;
  }

  String _getQrHash(String cookie) {
    // DJB2 hash for ptqrtoken
    int hash = 0;
    for (int i = 0; i < cookie.length; i++) {
      hash = ((hash << 5) + hash) + cookie.codeUnitAt(i);
      hash = hash & 0xFFFFFFFF; // keep 32-bit
    }
    return (hash & 0x7FFFFFFF).toString();
  }

  /// Get user profile homepage.
  Future<Map<String, dynamic>> getUserInfo(String uin) async {
    final res = await _dio.get(
      QqEndpoints.profileHomepage,
      queryParameters: {'cid': 205360838, 'userid': uin, 'reqfrom': 1},
      options: Options(
        responseType: ResponseType.json,
        headers: {
          'Referer': 'https://y.qq.com/portal/profile.html',
          'cookie': _cookie ?? '',
        },
      ),
    );
    return responseMapOf(res.data);
  }

  /// Get user playlists
  Future<Map<String, dynamic>> getUserPlaylists(String uin) async {
    final res = await _dio.get(
      QqEndpoints.userCreatedDiss,
      queryParameters: {
        'hostUin': 0,
        'hostuin': uin,
        'sin': 0,
        'size': 200,
        'g_tk': _gTk,
        'loginUin': 0,
        'format': 'json',
        'inCharset': 'utf8',
        'outCharset': 'utf-8',
        'notice': 0,
        'platform': 'yqq.json',
        'needNewCode': 0,
      },
      options: Options(
        responseType: ResponseType.json,
        headers: {
          'Referer': 'https://y.qq.com/portal/profile.html',
          'cookie': _cookie ?? '',
        },
      ),
    );
    return responseMapOf(res.data);
  }

  /// Get playlist detail (song list)
  Future<Map<String, dynamic>> getPlaylistDetail(
    String disstid, {
    int songBegin = 0,
    int songNum = 200,
  }) async {
    return musicu({
      'comm': {'ct': 19, 'cv': 1845},
      'req_0': {
        'module': QqEndpoints.modulePlaylistDetail,
        'method': QqEndpoints.methodGetPlaylistDetail,
        'param': {
          'disstid': int.tryParse(disstid) ?? 0,
          'dirid': 0,
          'tag': 1,
          'song_num': songNum,
          'song_begin': songBegin,
          'userinfo': 1,
        },
      },
    });
  }

  /// Public legacy playlist detail endpoint. It still exposes many shared
  /// playlists whose PC page requires a logged-in browser session.
  Future<Map<String, dynamic>> getLegacyPlaylistDetail(String disstid) async {
    final res = await _dio.get(
      QqEndpoints.legacyPlaylistDetail,
      queryParameters: {
        'type': 1,
        'json': 1,
        'utf8': 1,
        'onlysong': 0,
        'disstid': disstid,
        'format': 'json',
        'g_tk': _gTk,
        'loginUin': 0,
        'hostUin': 0,
        'inCharset': 'utf8',
        'outCharset': 'utf-8',
        'notice': 0,
        'platform': 'yqq',
        'needNewCode': 0,
      },
      options: Options(
        responseType: ResponseType.json,
        headers: {'Referer': 'https://y.qq.com/'},
      ),
    );
    return responseMapOf(res.data);
  }

  /// Get liked/favorite songs
  Future<Map<String, dynamic>> getLikedSongs({
    int page = 0,
    int limit = 50,
  }) async {
    return musicu({
      'comm': {'ct': 19, 'cv': 1845},
      'req_0': {
        'module': QqEndpoints.moduleFavRead,
        'method': QqEndpoints.methodGetUserFavSongList,
        'param': {'v_songId': 0, 'v_begin': page * limit, 'v_num': limit},
      },
    });
  }

  /// Like a song
  Future<Map<String, dynamic>> likeSong(String songMid, String songId) async {
    return musicu({
      'comm': {'ct': 19, 'cv': 1845},
      'req_0': {
        'module': QqEndpoints.moduleFavWrite,
        'method': QqEndpoints.methodAddSongFav,
        'param': {'v_songMid': songMid, 'v_songId': songId},
      },
    });
  }

  /// Add a song to a user playlist.
  Future<Map<String, dynamic>> addSongToPlaylist(
    String dirid,
    String songMid,
  ) async {
    final res = await _dio.get(
      QqEndpoints.addSongToDir,
      queryParameters: {
        'g_tk': _gTk,
        'midlist': songMid,
        'typelist': '13',
        'dirid': dirid,
        'addtype': '',
        'formsender': 4,
        'r2': 0,
        'r3': 1,
        'utf8': 1,
      },
      options: Options(
        responseType: ResponseType.json,
        headers: {
          'Referer': 'https://y.qq.com/n/yqq/playlist',
          'cookie': _cookie ?? '',
        },
      ),
    );
    return responseMapOf(res.data);
  }

  /// Create a QQ Music playlist.
  Future<Map<String, dynamic>> createPlaylist(String name) async {
    final uin =
        _extractCookie('uin')?.replaceAll(RegExp(r'\D'), '') ??
        _extractCookie('qqmusic_uin')?.replaceAll(RegExp(r'\D'), '') ??
        '';
    final res = await _dio.post(
      QqEndpoints.createPlaylist,
      data: {
        'loginUin': uin,
        'hostUin': 0,
        'format': 'json',
        'inCharset': 'utf8',
        'outCharset': 'utf8',
        'notice': 0,
        'platform': 'yqq',
        'needNewCode': 0,
        'g_tk': _gTk,
        'uin': uin,
        'name': name,
        'show': 1,
        'formsender': 1,
        'utf8': 1,
        'qzreferrer':
            'https://y.qq.com/portal/profile.html#sub=other&tab=create&',
      },
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        responseType: ResponseType.json,
        headers: {
          'Referer': 'https://y.qq.com/n/yqq/playlist',
          'cookie': _cookie ?? '',
        },
      ),
    );
    return responseMapOf(res.data);
  }

  /// Collect or uncollect a QQ Music playlist.
  Future<Map<String, dynamic>> collectPlaylist(
    String playlistId, {
    bool collect = true,
  }) async {
    final uin =
        _extractCookie('uin')?.replaceAll(RegExp(r'\D'), '') ??
        _extractCookie('qqmusic_uin')?.replaceAll(RegExp(r'\D'), '') ??
        '';
    final res = await _dio.post(
      QqEndpoints.collectPlaylist,
      data: {
        'loginUin': uin,
        'hostUin': 0,
        'inCharset': 'GB2312',
        'outCharset': 'utf8',
        'platform': 'yqq',
        'format': 'json',
        'g_tk': _gTk,
        'uin': uin,
        'dissid': playlistId,
        'notice': 0,
        'needNewCode': 0,
        'from': 1,
        'optype': collect ? 1 : 2,
        'utf8': 1,
        'qzreferrer': 'https://y.qq.com/n/yqq/playlist/$playlistId.html',
      },
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        responseType: ResponseType.json,
        headers: {
          'Referer': 'https://y.qq.com/n/yqq/playlist/$playlistId.html',
          'cookie': _cookie ?? '',
        },
      ),
    );
    return responseMapOf(res.data);
  }

  /// Unlike a song
  Future<Map<String, dynamic>> unlikeSong(String songMid, String songId) async {
    return musicu({
      'comm': {'ct': 19, 'cv': 1845},
      'req_0': {
        'module': QqEndpoints.moduleFavWrite,
        'method': QqEndpoints.methodDeleteSongFav,
        'param': {'v_songMid': songMid, 'v_songId': songId},
      },
    });
  }

  /// QQ Music's personalised daily list is exposed on the PC page as the
  /// 「今日私享」playlist. Returns that playlist id when a cookie can see it.
  ///
  /// Verified anonymously 2026-10: the page is 8269 bytes and does not contain
  /// 今日私享 at all, so an anonymous caller gets `null` and must fall back to a
  /// chart. The old anonymous fallback (`musicToplist.ChartInfo/
  /// GetDailyRecommend`) was removed because it now answers
  /// `code 500003 / subcode 860100005` (dead endpoint, no data for any caller).
  Future<String?> getDailyPlaylistId() async {
    final res = await _dio.get(
      QqEndpoints.dailyPrivatePage,
      options: Options(
        responseType: ResponseType.plain,
        headers: {'Referer': 'https://y.qq.com/', 'cookie': _cookie ?? ''},
      ),
    );
    final html = res.data?.toString() ?? '';
    final itemMatch = RegExp(
      "<li[^>]*playlist__item[^>]*>[\\s\\S]*?今日私享[\\s\\S]*?</li>",
    ).firstMatch(html);
    final scope = itemMatch?.group(0) ?? _windowAround(html, '今日私享', 1600);
    if (scope == null || scope.isEmpty) return null;
    final match =
        RegExp("data-rid=[\"']?(\\d+)").firstMatch(scope) ??
        RegExp("dissid[=:][\"']?(\\d+)").firstMatch(scope) ??
        RegExp("playlist/(\\d+)").firstMatch(scope) ??
        RegExp("id=(\\d+)").firstMatch(scope);
    return match?.group(1);
  }

  String? _windowAround(String text, String marker, int radius) {
    final index = text.indexOf(marker);
    if (index < 0) return null;
    final start = index > radius ? index - radius : 0;
    final end = (index + radius).clamp(0, text.length);
    return text.substring(start, end);
  }

  /// Get VIP status
  Future<Map<String, dynamic>> getVipInfo(String uin) async {
    return musicu({
      'comm': {'ct': 19, 'cv': 1845},
      'req_0': {
        'module': QqEndpoints.moduleVipInfo,
        'method': QqEndpoints.methodGetVipInfo,
        'param': {'uin': uin},
      },
    });
  }

  /// Every chart QQ publishes, with its group (巅峰榜/地区榜/特色榜/全球榜).
  ///
  /// Request key must match the response key — this one is `toplist`.
  Future<Map<String, dynamic>> getToplistCatalogue() async {
    return musicu({
      'comm': {'ct': 19, 'cv': 1845},
      'toplist': {
        'module': QqEndpoints.moduleToplist,
        'method': QqEndpoints.methodGetToplistCatalogue,
        'param': <String, dynamic>{},
      },
    });
  }

  /// Chart detail through the modern musicu module.
  ///
  /// Returns the chart definition in `toplist.data.data` (title, intro, period,
  /// totalNum, `song[]` with real `rank`/`rankValue`) and the songs in
  /// `toplist.data.songInfoList[]` (full song objects, **no** rank field, so the
  /// rank comes from `songInfoList`'s index or from the parallel `song[]`).
  Future<Map<String, dynamic>> getToplistDetail(
    int topId, {
    int offset = 0,
    int num = 100,
    String? period,
  }) async {
    return musicu({
      'comm': {'ct': 19, 'cv': 1845},
      'toplist': {
        'module': QqEndpoints.moduleToplist,
        'method': QqEndpoints.methodGetToplistDetail,
        'param': {
          'topId': topId,
          'offset': offset,
          'num': num,
          // Weekly charts (地区榜/特色榜/全球榜) are addressed by period
          // ("2026_40"); empty means "current".
          if (period != null && period.isNotEmpty) 'period': period,
        },
      },
    });
  }

  /// One page of a chart through the legacy `toplist_cp` endpoint.
  ///
  /// Unlike [getToplistDetail] this returns per-track movement
  /// (`cur_count` = rank, `old_count` = previous rank, so
  /// `rankChange = old_count - cur_count`) plus `Franking_value`. The endpoint
  /// serves at most [QqToplistIds.pageSize] tracks per call regardless of
  /// `num`, so callers page with [offset].
  Future<Map<String, dynamic>> getToplistCp({
    required int topId,
    int offset = 0,
    int num = QqToplistIds.pageSize,
  }) async {
    final res = await _dio.get(
      QqEndpoints.toplistCp,
      queryParameters: {
        'topid': topId,
        'format': 'json',
        'page': 'detail',
        'tpl': 3,
        'type': 'top',
        'song_begin': offset,
        'song_num': num.clamp(1, QqToplistIds.pageSize),
      },
      options: Options(
        responseType: ResponseType.json,
        headers: {'Referer': 'https://y.qq.com/'},
      ),
    );
    return responseMapOf(res.data);
  }

  /// Artist profile (legacy endpoint): `getSingerInfo`, `singerBrief`,
  /// `total_song`, `total_album` and a first page of hot songs in
  /// `getSongInfo[]`.
  Future<Map<String, dynamic>> getSingerDetail(String singerMid) async {
    final res = await _dio.get(
      QqEndpoints.singerDetail,
      queryParameters: {
        'singermid': singerMid,
        'format': 'json',
        'utf8': 1,
        'outCharset': 'utf-8',
      },
      options: Options(
        responseType: ResponseType.json,
        headers: {'Referer': 'https://y.qq.com/'},
      ),
    );
    return responseMapOf(res.data);
  }

  /// Artist avatar source: musicu `singer` module, whose
  /// `basic_info.singer_pmid` is what the `T001R300x300M000<pmid>.jpg` cover
  /// template needs (the legacy endpoint has no picture at all).
  Future<Map<String, dynamic>> getSingerProfile(String singerMid) async {
    return musicu({
      'comm': {'ct': 19, 'cv': 1845},
      'singer': {
        'module': QqEndpoints.moduleSinger,
        'method': QqEndpoints.methodGetSingerDetail,
        'param': {
          'singer_mids': [singerMid],
          'ex_singer': 1,
          'wiki_singer': 1,
          'group_singer': 1,
          'pic': 1,
        },
      },
    });
  }

  /// Artist album list. `req_0.data.albumList[]` (verified live);
  /// `music.musichallAlbum.AlbumListInter` — the module many older clients
  /// used — answers `code 500003` instead.
  Future<Map<String, dynamic>> getSingerAlbums(
    String singerMid, {
    int begin = 0,
    int num = 30,
    int order = 1,
  }) async {
    return musicu({
      'comm': {'ct': 19, 'cv': 1845},
      'req_0': {
        'module': QqEndpoints.moduleAlbumList,
        'method': QqEndpoints.methodGetAlbumList,
        'param': {
          'singerMid': singerMid,
          'begin': begin,
          'num': num,
          'order': order,
        },
      },
    });
  }

  /// Album search (`search_type: 2`), used as the artist-albums fallback when
  /// the album-list module is unavailable. The mobile search method is the one
  /// that actually returns rows (`body.item_album.list[]`); the desktop method
  /// answers `code 2001` with an empty album list.
  Future<Map<String, dynamic>> searchAlbums(
    String keyword, {
    int page = 1,
    int limit = 30,
  }) async {
    return musicu({
      'comm': {'ct': 19, 'cv': 1845},
      'req_0': {
        'module': QqEndpoints.moduleSearch,
        'method': QqEndpoints.methodMobileSearch,
        'param': {
          'search_type': 2,
          'query': keyword,
          'num_per_page': limit,
          'page_num': page,
          'grp': 1,
        },
      },
    });
  }

  /// Album detail (legacy): `data.list[]` are the album's tracks, plus
  /// `aDate`/`company`/`genre`/`lan`/`desc`/`singermid` metadata.
  Future<Map<String, dynamic>> getAlbumInfo(String albumMid) async {
    final res = await _dio.get(
      QqEndpoints.albumInfo,
      queryParameters: {
        'albummid': albumMid,
        'format': 'json',
        'utf8': 1,
        'outCharset': 'utf-8',
      },
      options: Options(
        responseType: ResponseType.json,
        headers: {'Referer': 'https://y.qq.com/'},
      ),
    );
    return responseMapOf(res.data);
  }

  /// New songs (新歌速递) for a QQ region `type`
  /// (1 内地 / 2 欧美 / 3 日本 / 4 韩国 / 5 全部 / 6 港台).
  ///
  /// `num` is ignored by the server (verified: asking for 3 returns 32), so the
  /// caller truncates client-side.
  Future<Map<String, dynamic>> getNewSongs({int type = 5}) async {
    return musicu({
      'comm': {'ct': 19, 'cv': 1845},
      'newsong': {
        'module': QqEndpoints.moduleNewSong,
        'method': QqEndpoints.methodGetNewSongInfo,
        'param': {'type': type, 'num': 100},
      },
    });
  }
}
