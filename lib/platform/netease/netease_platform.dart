import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../core/network/api_exception.dart';
import '../../core/network/platform_http.dart';
import '../../models/song.dart';
import '../../models/artist.dart';
import '../../models/album.dart';
import '../../models/toplist.dart';
import '../../models/user.dart';
import '../../models/playlist.dart';
import '../../models/audio_quality.dart';
import '../../models/platform_type.dart';
import '../../models/recommendation_source.dart';
import '../base/music_platform.dart';
import '../../core/storage/session_storage.dart';
import 'netease_api.dart';
import 'netease_endpoints.dart';

class NeteasePlatform extends MusicPlatform {
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

  // --- Capabilities ---
  //
  // 网易云 is the only platform whose "daily recommendation" the app has been
  // able to rely on (it returns a genuinely personalised playlist); QQ and
  // 酷狗 opt in from Wave 1 once their real sources are implemented.

  @override
  bool get supportsDailyRecommendations => true;

  /// 网易云的三类内容接口（艺人页 / 专辑页 / 新歌速递）都已在 Wave 1 实测可用，
  /// 见 `docs/netease-wave-b-probe.md`（18 个端点全部 HTTP 200）。
  @override
  bool get supportsArtistPage => true;

  @override
  bool get supportsAlbumPage => true;

  @override
  bool get supportsNewSongs => true;

  @override
  Future<RecommendationResult> getDailyRecommendation() async {
    final songs = await getDailyRecommendations();
    return RecommendationResult(
      songs: songs,
      source: songs.isEmpty
          ? null
          : const RecommendationSource(
              platform: PlatformType.netease,
              kind: RecommendationKind.personalizedDaily,
              label: '每日推荐',
            ),
    );
  }

  // --- Auth ---

  @override
  Future<QrLoginResult> getQrCode() async {
    final keyRes = await _api.getQrKey();
    debugPrint('Netease QR key response: $keyRes');
    // API returns unikey in data: {"code": 200, "data": {"unikey": "..."}}
    final unikey = keyRes['data']?['unikey'] ?? keyRes['unikey'];
    if (unikey == null) throw Exception('获取二维码key失败: ${keyRes['code']}');

    // Construct QR URL client-side for qr_flutter to render
    final qrUrl = NeteaseEndpoints.qrLoginUrl(unikey.toString());
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
        NeteaseEndpoints.smsCaptchaSent,
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
        NeteaseEndpoints.loginCellphone,
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

  /// Parse one 网易云 song object.
  ///
  /// 网易云**同一个实体在不同端点用两套字段名**，两套都在生产响应里实测到
  /// （`docs/netease-wave-b-probe.md`）：
  ///
  /// * 新接口 —— search / `v6/playlist/detail` / `artist/top/song` /
  ///   `v1/album/{id}`：`ar` / `al` / `dt`（probe 2/4c/7d）；
  /// * 旧接口 —— `artist/{id}` 的 `hotSongs`、`personalized/newsong` 的
  ///   `song`、`v1/discovery/new/songs` 的 `data[]`：`artists` / `album` /
  ///   `duration`（probe 4b/7b/7f）。
  ///
  /// 只认一套就会让另一套端点的歌曲**静默退化成"无名无歌手"**，所以这里同时兼容。
  Song _parseSong(dynamic s) {
    final rawArtists =
        (s['ar'] as List<dynamic>?) ?? (s['artists'] as List<dynamic>?);
    final artists =
        rawArtists
            ?.whereType<Map>()
            .map(
              (a) => Artist(
                id: '${a['id'] ?? ''}',
                name: '${a['name'] ?? ''}',
              ),
            )
            .toList() ??
        [];

    final rawAlbum = s['al'] ?? s['album'];
    final album = rawAlbum is Map
        ? Album(
            id: '${rawAlbum['id'] ?? ''}',
            name: '${rawAlbum['name'] ?? ''}',
            coverUrl: rawAlbum['picUrl']?.toString(),
          )
        : null;
    final albumId = (album == null || album.id.isEmpty) ? null : album.id;

    final durationMs = _asInt(s['dt']) ?? _asInt(s['duration']) ?? 0;

    return Song(
      id: '${s['id'] ?? ''}',
      platform: PlatformType.netease,
      name: '${s['name'] ?? ''}',
      artists: artists,
      album: album,
      duration: Duration(milliseconds: durationMs),
      coverUrl: album?.coverUrl,
      albumId: albumId,
      artistId: artists.isEmpty ? null : artists.first.id,
      trackNumber: _asInt(s['no']),
      fee: _asInt(s['fee']),
    );
  }

  static int? _asInt(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  /// `publishTime` / `trackNumberUpdateTime` 之类都是**毫秒**时间戳。
  static DateTime? _asDateTime(Object? value) {
    final ms = _asInt(value);
    if (ms == null || ms <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  /// 调用方主动取消（页面销毁 / 被新查询取代）不是"失败"。
  ///
  /// 取消必须保持 [RequestCancelledException] 类型上抛：一旦被兜底逻辑吞掉，
  /// 就会退化成"空列表"或"另一个端点的数据"，而 UI 只会看到"没内容"。
  ///
  /// 走 [apiExceptionOf] 判断而不是自己 `is DioException`：这样无论请求经过的是
  /// 装了 `PlatformErrorInterceptor` 的生产 Dio（异常挂在 `DioException.error`）
  /// 还是测试里的裸 Dio，判断结果一致，平台层也不必依赖 dio 类型。
  static bool _isCancellation(Object error) =>
      apiExceptionOf(error) is RequestCancelledException;

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
    // `res['data']` 在"没有音源"时是**空数组**而不是 null：直接 `?.first` 会抛
    // StateError: No element（一个跟业务无关的裸错误），所以先判空。
    final rawData = res['data'];
    final data = rawData is List && rawData.isNotEmpty ? rawData.first : null;
    if (data == null) {
      debugPrint('Netease getSongUrl: data is null, full response: $res');
      // 服务端正常应答但没有可用音源：这是"歌曲不可用"，不是网络错误。
      throw SongNotAvailableException(platform: platformName);
    }

    final freeTrialInfo = data['freeTrialInfo'];
    if (freeTrialInfo != null) {
      debugPrint(
        'Netease getSongUrl: trial-only url rejected - $freeTrialInfo',
      );
      throw NoVipMembershipException(platformName);
    }

    final url = data['url'] as String?;
    if (url == null) {
      debugPrint(
        'Netease getSongUrl: url is null, code=${data['code']}, fee=${data['fee']}, freeTrialInfo=$freeTrialInfo',
      );
      // `fee >= 1` 表示这首歌本身是付费/会员曲目，否则只能判定为不可用。
      // 以前这里抛裸 Exception，UI 无法区分"要开会员"和"这首没版权"。
      final fee = data['fee'];
      if (fee is int && fee >= 1) {
        throw NoVipMembershipException(platformName);
      }
      throw SongNotAvailableException(platform: platformName);
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
        NeteaseEndpoints.playlistTrackManipulate,
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
      // 热歌榜 = 歌单 3778678（getToplists 实测它就在 list 里，200 首）。
      // 走 getRankedSongs 而不是直接取 detail，这样排名与分页缺口补齐的行为
      // 和榜单页完全一致。
      final ranked = await getRankedSongs('3778678', num: 30);
      return ranked.map((r) => r.song).toList();
    } catch (e) {
      debugPrint('Netease getRankingList error: $e');
      return [];
    }
  }

  // --- Artist ---

  /// 艺人 id -> (信息, 是否来自 head/info/get)。
  ///
  /// 两条路都实测可用：`POST /api/artist/head/info/get`（`data.artist`，简介完整
  /// 665 字）优先，旧明文 `GET /api/artist/{id}` 兜底（简介是空字符串，但一次
  /// 附带 50 首热门）。两条都"应答正常但无该艺人"时返回 null，而不是编造。
  @override
  Future<Artist?> getArtistDetail(String artistId) async {
    Object? firstError;
    var answered = false;

    try {
      final res = await _api.getArtistHeadInfo(artistId);
      answered = true;
      final artist = res['data']?['artist'];
      if (artist is Map) {
        debugPrint('Netease getArtistDetail: head/info/get hit for $artistId');
        return _parseArtist(artist);
      }
    } on Object catch (e) {
      if (_isCancellation(e)) throw apiExceptionOf(e);
      firstError ??= e;
      debugPrint('Netease getArtistDetail head/info/get failed: $e');
    }

    try {
      final res = await _api.getArtistLegacy(artistId);
      answered = true;
      final artist = res['artist'];
      if (artist is Map) {
        debugPrint('Netease getArtistDetail: legacy /api/artist hit');
        return _parseArtist(artist);
      }
    } on Object catch (e) {
      if (_isCancellation(e)) throw apiExceptionOf(e);
      firstError ??= e;
      debugPrint('Netease getArtistDetail legacy failed: $e');
    }

    if (!answered && firstError != null) {
      // 两个端点都没应答 → 这是请求失败，不是"没有这个艺人"。
      throw apiExceptionOf(firstError);
    }
    return null;
  }

  Artist _parseArtist(Map<dynamic, dynamic> a) {
    return Artist(
      id: '${a['id'] ?? ''}',
      name: '${a['name'] ?? ''}',
      // head/info/get 用 cover/avatar，旧接口用 picUrl。
      avatarUrl:
          a['cover']?.toString() ??
          a['picUrl']?.toString() ??
          a['avatar']?.toString(),
      briefDesc: a['briefDesc']?.toString(),
      // 网易云把曲目数叫 musicSize，专辑数叫 albumSize。
      songCount: _asInt(a['musicSize']),
      albumCount: _asInt(a['albumSize']),
      // 实测两个端点都没有 fansCount（probe 7a/4b），宁可为 null 也不编造。
      fansCount: _asInt(a['fansCount']),
    );
  }

  @override
  Future<List<Song>> getArtistTopSongs(
    String artistId, {
    int limit = 50,
  }) async {
    if (limit <= 0) return const [];
    Object? firstError;
    var answered = false;

    // 专用端点：GET /api/artist/top/song?id= → songs[]，实测 50 首（ar/al/dt）。
    try {
      final res = await _api.getArtistTopSongs(artistId);
      answered = true;
      final songs = res['songs'];
      // 空数组必须继续走兜底：该端点偶尔只回空 `songs`，而旧接口还带 50 首热门。
      if (songs is List && songs.isNotEmpty) {
        return songs.map(_parseSong).take(limit).toList();
      }
    } on Object catch (e) {
      if (_isCancellation(e)) throw apiExceptionOf(e);
      firstError ??= e;
      debugPrint('Netease getArtistTopSongs top/song failed: $e');
    }

    // 兜底：旧接口的 hotSongs（实测 50 首，字段名是 artists/album/duration）。
    try {
      final res = await _api.getArtistLegacy(artistId);
      answered = true;
      final songs = res['hotSongs'];
      if (songs is List) {
        return songs.map(_parseSong).take(limit).toList();
      }
    } on Object catch (e) {
      if (_isCancellation(e)) throw apiExceptionOf(e);
      firstError ??= e;
      debugPrint('Netease getArtistTopSongs hotSongs fallback failed: $e');
    }

    if (!answered && firstError != null) throw apiExceptionOf(firstError);
    return const [];
  }

  @override
  Future<List<Album>> getArtistAlbums(
    String artistId, {
    int page = 1,
    int limit = 30,
  }) async {
    if (limit <= 0) return const [];
    final offset = (page - 1).clamp(0, 10000) * limit;
    try {
      final res = await _api.getArtistAlbums(
        artistId,
        limit: limit,
        offset: offset,
      );
      final albums = res['hotAlbums'];
      if (albums is! List) return const [];
      return albums
          .map((a) => _parseAlbumBrief(a))
          .take(limit)
          .toList(growable: false);
    } on Object catch (e) {
      throw apiExceptionOf(e);
    }
  }

  /// `hotAlbums[]` / `album{}` 都共用这些字段，只在取 artist 时两种形状不同。
  Album _parseAlbumBrief(dynamic raw) {
    final a = raw as Map;
    final artist = a['artist'] is Map
        ? a['artist'] as Map
        : (a['artists'] is List && (a['artists'] as List).isNotEmpty
              ? (a['artists'] as List).first as Map
              : null);
    return Album(
      id: '${a['id'] ?? ''}',
      name: '${a['name'] ?? ''}',
      artistName: artist == null ? null : '${artist['name'] ?? ''}',
      artistId: artist == null ? null : '${artist['id'] ?? ''}',
      coverUrl: a['picUrl']?.toString(),
      releaseDate: _asDateTime(a['publishTime']),
      description: a['description']?.toString(),
      songCount: _asInt(a['size']),
      company: a['company']?.toString(),
      genre: _albumGenre(a),
    );
  }

  /// 实测没有 `album.genre`（probe 7d），只有 `album.tags[]`，且多数为空。
  /// 有值时拼成 `A/B`，没有就如实留 null。
  String? _albumGenre(Map a) {
    final tags = a['tags'];
    if (tags is! List) return null;
    final values = tags
        .map((t) => t?.toString().trim() ?? '')
        .where((t) => t.isNotEmpty)
        .toList();
    return values.isEmpty ? null : values.join('/');
  }

  // --- Album ---

  @override
  Future<Album?> getAlbumDetail(String albumId) async {
    try {
      final res = await _api.getAlbumDetail(albumId);
      final album = res['album'];
      if (album is! Map) return null;
      return _parseAlbumBrief(album);
    } on Object catch (e) {
      throw apiExceptionOf(e);
    }
  }

  @override
  Future<List<Song>> getAlbumSongs(String albumId) async {
    try {
      final res = await _api.getAlbumDetail(albumId);
      // 实测曲目在**顶层** songs（`album.songs` 是空数组，probe 7d）。
      final songs = res['songs'];
      if (songs is! List) return const [];
      final parsed = songs.map(_parseSong).toList();
      // `no` = 专辑内曲目号（实测 1..N 连续）。服务端已按序返回，但显式排序
      // 才能保证 UI 上"第 N 首"这个承诺成立。
      final allNumbered = parsed.every((s) => s.trackNumber != null);
      if (!allNumbered) return parsed;
      parsed.sort(
        (a, b) => (a.trackNumber ?? 0).compareTo(b.trackNumber ?? 0),
      );
      return parsed;
    } on Object catch (e) {
      throw apiExceptionOf(e);
    }
  }

  // --- New songs ---

  /// 网易云新歌速递的 `areaId` 映射（probe 7f 逐一实测，结果互不相同）。
  static const Map<NewSongRegion, int> _newSongAreaIds = {
    NewSongRegion.all: 0,
    NewSongRegion.chinese: 7,
    NewSongRegion.western: 96,
    NewSongRegion.japanese: 8,
    NewSongRegion.korean: 16,
  };

  @override
  Future<List<Song>> getNewSongs({
    int limit = 100,
    NewSongRegion region = NewSongRegion.all,
  }) async {
    if (limit <= 0) return const [];
    final areaId = _newSongAreaIds[region];
    if (areaId == null) {
      // 实测 areaId 6/14/60 都返回空 data（probe 7f）：网易云的新歌速递没有
      // 港台地区。宁可抛"暂不支持"，也不返回一个"全部地区"的列表冒充港台。
      throw UnsupportedActionException(
        platformName,
        details: '新歌速递不提供港台地区（areaId 6/14/60 实测均返回空）',
      );
    }

    try {
      final res = await _api.getNewSongsByArea(areaId: areaId);
      final data = res['data'];
      if (data is List) {
        // 实测服务端忽略 limit（请求 limit=3 返回 100 条），必须自己切片。
        return data.map(_parseSong).take(limit).toList();
      }
      debugPrint('Netease getNewSongs: unexpected body keys=${res.keys}');
    } on Object catch (e) {
      // 取消不是故障：不要拿"全部新歌"去兜一个被取消的华语请求。
      if (_isCancellation(e)) throw apiExceptionOf(e);
      if (region != NewSongRegion.all) {
        // 地区列表没有等价兜底：personalized/newsong 忽略地区参数，
        // 拿它冒充"华语新歌"就是造假数据，所以只把异常翻译后抛出。
        throw apiExceptionOf(e);
      }
      debugPrint('Netease getNewSongs area endpoint failed: $e');
    }

    if (region != NewSongRegion.all) return const [];

    // 兜底（仅"全部"）：personalized/newsong 也是全站新歌，承诺一致。
    // 注意 type 是 int 4 而不是字符串 'song'（probe 7b），所以按
    // "有 song 子对象 且 type 不是其它类型" 过滤，而不是照抄 type=='song'。
    final res = await _api.getPersonalizedNewSongs();
    final result = res['result'];
    if (result is! List) return const [];
    return result
        .where((item) => item is Map && item['song'] is Map)
        .where((item) {
          final type = (item as Map)['type'];
          return type == 4 || type == 'song' || type == null;
        })
        .map((item) => _parseSong((item as Map)['song']))
        .take(limit)
        .toList();
  }

  // --- Charts ---

  @override
  Future<List<Toplist>> getToplists() async {
    try {
      final res = await _api.getToplists();
      final list = res['list'];
      if (list is! List) return const [];
      return list
          .whereType<Map>()
          .map(
            (t) => Toplist(
              id: '${t['id'] ?? ''}',
              name: '${t['name'] ?? ''}',
              coverUrl: t['coverImgUrl']?.toString(),
              updateFrequency: t['updateFrequency']?.toString(),
              // 实测曲目数在 trackCount；`trackNumberUpdate` 不存在，
              // `trackNumberUpdateTime` 是毫秒时间戳。
              songCount: _asInt(t['trackCount']),
            ),
          )
          .where((t) => t.id.isNotEmpty && t.name.isNotEmpty)
          .toList(growable: false);
    } on Object catch (e) {
      throw apiExceptionOf(e);
    }
  }

  /// 单次 detail 请求最多取多少首（与 [getPlaylistDetail] 的 `n` 上限一致）。
  static const int _maxRankedFetch = 1000;

  @override
  Future<List<RankedSong>> getRankedSongs(
    String toplistId, {
    int offset = 0,
    int num = 100,
    String? period,
  }) async {
    if (num <= 0) return const [];
    final start = offset < 0 ? 0 : offset;
    final wanted = start + num;

    try {
      // `n` 实测就是"返回榜单前 n 首"（probe 7g：n=3 的歌名/id 序列与完整榜单
      // 前三首逐一对上），所以一次请求就能覆盖 [0, start+num)，再本地切片。
      // 网易云榜单不是按周期寻址的，`period` 一律忽略。
      final res = await _api.getPlaylistDetail(
        toplistId,
        n: wanted.clamp(1, _maxRankedFetch),
      );
      final playlist = res['playlist'];
      final rawTracks = playlist?['tracks'] as List<dynamic>? ?? const [];
      final songs = rawTracks.map(_parseSong).toList();

      // `n` 只截 tracks、不截 trackIds（probe 2 对照：n=50 时 tracks=50 而
      // trackIds=200），所以窗口超出 tracks 时用 trackIds 按 200 一批补齐
      // —— 与 getPlaylistDetail 的补齐手法相同。
      final trackIds = _extractTrackIds(playlist?['trackIds']);
      final needed = wanted.clamp(0, trackIds.length);
      if (songs.length < needed) {
        final loadedIds = songs.map((song) => song.id).toSet();
        final gapStart = songs.length.clamp(0, needed);
        final missingIds = trackIds
            .sublist(gapStart, needed)
            .where((id) => id.isNotEmpty && !loadedIds.contains(id))
            .toList(growable: false);
        for (var i = 0; i < missingIds.length; i += 200) {
          final end = (i + 200).clamp(0, missingIds.length);
          final detail = await _api.getSongDetails(
            missingIds.sublist(i, end),
          );
          final detailSongs = detail['songs'] as List<dynamic>? ?? const [];
          songs.addAll(detailSongs.map(_parseSong));
        }
      }

      final sliceEnd = wanted.clamp(0, songs.length);
      if (start >= sliceEnd) return const [];
      return [
        for (var i = start; i < sliceEnd; i++)
          // 排名 = 榜单内下标 + 1（第一首是 1，不是 0）。
          RankedSong(song: songs[i], rank: i + 1),
      ];
    } on Object catch (e) {
      throw apiExceptionOf(e);
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
        final fragmentUri = Uri.tryParse(
          '${NeteaseEndpoints.baseUrl}$fragment',
        );
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
