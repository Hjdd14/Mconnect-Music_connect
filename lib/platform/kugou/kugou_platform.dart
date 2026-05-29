import 'dart:convert';

import 'package:flutter/foundation.dart';
import '../../models/song.dart';
import '../../models/artist.dart';
import '../../models/album.dart';
import '../../models/user.dart';
import '../../models/playlist.dart';
import '../../models/audio_quality.dart';
import '../../models/platform_type.dart';
import '../base/music_platform.dart';
import '../../core/diagnostics/diagnostics_service.dart';
import '../../core/storage/session_storage.dart';
import 'kugou_api.dart';

class KugouPlatform implements MusicPlatform {
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

  @override
  Future<LoginResult> sendPhoneCode(String phone) async {
    if (_api.clientMode == KugouPlaybackClient.lite) {
      return const LoginResult(success: false, error: '酷狗概念版请使用二维码登录');
    }
    try {
      final res = await _api.sendMobileCode(phone);
      final status = res['status'];
      final error = res['error_msg'] ?? res['msg'] ?? res['message'];
      if (status == 1 ||
          status == true ||
          res['code'] == 0 ||
          res['errcode'] == 0) {
        return const LoginResult(success: true);
      }
      return LoginResult(success: false, error: error?.toString() ?? '验证码发送失败');
    } catch (e) {
      return LoginResult(success: false, error: e.toString());
    }
  }

  @override
  Future<LoginResult> loginByPhone(String phone, String code) async {
    if (_api.clientMode == KugouPlaybackClient.lite) {
      return const LoginResult(success: false, error: '酷狗概念版请使用二维码登录');
    }
    try {
      final res = await _api.login(phone, code);
      if (_isSuccessResponse(res)) {
        final data = res['data'];
        _syncApiSessionFields(data);
        _syncApiSessionFields(res);
        final userid = _extractUserId(data) ?? _extractUserId(res);
        _currentUser = data is Map
            ? _userFromData(data, fallbackUserId: userid)
            : User(
                id: userid ?? '',
                nickname: '閰风嫍鐢ㄦ埛',
                platform: PlatformType.kugou,
              );
        return LoginResult(success: true, user: _currentUser);
      }
      return LoginResult(success: false, error: res['error_msg'] ?? '登录失败');
    } catch (e) {
      return LoginResult(success: false, error: e.toString());
    }
  }

  @override
  Future<User?> getUserInfo() async => _currentUser;

  @override
  Future<void> logout() async => _currentUser = null;

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
    final durationSeconds =
        int.tryParse((s['duration'] ?? s['timeLength'] ?? 0).toString()) ?? 0;
    final timelenMs = int.tryParse((s['timelen'] ?? 0).toString()) ?? 0;

    return Song(
      id: s['hash'] ?? '',
      platform: PlatformType.kugou,
      name: songName,
      artists: [Artist(id: s['singerid']?.toString() ?? '', name: singerName)],
      album: s['album_name'] != null
          ? Album(id: s['album_id']?.toString() ?? '', name: s['album_name'])
          : null,
      duration: timelenMs > 0
          ? Duration(milliseconds: timelenMs)
          : Duration(seconds: durationSeconds),
      coverUrl: coverUrl,
    );
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
    throw Exception('无法获取酷狗播放地址');
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

  @override
  Future<List<Song>> getDailyRecommendations() async {
    try {
      final res = await _api.getRecommend();
      final data = res['data']?['info'] as List<dynamic>?;
      if (data == null) return [];
      return data.map((s) => _parseSong(s)).toList();
    } catch (_) {
      return [];
    }
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
