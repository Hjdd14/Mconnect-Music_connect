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
import 'netease_api.dart';

class NeteasePlatform implements MusicPlatform {
  final NeteaseApi _api;
  User? _currentUser;

  NeteasePlatform({NeteaseApi? api}) : _api = api ?? NeteaseApi();

  NeteaseApi get api => _api;

  @override
  PlatformType get platformType => PlatformType.netease;

  @override
  String get platformName => '网易云音乐';

  @override
  bool get isLoggedIn => _currentUser != null;

  // --- Auth ---

  @override
  Future<QrLoginResult> getQrCode() async {
    final keyRes = await _api.getQrKey();
    debugPrint('Netease QR key response: $keyRes');
    // API returns unikey in data: {"code": 200, "data": {"unikey": "..."}}
    final unikey = keyRes['data']?['unikey'] ?? keyRes['unikey'];
    if (unikey == null) throw Exception('获取二维码key失败: ${keyRes['code']}');

    // Construct QR URL client-side for qr_flutter to render
    final qrUrl = 'https://music.163.com/login?codekey=$unikey';
    debugPrint('Netease QR url: $qrUrl');

    return QrLoginResult(key: unikey, qrUrl: qrUrl, qrBytes: null);
  }

  @override
  Stream<QrLoginStatus> pollQrStatus(String key) async* {
    while (true) {
      await Future.delayed(const Duration(seconds: 2));
      try {
        final res = await _api.checkQr(key);
        final code = res['code'];
        switch (code) {
          case 803:
            // Cookie already captured from Set-Cookie header in post()
            // Also check response body as fallback
            final cookie = res['cookie'];
            if (cookie != null) _api.setCookie(cookie);
            await _fetchUserInfo();
            yield QrLoginStatus.success;
            return;
          case 802:
            yield QrLoginStatus.scanned;
            break;
          case 800:
            yield QrLoginStatus.expired;
            return;
          default:
            yield QrLoginStatus.waiting;
        }
      } catch (_) {
        yield QrLoginStatus.failed;
        return;
      }
    }
  }

  @override
  Future<LoginResult> sendPhoneCode(String phone) async {
    try {
      final res = await _api.post(
        '/api/sms/captcha/sent',
        params: {'phone': phone},
      );
      final code = res['code'];
      return LoginResult(
        success: code == 200,
        error: code == 200
            ? null
            : (res['message'] ?? res['msg'] ?? '验证码发送失败')?.toString(),
      );
    } catch (e) {
      return LoginResult(success: false, error: e.toString());
    }
  }

  @override
  Future<LoginResult> loginByPhone(String phone, String code) async {
    try {
      final res = await _api.post(
        '/api/login/cellphone',
        params: {'phone': phone, 'captcha': code},
      );
      if (res['code'] == 200) {
        final cookie = res['cookie'];
        if (cookie != null) _api.setCookie(cookie);
        await _fetchUserInfo();
        return LoginResult(success: true, user: _currentUser, cookie: cookie);
      }
      return LoginResult(success: false, error: res['msg'] ?? '登录失败');
    } catch (e) {
      return LoginResult(success: false, error: e.toString());
    }
  }

  Future<void> _fetchUserInfo() async {
    try {
      final res = await _api.getUserInfo();
      final profile = res['profile'];
      if (profile != null) {
        _currentUser = User(
          id: profile['userId'].toString(),
          nickname: profile['nickname'] ?? '',
          avatarUrl: profile['avatarUrl'],
          platform: PlatformType.netease,
        );
      }
    } catch (e) {
      debugPrint('Netease _fetchUserInfo error: $e');
    }
  }

  @override
  Future<User?> getUserInfo() async {
    if (_currentUser == null) await _fetchUserInfo();
    return _currentUser;
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
    final songs = res['result']?['songs'] as List<dynamic>?;
    if (songs == null) return [];

    return songs.map((s) => _parseSong(s)).toList();
  }

  @override
  Future<List<Playlist>> searchPlaylists(
    String keyword, {
    int page = 1,
    int limit = 30,
  }) async {
    try {
      final res = await _api.searchPlaylists(keyword, page: page, limit: limit);
      final playlists = res['result']?['playlists'] as List<dynamic>?;
      if (playlists == null) return [];
      return playlists.map((p) => _parsePlaylist(p, editable: false)).toList();
    } catch (e) {
      debugPrint('Netease searchPlaylists error: $e');
      return [];
    }
  }

  Song _parseSong(dynamic s) {
    final artists =
        (s['ar'] as List<dynamic>?)
            ?.map((a) => Artist(id: a['id'].toString(), name: a['name'] ?? ''))
            .toList() ??
        [];

    final album = s['al'] != null
        ? Album(
            id: s['al']['id'].toString(),
            name: s['al']['name'] ?? '',
            coverUrl: s['al']['picUrl'],
          )
        : null;

    return Song(
      id: s['id'].toString(),
      platform: PlatformType.netease,
      name: s['name'] ?? '',
      artists: artists,
      album: album,
      duration: Duration(milliseconds: s['dt'] ?? 0),
      coverUrl: album?.coverUrl,
    );
  }

  // --- Playback ---

  @override
  Future<String> getSongUrl(
    String songId, {
    AudioLevel quality = AudioLevel.low,
  }) async {
    final level = _levelNameFor(quality);
    debugPrint('Netease getSongUrl: songId=$songId, level=$level');
    final res = await _api.getSongUrl(songId, level: level);
    debugPrint('Netease getSongUrl response keys: ${res.keys.toList()}');
    final data = (res['data'] as List<dynamic>?)?.first;
    if (data == null) {
      debugPrint('Netease getSongUrl: data is null, full response: $res');
      throw Exception('无法获取播放地址');
    }

    // Check for trial-only playback
    final freeTrialInfo = data['freeTrialInfo'];
    if (freeTrialInfo != null) {
      debugPrint('Netease getSongUrl: TRIAL ONLY - $freeTrialInfo');
    }

    final url = data['url'] as String?;
    if (url == null) {
      debugPrint(
        'Netease getSongUrl: url is null, code=${data['code']}, fee=${data['fee']}, freeTrialInfo=$freeTrialInfo',
      );
      throw Exception('无法获取播放地址，可能需要会员');
    }
    debugPrint(
      'Netease getSongUrl: url=$url, level=${data['level']}, br=${data['br']}',
    );
    return url;
  }

  @visibleForTesting
  static String levelNameForTest(AudioLevel quality) => _levelNameFor(quality);

  static String _levelNameFor(AudioLevel quality) {
    return switch (quality) {
      AudioLevel.low => 'standard',
      AudioLevel.medium => 'higher',
      AudioLevel.high => 'exhigh',
      AudioLevel.lossless => 'lossless',
      AudioLevel.hires => 'hires',
      AudioLevel.spatial => 'jyeffect',
      AudioLevel.dolby => 'sky',
      AudioLevel.master => 'jymaster',
    };
  }

  @override
  Future<List<AudioQuality>> getAvailableQualities(String songId) async {
    final res = await _api.getSongUrl(songId, level: 'jymaster');
    final data = (res['data'] as List<dynamic>?)?.first;
    if (data == null) return [];

    final qualities = <AudioQuality>[];
    final level = data['level'] ?? 'none';
    final br = data['br'] ?? 0;

    if (level != 'none') {
      qualities.add(
        AudioQuality(level: AudioLevel.low, bitrate: 128000, format: 'mp3'),
      );
    }
    if (br >= 192000) {
      qualities.add(
        AudioQuality(level: AudioLevel.medium, bitrate: 192000, format: 'mp3'),
      );
    }
    if (br >= 320000) {
      qualities.add(
        AudioQuality(level: AudioLevel.high, bitrate: 320000, format: 'mp3'),
      );
    }
    if (data['fl'] != null && data['fl'] >= 1000) {
      qualities.add(
        AudioQuality(
          level: AudioLevel.lossless,
          bitrate: data['fl'],
          format: 'flac',
        ),
      );
    }
    if (level == 'hires') {
      qualities.add(
        AudioQuality(
          level: AudioLevel.hires,
          bitrate: data['br'] ?? 999000,
          format: data['ft'] ?? 'flac',
        ),
      );
    }
    if (level == 'jyeffect') {
      qualities.add(
        AudioQuality(
          level: AudioLevel.spatial,
          bitrate: data['br'] ?? 320000,
          format: data['ft'] ?? 'mp3',
        ),
      );
    }
    if (level == 'sky') {
      qualities.add(
        AudioQuality(
          level: AudioLevel.dolby,
          bitrate: data['br'] ?? 320000,
          format: data['ft'] ?? 'mp3',
        ),
      );
    }
    if (level == 'jymaster') {
      qualities.add(
        AudioQuality(
          level: AudioLevel.master,
          bitrate: data['br'] ?? 999000,
          format: data['ft'] ?? 'flac',
        ),
      );
    }
    return qualities;
  }

  // --- Lyrics ---

  @override
  Future<String?> getLyrics(String songId) async {
    try {
      debugPrint('Netease getLyrics: songId=$songId');
      final res = await _api.getLyric(songId);
      debugPrint('Netease getLyrics: response keys=${res.keys.toList()}');
      final lrc = res['lrc']?['lyric'] as String?;
      final tlyric = res['tlyric']?['lyric'] as String?;
      debugPrint('Netease getLyrics: lrc length=${lrc?.length ?? 'null'}');
      if (lrc == null || lrc.isEmpty) return null;
      if (tlyric == null || tlyric.isEmpty) return lrc;
      return '$lrc\n$tlyric';
    } catch (e) {
      debugPrint('Netease getLyrics error: $e');
      return null;
    }
  }

  // --- Library ---

  @override
  Future<List<Playlist>> getUserPlaylists() async {
    if (_currentUser == null) return [];
    final res = await _api.getUserPlaylist(_currentUser!.id);
    final playlists = res['playlist'] as List<dynamic>?;
    if (playlists == null) return [];

    return playlists.map((p) => _parsePlaylist(p, editable: true)).toList();
  }

  @override
  Future<List<Song>> getPlaylistDetail(String playlistId) async {
    final res = await _api.getPlaylistDetail(playlistId);
    final playlist = res['playlist'];
    final tracks = playlist?['tracks'] as List<dynamic>? ?? const [];
    final songs = tracks.map((t) => _parseSong(t)).toList();

    final trackIds = _extractTrackIds(playlist?['trackIds']);
    if (trackIds.length <= songs.length) return songs;

    final loadedIds = songs.map((song) => song.id).toSet();
    final missingIds = trackIds
        .where((id) => id.isNotEmpty && !loadedIds.contains(id))
        .toList(growable: false);
    for (var i = 0; i < missingIds.length; i += 200) {
      final end = (i + 200).clamp(0, missingIds.length);
      final batch = missingIds.sublist(i, end);
      final detail = await _api.getSongDetails(batch);
      final detailSongs = detail['songs'] as List<dynamic>? ?? const [];
      songs.addAll(detailSongs.map((s) => _parseSong(s)));
    }
    return songs;
  }

  @override
  Future<List<Song>> getLikedSongs() async {
    if (_currentUser == null) return [];
    final playlists = await getUserPlaylists();
    final likedPlaylist = playlists.firstWhere(
      (p) => p.name == '我喜欢的音乐',
      orElse: () => playlists.isNotEmpty
          ? playlists.first
          : const Playlist(id: '', name: '', platform: PlatformType.netease),
    );
    if (likedPlaylist.id.isEmpty) return [];
    return getPlaylistDetail(likedPlaylist.id);
  }

  @override
  Future<bool> likeSong(String songId, {bool like = true}) async {
    try {
      await _api.likeSong(songId, like: like);
      return true;
    } catch (e) {
      debugPrint('Netease likeSong error: $e');
      return false;
    }
  }

  @override
  Future<bool> addSongToPlaylist(String playlistId, Song song) async {
    try {
      final res = await _api.post(
        '/api/playlist/manipulate/tracks',
        params: {
          'op': 'add',
          'pid': playlistId,
          'trackIds': '[${song.id}]',
          'imme': 'true',
        },
      );
      return res['code'] == 200;
    } catch (e) {
      debugPrint('Netease addSongToPlaylist error: $e');
      return false;
    }
  }

  @override
  Future<Playlist?> createPlaylist(String name) async {
    try {
      final res = await _api.createPlaylist(name);
      final playlist = res['playlist'];
      if (res['code'] == 200 && playlist != null) {
        return _parsePlaylist(playlist, editable: true);
      }
      return null;
    } catch (e) {
      debugPrint('Netease createPlaylist error: $e');
      return null;
    }
  }

  @override
  Future<bool> collectPlaylist(String playlistId, {bool collect = true}) async {
    try {
      final res = await _api.subscribePlaylist(playlistId, subscribe: collect);
      return res['code'] == 200;
    } catch (e) {
      debugPrint('Netease collectPlaylist error: $e');
      return false;
    }
  }

  // --- Recommendations ---

  @override
  Future<List<Song>> getDailyRecommendations() async {
    try {
      final res = await _api.getRecommendSongs();
      final songs = res['data']?['dailySongs'] as List<dynamic>?;
      if (songs == null) return [];
      return songs.map((s) => _parseSong(s)).toList();
    } catch (e) {
      debugPrint('Netease getDailyRecommendations error: $e');
      return [];
    }
  }

  @override
  Future<List<Song>> getRankingList() async {
    try {
      // Use well-known Netease hot song top list ID
      final res = await _api.getPlaylistDetail('3778678');
      final tracks = res['playlist']?['tracks'] as List<dynamic>?;
      if (tracks == null) return [];
      return tracks.take(30).map((s) => _parseSong(s)).toList();
    } catch (e) {
      debugPrint('Netease getRankingList error: $e');
      return [];
    }
  }

  // --- VIP ---

  @override
  Future<VipLevel> getVipStatus() async {
    try {
      final res = await _api.getUserInfo();
      final profile = res['profile'];
      if (profile == null) return VipLevel.free;
      final vipType = profile['vipType'] ?? 0;
      if (vipType >= 11) return VipLevel.svip;
      if (vipType >= 10) return VipLevel.vip;
      return VipLevel.free;
    } catch (e) {
      debugPrint('Netease getVipStatus error: $e');
      return VipLevel.free;
    }
  }

  // --- Playlist Import ---

  @override
  Future<Playlist?> parseShareLink(String url) async {
    final id = _extractPlaylistId(url);
    if (id == null) return null;
    try {
      final detail = await _api.getPlaylistDetail(id);
      final p = detail['playlist'];
      if (p == null) return null;
      return Playlist(
        id: p['id'].toString(),
        name: p['name'] ?? '',
        platform: PlatformType.netease,
        songCount: p['trackCount'] ?? 0,
        coverUrl: p['coverImgUrl'],
      );
    } catch (e) {
      debugPrint('Netease parseShareLink error: $e');
      return null;
    }
  }

  String? _extractPlaylistId(String url) {
    final uri = Uri.tryParse(url);
    if (uri != null && uri.host.contains('music.163.com')) {
      final id = uri.queryParameters['id'];
      if (id != null && RegExp(r'^\d+$').hasMatch(id)) return id;

      final segments = uri.pathSegments;
      final playlistIndex = segments.indexOf('playlist');
      if (playlistIndex >= 0 && playlistIndex + 1 < segments.length) {
        final pathId = segments[playlistIndex + 1];
        if (RegExp(r'^\d+$').hasMatch(pathId)) return pathId;
      }

      if (uri.fragment.isNotEmpty) {
        final fragment = uri.fragment.startsWith('/')
            ? uri.fragment
            : '/${uri.fragment}';
        final fragmentUri = Uri.tryParse('https://music.163.com$fragment');
        final fragmentId = fragmentUri?.queryParameters['id'];
        if (fragmentId != null && RegExp(r'^\d+$').hasMatch(fragmentId)) {
          return fragmentId;
        }
      }
    }

    final match = RegExp(
      r'music\.163\.com/(?:#/)?(?:m/)?playlist(?:/|\?id=)(\d+)',
    ).firstMatch(url);
    return match?.group(1);
  }

  List<String> _extractTrackIds(dynamic rawTrackIds) {
    if (rawTrackIds is! List) return const [];
    return rawTrackIds
        .map((item) {
          if (item is Map) return item['id']?.toString() ?? '';
          return item?.toString() ?? '';
        })
        .where((id) => id.isNotEmpty)
        .toList(growable: false);
  }

  Playlist _parsePlaylist(dynamic p, {required bool editable}) {
    return Playlist(
      id: p['id'].toString(),
      name: p['name'] ?? '',
      platform: PlatformType.netease,
      songCount: p['trackCount'] ?? p['bookCount'] ?? 0,
      coverUrl: p['coverImgUrl'] ?? p['coverUrl'] ?? p['picUrl'] ?? p['imgurl'],
      creatorName: p['creator']?['nickname']?.toString(),
      editable: editable,
      collected: !editable,
    );
  }
}
