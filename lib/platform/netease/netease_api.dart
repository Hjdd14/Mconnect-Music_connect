import 'dart:convert';
import 'dart:math';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../core/network/platform_http.dart';
import '../../models/platform_type.dart';
import 'netease_endpoints.dart';

class NeteaseApi {
  final Dio _dio;
  String? _cookie;
  String? _csrf;
  String? _musicA;

  NeteaseApi({Dio? dio})
      : _dio = dio ??
            createPlatformDio(
              // Enables central session-expiry reporting (see platform_http).
              platform: PlatformType.netease,
              label: '网易云音乐',
              baseUrl: NeteaseEndpoints.baseUrl,
              headers: {
                'User-Agent':
                    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Safari/537.36 Chrome/125.0.0.0 NeteaseMusicDesktop/3.0.18.203152',
                'Referer': '${NeteaseEndpoints.baseUrl}/',
                'Origin': NeteaseEndpoints.baseUrl,
              },
            ) {
    _initCookie();
  }

  /// The [Dio] this adapter talks through.
  ///
  /// Exposed so tests can assert that the default constructor really goes
  /// through [createPlatformDio] (retry + typed error translation installed)
  /// instead of a bare `Dio` — that regression is exactly what Wave 1 fixed.
  @visibleForTesting
  Dio get dio => _dio;


  /// Generate initial cookie header with required fields.
  void _initCookie() {
    final rng = Random();
    final nmtid = _randomHex(rng, 16);
    final ntesNuid = _randomHex(rng, 32);
    final deviceId = _randomHex(rng, 16);
    final csrf = _randomHex(rng, 16);
    _csrf = csrf;

    _cookie = 'os=pc; appver=3.0.18.203152; osver=Microsoft-Windows-10-Professional-build-22631-64bit'
        '; deviceId=$deviceId; channel=netease'
        '; NMTID=$nmtid; _ntes_nuid=$ntesNuid'
        '; __csrf=$csrf; __remember_me=true'
        '; WEVNSM=1.0.0; resolution=1920x1080'
        '; requestId=${DateTime.now().millisecondsSinceEpoch}_${rng.nextInt(9000) + 1000}';
    _dio.options.headers['cookie'] = _cookie;
  }

  String _randomHex(Random rng, int length) {
    return List.generate(length, (_) => rng.nextInt(16).toRadixString(16)).join();
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
  ///
  /// [cancelToken] lets a caller abort a query (screen disposed, a newer query
  /// superseded this one). A cancelled request surfaces as
  /// `RequestCancelledException`, **not** `NetworkException` — do not treat it
  /// as a connectivity failure.
  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, dynamic>? query,
    CancelToken? cancelToken,
  }) async {
    final response = await _dio.get(
      path,
      queryParameters: query,
      cancelToken: cancelToken,
    );
    _captureCookie(response);
    _captureMusicA(response);
    return _parseResponse(response.data);
  }

  /// Generic POST request (form-encoded, no encryption)
  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? params,
    CancelToken? cancelToken,
  }) async {
    final response = await _dio.post(
      path,
      data: params,
      options: Options(contentType: 'application/x-www-form-urlencoded'),
      cancelToken: cancelToken,
    );
    _captureCookie(response);
    _captureMusicA(response);
    return _parseResponse(response.data);
  }

  /// Search songs (GET, no encryption)
  Future<Map<String, dynamic>> search(String keyword,
      {int page = 1, int limit = 30, int type = 1}) async {
    return get(NeteaseEndpoints.search, query: {
      's': keyword,
      'type': type,
      'limit': limit,
      'offset': (page - 1) * limit,
    });
  }

  Future<Map<String, dynamic>> searchPlaylists(String keyword,
      {int page = 1, int limit = 30}) {
    return search(keyword, page: page, limit: limit, type: 1000);
  }

  /// Get song playback URL (POST, form-encoded)
  Future<Map<String, dynamic>> getSongUrl(String songId,
      {String level = 'exhigh'}) async {
    return post(NeteaseEndpoints.songUrl, params: {
      'ids': jsonEncode([songId]),
      'level': level,
      'encodeType': '',
      'csrf': _csrf ?? '',
    });
  }

  /// Get lyrics (GET, no encryption)
  Future<Map<String, dynamic>> getLyric(String songId) async {
    return get(NeteaseEndpoints.lyric, query: {
      'id': songId,
      'lv': -1,
      'tv': -1,
    });
  }

  /// QR code key (POST, form-encoded)
  Future<Map<String, dynamic>> getQrKey() async {
    return post(NeteaseEndpoints.qrKey, params: {'type': 3});
  }

  /// Check QR code login status (POST, form-encoded)
  /// Returns: 800=expired, 801=waiting, 802=scanned, 803=success
  Future<Map<String, dynamic>> checkQr(String key) async {
    return post(NeteaseEndpoints.qrCheck, params: {
      'key': key,
      'type': 3,
    });
  }

  /// Get user info (POST, form-encoded)
  Future<Map<String, dynamic>> getUserInfo() async {
    return post(NeteaseEndpoints.userInfo, params: {});
  }

  /// Get user playlists (POST, form-encoded)
  Future<Map<String, dynamic>> getUserPlaylist(String uid,
      {int limit = 30, int offset = 0}) async {
    return post(NeteaseEndpoints.userPlaylist, params: {
      'uid': uid,
      'limit': limit,
      'offset': offset,
    });
  }

  /// Get playlist detail (POST, form-encoded). The first detail response is
  /// capped so huge playlists do not block the UI; callers can use trackIds and
  /// getSongDetails() to page in the remaining songs.
  Future<Map<String, dynamic>> getPlaylistDetail(String id, {int n = 1000}) async {
    return post(NeteaseEndpoints.playlistDetail, params: {
      'id': id,
      'n': n,
    });
  }

  /// Get song details for a batch of song IDs.
  Future<Map<String, dynamic>> getSongDetails(List<String> ids) async {
    if (ids.isEmpty) return {'songs': <dynamic>[]};
    final normalizedIds = ids
        .map((id) => int.tryParse(id) ?? id)
        .toList(growable: false);
    return post(NeteaseEndpoints.songDetail, params: {
      'ids': jsonEncode(normalizedIds),
      'c': jsonEncode([
        for (final id in normalizedIds) {'id': id},
      ]),
      'csrf': _csrf ?? '',
    });
  }

  /// Get daily recommendations (GET, no encryption)
  Future<Map<String, dynamic>> getRecommendSongs() async {
    return get(NeteaseEndpoints.recommendSongs);
  }

  /// Like a song (POST, form-encoded)
  Future<Map<String, dynamic>> likeSong(String songId, {bool like = true}) async {
    return post(NeteaseEndpoints.like, params: {
      'trackId': songId,
      'like': like,
    });
  }

  Future<Map<String, dynamic>> createPlaylist(String name, {int privacy = 0}) async {
    return post(NeteaseEndpoints.playlistCreate, params: {
      'name': name,
      'privacy': privacy,
      'type': 'NORMAL',
      'csrf': _csrf ?? '',
    });
  }

  Future<Map<String, dynamic>> subscribePlaylist(String playlistId, {bool subscribe = true}) async {
    return post(
      subscribe
          ? NeteaseEndpoints.playlistSubscribe
          : NeteaseEndpoints.playlistUnsubscribe,
      params: {
        'id': playlistId,
        'csrf': _csrf ?? '',
      },
    );
  }

  // ---------------------------------------------------------------------------
  // 榜单 / 新歌 / 艺人 / 专辑
  //
  // 端点与字段名全部实测（`docs/netease-wave-b-probe.md`，2026-10-06）：18 个
  // 端点全部 HTTP 200。注释里标出的"实测"结论都是探针跑出来的，不是推测。
  // ---------------------------------------------------------------------------

  /// 全部榜单（`GET /api/toplist`）。
  ///
  /// 实测：`list` 63 条，字段 `id/name/coverImgUrl/updateFrequency/trackCount`。
  Future<Map<String, dynamic>> getToplists({CancelToken? cancelToken}) {
    return get(NeteaseEndpoints.toplist, cancelToken: cancelToken);
  }

  /// 新歌速递，按地区（`GET /api/v1/discovery/new/songs?areaId=`）。
  ///
  /// 实测：服务端**忽略** `limit`/`offset`，固定返回 100 条 `data[]`，所以切片
  /// 必须由调用方（[NeteasePlatform.getNewSongs]）自己做。
  Future<Map<String, dynamic>> getNewSongsByArea({
    int areaId = 0,
    CancelToken? cancelToken,
  }) {
    return get(
      NeteaseEndpoints.newSongsByArea,
      query: {'areaId': areaId, 'limit': 100},
      cancelToken: cancelToken,
    );
  }

  /// 个性推荐新歌（`GET /api/personalized/newsong`），用作"全部地区"的兜底。
  ///
  /// 实测：真实歌曲在 `result[].song`，且 `result[].type` 是 **int 4** —— 按任务
  /// 书写的 `type == 'song'` 过滤会把 100 条全部滤掉（probe 7b：type 取值集合
  /// 只有 `{4 (int)}`）。另外该接口忽略 `type`/`areaId`（probe 7c/7e：8 种 type
  /// 返回同一批歌），所以它**不能**用于地区筛选。
  Future<Map<String, dynamic>> getPersonalizedNewSongs({
    CancelToken? cancelToken,
  }) {
    return get(
      NeteaseEndpoints.personalizedNewSongs,
      query: {'limit': 100},
      cancelToken: cancelToken,
    );
  }

  /// 艺人信息（`POST /api/artist/head/info/get` → `data.artist`）。
  ///
  /// 实测字段：`id/name/cover/avatar/briefDesc(665 字)/musicSize/albumSize`；
  /// **没有** `fansCount`。
  Future<Map<String, dynamic>> getArtistHeadInfo(
    String artistId, {
    CancelToken? cancelToken,
  }) {
    return post(
      NeteaseEndpoints.artistHeadInfo,
      params: {'id': artistId},
      cancelToken: cancelToken,
    );
  }

  /// 旧明文艺人接口（`GET /api/artist/{id}`），一次返回艺人信息 + 50 首热门。
  ///
  /// 实测：`artist{musicSize,albumSize,briefDesc(空字符串!)}` + `hotSongs[]`(50)。
  /// 它的 `briefDesc` 是空的，所以简介要优先用 [getArtistHeadInfo]。
  Future<Map<String, dynamic>> getArtistLegacy(
    String artistId, {
    CancelToken? cancelToken,
  }) {
    return get(
      '${NeteaseEndpoints.artistLegacyPrefix}$artistId',
      cancelToken: cancelToken,
    );
  }

  /// 艺人热门歌曲（`GET /api/artist/top/song?id=`）。
  ///
  /// 实测：`songs` 50 首，用 `ar/al/dt` 命名。
  Future<Map<String, dynamic>> getArtistTopSongs(
    String artistId, {
    CancelToken? cancelToken,
  }) {
    return get(
      NeteaseEndpoints.artistTopSong,
      query: {'id': artistId},
      cancelToken: cancelToken,
    );
  }

  /// 艺人专辑（`GET /api/artist/albums/{id}?limit&offset`）。
  ///
  /// 实测：`hotAlbums[]`，含 `id/name/picUrl/publishTime/size/company/description`，
  /// `limit` 与 `offset` **都生效**（offset=5 时首条 id 与 offset=0 不同）。
  Future<Map<String, dynamic>> getArtistAlbums(
    String artistId, {
    int limit = 30,
    int offset = 0,
    CancelToken? cancelToken,
  }) {
    return get(
      '${NeteaseEndpoints.artistAlbumsPrefix}$artistId',
      query: {'limit': limit, 'offset': offset},
      cancelToken: cancelToken,
    );
  }

  /// 专辑详情 + 曲目（`GET /api/v1/album/{id}`）。
  ///
  /// 实测：元数据在 `album{}`，曲目在**顶层** `songs[]`（`album.songs` 是空数组，
  /// 用它会得到 0 首），曲目 `no` 为 1..N 连续。
  Future<Map<String, dynamic>> getAlbumDetail(
    String albumId, {
    CancelToken? cancelToken,
  }) {
    return get(
      '${NeteaseEndpoints.albumDetailPrefix}$albumId',
      cancelToken: cancelToken,
    );
  }
}
