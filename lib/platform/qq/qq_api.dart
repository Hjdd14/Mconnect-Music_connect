import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../models/audio_quality.dart';
import 'qq_endpoints.dart';

class QqApi {
  final Dio _dio;
  String? _cookie;
  String? _playbackGuid;

  QqApi({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 15),
              headers: {
                'User-Agent':
                    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
                'Referer': 'https://y.qq.com/portal/player.html',
                'Origin': 'https://y.qq.com',
              },
            ),
          );

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
    if (res.data is String) {
      return jsonDecode(res.data as String) as Map<String, dynamic>;
    }
    return res.data as Map<String, dynamic>;
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
      'https://c.y.qq.com/soso/fcgi-bin/client_music_search_songlist',
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
    if (res.data is String) {
      return jsonDecode(res.data as String) as Map<String, dynamic>;
    }
    return res.data as Map<String, dynamic>;
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
      if (data is Map && data['lyric'] != null) {
        final lyric = _decodeLyricField(data['lyric']);
        final translation = _decodeLyricField(
          data['trans'] ?? data['translation'] ?? data['transLyric'],
        );
        if (lyric == null || lyric.isEmpty) return null;
        if (translation == null || translation.isEmpty) return lyric;
        return '$lyric\n$translation';
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  String? _decodeLyricField(dynamic value) {
    if (value == null) return null;
    final text = value.toString();
    if (text.isEmpty) return null;
    try {
      return utf8.decode(base64Decode(text));
    } catch (_) {
      return text;
    }
  }

  /// Get QRC lyrics (encrypted, word-by-word)
  Future<Map<String, dynamic>?> getQrcLyric(String songMid) async {
    try {
      final res = await _dio.get(
        QqEndpoints.lyricBase,
        queryParameters: {'songmid': songMid, 'format': 'json', 'nobase64': 1},
      );
      dynamic data = res.data;
      if (data is String) {
        data = jsonDecode(data);
      }
      return data as Map<String, dynamic>?;
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
      // Store qrsig cookie
      final cookies = res.headers['set-cookie'];
      if (cookies != null) {
        final cookieStr = cookies.join('; ');
        setCookie(cookieStr);
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
          'u1': 'https://graph.qq.com/oauth2.0/login_jump',
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
      final cookieStr = cookieHeaders?.join('; ');
      return {'raw': text, 'cookies': cookieStr};
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  /// Follow check_sig redirect to graph.qq.com, then OAuth authorize, then exchange code
  Future<String?> completeOAuthLogin(String redirectUrl) async {
    try {
      // Step 3: Follow check_sig URL → sets cookies on graph.qq.com
      debugPrint('QQ OAuth: following check_sig redirect');
      final res1 = await _dio.get(
        redirectUrl,
        options: Options(
          responseType: ResponseType.plain,
          headers: {
            'Referer': 'https://xui.ptlogin2.qq.com/',
            'cookie': _cookie ?? '',
          },
        ),
      );
      // Capture cookies from graph.qq.com
      final cookies1 = res1.headers['set-cookie'];
      if (cookies1 != null) {
        final existing = _cookie ?? '';
        _cookie = '$existing; ${cookies1.join('; ')}';
      }
      debugPrint(
        'QQ OAuth: check_sig done, cookies: ${_cookie != null ? _cookie!.length : 0} chars',
      );

      // Extract p_skey for g_tk hash
      final pSkey = _extractCookie('p_skey');
      final gTk = pSkey != null ? _hash5381(pSkey) : 5381;
      debugPrint(
        'QQ OAuth: p_skey=${pSkey != null ? "found" : "null"}, g_tk=$gTk',
      );

      // Step 4: OAuth authorize
      final uri = Uri.parse(redirectUrl);
      final surl =
          uri.queryParameters['surl'] ?? uri.queryParameters['uin'] ?? '';
      debugPrint('QQ OAuth: calling oauth2.0/show, surl=$surl');
      final authRes = await _dio.get(
        'https://graph.qq.com/oauth2.0/show',
        queryParameters: {
          'which': 'Login',
          'display': 'pc',
          'response_type': 'code',
          'client_id': 100497308,
          'redirect_uri':
              'https://y.qq.com/portal/wx_redirect.html?login_type=1',
          'surl': surl,
          'state': DateTime.now().millisecondsSinceEpoch ~/ 1000,
          'scope': 'get_user_info',
        },
        options: Options(
          responseType: ResponseType.plain,
          headers: {'cookie': _cookie ?? ''},
        ),
      );
      // Capture more cookies
      final cookies2 = authRes.headers['set-cookie'];
      if (cookies2 != null) {
        _cookie = '$_cookie; ${cookies2.join('; ')}';
      }

      // POST to authorize endpoint to get the auth code
      debugPrint('QQ OAuth: calling oauth2.0/authorize');
      final authCodeRes = await _dio.post(
        'https://graph.qq.com/oauth2.0/authorize',
        data:
            'response_type=code&client_id=100497308'
            '&redirect_uri=https://y.qq.com/portal/wx_redirect.html?login_type=1'
            '&g_tk=$gTk&from_ptlogin=1&src=1&update_auth=1&openapi=1010&g_tk=$gTk'
            '&q_login_code=&q_state=&from=login',
        options: Options(
          contentType: 'application/x-www-form-urlencoded',
          responseType: ResponseType.plain,
          followRedirects: false,
          validateStatus: (s) => s != null && s < 400,
          headers: {'cookie': _cookie ?? ''},
        ),
      );

      // Extract auth code from Location header
      final authLocation = authCodeRes.headers.value('location');
      String? authCode;
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
          if (pSkey != null) cookies3.add('p_skey=$pSkey');
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
      debugPrint('QQ OAuth: exception: $e');
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
      'https://c.y.qq.com/rsc/fcgi-bin/fcg_get_profile_homepage.fcg',
      queryParameters: {'cid': 205360838, 'userid': uin, 'reqfrom': 1},
      options: Options(
        responseType: ResponseType.json,
        headers: {
          'Referer': 'https://y.qq.com/portal/profile.html',
          'cookie': _cookie ?? '',
        },
      ),
    );
    if (res.data is String) {
      return jsonDecode(res.data as String) as Map<String, dynamic>;
    }
    return res.data as Map<String, dynamic>;
  }

  /// Get user playlists
  Future<Map<String, dynamic>> getUserPlaylists(String uin) async {
    final res = await _dio.get(
      'https://c.y.qq.com/rsc/fcgi-bin/fcg_user_created_diss',
      queryParameters: {
        'hostUin': 0,
        'hostuin': uin,
        'sin': 0,
        'size': 200,
        'g_tk': 5381,
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
    if (res.data is String) {
      return jsonDecode(res.data as String) as Map<String, dynamic>;
    }
    return res.data as Map<String, dynamic>;
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
      'https://c.y.qq.com/qzone/fcg-bin/fcg_ucc_getcdinfo_byids_cp.fcg',
      queryParameters: {
        'type': 1,
        'json': 1,
        'utf8': 1,
        'onlysong': 0,
        'disstid': disstid,
        'format': 'json',
        'g_tk': 5381,
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
    if (res.data is String) {
      return jsonDecode(res.data as String) as Map<String, dynamic>;
    }
    return res.data as Map<String, dynamic>;
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
      'https://c.y.qq.com/splcloud/fcgi-bin/fcg_music_add2songdir.fcg',
      queryParameters: {
        'g_tk': 5381,
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
    if (res.data is String) {
      return jsonDecode(res.data as String) as Map<String, dynamic>;
    }
    return res.data as Map<String, dynamic>;
  }

  /// Create a QQ Music playlist.
  Future<Map<String, dynamic>> createPlaylist(String name) async {
    final uin =
        _extractCookie('uin')?.replaceAll(RegExp(r'\D'), '') ??
        _extractCookie('qqmusic_uin')?.replaceAll(RegExp(r'\D'), '') ??
        '';
    final res = await _dio.post(
      'https://c.y.qq.com/splcloud/fcgi-bin/create_playlist.fcg',
      data: {
        'loginUin': uin,
        'hostUin': 0,
        'format': 'json',
        'inCharset': 'utf8',
        'outCharset': 'utf8',
        'notice': 0,
        'platform': 'yqq',
        'needNewCode': 0,
        'g_tk': 5381,
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
    if (res.data is String) {
      return jsonDecode(res.data as String) as Map<String, dynamic>;
    }
    return res.data as Map<String, dynamic>;
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
      'https://c.y.qq.com/folder/fcgi-bin/fcg_qm_order_diss.fcg',
      data: {
        'loginUin': uin,
        'hostUin': 0,
        'inCharset': 'GB2312',
        'outCharset': 'utf8',
        'platform': 'yqq',
        'format': 'json',
        'g_tk': 5381,
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
    if (res.data is String) {
      return jsonDecode(res.data as String) as Map<String, dynamic>;
    }
    return res.data as Map<String, dynamic>;
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

  /// Get daily recommendations
  Future<Map<String, dynamic>> getDailyRecommend() async {
    return musicu({
      'comm': {'ct': 19, 'cv': 1845},
      'req_0': {
        'module': QqEndpoints.moduleChartInfo,
        'method': QqEndpoints.methodGetDailyRecommend,
        'param': {},
      },
    });
  }

  /// QQ Music "daily 30" is exposed on the PC page as the "today private"
  /// playlist. This returns that playlist id when the logged-in cookie can see it.
  Future<String?> getDailyPlaylistId() async {
    final res = await _dio.get(
      'https://c.y.qq.com/node/musicmac/v6/index.html',
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

  /// Get toplist detail (ranking songs)
  Future<Map<String, dynamic>> getToplistDetail(
    int topId, {
    int offset = 0,
    int num = 100,
  }) async {
    return musicu({
      'comm': {'ct': 19, 'cv': 1845},
      'toplist': {
        'module': QqEndpoints.moduleToplist,
        'method': QqEndpoints.methodGetToplistDetail,
        'param': {'topId': topId, 'offset': offset, 'num': num},
      },
    });
  }
}
