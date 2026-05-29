import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../models/song.dart';
import '../../models/artist.dart';
import '../../models/album.dart';
import '../../models/user.dart';
import '../../models/playlist.dart';
import '../../models/audio_quality.dart';
import '../../models/platform_type.dart';
import '../base/music_platform.dart';
import '../../core/storage/session_storage.dart';
import 'qq_api.dart';

class QqPlatform implements MusicPlatform {
  final QqApi _api;
  User? _currentUser;

  QqPlatform({QqApi? api}) : _api = api ?? QqApi();

  QqApi get api => _api;

  @override
  PlatformType get platformType => PlatformType.qq;

  @override
  String get platformName => 'QQ音乐';

  @override
  bool get isLoggedIn => _currentUser != null;

  // --- Auth ---

  @override
  Future<QrLoginResult> getQrCode() async {
    final qrBytes = await _api.getQrImage();
    return QrLoginResult(
      key: DateTime.now().millisecondsSinceEpoch.toString(),
      qrBytes: qrBytes,
    );
  }

  @override
  Stream<QrLoginStatus> pollQrStatus(String key) async* {
    const maxAttempts = 150; // 5 minutes
    for (var i = 0; i < maxAttempts; i++) {
      await Future.delayed(const Duration(seconds: 2));
      try {
        final res = await _api.checkQr();
        final raw = res['raw']?.toString() ?? '';
        debugPrint(
          'QQ QR poll [$i]: ${raw.length > 120 ? raw.substring(0, 120) : raw}',
        );

        // Extract ptui_CB code from JS callback
        // Format: ptuiCB('code',0,'url',0,'msg',0)
        final codeMatch = RegExp(r"ptui[Cc]B\('(\d+)'").firstMatch(raw);
        final code = codeMatch?.group(1);

        if (code == '0' || raw.contains('Login completed')) {
          // Success — extract redirect URL and complete OAuth flow
          final urlMatch = RegExp(
            r"ptui[Cc]B\('\d+',\d+,'([^']+)'",
          ).firstMatch(raw);
          final redirectUrl = urlMatch?.group(1);

          // Capture cookies from polling response
          final cookies = res['cookies'] as String?;
          if (cookies != null && cookies.isNotEmpty) {
            _api.setCookie(cookies);
          }

          // Complete full OAuth login flow
          if (redirectUrl != null && redirectUrl.isNotEmpty) {
            final cookie = await _api.completeOAuthLogin(redirectUrl);
            if (cookie != null && cookie.isNotEmpty) {
              _api.setCookie(cookie);
            }
          }

          try {
            // Extract uin from cookies (set during OAuth login)
            final cookie = _api.cookie ?? '';
            final uin = _extractUinFromCookie(cookie);
            if (uin != null && uin.isNotEmpty) {
              _currentUser = User(
                id: uin,
                nickname: 'QQ用户',
                platform: PlatformType.qq,
              );
            } else {
              // Fallback: try API
              final userRes = await _api.getUserInfo(uin ?? '');
              final profile = userRes['profile'];
              if (profile != null) {
                _currentUser = User(
                  id: profile['uin']?.toString() ?? '',
                  nickname: profile['nick'] ?? 'QQ用户',
                  platform: PlatformType.qq,
                );
              }
            }
          } catch (e) {
            debugPrint('QQ getUserInfo after login error: $e');
          }
          if (_currentUser != null) {
            final freshUser = await _fetchUserInfo();
            if (freshUser != null) _currentUser = freshUser;
          }
          if (_currentUser != null) {
            yield QrLoginStatus.success;
          } else {
            debugPrint(
              'QQ login: QR scan confirmed but failed to get user info',
            );
            yield QrLoginStatus.failed;
          }
          return;
        } else if (code == '65') {
          yield QrLoginStatus.expired;
          return;
        } else if (code == '66') {
          yield QrLoginStatus.scanned;
        } else {
          yield QrLoginStatus.waiting;
        }
      } catch (e) {
        debugPrint('QQ QR poll error: $e');
        yield QrLoginStatus.failed;
        return;
      }
    }
    yield QrLoginStatus.failed;
  }

  @override
  Future<LoginResult> sendPhoneCode(String phone) async {
    return const LoginResult(
      success: false,
      error: 'QQ Music does not support phone-code login.',
    );
  }

  @override
  Future<LoginResult> loginByPhone(String phone, String code) async {
    return LoginResult(success: false, error: 'QQ音乐暂不支持手机号登录');
  }

  @override
  Future<User?> getUserInfo() async {
    _currentUser = await _fetchUserInfo() ?? _currentUser;
    return _currentUser;
  }

  Future<User?> _fetchUserInfo() async {
    final cookie = _api.cookie ?? '';
    final uin = _extractUinFromCookie(cookie);
    if (uin == null || uin.isEmpty) return _currentUser;
    try {
      final userRes = await _api.getUserInfo(uin);
      return _parseUserFromProfile(userRes, fallbackUin: uin);
    } catch (e) {
      debugPrint('QQ fetch user profile error: $e');
      return _currentUser ??
          User(id: uin, nickname: 'QQ用户', platform: PlatformType.qq);
    }
  }

  @visibleForTesting
  static User parseUserFromProfileForTest(
    Map<String, dynamic> data, {
    required String fallbackUin,
  }) {
    return _parseUserFromProfile(data, fallbackUin: fallbackUin);
  }

  @visibleForTesting
  static String? extractUinFromCookieForTest(String cookie) {
    return _extractUinFromCookie(cookie);
  }

  static String? _extractUinFromCookie(String cookie) {
    const candidates = [
      'uin',
      'qqmusic_uin',
      'loginUin',
      'musicid',
      'web_uin',
      'wxuin',
    ];
    for (final name in candidates) {
      final match = RegExp('(?:^|;\\s*)$name=o?(\\d+)').firstMatch(cookie);
      final value = match?.group(1);
      if (value != null && value.isNotEmpty && value != '0') return value;
    }
    return null;
  }

  static User _parseUserFromProfile(
    Map<String, dynamic> data, {
    required String fallbackUin,
  }) {
    final root = data['data'] is Map ? data['data'] as Map : data;
    final home = root['home'] is Map ? root['home'] as Map : null;
    final creator = _firstMap([
      root['creator'],
      home?['creator'],
      root['host'],
      root['user'],
    ]);
    final profile = _firstMap([
      root['profile'],
      home?['profile'],
      root['userinfo'],
      root['userInfo'],
    ]);
    final info = _firstMap([root['info'], home?['info'], root['base']]);
    final nick =
        creator?['nick'] ??
        creator?['nickname'] ??
        creator?['nick_name'] ??
        creator?['hostname'] ??
        creator?['name'] ??
        profile?['nick'] ??
        profile?['nickname'] ??
        profile?['nick_name'] ??
        profile?['name'] ??
        info?['nick'] ??
        info?['nickname'] ??
        info?['nick_name'] ??
        info?['name'] ??
        root['hostname'] ??
        root['nick'] ??
        root['nickname'] ??
        root['nick_name'] ??
        root['name'] ??
        'QQ用户';
    final avatar =
        creator?['headpic'] ??
        creator?['headurl'] ??
        creator?['avatar'] ??
        creator?['avatarUrl'] ??
        profile?['headpic'] ??
        profile?['headurl'] ??
        profile?['avatar'] ??
        profile?['avatarUrl'] ??
        info?['headpic'] ??
        info?['headurl'] ??
        info?['avatar'] ??
        info?['avatarUrl'] ??
        root['headpic'] ??
        root['avatar'];
    return User(
      id: fallbackUin,
      nickname: nick.toString(),
      avatarUrl: avatar?.toString(),
      platform: PlatformType.qq,
    );
  }

  static Map? _firstMap(List<dynamic> values) {
    for (final value in values) {
      if (value is Map) return value;
    }
    return null;
  }

  @override
  Future<void> logout() async {
    _currentUser = null;
    _api.setCookie('');
  }

  @override
  Future<void> saveSession(SessionStorage storage) async {
    if (_currentUser != null) {
      await storage.saveUser(platformType, _currentUser!);
    }
    final cookie = _api.cookie;
    if (cookie != null && cookie.isNotEmpty) {
      await storage.saveCookie(platformType, cookie);
    }
  }

  @override
  Future<void> restoreSession(SessionStorage storage) async {
    final cookie = await storage.loadCookie(platformType);
    if (cookie != null && cookie.isNotEmpty) {
      _api.restoreCookie(cookie);
    }
    final user = await storage.loadUser(platformType);
    if (user != null) {
      _currentUser = user;
    }
  }

  // --- Search ---

  @override
  Future<List<Song>> search(
    String keyword, {
    int page = 1,
    int limit = 30,
  }) async {
    final res = await _api.search(keyword, page: page, limit: limit);
    final searchData = res['req_0'];
    final body =
        searchData?['data']?['body']?['song']?['list'] as List<dynamic>?;
    if (body == null) return [];

    return body.map((s) => _parseSong(s)).toList();
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
          res['list'] as List<dynamic>? ??
          res['data']?['list'] as List<dynamic>? ??
          const [];
      return list.map((p) => _parsePlaylist(p, editable: false)).toList();
    } catch (e) {
      debugPrint('QQ searchPlaylists error: $e');
      return [];
    }
  }

  Song _parseSong(dynamic s) {
    final songId =
        (s['mid'] ??
                s['songmid'] ??
                s['songMid'] ??
                s['strMediaMid'] ??
                s['id']?.toString() ??
                s['songid']?.toString())
            ?.toString() ??
        '';
    final songName =
        (s['name'] ?? s['title'] ?? s['songname'] ?? s['songName'] ?? '')
            .toString();
    final singers =
        (s['singer'] as List<dynamic>?)
            ?.map(
              (a) => Artist(
                id: (a['mid'] ?? a['id'] ?? '').toString(),
                name: (a['name'] ?? a['title'] ?? '').toString(),
              ),
            )
            .toList() ??
        [];

    final albumMid =
        s['album']?['mid'] ?? s['albumMid'] ?? s['albummid'] ?? s['album_mid'];
    final albumName =
        s['album']?['name'] ?? s['albumName'] ?? s['albumname'] ?? '';
    final coverUrl = albumMid != null
        ? 'https://y.qq.com/music/photo_new/T002R300x300M000$albumMid.jpg'
        : null;

    return Song(
      id: songId,
      platform: PlatformType.qq,
      name: songName,
      artists: singers,
      album: albumName.isNotEmpty
          ? Album(id: albumMid ?? '', name: albumName, coverUrl: coverUrl)
          : null,
      duration: Duration(
        seconds:
            int.tryParse((s['interval'] ?? s['duration'] ?? 0).toString()) ?? 0,
      ),
      coverUrl: coverUrl,
    );
  }

  // --- Playback ---

  @override
  Future<String> getSongUrl(
    String songId, {
    AudioLevel quality = AudioLevel.low,
  }) async {
    final res = await _api.getSongUrl(songId, quality: quality);
    final req1 = res['req_1']?['data']?['midurlinfo'] as List<dynamic>?;
    if (req1 == null || req1.isEmpty) {
      throw Exception('无法获取播放地址，可能需要会员');
    }
    final purl = req1.first['purl'];

    if (purl == null || purl.isEmpty) {
      throw Exception('无法获取播放地址，可能需要会员');
    }

    final sip = res['req_1']?['data']?['sip'] as List<dynamic>?;
    final cdnsip = sip?.isNotEmpty == true ? sip!.first : '';
    return '$cdnsip$purl';
  }

  @override
  Future<List<AudioQuality>> getAvailableQualities(String songId) async {
    // QQ Music qualities are determined by membership
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
      const AudioQuality(
        level: AudioLevel.dolby,
        bitrate: 999000,
        format: 'flac',
      ),
      const AudioQuality(
        level: AudioLevel.master,
        bitrate: 999000,
        format: 'flac',
      ),
    ];
  }

  // --- Lyrics ---

  @override
  Future<String?> getLyrics(String songId) async {
    debugPrint(
      'QQ getLyrics: songId=$songId, hasCookie=${_api.cookie != null && _api.cookie!.isNotEmpty}',
    );
    try {
      final result = await _api.getLyric(songId);
      debugPrint('QQ getLyrics: result length=${result?.length ?? 'null'}');
      return result;
    } catch (e) {
      debugPrint('QQ getLyrics error: $e');
      return null;
    }
  }

  // --- Library ---

  @override
  Future<List<Playlist>> getUserPlaylists() async {
    if (_currentUser == null) return [];
    try {
      final res = await _api.getUserPlaylists(_currentUser!.id);
      final plistlist =
          res['data']?['disslist'] as List<dynamic>? ??
          res['req_0']?['data']?['plistlist'] as List<dynamic>?;
      if (plistlist == null) return [];
      return plistlist.map((p) => _parsePlaylist(p, editable: true)).toList();
    } catch (e) {
      debugPrint('QQ getUserPlaylists error: $e');
      return [];
    }
  }

  @override
  Future<List<Song>> getPlaylistDetail(String playlistId) async {
    try {
      final songlist = await _loadPlaylistSongList(playlistId);
      if (songlist == null) return [];
      return songlist.map((s) => _parseSong(_songPayload(s))).toList();
    } catch (e) {
      debugPrint('QQ getPlaylistDetail error: $e');
      return [];
    }
  }

  @override
  Future<List<Song>> getLikedSongs() async {
    try {
      final res = await _api.getLikedSongs();
      final songlist = res['req_0']?['data']?['songlist'] as List<dynamic>?;
      if (songlist == null) return [];
      return songlist.map((s) => _parseSong(s)).toList();
    } catch (e) {
      debugPrint('QQ getLikedSongs error: $e');
      return [];
    }
  }

  @override
  Future<bool> likeSong(String songId, {bool like = true}) async {
    try {
      // songId is the song mid for QQ
      if (like) {
        await _api.likeSong(songId, songId);
      } else {
        await _api.unlikeSong(songId, songId);
      }
      return true;
    } catch (e) {
      debugPrint('QQ likeSong error: $e');
      return false;
    }
  }

  @override
  Future<bool> addSongToPlaylist(String playlistId, Song song) async {
    try {
      await _api.addSongToPlaylist(playlistId, song.id);
      return true;
    } catch (e) {
      debugPrint('QQ addSongToPlaylist error: $e');
      return false;
    }
  }

  @override
  Future<Playlist?> createPlaylist(String name) async {
    try {
      final res = await _api.createPlaylist(name);
      if (res['code'] == 0 || res['result'] == 100) {
        final id =
            res['dirid']?.toString() ??
            res['data']?['dirid']?.toString() ??
            res['id']?.toString() ??
            '';
        final refreshed = await _findCreatedPlaylistByDirId(id, name);
        if (refreshed != null) return refreshed;
        return null;
      }
      return null;
    } catch (e) {
      debugPrint('QQ createPlaylist error: $e');
      return null;
    }
  }

  Future<Playlist?> _findCreatedPlaylistByDirId(String dirId, String name) async {
    if (dirId.isEmpty || _currentUser == null) return null;
    final playlists = await getUserPlaylists();
    for (final playlist in playlists) {
      if (playlist.id.isNotEmpty && playlist.editableId == dirId) {
        return playlist;
      }
    }
    for (final playlist in playlists) {
      if (playlist.id.isNotEmpty && playlist.name == name) return playlist;
    }
    return null;
  }

  @override
  Future<bool> collectPlaylist(String playlistId, {bool collect = true}) async {
    try {
      final res = await _api.collectPlaylist(playlistId, collect: collect);
      return res['code'] == 0 || res['result'] == 100;
    } catch (e) {
      debugPrint('QQ collectPlaylist error: $e');
      return false;
    }
  }

  // --- Recommendations ---

  @override
  Future<List<Song>> getDailyRecommendations() async {
    try {
      final playlistId = await _api.getDailyPlaylistId().timeout(
        const Duration(seconds: 12),
        onTimeout: () => null,
      );
      if (playlistId != null && playlistId.isNotEmpty) {
        final songs = await getPlaylistDetail(playlistId);
        if (songs.isNotEmpty) return songs.take(30).toList();
      }

      final res = await _api.getDailyRecommend();
      final data = res['req_0']?['data'];
      final songlist =
          data?['songlist'] as List<dynamic>? ??
          data?['list'] as List<dynamic>? ??
          data?['v_song'] as List<dynamic>?;
      if (songlist == null) return [];
      return songlist.map((s) => _parseSong(_songPayload(s))).take(30).toList();
    } catch (e) {
      debugPrint('QQ getDailyRecommendations error: $e');
      return [];
    }
  }

  @override
  Future<List<Song>> getRankingList() async {
    try {
      final res = await _api.getToplistDetail(4); // topId=4 热歌榜
      final songlist = res['toplist']?['data']?['songList'] as List<dynamic>?;
      if (songlist == null) return [];
      return songlist.map((s) => _parseSong(s)).toList();
    } catch (e) {
      debugPrint('QQ getRankingList error: $e');
      return [];
    }
  }

  // --- VIP ---

  @override
  Future<VipLevel> getVipStatus() async {
    if (_currentUser == null) return VipLevel.free;
    try {
      final res = await _api.getVipInfo(_currentUser!.id);
      final vipInfo = res['req_0']?['data'];
      if (vipInfo == null) return VipLevel.free;
      final vipType = vipInfo['vipType'] ?? 0;
      if (vipType >= 2) return VipLevel.svip;
      if (vipType >= 1) return VipLevel.vip;
      return VipLevel.free;
    } catch (e) {
      debugPrint('QQ getVipStatus error: $e');
      return VipLevel.free;
    }
  }

  // --- Playlist Import ---

  @override
  Future<Playlist?> parseShareLink(String url) async {
    final id = _extractSharePlaylistId(url);
    if (id == null) return null;
    try {
      final detail = await _loadPlaylistDetailWithFallback(id);
      final metadata = detail == null ? null : _extractPlaylistMetadata(detail);
      final songlist = detail == null ? null : _extractPlaylistSongList(detail);
      final metadataSongCount = int.tryParse(
        (metadata?['songnum'] ??
                metadata?['song_cnt'] ??
                metadata?['song_count'] ??
                metadata?['total_song_num'] ??
                0)
            .toString(),
      );
      final songCount =
          metadataSongCount != null &&
              metadataSongCount > (songlist?.length ?? 0)
          ? metadataSongCount
          : songlist?.length ?? 0;
      final Map<String, dynamic>? dirinfo = metadata == null
          ? null
          : {
              'title':
                  metadata['title'] ?? metadata['dissname'] ?? metadata['name'],
              'picurl':
                  metadata['picurl'] ?? metadata['logo'] ?? metadata['coverurl'],
            };
      return Playlist(
        id: id,
        name: dirinfo?['title'] ?? 'QQ歌单',
        platform: PlatformType.qq,
        songCount: songCount,
        coverUrl: dirinfo?['picurl'],
      );
    } catch (e) {
      debugPrint('QQ parseShareLink error: $e');
      return Playlist(
        id: id,
        name: 'QQ歌单',
        platform: PlatformType.qq,
        songCount: 0,
      );
    }
  }

  Future<Map<String, dynamic>?> _loadPlaylistDetailWithFallback(
    String playlistId,
  ) async {
    try {
      final res = await _api.getPlaylistDetail(playlistId);
      final songlist = _extractPlaylistSongList(res);
      if (songlist != null && songlist.isNotEmpty) return res;
    } catch (e) {
      debugPrint('QQ modern playlist detail unavailable: $e');
    }

    try {
      return await _api.getLegacyPlaylistDetail(playlistId);
    } catch (e) {
      debugPrint('QQ legacy playlist detail unavailable: $e');
      return null;
    }
  }

  Future<List<dynamic>?> _loadPlaylistSongList(String playlistId) async {
    final detail = await _loadPlaylistDetailWithFallback(playlistId);
    if (detail == null) return null;

    final firstPage = _extractPlaylistSongList(detail);
    if (firstPage == null) return null;

    final total = _extractPlaylistSongCount(detail);
    if (!_isModernPlaylistDetail(detail) ||
        total == null ||
        total <= firstPage.length) {
      return firstPage;
    }

    final songs = List<dynamic>.from(firstPage);
    const pageSize = 200;
    var begin = firstPage.length;
    while (begin < total) {
      Map<String, dynamic>? pageDetail;
      try {
        pageDetail = await _api.getPlaylistDetail(
          playlistId,
          songBegin: begin,
          songNum: pageSize,
        );
      } catch (e) {
        debugPrint('QQ paged playlist detail unavailable: $e');
        break;
      }
      final pageSongs = _extractPlaylistSongList(pageDetail);
      if (pageSongs == null || pageSongs.isEmpty) break;
      songs.addAll(pageSongs);
      if (pageSongs.length < pageSize) break;
      begin += pageSongs.length;
    }
    return songs;
  }

  String? _extractSharePlaylistId(String url) {
    final uri = Uri.tryParse(url);
    if (uri != null && uri.host.contains('y.qq.com')) {
      final id = uri.queryParameters['id'] ?? uri.queryParameters['disstid'];
      if (id != null && id.isNotEmpty) return id;

      final segments = uri.pathSegments;
      final playlistIndex = segments.indexOf('playlist');
      if (playlistIndex >= 0 && playlistIndex + 1 < segments.length) {
        final pathId = segments[playlistIndex + 1].replaceAll('.html', '');
        if (pathId.isNotEmpty) return pathId;
      }
    }

    final match = RegExp(
      r'y\.qq\.com/.*[?&](?:id|disstid)=(\w+)|y\.qq\.com/n/ryqq/playlist/(\w+)|y\.qq\.com/n/yqq/playlist/(\w+)',
    ).firstMatch(url);
    return match?.group(1) ?? match?.group(2) ?? match?.group(3);
  }

  List<dynamic>? _extractPlaylistSongList(Map<String, dynamic> res) {
    final data = res['req_0']?['data'];
    final reqList = data?['songlist'];
    if (reqList is List<dynamic>) return reqList;

    final cdlist = res['cdlist'];
    if (cdlist is List && cdlist.isNotEmpty) {
      final first = cdlist.first;
      if (first is Map && first['songlist'] is List<dynamic>) {
        return first['songlist'] as List<dynamic>;
      }
    }

    final normalizedData = res['data'];
    if (normalizedData is List && normalizedData.isNotEmpty) {
      final first = normalizedData.first;
      if (first is Map && first['songlist'] is List<dynamic>) {
        return first['songlist'] as List<dynamic>;
      }
    }
    if (normalizedData is Map && normalizedData['songlist'] is List<dynamic>) {
      return normalizedData['songlist'] as List<dynamic>;
    }
    return null;
  }

  Map? _extractPlaylistMetadata(Map<String, dynamic> res) {
    final data = res['req_0']?['data'];
    if (data is Map && data['dirinfo'] is Map) return data['dirinfo'] as Map;

    final cdlist = res['cdlist'];
    if (cdlist is List && cdlist.isNotEmpty && cdlist.first is Map) {
      return cdlist.first as Map;
    }

    final normalizedData = res['data'];
    if (normalizedData is List &&
        normalizedData.isNotEmpty &&
        normalizedData.first is Map) {
      return normalizedData.first as Map;
    }
    if (normalizedData is Map) return normalizedData;
    return null;
  }

  int? _extractPlaylistSongCount(Map<String, dynamic> res) {
    final metadata = _extractPlaylistMetadata(res);
    if (metadata == null) return null;
    for (final key in const [
      'songnum',
      'song_cnt',
      'song_count',
      'total_song_num',
      'total_song_count',
      'count',
    ]) {
      final count = int.tryParse(metadata[key]?.toString() ?? '');
      if (count != null && count > 0) return count;
    }
    return null;
  }

  bool _isModernPlaylistDetail(Map<String, dynamic> res) {
    return res['req_0']?['data'] is Map;
  }

  Playlist _parsePlaylist(dynamic p, {required bool editable}) {
    final detailId =
        (p['disstid'] ?? p['dissid'] ?? p['tid'] ?? p['dirid'] ?? '')
            .toString();
    final editId = (p['dirid'] ?? p['tid'])?.toString();
    return Playlist(
      id: detailId,
      name: (p['diss_name'] ?? p['title'] ?? p['dissname'] ?? p['name'] ?? '')
          .toString(),
      platform: PlatformType.qq,
      songCount:
          int.tryParse(
            (p['song_cnt'] ?? p['songcnt'] ?? p['song_count'] ?? 0).toString(),
          ) ??
          0,
      coverUrl:
          (p['diss_cover'] ??
                  p['dirpicurl'] ??
                  p['imgurl'] ??
                  p['cover'] ??
                  p['picurl'])
              ?.toString(),
      creatorName:
          (p['creator']?['name'] ?? p['creator']?['nick'] ?? p['nickname'])
              ?.toString(),
      editable: editable,
      collected: !editable,
      editId: editId != null && editId != detailId ? editId : null,
    );
  }

  dynamic _songPayload(dynamic value) {
    if (value is Map) {
      return value['songInfo'] ?? value['song'] ?? value['musicData'] ?? value;
    }
    return value;
  }
}
