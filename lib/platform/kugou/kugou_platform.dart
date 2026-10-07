import 'dart:convert';

import 'package:flutter/foundation.dart';
import '../../models/song.dart';
import '../../models/artist.dart';
import '../../models/album.dart';
import '../../models/toplist.dart';
import '../../models/recommendation_source.dart';
import '../../models/user.dart';
import '../../models/playlist.dart';
import '../../models/audio_quality.dart';
import '../../models/platform_type.dart';
import '../base/music_platform.dart';
import '../../core/diagnostics/diagnostics_service.dart';
import '../../core/network/api_exception.dart';
import '../../core/network/platform_http.dart';
import '../../core/storage/session_storage.dart';
import 'kugou_api.dart';

class KugouPlatform extends MusicPlatform {
  final KugouApi _api;
  User? _currentUser;

  KugouPlatform({KugouApi? api}) : _api = api ?? KugouApi();

  KugouApi get api => _api;

  void setClientVariant(String? variant) {
    _api.setClientVariant(variant);
  }

  @override
  PlatformType get platformType => PlatformType.kugou;

  @override
  String get platformName => '酷狗音乐';

  @override
  bool get isLoggedIn => _currentUser != null;

  // --- Capabilities ---

  /// Kugou's official recommendation endpoints are refused server-side, but the
  /// mobile homepage module reliably provides a (non-personalised) list, and
  /// [getDailyRecommendation] reports that provenance instead of pretending it
  /// is a personalised daily playlist.
  @override
  bool get supportsDailyRecommendations => true;

  /// Kugou is **QR-code login only** since v1.4.1.
  ///
  /// The phone/SMS path was removed both here and in the login page: its
  /// request would carry the phone number (and the code) in cleartext, and
  /// `login.user.kugou.com` has no usable TLS
  /// (docs/kugou-cleartext-probe.md). [MusicPlatform.sendPhoneCode] and
  /// `loginByPhone` cannot be deleted from the interface (8 test doubles
  /// override them), so they stay as explicit refusals.
  @override
  bool get supportsPhoneLogin => false;

  @override
  bool get supportsArtistPage => true;

  @override
  bool get supportsAlbumPage => true;

  /// No live 新歌 endpoint: `/api/v3/newcd/list` answers `Access Deny !!!` and
  /// `/api/v3/album/newsongs` answers `Access Deny ! No Actions !`, and
  /// `rank/list` publishes no 新歌榜 (probed 2026-10-06). Reported honestly as
  /// unsupported instead of returning an empty list.
  @override
  bool get supportsNewSongs => false;

  // --- Auth ---

  @override
  Future<QrLoginResult> getQrCode() async {
    try {
      final res = await _api.getQrLoginKey();
      final data = res['data'];
      final key = (data?['qrcode'] ?? data?['key'] ?? data?['qrcode_id'] ?? '')
          .toString();
      final qrBytes = _decodeQrImage(data?['qrcode_img']?.toString());
      return QrLoginResult(key: key, qrUrl: _qrLoginUrl(key), qrBytes: qrBytes);
    } catch (e) {
      debugPrint('Kugou getQrCode error: $e');
      return const QrLoginResult(key: '');
    }
  }

  String _qrLoginUrl(String key) {
    final appid = _api.clientMode == KugouPlaybackClient.lite ? '3116' : '1005';
    return Uri.https('h5.kugou.com', '/apps/loginQRCode/html/index.html', {
      'appid': appid,
      'qrcode': key,
    }).toString();
  }

  List<int>? _decodeQrImage(String? value) {
    if (value == null || value.isEmpty) return null;
    final marker = value.indexOf('base64,');
    final payload = marker >= 0
        ? value.substring(marker + 'base64,'.length)
        : value;
    try {
      return base64Decode(payload);
    } catch (_) {
      return null;
    }
  }

  @override
  Stream<QrLoginStatus> pollQrStatus(String key) async* {
    const maxAttempts = 150; // 5 minutes
    for (var i = 0; i < maxAttempts; i++) {
      await Future.delayed(const Duration(seconds: 2));
      try {
        final res = await _api.checkQrLogin(key);
        final status =
            int.tryParse((res['data']?['status'] ?? -2).toString()) ?? -2;
        switch (status) {
          case 4:
            // Extract token and user info before reporting success.
            final loginData = res['data'];
            _syncApiSessionFields(loginData);
            final token = _extractToken(loginData);
            final userid = _extractUserId(loginData);
            if (token != null && token.isNotEmpty) {
              try {
                final userRes = await _api.getUserInfoFromToken();
                final userData = userRes['data'];
                if (userData is Map) {
                  _syncApiSessionFields(userData);
                  _currentUser = _userFromData(
                    userData,
                    fallbackUserId: userid,
                  );
                }
              } catch (e) {
                debugPrint('Kugou QR profile fetch error: $e');
              }
              _currentUser ??= _fallbackQrUser(res['data'], userid: userid);
              _syncApiUserIdFromCurrentUser();
            }
            if (_currentUser != null) {
              yield QrLoginStatus.success;
            } else {
              debugPrint(
                'Kugou QR login confirmed but no token/user id was returned',
              );
              yield QrLoginStatus.failed;
            }
            return;
          case 2:
            yield QrLoginStatus.scanned;
            break;
          case 0:
            yield QrLoginStatus.expired;
            return;
          case 1:
          default:
            yield QrLoginStatus.waiting;
        }
      } catch (_) {
        yield QrLoginStatus.failed;
        return;
      }
    }
    yield QrLoginStatus.failed;
  }

  User _userFromData(Map<dynamic, dynamic> data, {String? fallbackUserId}) {
    final id =
        (data['user_id'] ??
                data['userid'] ??
                data['uid'] ??
                data['id'] ??
                fallbackUserId ??
                '')
            .toString();
    final nickname =
        (data['nick_name'] ??
                data['nickname'] ??
                data['username'] ??
                data['user_name'] ??
                '酷狗用户')
            .toString();
    return User(
      id: id,
      nickname: nickname.isEmpty ? '酷狗用户' : nickname,
      platform: PlatformType.kugou,
    );
  }

  User? _fallbackQrUser(dynamic data, {String? userid}) {
    final userId =
        (userid ??
                (data is Map
                    ? data['userid'] ?? data['user_id'] ?? data['uid']
                    : null) ??
                '')
            .toString();
    if (userId.isEmpty) return null;
    return User(
      id: userId,
      nickname: data is Map
          ? (data['nickname'] ?? data['nick_name'] ?? '酷狗用户').toString()
          : '酷狗用户',
      platform: PlatformType.kugou,
    );
  }

  String? _stringField(dynamic source, Iterable<String> keys) {
    if (source is! Map) return null;
    for (final key in keys) {
      final value = source[key]?.toString().trim();
      if (value != null && value.isNotEmpty && value != 'null') {
        return value;
      }
    }
    return null;
  }

  String? _extractToken(dynamic data) {
    final direct = _stringField(data, const ['token', 'usertoken', 't']);
    if (direct != null) return direct;
    if (data is Map) {
      for (final key in const [
        'user_info',
        'userinfo',
        'userInfo',
        'profile',
        'data',
      ]) {
        final nested = _extractToken(data[key]);
        if (nested != null) return nested;
      }
    }
    return null;
  }

  String? _extractUserId(dynamic data) {
    final direct = _stringField(data, const ['userid', 'user_id', 'uid', 'id']);
    if (direct != null) return direct;
    if (data is Map) {
      for (final key in const [
        'user_info',
        'userinfo',
        'userInfo',
        'profile',
        'data',
      ]) {
        final nested = _extractUserId(data[key]);
        if (nested != null) return nested;
      }
    }
    return null;
  }

  String? _extractStringDeep(dynamic data, Iterable<String> keys) {
    final direct = _stringField(data, keys);
    if (direct != null) return direct;
    if (data is Map) {
      for (final key in const [
        'user_info',
        'userinfo',
        'userInfo',
        'profile',
        'data',
        'cookie',
      ]) {
        final nested = _extractStringDeep(data[key], keys);
        if (nested != null) return nested;
      }
    }
    return null;
  }

  void _syncApiSessionFields(dynamic data) {
    _api.setSessionFields(
      token: _extractToken(data),
      userid: _extractUserId(data),
      vipToken: _extractStringDeep(data, const [
        'vip_token',
        'vipToken',
        'viptoken',
      ]),
      vipType: _extractStringDeep(data, const [
        'vip_type',
        'vipType',
        'viptype',
        'vip',
      ]),
      dfid: _extractStringDeep(data, const ['dfid', 'DFID']),
      mid: _extractStringDeep(data, const ['mid', 'KUGOU_API_MID', 'kg_mid']),
      uuid: _extractStringDeep(data, const ['uuid', 'KUGOU_API_GUID', 'guid']),
    );
  }

  void _syncApiUserIdFromCurrentUser() {
    final id = _currentUser?.id.trim();
    if ((_api.userid == null || _api.userid!.isEmpty) &&
        id != null &&
        id.isNotEmpty) {
      _api.setUserId(id);
    }
  }

  bool _isSuccessResponse(Map<String, dynamic> res) {
    final status = res['status'];
    if (status == 1 || status == true) return true;
    for (final key in const ['code', 'errcode', 'error_code', 'errorCode']) {
      final value = int.tryParse(res[key]?.toString() ?? '');
      if (value == 0 || value == 200) return true;
    }
    return false;
  }

  /// Retired in v1.4.1: Kugou is QR-only. Returns a refusal **without issuing
  /// any network request** — the request used to put the phone number on the
  /// wire in cleartext to a host that cannot be reached over TLS.
  @override
  Future<LoginResult> sendPhoneCode(String phone) async {
    return const LoginResult(
      success: false,
      error: _phoneLoginRetiredMessage,
    );
  }

  /// Retired in v1.4.1 — see [sendPhoneCode]. No network request is made.
  @override
  Future<LoginResult> loginByPhone(String phone, String code) async {
    return const LoginResult(
      success: false,
      error: _phoneLoginRetiredMessage,
    );
  }

  static const String _phoneLoginRetiredMessage =
      '酷狗已不再支持手机号登录，请使用扫码登录';

  @override
  Future<User?> getUserInfo() async => _currentUser;

  @override
  Future<void> logout() async {
    _currentUser = null;
    // Clearing only `_currentUser` used to leave `token`/`userid`/`vipToken` in
    // the API client, where `_signedAndroidParams` kept injecting them into
    // every subsequent request until the process restarted.
    _api.clearSession();
  }

  @override
  Future<void> saveSession(SessionStorage storage) async {
    if (_currentUser != null) {
      await storage.saveUser(platformType, _currentUser!);
    }
    final token = _api.token;
    if (token != null && token.isNotEmpty) {
      await storage.saveCookie(
        platformType,
        jsonEncode({
          'token': token,
          if (_api.userid != null) 'userid': _api.userid,
          if (_api.vipToken != null) 'vip_token': _api.vipToken,
          if (_api.vipType != null) 'vip_type': _api.vipType,
          if (_api.dfid != null) 'dfid': _api.dfid,
          if (_api.mid != null) 'mid': _api.mid,
          if (_api.uuid != null) 'uuid': _api.uuid,
          'client': _api.clientModeName,
        }),
      );
    }
  }

  @override
  Future<void> restoreSession(SessionStorage storage) async {
    final cookie = await storage.loadCookie(platformType);
    if (cookie != null && cookie.isNotEmpty) {
      _restoreApiSessionCookie(cookie);
    }
    final user = await storage.loadUser(platformType);
    if (user != null) {
      _currentUser = user;
      _syncApiUserIdFromCurrentUser();
    }
  }

  void _restoreApiSessionCookie(String cookie) {
    if (cookie.trimLeft().startsWith('{')) {
      try {
        final data = jsonDecode(cookie) as Map<String, dynamic>;
        _api.setSessionFields(
          token: data['token']?.toString(),
          userid: data['userid']?.toString(),
          vipToken: data['vip_token']?.toString(),
          vipType: data['vip_type']?.toString(),
          dfid: data['dfid']?.toString(),
          mid: data['mid']?.toString(),
          uuid: data['uuid']?.toString(),
        );
        _api.setClientVariant(data['client']?.toString());
        return;
      } catch (_) {
        // Fall through to the old token|userid format.
      }
    }
    final parts = cookie.split('|');
    _api.restoreToken(parts.first);
    if (parts.length > 1) _api.setUserId(parts[1]);
  }

  // --- Search ---

  @override
  Future<List<Song>> search(
    String keyword, {
    int page = 1,
    int limit = 30,
  }) async {
    final res = await _api.search(keyword, page: page, limit: limit);
    final data = res['data']?['info'] as List<dynamic>?;
    if (data == null) return [];

    return data.map((s) => _parseSong(s)).toList();
  }

  @override
  Future<List<Playlist>> searchPlaylists(
    String keyword, {
    int page = 1,
    int limit = 30,
  }) async {
    try {
      final res = await _api.searchPlaylists(keyword, page: page, limit: limit);
      final list =
          res['data']?['lists'] as List<dynamic>? ??
          res['data']?['info'] as List<dynamic>? ??
          res['data']?['list'] as List<dynamic>? ??
          const [];
      return list.map((p) => _parsePlaylist(p, editable: false)).toList();
    } catch (e) {
      debugPrint('Kugou searchPlaylists error: $e');
      return [];
    }
  }

  Song _parseSong(dynamic s) {
    var songName = (s['songname'] ?? s['song_name'] ?? s['name'] ?? '')
        .toString()
        .replaceAll(RegExp(r'<[^>]*>'), '');
    var singerName = (s['singername'] ?? s['singer_name'] ?? '')
        .toString()
        .replaceAll(RegExp(r'<[^>]*>'), '');
    final singerInfo = s['singerinfo'];
    if (singerName.isEmpty && singerInfo is List && singerInfo.isNotEmpty) {
      final first = singerInfo.first;
      if (first is Map) {
        singerName = (first['name'] ?? first['singername'] ?? '').toString();
      }
    }
    final filename = (s['filename'] ?? s['name'] ?? '').toString();
    if ((songName.isEmpty || singerName.isEmpty) && filename.contains(' - ')) {
      final parts = filename.split(' - ');
      if (singerName.isEmpty) singerName = parts.first.trim();
      if (songName.isEmpty) songName = parts.sublist(1).join(' - ').trim();
    }
    if (songName.contains(' - ') &&
        (singerName.isEmpty || songName.startsWith('$singerName - '))) {
      final parts = songName.split(' - ');
      if (singerName.isEmpty) singerName = parts.first.trim();
      songName = parts.sublist(1).join(' - ').trim();
    }

    // Cover URL: search API stores it in trans_param.union_cover with {size} placeholder
    String? coverUrl;
    final transParam = s['trans_param'];
    if (transParam is Map) {
      final unionCover = transParam['union_cover']?.toString();
      if (unionCover != null && unionCover.isNotEmpty) {
        coverUrl = unionCover.replaceFirst('{size}', '480');
      }
    }
    coverUrl ??= s['album_img'] ?? s['image'] ?? s['cover'];
    coverUrl ??= s['album_sizable_cover'];
    coverUrl = _normalizeSizeTemplate(coverUrl);
    final durationSeconds =
        int.tryParse((s['duration'] ?? s['timeLength'] ?? 0).toString()) ?? 0;
    final timelenMs = int.tryParse((s['timelen'] ?? 0).toString()) ?? 0;

    return Song(
      id: s['hash'] ?? '',
      platform: PlatformType.kugou,
      name: songName,
      artists: _artistsFromSong(s, fallbackName: singerName),
      album: s['album_name'] != null
          ? Album(id: s['album_id']?.toString() ?? '', name: s['album_name'])
          : null,
      duration: timelenMs > 0
          ? Duration(milliseconds: timelenMs)
          : Duration(seconds: durationSeconds),
      coverUrl: coverUrl,
    );
  }

  /// `rank/song`, `album/song` and the homepage payload list performers as
  /// `authors: [{author_id, author_name}]` instead of `singername`, so a cover
  /// or chart row used to lose every artist but the first one from `filename`.
  List<Artist> _artistsFromSong(dynamic s, {required String fallbackName}) {
    final authors = s is Map ? s['authors'] : null;
    if (authors is List) {
      final artists = <Artist>[];
      for (final author in authors) {
        if (author is! Map) continue;
        final name = (author['author_name'] ?? author['name'] ?? '')
            .toString()
            .trim();
        if (name.isEmpty) continue;
        artists.add(
          Artist(id: (author['author_id'] ?? '').toString(), name: name),
        );
      }
      if (artists.isNotEmpty) return artists;
    }
    return [Artist(id: s['singerid']?.toString() ?? '', name: fallbackName)];
  }

  // --- Playback ---

  @override
  Future<String> getSongUrl(
    String songId, {
    AudioLevel quality = AudioLevel.low,
  }) async {
    final res = await _api.getSongInfo(songId);
    final playUrl = _extractPlayableUrl(res);
    if (quality == AudioLevel.low && playUrl != null && playUrl.isNotEmpty) {
      return playUrl;
    }

    final hash = _playbackHashForQuality(res, songId, quality);
    final albumId = _songInfoString(res, const [
      'albumid',
      'album_id',
      'req_albumid',
    ]);
    final albumAudioId = _songInfoString(res, const [
      'album_audio_id',
      'audio_id',
      'mixsongid',
      'MixSongID',
    ]);
    final failures = <String>[];

    Future<String?> tryRoute(
      String name,
      Future<Map<String, dynamic>> Function() request,
    ) async {
      try {
        final response = await request();
        final url = _extractPlayableUrl(response);
        if (url != null && url.isNotEmpty) return url;
        failures.add('$name:no_url');
        return null;
      } catch (error) {
        failures.add('$name:${error.runtimeType}');
        return null;
      }
    }

    if (_api.hasVipPlaybackSession) {
      final privateUrl = await tryRoute(
        'private',
        () => _api.getSongPrivatePlaybackUrl(
          hash,
          albumAudioId: albumAudioId,
          quality: quality,
        ),
      );
      if (privateUrl != null) return privateUrl;
    }

    final ordinaryUrl = await tryRoute(
      'android_v5',
      () => _api.getSongPlaybackUrl(
        hash,
        albumId: albumId,
        albumAudioId: albumAudioId,
        quality: quality,
        client: KugouPlaybackClient.android,
      ),
    );
    if (ordinaryUrl != null) return ordinaryUrl;

    final liteUrl = await tryRoute(
      'lite_v5',
      () => _api.getSongPlaybackUrl(
        hash,
        albumId: albumId,
        albumAudioId: albumAudioId,
        quality: quality,
        client: KugouPlaybackClient.lite,
      ),
    );
    if (liteUrl != null) return liteUrl;

    // Last resort: the play info URL we already fetched from the *HTTPS*
    // `getSongInfo` endpoint. Reached when the higher-quality routes fail, so
    // playback degrades to whatever bitrate that URL carries instead of failing
    // outright — and unlike the retired cleartext path it cannot be rewritten
    // on-path. The downgrade is recorded, not hidden.
    if (playUrl != null && playUrl.isNotEmpty) {
      DiagnosticsService.instance.record(
        'kugou_playback',
        'quality_downgraded_to_songinfo',
        data: {
          'song_id_hash_prefix': songId.length >= 8
              ? songId.substring(0, 8)
              : songId,
          'requested_quality': quality.name,
          'kugou_client': _api.clientModeName,
          'failed_routes': failures.join(','),
        },
      );
      return playUrl;
    }

    DiagnosticsService.instance.record(
      'kugou_playback',
      'url_resolution_failed',
      data: {
        'song_id_hash_prefix': songId.length >= 8
            ? songId.substring(0, 8)
            : songId,
        'quality': quality.name,
        'kugou_client': _api.clientModeName,
        'has_token': _api.hasToken,
        'has_userid': _api.hasUserId,
        'has_vip_token': _api.hasVipToken,
        'has_vip_session': _api.hasVipPlaybackSession,
        'routes': failures.join(','),
      },
    );
    throw SongNotAvailableException(platform: platformName);
  }

  String? _songInfoString(Map<String, dynamic> res, Iterable<String> keys) {
    return _stringField(res, keys) ??
        _stringField(res['data'], keys) ??
        _stringField(res['info'], keys) ??
        _stringField(res['audio_info'], keys) ??
        _stringField(res['audioInfo'], keys);
  }

  String _playbackHashForQuality(
    Map<String, dynamic> res,
    String songId,
    AudioLevel quality,
  ) {
    final extra = res['extra'];
    final transParam = res['trans_param'];
    final keys = switch (quality) {
      AudioLevel.low => const ['128hash', 'hash'],
      AudioLevel.medium ||
      AudioLevel.high => const ['320hash', 'highhash', '128hash', 'hash'],
      AudioLevel.lossless => const ['sqhash', '320hash', '128hash', 'hash'],
      AudioLevel.hires ||
      AudioLevel.spatial ||
      AudioLevel.dolby ||
      AudioLevel.master => const [
        'highhash',
        'sqhash',
        '320hash',
        '128hash',
        'hash',
      ],
    };
    for (final key in keys) {
      final value =
          _stringField(extra, [key]) ??
          _stringField(res, [key]) ??
          _stringField(transParam, [key]);
      if (value != null) return value;
    }
    return songId;
  }

  String? _extractPlayableUrl(dynamic source, [int depth = 0]) {
    if (depth > 4 || source == null) return null;
    if (source is String) return _normalizePlayableUrl(source);
    if (source is Iterable) {
      for (final item in source) {
        final url = _extractPlayableUrl(item, depth + 1);
        if (url != null) return url;
      }
      return null;
    }
    if (source is! Map) return null;

    for (final key in const [
      'url',
      'play_url',
      'playUrl',
      'playurl',
      'audio_url',
      'audioUrl',
      'download_url',
      'downloadUrl',
      'backup_url',
      'backupUrl',
      'backup_urls',
      'backupUrls',
      'play_backup_url',
      'playBackupUrl',
      'play_backup_urls',
      'playBackupUrls',
    ]) {
      final url = _extractPlayableUrl(source[key], depth + 1);
      if (url != null) return url;
    }

    for (final key in const [
      'data',
      'info',
      'song_info',
      'songInfo',
      'audio_info',
      'audioInfo',
      'file',
    ]) {
      final url = _extractPlayableUrl(source[key], depth + 1);
      if (url != null) return url;
    }

    return null;
  }

  String? _normalizePlayableUrl(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed == 'null') return null;
    if (trimmed.startsWith('//')) return 'https:$trimmed';
    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme) return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    return trimmed;
  }

  @override
  Future<List<AudioQuality>> getAvailableQualities(String songId) async {
    return [
      const AudioQuality(level: AudioLevel.low, bitrate: 128000, format: 'mp3'),
      const AudioQuality(
        level: AudioLevel.medium,
        bitrate: 320000,
        format: 'mp3',
      ),
      const AudioQuality(
        level: AudioLevel.lossless,
        bitrate: 999000,
        format: 'flac',
      ),
      const AudioQuality(
        level: AudioLevel.hires,
        bitrate: 2400000,
        format: 'flac',
      ),
      const AudioQuality(
        level: AudioLevel.spatial,
        bitrate: 999000,
        format: 'flac',
      ),
    ];
  }

  // --- Lyrics ---

  @override
  Future<String?> getLyrics(String songId) async {
    // songId is the Kugou hash
    try {
      debugPrint('Kugou getLyrics: songId=$songId');

      // Primary: hash-based search (most reliable, no singer/song name needed)
      var candidates = await _api.searchLyricsByHash(songId);
      debugPrint(
        'Kugou getLyrics: hash-based search returned ${candidates.length} candidates',
      );

      // Fallback: keyword-based search
      if (candidates.isEmpty) {
        final songInfo = await _api.getSongInfo(songId);
        debugPrint('Kugou getLyrics: songInfo keys=${songInfo.keys.toList()}');
        final singer =
            songInfo['singerName'] ??
            songInfo['author_name'] ??
            songInfo['choricSinger'] ??
            '';
        final songName = songInfo['songName'] ?? '';
        var duration = songInfo['timeLength'] ?? 0;
        if (duration == 0) {
          final climax = songInfo['climax_info'];
          if (climax is Map) {
            duration = climax['timelength'] ?? 0;
          }
        }
        debugPrint(
          'Kugou getLyrics: fallback keyword search, singer="$singer", songName="$songName"',
        );
        if (singer.isNotEmpty && songName.isNotEmpty) {
          candidates = await _api.searchLyrics(
            '$singer-$songName',
            duration: duration,
          );
          debugPrint(
            'Kugou getLyrics: singer-song search returned ${candidates.length} candidates',
          );
        }
        if (candidates.isEmpty && songName.isNotEmpty) {
          candidates = await _api.searchLyrics(songName, duration: duration);
          debugPrint(
            'Kugou getLyrics: song-only search returned ${candidates.length} candidates',
          );
        }
        if (candidates.isEmpty && songName.isNotEmpty && duration > 1000) {
          candidates = await _api.searchLyrics(
            songName,
            duration: duration ~/ 1000,
          );
          debugPrint(
            'Kugou getLyrics: song-only seconds-duration search returned ${candidates.length} candidates',
          );
        }
      }

      if (candidates.isEmpty) return null;

      final first = candidates.first;
      final id = first['id']?.toString();
      final accesskey = first['accesskey']?.toString();
      debugPrint('Kugou getLyrics: downloading KRC id=$id');
      if (id == null || accesskey == null) return null;

      debugPrint('Kugou getLyrics: candidate keys=${first.keys.toList()}');
      final result = await _api.downloadKrc(id, accesskey);
      debugPrint(
        'Kugou getLyrics: KRC result length=${result?.length ?? 'null'}',
      );
      return result;
    } catch (e) {
      debugPrint('Kugou getLyrics error: $e');
      return null;
    }
  }

  /// Get lyrics by keyword and duration (for better matching)
  Future<String?> getLyricsByInfo(String keyword, int duration) async {
    try {
      final candidates = await _api.searchLyrics(keyword, duration: duration);
      if (candidates.isEmpty) return null;

      final first = candidates.first;
      final id = first['id']?.toString();
      final accesskey = first['accesskey']?.toString();
      if (id == null || accesskey == null) return null;

      return await _api.downloadKrc(id, accesskey);
    } catch (e) {
      debugPrint('Kugou getLyricsByInfo error: $e');
      return null;
    }
  }

  // --- Library ---

  @override
  Future<List<Playlist>> getUserPlaylists() async {
    try {
      final res = await _api.getUserPlaylists();
      final data = res['data'];
      final list = <dynamic>[];
      _collectPlaylistItems(data, list);
      _collectPlaylistItems(res, list);
      final seen = <String>{};
      final playlists = <Playlist>[];
      for (final item in list) {
        final playlist = _parsePlaylist(item, editable: true);
        final key = playlist.id.isNotEmpty ? playlist.id : playlist.editableId;
        if (key.isEmpty || !seen.add(key)) continue;
        playlists.add(playlist);
      }
      return playlists;
    } catch (e) {
      debugPrint('Kugou getUserPlaylists error: $e');
      return [];
    }
  }

  @override
  Future<List<Song>> getPlaylistDetail(String playlistId) async {
    try {
      final list = playlistId.startsWith('collection_')
          ? await _loadPagedSongs(
              (page, limit) => _api.getSharedPlaylistSongs(
                playlistId,
                page: page,
                limit: limit,
              ),
            )
          : await _loadPagedSongs(
              (page, limit) =>
                  _api.getPlaylistSongs(playlistId, page: page, limit: limit),
            );
      var resolvedList = list;
      if (resolvedList.isEmpty && !playlistId.startsWith('collection_')) {
        resolvedList = await _loadPagedSongs(
          (page, limit) =>
              _api.getUserPlaylistSongs(playlistId, page: page, limit: limit),
        );
      }
      if (resolvedList.isEmpty && playlistId.startsWith('collection_')) {
        final listId = _extractListIdFromCollectionId(playlistId);
        if (listId != null) {
          resolvedList = await _loadPagedSongs(
            (page, limit) =>
                _api.getUserPlaylistSongs(listId, page: page, limit: limit),
          );
        }
      }
      return resolvedList.map((s) => _parseSong(s)).toList();
    } catch (e) {
      debugPrint('Kugou getPlaylistDetail error: $e');
      return [];
    }
  }

  @override
  Future<List<Song>> getLikedSongs() async {
    try {
      final res = await _api.getLikedSongs();
      final list = res['data']?['info'] as List<dynamic>?;
      if (list == null) return [];
      return list.map((s) => _parseSong(s)).toList();
    } catch (e) {
      debugPrint('Kugou getLikedSongs error: $e');
      return [];
    }
  }

  @override
  Future<bool> likeSong(String songId, {bool like = true}) async {
    try {
      if (like) {
        await _api.collectSong(songId);
      } else {
        await _api.uncollectSong(songId);
      }
      return true;
    } catch (e) {
      debugPrint('Kugou likeSong error: $e');
      return false;
    }
  }

  @override
  Future<bool> addSongToPlaylist(String playlistId, Song song) async {
    return false;
  }

  @override
  Future<Playlist?> createPlaylist(String name) async {
    try {
      final res = await _api.createPlaylist(name);
      if (_isSuccessResponse(res)) {
        final refreshed = await _findCreatedPlaylistByName(name);
        if (refreshed != null) return refreshed;
        final data = res['data'];
        final id =
            (data?['global_collection_id'] ?? data?['global_specialid'] ?? '')
                .toString();
        final editId = (data?['listid'] ?? data?['id'])?.toString();
        if (id.isEmpty) return null;
        return Playlist(
          id: id,
          name: name,
          platform: PlatformType.kugou,
          editable: true,
          editId: editId != null && editId != id ? editId : null,
        );
      }
      return null;
    } catch (e) {
      debugPrint('Kugou createPlaylist error: $e');
      return null;
    }
  }

  Future<Playlist?> _findCreatedPlaylistByName(String name) async {
    final playlists = await getUserPlaylists();
    for (final playlist in playlists) {
      if (playlist.id.isNotEmpty && playlist.name.trim() == name.trim()) {
        return playlist;
      }
    }
    return null;
  }

  @override
  Future<bool> collectPlaylist(String playlistId, {bool collect = true}) async {
    try {
      final res = await _api.collectPlaylist(playlistId, collect: collect);
      return _isSuccessResponse(res);
    } catch (e) {
      debugPrint('Kugou collectPlaylist error: $e');
      return false;
    }
  }

  // --- Recommendations ---

  /// How many songs the homepage fallback returns at most.
  static const int _homepageRecommendationLimit = 30;

  @override
  Future<RecommendationResult> getDailyRecommendation() async {
    final official = await _fetchOfficialRecommendations();
    if (official != null && official.isNotEmpty) {
      return RecommendationResult(
        songs: official,
        source: RecommendationSource(
          platform: platformType,
          kind: RecommendationKind.personalizedDaily,
          label: '每日推荐',
        ),
      );
    }

    final source = RecommendationSource(
      platform: platformType,
      kind: RecommendationKind.fallbackHomepage,
      label: '酷狗推荐',
      note: '官方推荐接口已不可用，来源为首页推荐',
    );
    try {
      final songs = await fetchHomepageRecommendations();
      if (songs.isEmpty) {
        // The homepage answered but carried no songs: surface it instead of
        // pretending the platform has nothing to recommend.
        return RecommendationResult(
          songs: const [],
          source: RecommendationSource(
            platform: platformType,
            kind: RecommendationKind.unavailable,
            label: '不可用',
            note: '首页推荐为空',
          ),
          error: '酷狗推荐暂不可用',
        );
      }
      return RecommendationResult(songs: songs, source: source);
    } catch (e) {
      // Never `catch (_) { return []; }`: the caller has to be able to tell
      // "the homepage module failed" from "Kugou has no recommendations".
      final error = apiExceptionOf(e);
      DiagnosticsService.instance.record(
        'kugou_recommend',
        'homepage_fallback_failed',
        data: {'error': error.message},
      );
      return RecommendationResult(
        songs: const [],
        source: RecommendationSource(
          platform: platformType,
          kind: RecommendationKind.unavailable,
          label: '不可用',
          note: error.message,
        ),
        error: error.message,
      );
    }
  }

  /// The official endpoint is refused by the server, so this returns `null`
  /// (and records why) rather than throwing: the caller falls back to the
  /// homepage. Kept as a real attempt so the fallback stays exercised.
  Future<List<Song>?> _fetchOfficialRecommendations() async {
    try {
      final res = await _api.getRecommend();
      final list = res['data']?['info'] as List<dynamic>?;
      if (list == null || list.isEmpty) {
        DiagnosticsService.instance.record(
          'kugou_recommend',
          'official_endpoint_empty',
          data: {'status': res['status']?.toString() ?? 'unknown'},
        );
        return null;
      }
      return list.map((s) => _parseSong(s)).toList();
    } catch (e) {
      final error = apiExceptionOf(e);
      DiagnosticsService.instance.record(
        'kugou_recommend',
        'official_endpoint_refused',
        data: {'error': error.message},
      );
      return null;
    }
  }

  @override
  Future<List<Song>> getDailyRecommendations() async {
    final result = await getDailyRecommendation();
    return result.songs;
  }

  /// Songs from the mobile homepage module: `data` (10 songs) plus the songs
  /// embedded in `special.list.info[]`, de-duplicated by hash.
  @visibleForTesting
  Future<List<Song>> fetchHomepageRecommendations() async {
    final res = await _api.getHomepage();
    final songs = <Song>[];
    final seen = <String>{};

    void add(dynamic raw) {
      if (raw is! Map) return;
      final song = _parseSong(raw);
      final key = song.id.isNotEmpty
          ? song.id
          : '${song.name}|${song.artists.isEmpty ? '' : song.artists.first.name}';
      if (key.isEmpty || !seen.add(key)) return;
      songs.add(song);
    }

    final data = res['data'];
    if (data is List) {
      for (final item in data) {
        add(item);
      }
    }
    final special = res['special'];
    if (special is Map) {
      final specialList = special['list'];
      if (specialList is Map) {
        final info = specialList['info'];
        if (info is List) {
          for (final item in info) {
            if (item is! Map) continue;
            final nested = item['songs'];
            if (nested is List) {
              for (final song in nested) {
                add(song);
              }
            }
          }
        }
      }
    }
    return songs.length > _homepageRecommendationLimit
        ? songs.sublist(0, _homepageRecommendationLimit)
        : songs;
  }

  @override
  Future<List<Song>> getRankingList() async {
    try {
      final res = await _api.getRankList();
      final list = res['data']?['info'] as List<dynamic>?;
      if (list == null) return [];
      return list.map((s) => _parseSong(s)).toList();
    } catch (e) {
      debugPrint('Kugou getRankingList error: $e');
      return [];
    }
  }

  // --- Charts (榜单中心) ---

  @override
  Future<List<Toplist>> getToplists() async {
    final res = await _api.getToplists();
    final list = res['data']?['info'] as List<dynamic>?;
    if (list == null) return const [];
    return list
        .whereType<Map>()
        .map((item) {
          final id = item['rankid']?.toString() ?? '';
          if (id.isEmpty) return null;
          return Toplist(
            id: id,
            name: (item['rankname'] ?? '酷狗榜单').toString(),
            coverUrl: _normalizeSizeTemplate(item['imgurl']?.toString()),
            updateFrequency: _nonEmpty(item['update_frequency']),
            songCount: _firstInt(item, const ['songcount']) ??
                _rankTotalFromExtra(item['extra']),
            period: _nonEmpty(item['rank_id_publish_date']),
            intro: _nonEmpty(item['intro']),
          );
        })
        .whereType<Toplist>()
        .toList();
  }

  /// `rank/list` hides the track count inside `extra.resp.all_total`
  /// (TOP500 reports 500).
  int? _rankTotalFromExtra(dynamic extra) {
    if (extra is! Map) return null;
    final resp = extra['resp'];
    if (resp is! Map) return null;
    return _firstInt(resp, const ['all_total', 'total']);
  }

  @override
  Future<List<RankedSong>> getRankedSongs(
    String toplistId, {
    int offset = 0,
    int num = 100,
    String? period,
  }) async {
    final rankId = int.tryParse(toplistId);
    if (rankId == null) {
      throw ApiException(message: '无效的酷狗榜单 id: $toplistId');
    }
    final pageSize = num <= 0 ? 100 : num;
    // `rank/song` is 1-based paged; translate the offset into pages.
    final firstPage = (offset < 0 ? 0 : offset) ~/ pageSize + 1;
    final songs = <RankedSong>[];
    for (var page = firstPage; page <= 100; page++) {
      final res = await _api.getRankList(
        rankId: rankId,
        page: page,
        pagesize: pageSize,
      );
      final list = res['data']?['info'] as List<dynamic>?;
      if (list == null || list.isEmpty) break;
      for (var i = 0; i < list.length; i++) {
        final raw = list[i];
        if (raw is! Map) continue;
        // `sort` is the real chart position when present; otherwise derive it
        // from the page/offset arithmetic.
        final absolute = offset + i;
        final rank = _firstInt(raw, const ['sort']) ??
            (absolute < 0 ? i + 1 : absolute + 1);
        songs.add(
          RankedSong(
            song: _parseSong(raw),
            rank: rank,
            rankChange: _rankChange(raw),
            isNew: _firstInt(raw, const ['isfirst']) == 1 ? true : null,
            rankValue: _nonEmpty(raw['rank_count']?.toString()),
          ),
        );
      }
      if (list.length < pageSize) break;
      if (songs.length >= num) break;
    }
    return songs.length > num && num > 0 ? songs.sublist(0, num) : songs;
  }

  /// Kugou reports `rank_count` (previous position) next to `sort` (current).
  /// Positive means the song moved **up**, matching [RankedSong.rankChange].
  int? _rankChange(Map raw) {
    final current = _firstInt(raw, const ['sort']);
    final previous = _firstInt(raw, const ['rank_count']);
    if (current == null || previous == null) return null;
    if (previous <= 0) return null;
    return previous - current;
  }

  // --- Artist / album pages ---

  @override
  Future<Artist?> getArtistDetail(String artistId) async {
    final res = await _api.getArtistInfo(artistId);
    final data = res['data'];
    if (data is! Map) return null;
    final name = (data['singername'] ?? '').toString();
    if (name.isEmpty) return null;
    return Artist(
      id: (data['singerid'] ?? artistId).toString(),
      name: name,
      avatarUrl: _normalizeSizeTemplate(
        (data['avatar'] ?? data['imgurl'])?.toString(),
      ),
      briefDesc: _nonEmpty(data['profile'] ?? data['intro']),
      songCount: _firstInt(data, const ['songcount']),
      albumCount: _firstInt(data, const ['albumcount']),
      fansCount: _firstInt(data, const ['fansnums', 'fanscount']),
    );
  }

  @override
  Future<List<Song>> getArtistTopSongs(
    String artistId, {
    int limit = 50,
  }) async {
    final pageSize = limit <= 0 ? 50 : limit;
    final res = await _api.getArtistSongs(artistId, pagesize: pageSize);
    final list = res['data']?['info'] as List<dynamic>?;
    if (list == null) return const [];
    final songs = list.map((s) => _parseSong(s)).toList();
    return songs.length > limit && limit > 0 ? songs.sublist(0, limit) : songs;
  }

  @override
  Future<List<Album>> getArtistAlbums(
    String artistId, {
    int page = 1,
    int limit = 30,
  }) async {
    final pageSize = limit <= 0 ? 30 : limit;
    final res = await _api.getArtistAlbums(
      artistId,
      page: page,
      pagesize: pageSize,
    );
    final list = res['data']?['info'] as List<dynamic>?;
    if (list == null) return const [];
    return list.whereType<Map>().map(_albumFromMap).toList();
  }

  @override
  Future<Album?> getAlbumDetail(String albumId) async {
    final res = await _api.getAlbumInfo(albumId);
    final data = res['data'];
    if (data is! Map) return null;
    final name = (data['albumname'] ?? '').toString();
    if (name.isEmpty) return null;
    return _albumFromMap(data);
  }

  @override
  Future<List<Song>> getAlbumSongs(String albumId) async {
    final res = await _api.getAlbumSongs(albumId);
    final list = res['data']?['info'] as List<dynamic>?;
    if (list == null) return const [];
    return list.map((s) => _parseSong(s)).toList();
  }

  Album _albumFromMap(Map raw) {
    return Album(
      id: (raw['albumid'] ?? '').toString(),
      name: (raw['albumname'] ?? '未知专辑').toString(),
      artistName: _nonEmpty(raw['singername']),
      artistId: _nonEmpty(raw['singerid']?.toString()),
      coverUrl: _normalizeSizeTemplate(
        (raw['imgurl'] ?? raw['album_sizable_cover'])?.toString(),
      ),
      releaseDate: _parseKugouDate(raw['publishtime']),
      description: _nonEmpty(raw['intro']),
      songCount: _firstInt(raw, const ['songcount']),
    );
  }

  DateTime? _parseKugouDate(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    if (text.isEmpty) return null;
    return DateTime.tryParse(text.replaceFirst(' ', 'T'));
  }

  String? _nonEmpty(dynamic value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty || text == 'null') return null;
    return text;
  }

  /// Kugou image URLs embed a `{size}` placeholder; a literal `{size}` must not
  /// reach the image loader verbatim.
  String? _normalizeSizeTemplate(String? url) {
    if (url == null || url.isEmpty) return null;
    return url.replaceAll('{size}', '480');
  }

  @override
  Future<List<Song>> getNewSongs({
    int limit = 100,
    NewSongRegion region = NewSongRegion.all,
  }) async {
    // Honest degradation: every candidate endpoint is refused or absent, and
    // `rank/list` publishes no 新歌榜. Returning `[]` would be indistinguishable
    // from "no new songs today".
    throw UnsupportedActionException(
      '酷狗音乐',
      details: '新歌接口（newcd/list、album/newsongs）已被服务端拒绝访问',
    );
  }

  // --- VIP ---

  @override
  Future<VipLevel> getVipStatus() async {
    final localLevel = _vipLevelFromSession();
    if (localLevel != VipLevel.free) return localLevel;

    try {
      final res = await _api.getVipInfo();
      final data = res['data'];
      if (data == null) return VipLevel.free;
      return _vipLevelFromData(data);
    } catch (e) {
      debugPrint('Kugou getVipStatus error: $e');
      return VipLevel.free;
    }
  }

  VipLevel _vipLevelFromSession() {
    final vipType = int.tryParse(_api.vipType ?? '');
    if (vipType != null) {
      if (vipType >= 2) return VipLevel.svip;
      if (vipType >= 1) return VipLevel.vip;
    }
    if (_api.hasVipPlaybackSession) return VipLevel.svip;
    return VipLevel.free;
  }

  VipLevel _vipLevelFromData(dynamic data) {
    if (data is! Map) return VipLevel.free;
    final vipType = _firstInt(data, const [
      'vip_type',
      'vipType',
      'viptype',
      'is_vip',
      'isVip',
      'vip',
    ]);
    if (vipType == null) return VipLevel.free;
    if (vipType >= 2) return VipLevel.svip;
    if (vipType >= 1) return VipLevel.vip;
    return VipLevel.free;
  }

  int? _firstInt(Map data, Iterable<String> keys) {
    for (final key in keys) {
      final value = data[key];
      if (value is num) return value.toInt();
      final parsed = int.tryParse(value?.toString() ?? '');
      if (parsed != null) return parsed;
    }
    return null;
  }

  // --- Playlist Import ---

  @override
  Future<Playlist?> parseShareLink(String url) async {
    final resolvedUrl = await _resolveShareUrlIfNeeded(url);
    final id = _extractSharePlaylistId(resolvedUrl ?? url);
    if (id == null) return null;
    try {
      final detail = id.startsWith('collection_')
          ? await _api.getSharedPlaylistSongs(id, limit: 1)
          : await _api.getPlaylistDetail(id);
      final rawData = detail['data'];
      if (rawData == null) return null;
      final dataMap = rawData is Map ? rawData : const {};
      final Map<String, dynamic> data = {
        'specialname':
            dataMap['specialname'] ?? dataMap['name'] ?? dataMap['listname'],
        'songcount':
            dataMap['songcount'] ?? dataMap['count'] ?? dataMap['total'],
        'imgurl': dataMap['imgurl'] ?? dataMap['cover'] ?? dataMap['image'],
      };
      return Playlist(
        id: id,
        name: data['specialname'] ?? '酷狗歌单',
        platform: PlatformType.kugou,
        songCount: data['songcount'] ?? 0,
        coverUrl: data['imgurl'],
      );
    } catch (e) {
      debugPrint('Kugou parseShareLink error: $e');
      return Playlist(
        id: id,
        name: '酷狗歌单',
        platform: PlatformType.kugou,
        songCount: 0,
      );
    }
  }

  Future<String?> _resolveShareUrlIfNeeded(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return url;
    if (uri.host == 't1.kugou.com' || uri.host == 't.kugou.com') {
      try {
        return await _api.resolveShareUrl(url);
      } catch (e) {
        debugPrint('Kugou resolveShareUrl error: $e');
        return url;
      }
    }
    return url;
  }

  String? _extractSharePlaylistId(String url) {
    final uri = Uri.tryParse(url);
    if (uri != null && uri.host.contains('kugou.com')) {
      final globalId =
          uri.queryParameters['global_specialid'] ??
          uri.queryParameters['global_collection_id'];
      if (globalId != null && globalId.isNotEmpty && globalId != '-') {
        return globalId;
      }
      final specialId = uri.queryParameters['specialid'];
      if (specialId != null &&
          specialId.isNotEmpty &&
          specialId != '-' &&
          specialId != '-2147483648') {
        return specialId;
      }
      final segments = uri.pathSegments;
      final songlistIndex = segments.indexOf('songlist');
      if (songlistIndex >= 0 && songlistIndex + 1 < segments.length) {
        return segments[songlistIndex + 1];
      }
      final playlistIndex = segments.indexOf('playlist');
      if (playlistIndex >= 0 && playlistIndex + 1 < segments.length) {
        return segments[playlistIndex + 1];
      }
    }

    final match = RegExp(
      r'kugou\.com/songlist/([^/?#]+)|kugou\.com/.*(?:global_specialid|global_collection_id)=([^&#]+)|kugou\.com/.*specialid=([^&#]+)|kugou\.com/.*playlist/([^/?#]+)',
    ).firstMatch(url);
    final id =
        match?.group(1) ??
        match?.group(2) ??
        match?.group(3) ??
        match?.group(4);
    if (id == null || id == '-' || id == '-2147483648') return null;
    return id;
  }

  Playlist _parsePlaylist(dynamic p, {required bool editable}) {
    final cover = (p['imgurl'] ?? p['image'] ?? p['pic'] ?? p['cover'])
        ?.toString();
    final detailId =
        (p['global_collection_id'] ??
                p['global_specialid'] ??
                p['specialid'] ??
                p['listid'] ??
                p['id'] ??
                '')
            .toString();
    final editId = (p['listid'] ?? p['list_create_listid'])?.toString();
    return Playlist(
      id: detailId,
      name:
          (p['specialname'] ??
                  p['name'] ??
                  p['playlistname'] ??
                  p['listname'] ??
                  '')
              .toString(),
      platform: PlatformType.kugou,
      songCount:
          int.tryParse(
            (p['songcount'] ??
                    p['song_count'] ??
                    p['total'] ??
                    p['count'] ??
                    p['song_num'] ??
                    0)
                .toString(),
          ) ??
          0,
      coverUrl: cover?.replaceAll('{size}', '480'),
      creatorName: (p['nickname'] ?? p['username'])?.toString(),
      editable: editable,
      collected: !editable,
      editId: editId != null && editId != detailId ? editId : null,
    );
  }

  void _collectPlaylistItems(dynamic source, List<dynamic> output) {
    if (source is List<dynamic>) {
      output.addAll(source);
      return;
    }
    if (source is! Map) return;
    for (final key in const [
      'list_create_list',
      'list_collect_list',
      'list',
      'info',
      'lists',
      'data',
    ]) {
      _collectPlaylistItems(source[key], output);
    }
  }

  List<dynamic>? _extractSongList(Map<String, dynamic> res) {
    final data = res['data'];
    if (data is Map) {
      for (final key in const ['info', 'songs', 'list', 'data', 'lists']) {
        final value = data[key];
        if (value is List<dynamic>) return value;
      }
    }
    for (final key in const ['info', 'songs', 'list', 'data', 'lists']) {
      final value = res[key];
      if (value is List<dynamic>) return value;
    }
    return null;
  }

  Future<List<dynamic>> _loadPagedSongs(
    Future<Map<String, dynamic>> Function(int page, int limit) loader,
  ) async {
    const pageSize = 100;
    final all = <dynamic>[];
    int? total;
    for (var page = 1; page <= 100; page++) {
      final res = await loader(page, pageSize);
      total ??= _extractSongTotal(res);
      final list = _extractSongList(res) ?? const [];
      if (list.isEmpty) break;
      all.addAll(list);
      if (total != null && all.length >= total) break;
      if (list.length < pageSize) break;
    }
    return all;
  }

  int? _extractSongTotal(Map<String, dynamic> res) {
    int? readCount(dynamic source) {
      if (source is! Map) return null;
      for (final key in const [
        'count',
        'total',
        'songcount',
        'song_count',
        'song_num',
        'total_count',
      ]) {
        final value = int.tryParse(source[key]?.toString() ?? '');
        if (value != null && value > 0) return value;
      }
      return null;
    }

    return readCount(res['data']) ?? readCount(res);
  }

  String? _extractListIdFromCollectionId(String id) {
    final parts = id.split('_');
    if (parts.length < 4 || parts.first != 'collection') return null;
    final listId = parts[3].trim();
    if (listId.isEmpty || listId == '0') return null;
    return listId;
  }
}
