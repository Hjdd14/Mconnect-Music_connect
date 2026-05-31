import 'dart:convert';
import 'dart:math';
import 'package:dio/dio.dart';
import 'netease_endpoints.dart';

class NeteaseApi {
  final Dio _dio;
  String? _cookie;
  String? _csrf;
  String? _musicA;

  NeteaseApi({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: 'https://music.163.com',
              headers: {
                'User-Agent':
                    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Safari/537.36 Chrome/125.0.0.0 NeteaseMusicDesktop/3.0.18.203152',
                'Referer': 'https://music.163.com/',
                'Origin': 'https://music.163.com',
              },
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 15),
            ),
          ) {
    _initCookie();
  }

  /// Generate initial cookie header with required fields.
  void _initCookie() {
    final rng = Random();
    final nmtid = _randomHex(rng, 16);
    final ntesNuid = _randomHex(rng, 32);
    final deviceId = _randomHex(rng, 16);
    final csrf = _randomHex(rng, 16);
    _csrf = csrf;

    _cookie =
        'os=pc; appver=3.0.18.203152; osver=Microsoft-Windows-10-Professional-build-22631-64bit'
        '; deviceId=$deviceId; channel=netease'
        '; NMTID=$nmtid; _ntes_nuid=$ntesNuid'
        '; __csrf=$csrf; __remember_me=true'
        '; WEVNSM=1.0.0; resolution=1920x1080'
        '; requestId=${DateTime.now().millisecondsSinceEpoch}_${rng.nextInt(9000) + 1000}';
    _dio.options.headers['cookie'] = _cookie;
  }

  String _randomHex(Random rng, int length) {
    return List.generate(
      length,
      (_) => rng.nextInt(16).toRadixString(16),
    ).join();
  }

  void setCookie(String cookie) {
    if (cookie.isEmpty) {
      _cookie = '';
      _dio.options.headers['cookie'] = '';
      return;
    }
    // Merge new cookie into existing
    final existing = _parseCookieMap(_cookie ?? '');
    existing.addAll(_parseCookieMap(cookie));
    _cookie = existing.entries.map((e) => '${e.key}=${e.value}').join('; ');
    _dio.options.headers['cookie'] = _cookie;
  }

  Map<String, String> _parseCookieMap(String cookieStr) {
    final map = <String, String>{};
    for (final part in cookieStr.split(';')) {
      final trimmed = part.trim();
      final eqIndex = trimmed.indexOf('=');
      if (eqIndex > 0) {
        map[trimmed.substring(0, eqIndex)] = trimmed.substring(eqIndex + 1);
      }
    }
    return map;
  }

  String? get cookie => _cookie;
  String? get csrf => _csrf;

  void restoreCookie(String cookie) {
    // Merge stored cookie into current (preserving fresh NMTID/_ntes_nuid/__csrf)
    final existing = _parseCookieMap(_cookie ?? '');
    existing.addAll(_parseCookieMap(cookie));
    _cookie = existing.entries.map((e) => '${e.key}=${e.value}').join('; ');
    _dio.options.headers['cookie'] = _cookie;
    _csrf = _extractCookie('__csrf');
  }

  /// Capture ALL cookies from Set-Cookie headers (merge, don't replace).
  void _captureCookie(Response response) {
    final setCookieHeaders = response.headers['set-cookie'];
    if (setCookieHeaders == null) return;
    final existing = _parseCookieMap(_cookie ?? '');
    for (final header in setCookieHeaders) {
      // Parse each Set-Cookie: "name=value; path=/; ..."
      final parts = header.split(';');
      if (parts.isNotEmpty) {
        final nameValue = parts[0].trim();
        final eqIndex = nameValue.indexOf('=');
        if (eqIndex > 0) {
          final name = nameValue.substring(0, eqIndex).trim();
          final value = nameValue.substring(eqIndex + 1).trim();
          existing[name] = value;
          if (name == '__csrf') _csrf = value;
        }
      }
    }
    _cookie = existing.entries.map((e) => '${e.key}=${e.value}').join('; ');
    _dio.options.headers['cookie'] = _cookie;
  }

  /// Capture anonymous token (MUSIC_A) if server provides it.
  void _captureMusicA(Response response) {
    final setCookieHeaders = response.headers['set-cookie'];
    if (setCookieHeaders == null) return;
    for (final header in setCookieHeaders) {
      final match = RegExp(r'MUSIC_A=([^;]+)').firstMatch(header);
      if (match != null) {
        _musicA = match.group(1);
        // Add MUSIC_A to cookie if not present
        if (_cookie != null && !_cookie!.contains('MUSIC_A=')) {
          _cookie = '$_cookie; MUSIC_A=$_musicA';
          _dio.options.headers['cookie'] = _cookie;
        }
        return;
      }
    }
  }

  String? _extractCookie(String name) {
    if (_cookie == null) return null;
    final match = RegExp('$name=([^;]+)').firstMatch(_cookie!);
    return match?.group(1);
  }

  /// Parse response data (handles both Map and String)
  Map<String, dynamic> _parseResponse(dynamic data) {
    if (data == null) throw Exception('服务器返回空响应');
    if (data is Map<String, dynamic>) return data;
    if (data is String) {
      if (data.isEmpty) throw Exception('服务器返回空响应');
      return jsonDecode(data) as Map<String, dynamic>;
    }
    throw Exception('响应格式异常: ${data.runtimeType}');
  }

  /// Generic GET request
  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    final response = await _dio.get(path, queryParameters: query);
    _captureCookie(response);
    _captureMusicA(response);
    return _parseResponse(response.data);
  }

  /// Generic POST request (form-encoded, no encryption)
  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? params,
  }) async {
    final response = await _dio.post(
      path,
      data: params,
      options: Options(contentType: 'application/x-www-form-urlencoded'),
    );
    _captureCookie(response);
    _captureMusicA(response);
    return _parseResponse(response.data);
  }

  /// Search songs (GET, no encryption)
  Future<Map<String, dynamic>> search(
    String keyword, {
    int page = 1,
    int limit = 30,
    int type = 1,
  }) async {
    return get(
      NeteaseEndpoints.search,
      query: {
        's': keyword,
        'type': type,
        'limit': limit,
        'offset': (page - 1) * limit,
      },
    );
  }

  Future<Map<String, dynamic>> searchPlaylists(
    String keyword, {
    int page = 1,
    int limit = 30,
  }) {
    return search(keyword, page: page, limit: limit, type: 1000);
  }

  /// Get song playback URL (POST, form-encoded)
  Future<Map<String, dynamic>> getSongUrl(
    String songId, {
    String level = 'exhigh',
  }) async {
    return post(
      NeteaseEndpoints.songUrl,
      params: {
        'ids': jsonEncode([songId]),
        'level': level,
        'encodeType': '',
        'csrf': _csrf ?? '',
      },
    );
  }

  /// Get lyrics (GET, no encryption)
  Future<Map<String, dynamic>> getLyric(String songId) async {
    return get(
      NeteaseEndpoints.lyric,
      query: {'id': songId, 'lv': -1, 'tv': -1},
    );
  }

  /// QR code key (POST, form-encoded)
  Future<Map<String, dynamic>> getQrKey() async {
    return post(NeteaseEndpoints.qrKey, params: {'type': 3});
  }

  /// Check QR code login status (POST, form-encoded)
  /// Returns: 800=expired, 801=waiting, 802=scanned, 803=success
  Future<Map<String, dynamic>> checkQr(String key) async {
    return post(NeteaseEndpoints.qrCheck, params: {'key': key, 'type': 3});
  }

  /// Get user info (POST, form-encoded)
  Future<Map<String, dynamic>> getUserInfo() async {
    return post(NeteaseEndpoints.userInfo, params: {});
  }

  /// Get user playlists (POST, form-encoded)
  Future<Map<String, dynamic>> getUserPlaylist(
    String uid, {
    int limit = 30,
    int offset = 0,
  }) async {
    return post(
      NeteaseEndpoints.userPlaylist,
      params: {'uid': uid, 'limit': limit, 'offset': offset},
    );
  }

  /// Get playlist detail (POST, form-encoded). The first detail response is
  /// capped so huge playlists do not block the UI; callers can use trackIds and
  /// getSongDetails() to page in the remaining songs.
  Future<Map<String, dynamic>> getPlaylistDetail(
    String id, {
    int n = 1000,
  }) async {
    return post(NeteaseEndpoints.playlistDetail, params: {'id': id, 'n': n});
  }

  /// Get song details for a batch of song IDs.
  Future<Map<String, dynamic>> getSongDetails(List<String> ids) async {
    if (ids.isEmpty) return {'songs': <dynamic>[]};
    final normalizedIds = ids
        .map((id) => int.tryParse(id) ?? id)
        .toList(growable: false);
    return post(
      '/api/v3/song/detail',
      params: {
        'ids': jsonEncode(normalizedIds),
        'c': jsonEncode([
          for (final id in normalizedIds) {'id': id},
        ]),
        'csrf': _csrf ?? '',
      },
    );
  }

  /// Get daily recommendations (GET, no encryption)
  Future<Map<String, dynamic>> getRecommendSongs() async {
    return get(NeteaseEndpoints.recommendSongs);
  }

  /// Like a song (POST, form-encoded)
  Future<Map<String, dynamic>> likeSong(
    String songId, {
    bool like = true,
  }) async {
    return post(
      NeteaseEndpoints.like,
      params: {'trackId': songId, 'like': like},
    );
  }

  Future<Map<String, dynamic>> createPlaylist(
    String name, {
    int privacy = 0,
  }) async {
    return post(
      '/api/playlist/create',
      params: {
        'name': name,
        'privacy': privacy,
        'type': 'NORMAL',
        'csrf': _csrf ?? '',
      },
    );
  }

  Future<Map<String, dynamic>> subscribePlaylist(
    String playlistId, {
    bool subscribe = true,
  }) async {
    return post(
      '/api/playlist/${subscribe ? 'subscribe' : 'unsubscribe'}',
      params: {'id': playlistId, 'csrf': _csrf ?? ''},
    );
  }
}
