import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import '../../core/network/api_exception.dart';
import '../../core/network/platform_http.dart';
import '../../models/audio_quality.dart';
import '../../models/platform_type.dart';
import 'kugou_endpoints.dart';

enum KugouPlaybackClient { android, lite }

class KugouApi {
  final Dio _dio;
  String? _token;
  String? _userid;
  String? _vipToken;
  String? _vipType;
  String? _dfid;
  String? _mid;
  String? _uuid;
  KugouPlaybackClient _clientMode = KugouPlaybackClient.android;

  /// [dio] is injectable for tests; production always goes through
  /// [createPlatformDio] so the shared retry / error-translation interceptors
  /// apply. Retries are restricted to idempotent methods there, so the POST
  /// writes in this class (`song/collect`, `createPlaylist`, …) are never
  /// replayed.
  KugouApi({Dio? dio})
    : _dio =
          dio ??
          createPlatformDio(
            // Enables central session-expiry reporting (see platform_http).
            platform: PlatformType.kugou,
            label: '酷狗音乐',
            headers: {
              'User-Agent':
                  'Mozilla/5.0 (Linux; Android 11) AppleWebKit/537.36',
            },
          );

  void setToken(String token) {
    setSessionFields(token: token);
  }

  void setUserId(String userid) {
    setSessionFields(userid: userid);
  }

  String? get token => _token;
  String? get userid => _userid;
  String? get vipToken => _vipToken;
  String? get vipType => _vipType;
  String? get dfid => _dfid;
  String? get mid => _mid;
  String? get uuid => _uuid;
  KugouPlaybackClient get clientMode => _clientMode;
  String get clientModeName =>
      _clientMode == KugouPlaybackClient.lite ? 'lite' : 'android';

  bool get hasToken => _token?.isNotEmpty ?? false;
  bool get hasUserId => _userid?.isNotEmpty ?? false;
  bool get hasVipToken => _vipToken?.isNotEmpty ?? false;

  bool get hasVipPlaybackSession =>
      (_token?.isNotEmpty ?? false) &&
      (_userid?.isNotEmpty ?? false) &&
      (_vipToken?.isNotEmpty ?? false);

  void setClientMode(KugouPlaybackClient mode) {
    _clientMode = mode;
  }

  void setClientVariant(String? variant) {
    _clientMode = clientModeFromVariant(variant);
  }

  static KugouPlaybackClient clientModeFromVariant(String? variant) {
    final normalized = variant?.trim().toLowerCase();
    if (normalized == 'lite' ||
        normalized == 'concept' ||
        normalized == 'kugou_concept' ||
        normalized == 'kugou_lite' ||
        normalized == '概念版' ||
        normalized == '酷狗概念版') {
      return KugouPlaybackClient.lite;
    }
    return KugouPlaybackClient.android;
  }

  void setSessionFields({
    String? token,
    String? userid,
    String? vipToken,
    String? vipType,
    String? dfid,
    String? mid,
    String? uuid,
  }) {
    void setIfPresent(String? value, void Function(String) set) {
      final trimmed = value?.trim();
      if (trimmed != null && trimmed.isNotEmpty && trimmed != 'null') {
        set(trimmed);
      }
    }

    setIfPresent(token, (value) => _token = value);
    setIfPresent(userid, (value) => _userid = value);
    setIfPresent(vipToken, (value) => _vipToken = value);
    setIfPresent(vipType, (value) => _vipType = value);
    setIfPresent(dfid, (value) => _dfid = value);
    setIfPresent(mid, (value) => _mid = value);
    setIfPresent(uuid, (value) => _uuid = value);
  }

  void restoreToken(String token) {
    setSessionFields(token: token);
  }

  /// Drops the cached session fields.
  ///
  /// [setSessionFields] cannot be used for this: it deliberately **skips empty
  /// values**, so calling `setSessionFields()` would leave the old token in
  /// place. Before this method existed, `KugouPlatform.logout()` only cleared
  /// `_currentUser`, and the stale `_token` kept being injected into every
  /// request by [_signedAndroidParams] until the process restarted.
  ///
  /// Account-scoped fields (`token`/`userid`/`vipToken`/`vipType`) are always
  /// cleared. Device-scoped fields (`dfid`/`mid`/`uuid`) are kept by default:
  /// they are not credentials, and rotating the fingerprint on every logout is
  /// exactly the kind of sudden device change Kugou's risk control reacts to.
  /// Pass [keepDeviceIds] `false` when the caller really wants anonymity.
  void clearSession({bool keepDeviceIds = true}) {
    _token = null;
    _userid = null;
    _vipToken = null;
    _vipType = null;
    if (!keepDeviceIds) {
      _dfid = null;
      _mid = null;
      _uuid = null;
    }
  }

  /// Decode response data - handles both Map and String (JSON) responses.
  ///
  /// Kugou answers WAF-rejected requests with **HTTP 200 and a non-JSON body**
  /// (`Access Deny ! No Actions !`), which used to surface as a generic
  /// `FormatException`. It is translated into an [ApiException] here so a
  /// refused endpoint can never be mistaken for an empty-but-successful list.
  Map<String, dynamic> _decodeResponse(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    if (data is String) {
      final cleaned = _stripResourceTags(data);
      try {
        final decoded = jsonDecode(cleaned);
        if (decoded is Map<String, dynamic>) return decoded;
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
        throw ApiException(
          message: '酷狗接口返回了意外的数据结构',
          details: '${decoded.runtimeType}',
        );
      } on FormatException {
        if (cleaned.contains('Access Deny')) {
          throw ApiException(
            message: '酷狗接口拒绝访问',
            details: cleaned.trim(),
          );
        }
        throw ApiException(
          message: '酷狗接口返回了非 JSON 响应',
          details: cleaned.length > 120 ? cleaned.substring(0, 120) : cleaned,
        );
      }
    }
    throw ApiException(
      message: '酷狗接口返回了意外的数据结构',
      details: '${data.runtimeType}',
    );
  }

  /// Some Kugou endpoints wrap the JSON document in
  /// `<!--KG_TAG_RES_START-->…<!--KG_TAG_RES_END-->` (seen on `singer/info`
  /// when `with_res_tag=1` is sent, and on payloads returned by an edge node).
  String _stripResourceTags(String body) {
    var cleaned = body;
    const startTag = '<!--KG_TAG_RES_START-->';
    const endTag = '<!--KG_TAG_RES_END-->';
    if (cleaned.contains(startTag)) {
      cleaned = cleaned.replaceAll(startTag, '');
    }
    if (cleaned.contains(endTag)) {
      cleaned = cleaned.replaceAll(endTag, '');
    }
    return cleaned.trim();
  }

  /// Search songs
  Future<Map<String, dynamic>> search(
    String keyword, {
    int page = 1,
    int limit = 30,
  }) async {
    final res = await _dio.get(
      KugouEndpoints.searchBase,
      queryParameters: {
        'format': 'json',
        'keyword': keyword,
        'page': page,
        'pagesize': limit,
        'showtype': 1,
      },
    );
    return _decodeResponse(res.data);
  }

  Future<Map<String, dynamic>> searchPlaylists(
    String keyword, {
    int page = 1,
    int limit = 30,
  }) async {
    final params = _signedAndroidParams({
      'keyword': keyword,
      'page': page,
      'pagesize': limit,
      'platform': 'AndroidFilter',
      'nocollect': 0,
      'iscorrection': 1,
    });
    final res = await _dio.get(
      KugouEndpoints.playlistSearch,
      queryParameters: params,
      options: Options(headers: {'x-router': 'complexsearch.kugou.com'}),
    );
    return _decodeResponse(res.data);
  }

  /// Get song info (playback URL)
  Future<Map<String, dynamic>> getSongInfo(String hash) async {
    final res = await _dio.get(
      KugouEndpoints.songInfo,
      queryParameters: {'cmd': 'playInfo', 'hash': hash},
    );
    return _decodeResponse(res.data);
  }

  Future<Map<String, dynamic>> getSongPlaybackUrl(
    String hash, {
    String? albumId,
    String? albumAudioId,
    AudioLevel quality = AudioLevel.low,
    KugouPlaybackClient client = KugouPlaybackClient.android,
  }) async {
    final normalizedHash = hash.toLowerCase();
    final userid = _userid ?? '0';
    final isLite = client == KugouPlaybackClient.lite;
    final appid = isLite ? 3116 : 1005;
    final params = <String, dynamic>{
      'album_id': int.tryParse(albumId ?? '') ?? 0,
      'area_code': 1,
      'hash': normalizedHash,
      'ssa_flag': 'is_fromtrack',
      'version': 11430,
      'page_id': isLite ? 967177915 : 151369488,
      'quality': _playbackQualityParam(quality),
      'album_audio_id': int.tryParse(albumAudioId ?? '') ?? 0,
      'behavior': 'play',
      'pid': isLite ? 411 : 2,
      'cmd': 26,
      'pidversion': 3001,
      'IsFreePart': 0,
      'ppage_id': isLite
          ? '356753938,823673182,967485191'
          : '463467626,350369493,788954147',
      'cdnBackup': 1,
      'module': '',
      'clientver': 11430,
      'key': _songUrlKey(
        normalizedHash,
        userid: userid,
        appid: appid,
        lite: isLite,
      ),
    };
    final res = await _dio.get(
      KugouEndpoints.songPlaybackUrl,
      queryParameters: _signedAndroidParams(params, '', client),
      options: Options(headers: {'x-router': 'trackercdn.kugou.com'}),
    );
    return _decodeResponse(res.data);
  }

  Future<Map<String, dynamic>> getSongPrivatePlaybackUrl(
    String hash, {
    String? albumAudioId,
    AudioLevel quality = AudioLevel.low,
  }) async {
    final normalizedHash = hash.toLowerCase();
    final userid = _userid ?? '0';
    final clienttimeMs = DateTime.now().millisecondsSinceEpoch;
    final albumAudioIdValue = int.tryParse(albumAudioId ?? '') ?? 0;
    final data = {
      'area_code': '1',
      'behavior': 'play',
      'qualities': _privateQualityPreferences(quality),
      'resource': {
        'album_audio_id': albumAudioIdValue,
        'collect_list_id': '3',
        'collect_time': clienttimeMs,
        'hash': normalizedHash,
        'id': 0,
        'page_id': 1,
        'type': 'audio',
      },
      'token': _token ?? '',
      'tracker_param': {
        'all_m': 1,
        'auth': '',
        'is_free_part': 0,
        'key': _privateTrackerKey(normalizedHash, userid: userid),
        'module_id': 0,
        'need_climax': 1,
        'need_xcdn': 1,
        'open_time': '',
        'pid': '411',
        'pidversion': '3001',
        'priv_vip_type': '6',
        'viptoken': _vipToken ?? '',
      },
      'userid': userid,
      'vip': _vipType ?? 0,
    };
    final res = await _dio.post(
      KugouEndpoints.songPrivateUrl,
      data: data,
      queryParameters: _signedAndroidParams(
        const {},
        jsonEncode(data),
        KugouPlaybackClient.lite,
      ),
    );
    return _decodeResponse(res.data);
  }

  String _playbackQualityParam(AudioLevel quality) {
    return switch (quality) {
      AudioLevel.low => '128',
      AudioLevel.medium || AudioLevel.high => '320',
      AudioLevel.lossless => 'flac',
      AudioLevel.hires => 'high',
      AudioLevel.spatial => 'viper_clear',
      AudioLevel.dolby => 'viper_atmos',
      AudioLevel.master => 'viper_tape',
    };
  }

  List<String> _privateQualityPreferences(AudioLevel quality) {
    final preferred = _playbackQualityParam(quality);
    const fallback = [
      'flac',
      'high',
      'viper_clear',
      'viper_atmos',
      'viper_tape',
      '320',
      '128',
      'multitrack',
      'super',
    ];
    return [preferred, ...fallback.where((item) => item != preferred)];
  }

  String _songUrlKey(
    String hash, {
    required String userid,
    int appid = 1005,
    bool lite = false,
  }) {
    final secret = lite
        ? '185672dd44712f60bb1736df5a377e82'
        : '57ae12eb6890223e355ccfcb74edf70d';
    final mid = _mid ?? 'mid';
    return md5.convert(utf8.encode('$hash$secret$appid$mid$userid')).toString();
  }

  String _privateTrackerKey(String hash, {required String userid}) {
    final mid = _mid ?? 'mid';
    return md5
        .convert(
          utf8.encode('${hash}185672dd44712f60bb1736df5a377e823116$mid$userid'),
        )
        .toString();
  }

  /// Search lyrics by keyword
  Future<List<Map<String, dynamic>>> searchLyrics(
    String keyword, {
    int duration = 0,
  }) async {
    final res = await _dio.get(
      KugouEndpoints.lyricsSearch,
      queryParameters: {
        'ver': 1,
        'man': 'yes',
        'client': 'pc',
        'keyword': keyword,
        'duration': duration,
        'hash': '',
      },
    );
    final data = _decodeResponse(res.data);
    final candidates = data['candidates'] as List<dynamic>?;
    if (candidates == null) return [];
    return candidates.cast<Map<String, dynamic>>();
  }

  /// Search lyrics by hash (more reliable than keyword-based)
  Future<List<Map<String, dynamic>>> searchLyricsByHash(String hash) async {
    try {
      final res = await _dio.get(
        KugouEndpoints.lyricsSearchByHash,
        queryParameters: {
          'ver': 1,
          'man': 'yes',
          'client': 'mobi',
          'keyword': '',
          'duration': '',
          'hash': hash,
          'album_audio_id': '',
        },
      );
      final data = _decodeResponse(res.data);
      final candidates = data['candidates'] as List<dynamic>?;
      if (candidates == null) return [];
      return candidates.cast<Map<String, dynamic>>();
    } catch (e) {
      developer.log('searchLyricsByHash error: $e', name: 'KugouApi');
      return [];
    }
  }

  /// Download KRC lyrics (encrypted)
  Future<String?> downloadKrc(String id, String accesskey) async {
    final krc = await _downloadLyrics(id, accesskey, format: 'krc');
    if (krc != null && krc.isNotEmpty) return krc;

    final lrc = await _downloadLyrics(id, accesskey, format: 'lrc');
    if (lrc != null && lrc.isNotEmpty) return lrc;
    return null;
  }

  Future<String?> _downloadLyrics(
    String id,
    String accesskey, {
    required String format,
  }) async {
    try {
      final res = await _dio.get(
        KugouEndpoints.lyricsDownload,
        queryParameters: {
          'ver': 1,
          'client': 'pc',
          'id': id,
          'accesskey': accesskey,
          'fmt': format,
          'charset': 'utf8',
        },
      );
      final data = _decodeResponse(res.data);
      return _decodeDownloadedLyrics(
        data['content'] as String?,
        format: format,
        contentType: int.tryParse(data['contenttype']?.toString() ?? ''),
      );
    } catch (e) {
      developer.log('downloadLyrics($format) error: $e', name: 'KugouApi');
      return null;
    }
  }

  @visibleForTesting
  String? decodeDownloadedLyricsForTest(
    String? content, {
    required String format,
    int? contentType,
  }) {
    return _decodeDownloadedLyrics(
      content,
      format: format,
      contentType: contentType,
    );
  }

  String? _decodeDownloadedLyrics(
    String? content, {
    required String format,
    int? contentType,
  }) {
    if (content == null || content.isEmpty) return null;
    if (format == 'lrc' || contentType != 0) {
      return _decodeBase64Text(content) ?? content;
    }
    return _decryptKrc(content);
  }

  String? _decodeBase64Text(String content) {
    try {
      return utf8.decode(base64Decode(content));
    } catch (_) {
      return null;
    }
  }

  /// Decrypt KRC lyrics
  /// Algorithm: Base64 decode -> skip 4 bytes header -> XOR with 16-byte key -> zlib decompress -> UTF-8
  String? _decryptKrc(String encrypted) {
    try {
      final data = base64Decode(encrypted);
      if (data.length < 4) return null;

      // Skip first 4 bytes (header)
      final encryptedBytes = data.sublist(4);

      // XOR key
      const key = [
        0x40,
        0x47,
        0x61,
        0x77,
        0x5e,
        0x32,
        0x74,
        0x47,
        0x51,
        0x36,
        0x31,
        0x2d,
        0xce,
        0xd2,
        0x6e,
        0x69,
      ];

      // XOR decrypt
      final decrypted = List<int>.generate(
        encryptedBytes.length,
        (i) => encryptedBytes[i] ^ key[i % key.length],
      );

      // zlib decompress
      final decompressed = zlib.decode(decrypted);

      if (decompressed.isEmpty) return null;
      return utf8.decode(decompressed);
    } catch (e) {
      developer.log('KRC decrypt error: $e', name: 'KugouApi');
      return null;
    }
  }

  /// Legacy 官方每日推荐 endpoint.
  ///
  /// The server answers HTTP 200 with the WAF page `Access Deny ! No Actions !`
  /// (probed 2026-10-06 with five signing variants), so [_decodeResponse] turns
  /// it into an [ApiException] instead of a silent empty result. Callers are
  /// expected to treat that as "official source unavailable" and fall back to
  /// [getHomepage] — see `KugouPlatform.getDailyRecommendation`.
  Future<Map<String, dynamic>> getRecommend() async {
    final res = await _dio.get(
      KugouEndpoints.recommend,
      queryParameters: {'format': 'json'},
    );
    return _decodeResponse(res.data);
  }

  /// Mobile homepage modules (`m.kugou.com/?json=true`).
  ///
  /// `data` is 10 recommended songs (same song shape as `rank/song`), and
  /// `special.list.info[].songs` carries more. This is the source behind the
  /// 酷狗推荐 list now that [getRecommend] is refused server-side.
  Future<Map<String, dynamic>> getHomepage() async {
    final res = await _dio.get(KugouEndpoints.homepage);
    return _decodeResponse(res.data);
  }

  /// Every chart Kugou publishes (`rank/list`, 25 rows).
  Future<Map<String, dynamic>> getToplists({
    int page = 1,
    int pagesize = 100,
  }) async {
    final res = await _dio.get(
      KugouEndpoints.rankList,
      queryParameters: {
        'format': 'json',
        'withsong': 0,
        'plat': 0,
        'page': page,
        'pagesize': pagesize,
      },
    );
    return _decodeResponse(res.data);
  }

  /// Artist profile (`singer/info`).
  ///
  /// `with_res_tag` is deliberately not sent: the response is plain JSON
  /// without it, and [_decodeResponse] strips the wrapper if a node adds it.
  Future<Map<String, dynamic>> getArtistInfo(String singerId) async {
    final res = await _dio.get(
      KugouEndpoints.singerInfo,
      queryParameters: {'singerid': singerId},
    );
    return _decodeResponse(res.data);
  }

  /// Artist songs (`singer/song`, `sorttype=2` = 最热).
  Future<Map<String, dynamic>> getArtistSongs(
    String singerId, {
    int page = 1,
    int pagesize = 100,
    int sortType = 2,
  }) async {
    final res = await _dio.get(
      KugouEndpoints.singerSongs,
      queryParameters: {
        'sorttype': sortType,
        'version': 9108,
        'identity': 3,
        'plat': 0,
        'pagesize': pagesize,
        'singerid': singerId,
        'area_code': 1,
        'page': page,
      },
    );
    return _decodeResponse(res.data);
  }

  /// Artist albums (`singer/album`; `singer/albumlist` is refused).
  Future<Map<String, dynamic>> getArtistAlbums(
    String singerId, {
    int page = 1,
    int pagesize = 100,
  }) async {
    final res = await _dio.get(
      KugouEndpoints.singerAlbums,
      queryParameters: {
        'singerid': singerId,
        'page': page,
        'pagesize': pagesize,
        'plat': 0,
      },
    );
    return _decodeResponse(res.data);
  }

  /// Album metadata (`album/info`).
  Future<Map<String, dynamic>> getAlbumInfo(String albumId) async {
    final res = await _dio.get(
      KugouEndpoints.albumInfo,
      queryParameters: {'albumid': albumId, 'format': 'json'},
    );
    return _decodeResponse(res.data);
  }

  /// Album tracks (`album/song`).
  Future<Map<String, dynamic>> getAlbumSongs(
    String albumId, {
    int page = 1,
    int pagesize = 100,
  }) async {
    final res = await _dio.get(
      KugouEndpoints.albumSongs,
      queryParameters: {
        'albumid': albumId,
        'page': page,
        'pagesize': pagesize,
        'plat': 0,
        'version': 11309,
      },
    );
    return _decodeResponse(res.data);
  }

  /// Login with phone number.
  ///
  /// **Unreachable from the app since v1.4.1**: Kugou is QR-login only
  /// (`KugouPlatform.supportsPhoneLogin == false`, and `loginByPhone` refuses
  /// before calling this). Kept only so the method that used to work still
  /// exists for reference; do NOT re-enable — `loginIndex` and
  /// `sendMobileCode` are cleartext hosts, and `login.user.kugou.com` has no
  /// usable TLS (probe: docs/kugou-cleartext-probe.md).
  Future<Map<String, dynamic>> login(String phone, String code) async {
    final res = await _dio.post(
      KugouEndpoints.loginIndex,
      data: {'phone': phone, 'code': code},
    );
    return _decodeResponse(res.data);
  }

  /// Request a phone verification code.
  ///
  /// **Unreachable from the app since v1.4.1** — see [login]. Sending a phone
  /// number over this host would be cleartext with no TLS alternative.
  Future<Map<String, dynamic>> sendMobileCode(String phone) async {
    final res = await _dio.post(
      KugouEndpoints.sendMobileCode,
      data: {
        'businessid': 5,
        'mobile': phone,
        'plat': _clientMode == KugouPlaybackClient.lite ? 1 : 3,
        'appid': _clientMode == KugouPlaybackClient.lite ? 3116 : 1005,
        'clientver': _clientMode == KugouPlaybackClient.lite ? 11440 : 20489,
      },
      options: Options(headers: {'x-router': 'login.user.kugou.com'}),
    );
    return _decodeResponse(res.data);
  }

  /// Get user VIP status
  Future<Map<String, dynamic>> getVipInfo() async {
    try {
      final res = await _dio.get(
        KugouEndpoints.vipInfoApi,
        queryParameters: {
          'format': 'json',
          if (_token != null) 'token': _token,
        },
      );
      return _decodeResponse(res.data);
    } catch (_) {
      return {};
    }
  }

  // --- QR Code Login ---

  /// Get QR code image for login
  Future<Map<String, dynamic>> getQrCodeImage() async {
    final res = await _dio.get(
      KugouEndpoints.qrCodeGet,
      queryParameters: {
        'appid': 1014,
        'time': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      },
    );
    return _decodeResponse(res.data);
  }

  Future<Map<String, dynamic>> getQrLoginKey() async {
    final appid = _clientMode == KugouPlaybackClient.lite ? 3116 : 1005;
    final params = _signedWebParams({
      'appid': 1001,
      'type': 1,
      'plat': 4,
      'qrcode_txt': '${KugouEndpoints.qrLoginPage}?appid=$appid&',
      'srcappid': 2919,
    }, _clientMode);
    final res = await _dio.get(KugouEndpoints.qrKey, queryParameters: params);
    return _decodeResponse(res.data);
  }

  Future<Map<String, dynamic>> checkQrLogin(String key) async {
    final appid = _clientMode == KugouPlaybackClient.lite ? 3116 : 1005;
    final params = _signedWebParams({
      'plat': 4,
      'appid': appid,
      'srcappid': 2919,
      'qrcode': key,
    }, _clientMode);
    final res = await _dio.get(
      KugouEndpoints.qrCheckNew,
      queryParameters: params,
    );
    return _decodeResponse(res.data);
  }

  /// Poll QR code scan status
  /// Returns: 0=waiting, 1=scanned, 2=success, -1=expired
  Future<Map<String, dynamic>> checkQrStatus(
    String qrcodeId,
    String token,
  ) async {
    final res = await _dio.get(
      KugouEndpoints.qrCodeCheck,
      queryParameters: {'qrcode_id': qrcodeId, 'token': token},
    );
    return _decodeResponse(res.data);
  }

  /// Get user info from token
  Future<Map<String, dynamic>> getUserInfoFromToken() async {
    final isLite = _clientMode == KugouPlaybackClient.lite;
    final res = await _dio.get(
      KugouEndpoints.userInfo,
      queryParameters: {
        'srcappid': 2919,
        'clientver': isLite ? 11440 : 20000,
        'clienttime': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'mid': _mid ?? 'mid',
        'uuid': _uuid ?? 'uuid',
        'dfid': _dfid ?? '-',
        'appid': isLite ? 3116 : 1005,
        if (_token != null) 'token': _token,
        if (_userid != null) 'userid': _userid,
        'platid': 4,
      },
    );
    return _decodeResponse(res.data);
  }

  // --- Library ---

  /// Get user playlists/collections
  Future<Map<String, dynamic>> getUserPlaylists({
    int page = 1,
    int limit = 50,
  }) async {
    final userid = _userid ?? '0';
    final token = _token ?? '';
    final data = {
      'userid': userid,
      'token': token,
      'total_ver': 979,
      'type': 2,
      'page': page,
      'pagesize': limit,
    };
    final res = await _dio.post(
      KugouEndpoints.userPlaylist,
      data: data,
      queryParameters: _signedAndroidParams(
        {'plat': 1, 'userid': int.tryParse(userid) ?? userid, 'token': token},
        jsonEncode(data),
        _clientMode,
      ),
      options: Options(headers: {'x-router': 'cloudlist.service.kugou.com'}),
    );
    return _decodeResponse(res.data);
  }

  /// Get playlist detail
  Future<Map<String, dynamic>> getPlaylistDetail(String specialid) async {
    final res = await _dio.get(
      KugouEndpoints.playlistDetail,
      queryParameters: {
        'specialid': specialid,
        'plat': 2,
        'ver': 1000,
        'withsong': 1,
      },
    );
    return _decodeResponse(res.data);
  }

  /// Get songs in a playlist
  Future<Map<String, dynamic>> getPlaylistSongs(
    String specialid, {
    int page = 1,
    int limit = 100,
  }) async {
    final res = await _dio.get(
      KugouEndpoints.playlistSongs,
      queryParameters: {
        'specialid': specialid,
        'page': page,
        'pagesize': limit,
        'plat': 2,
        'version': 11309,
      },
    );
    return _decodeResponse(res.data);
  }

  Future<String?> resolveShareUrl(String url) async {
    final res = await _dio.get(
      url,
      options: Options(
        followRedirects: false,
        validateStatus: (status) => status != null && status < 400,
        responseType: ResponseType.plain,
      ),
    );
    return res.headers.value('location') ?? res.realUri.toString();
  }

  /// Get songs from Kugou H5 shared cloud playlists such as t1.kugou.com links.
  Future<Map<String, dynamic>> getSharedPlaylistSongs(
    String globalCollectionId, {
    int page = 1,
    int limit = 100,
  }) async {
    final params = _signedH5Params({
      'srcappid': 2919,
      'clientver': 1000,
      'appid': 1058,
      'type': 0,
      'module': 'playlist',
      'page': page,
      'pagesize': limit,
      'global_collection_id': globalCollectionId,
      'uid': _userid ?? '0',
      'token': _token ?? '',
    });
    final res = await _dio.get(
      KugouEndpoints.sharedPlaylistSongs,
      queryParameters: params,
      options: Options(
        headers: {'Referer': KugouEndpoints.sharedPlaylistReferer},
      ),
    );
    return _decodeResponse(res.data);
  }

  /// Get songs in a logged-in user's created/collected cloud playlist.
  Future<Map<String, dynamic>> getUserPlaylistSongs(
    String listid, {
    int page = 1,
    int limit = 100,
  }) async {
    final userid = _userid ?? '0';
    final token = _token ?? '';
    final data = {
      'listid': listid,
      'userid': userid,
      'token': token,
      'page': page,
      'pagesize': limit,
      'show_album_info': 1,
    };
    final res = await _dio.post(
      KugouEndpoints.userPlaylistSongs,
      data: data,
      queryParameters: _signedAndroidParams(
        const {},
        jsonEncode(data),
        _clientMode,
      ),
      options: Options(headers: {'x-router': 'cloudlist.service.kugou.com'}),
    );
    return _decodeResponse(res.data);
  }

  /// Get liked/collected songs
  Future<Map<String, dynamic>> getLikedSongs({
    int page = 1,
    int limit = 50,
  }) async {
    final res = await _dio.get(
      KugouEndpoints.userCollection,
      queryParameters: {
        'type': 1,
        'page': page,
        'pagesize': limit,
        if (_token != null) 'token': _token,
        if (_userid != null) 'userid': _userid,
        'appid': 1005,
      },
    );
    return _decodeResponse(res.data);
  }

  /// Collect (like) a song
  Future<Map<String, dynamic>> collectSong(String hash) async {
    final res = await _dio.get(
      KugouEndpoints.songCollect,
      queryParameters: {
        'hash': hash,
        'appid': 1014,
        if (_token != null) 'token': _token,
        'mid': 'mid',
        'plat': 0,
        'version': 11309,
      },
    );
    return _decodeResponse(res.data);
  }

  /// Uncollect (unlike) a song
  Future<Map<String, dynamic>> uncollectSong(String hash) async {
    final res = await _dio.get(
      KugouEndpoints.songUncollect,
      queryParameters: {
        'hash': hash,
        'appid': 1014,
        if (_token != null) 'token': _token,
        'mid': 'mid',
        'plat': 0,
        'version': 11309,
      },
    );
    return _decodeResponse(res.data);
  }

  /// Get ranking songs
  Future<Map<String, dynamic>> getRankList({
    int rankId = 8888,
    int page = 1,
    int pagesize = 100,
  }) async {
    final res = await _dio.get(
      KugouEndpoints.rankSong,
      queryParameters: {
        'rankid': rankId,
        'page': page,
        'pagesize': pagesize,
        'plat': 0,
        'version': 11309,
      },
    );
    return _decodeResponse(res.data);
  }

  Future<Map<String, dynamic>> createPlaylist(String name) async {
    final data = {
      'userid': _userid ?? '0',
      'token': _token ?? '',
      'total_ver': 0,
      'name': name,
      'type': 0,
      'source': 1,
      'is_pri': 0,
      'list_create_userid': null,
      'list_create_listid': null,
      'list_create_gid': '',
      'from_shupinmv': 0,
    };
    final params = _signedAndroidParams(
      {
        'last_time': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'last_area': 'gztx',
        'userid': _userid ?? '0',
        'token': _token ?? '',
      },
      jsonEncode(data),
      _clientMode,
    );
    final res = await _dio.post(
      KugouEndpoints.playlistAdd,
      data: data,
      queryParameters: params,
      // NO `x-router` here. Measured 2026-10-09 against the live gateway:
      //   POST gateway.kugou.com/cloudlist.service/v5/add_list  (no x-router)  -> 200
      //   same URL with x-router: cloudlist.service.kugou.com                   -> 404
      // (x-router: cloudlist.service -> 403; gateway.kugou.com -> 200.) The 404 is
      // what surfaced to the user as "新建歌单失败" with the not-found wording.
      //
      // Independent evidence that this is not a coincidence: `collectPlaylist`
      // below posts to the SAME endpoint without the header, and the sibling
      // `getUserPlaylists` also omits it — createPlaylist was the odd one out.
    );
    return _decodeResponse(res.data);
  }

  Future<Map<String, dynamic>> collectPlaylist(
    String playlistId, {
    bool collect = true,
  }) async {
    if (!collect) return {'status': 0, 'error_msg': 'uncollect unsupported'};
    final data = {
      'userid': _userid ?? '0',
      'token': _token ?? '',
      'total_ver': 0,
      'name': '',
      'type': 1,
      'source': 1,
      'is_pri': 0,
      'list_create_userid': _userid ?? '0',
      'list_create_listid': playlistId,
      'list_create_gid': '',
      'from_shupinmv': 0,
    };
    final params = _signedAndroidParams(const {}, jsonEncode(data));
    final res = await _dio.post(
      KugouEndpoints.playlistAdd,
      data: data,
      queryParameters: params,
    );
    return _decodeResponse(res.data);
  }

  Map<String, dynamic> _signedAndroidParams([
    Map<String, dynamic> params = const {},
    String data = '',
    KugouPlaybackClient client = KugouPlaybackClient.android,
  ]) {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final isLite = client == KugouPlaybackClient.lite;
    final all = <String, dynamic>{
      'dfid': _dfid ?? '-',
      'mid': _mid ?? 'mid',
      'uuid': _uuid ?? '-',
      'appid': isLite ? 3116 : 1005,
      'clientver': isLite ? 11440 : 20489,
      'clienttime': now,
      if (_token != null) 'token': _token,
      if (_userid != null) 'userid': _userid,
      ...params,
    };
    all['signature'] = _androidSignature(all, data, client);
    return all;
  }

  Map<String, dynamic> _signedWebParams(
    Map<String, dynamic> params, [
    KugouPlaybackClient? client,
  ]) {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final isLite = (client ?? _clientMode) == KugouPlaybackClient.lite;
    final all = <String, dynamic>{
      'dfid': _dfid ?? '-',
      'mid': _mid ?? 'mid',
      'uuid': _uuid ?? '-',
      'appid': isLite ? 3116 : 1005,
      'clientver': isLite ? 11440 : 20489,
      'clienttime': now,
      if (_token != null) 'token': _token,
      if (_userid != null) 'userid': _userid,
      ...params,
    };
    all['signature'] = _webSignature(all);
    return all;
  }

  Map<String, dynamic> _signedH5Params(Map<String, dynamic> params) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final all = <String, dynamic>{
      'dfid': '-',
      'mid': 'mid',
      'uuid': 'uuid',
      'clienttime': now,
      ...params,
    };
    all['signature'] = _webSignature(all);
    return all;
  }

  String _androidSignature(
    Map<String, dynamic> params,
    String data, [
    KugouPlaybackClient client = KugouPlaybackClient.android,
  ]) {
    final secret = client == KugouPlaybackClient.lite
        ? 'LnT6xpN3khm36zse0QzvmgTZ3waWdRSA'
        : 'OIlwieks28dk2k092lksi2UIkp';
    final paramsString = params.keys.toList()..sort();
    final body = paramsString
        .map(
          (key) =>
              '$key=${params[key] is Map || params[key] is List ? jsonEncode(params[key]) : params[key]}',
        )
        .join();
    return md5.convert(utf8.encode('$secret$body$data$secret')).toString();
  }

  String _webSignature(Map<String, dynamic> params) {
    const secret = 'NVPh5oo715z5DIWAeQlhMDsWXXQV4hwt';
    final keys = params.keys.toList()..sort();
    final body = keys.map((key) => '$key=${params[key]}').join();
    return md5.convert(utf8.encode('$secret$body$secret')).toString();
  }
}
