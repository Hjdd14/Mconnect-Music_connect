import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../lyrics/models/lyrics_bundle.dart';
import '../../lyrics/models/lyrics_line.dart';
import '../../models/song.dart';
import '../../models/artist.dart';
import '../../models/album.dart';
import '../../models/user.dart';
import '../../models/playlist.dart';
import '../../models/audio_quality.dart';
import '../../models/platform_type.dart';
import '../../models/recommendation_source.dart';
import '../../models/toplist.dart';
import '../base/music_platform.dart';
import '../../core/network/api_exception.dart';
import '../../core/network/platform_http.dart';
import '../../core/diagnostics/diagnostics_service.dart';
import '../../core/storage/session_storage.dart';
import 'qq_api.dart';
import 'qq_endpoints.dart';
import 'qq_toplist_ids.dart';

class QqPlatform extends MusicPlatform {
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

  // --- Capabilities --------------------------------------------------------
  //
  // All four are implemented below and verified against the live endpoints, so
  // the UI may offer the entry points. `supportsDailyRecommendations` is true
  // even though the anonymous list is a chart — [getDailyRecommendation]
  // reports that provenance instead of pretending it is personalised.

  @override
  bool get supportsDailyRecommendations => true;

  @override
  bool get supportsArtistPage => true;

  @override
  bool get supportsAlbumPage => true;

  @override
  bool get supportsNewSongs => true;

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

  Song _parseSong(dynamic raw) {
    final s = _asMap(raw);
    final songId =
        _firstText([
          s['mid'],
          s['songmid'],
          s['songMid'],
          s['strMediaMid'],
          s['id'],
          s['songid'],
        ]) ??
        '';
    final songName = _firstText([s['name'], s['title'], s['songname'], s['songName']]) ?? '';
    final singers = <Artist>[];
    final singerRows = s['singer'];
    if (singerRows is List) {
      for (final row in singerRows) {
        final singer = _asMap(row);
        final name = _firstText([singer['name'], singer['title']]);
        if (name == null) continue;
        singers.add(
          Artist(id: _firstText([singer['mid'], singer['id'], name]) ?? name, name: name),
        );
      }
    }

    final album = _asMap(s['album']);
    final albumMid = _firstText([
      album['mid'],
      s['albumMid'],
      s['albummid'],
      s['album_mid'],
    ]);
    final albumName =
        _firstText([album['name'], album['title'], s['albumName'], s['albumname']]) ?? '';
    final coverUrl =
        (albumMid != null && albumMid.isNotEmpty
            ? _albumCover(albumMid)
            : _firstText([album['cover'], s['cover'], s['pic']]));

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
            _asInt(s['interval'] ?? s['duration']) ?? 0,
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
    Map<String, dynamic> res;
    try {
      res = await _api.getSongUrl(songId, quality: quality);
    } on Object catch (e) {
      // Never leak a bare DioException/Exception to the UI: the playback layer
      // needs a typed error to decide between "retry" and "需要会员".
      throw apiExceptionOf(e);
    }
    final req1 = res['req_1']?['data']?['midurlinfo'] as List<dynamic>?;
    if (req1 == null || req1.isEmpty) {
      throw SongNotAvailableException(platform: platformName);
    }
    final purl = req1.first['purl'];

    if (purl == null || purl.isEmpty) {
      throw SongNotAvailableException(platform: platformName);
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

  /// Plain LRC (guaranteed) plus the word-by-word QRC track **when it is
  /// readable**.
  ///
  /// QQ's `.qrc` body is 3DES-encrypted and this repository has no key — and does
  /// not guess keys (see the `.qrc` note in `docs/mconnect-improvement-plan.md`).
  /// So the QRC track is only forwarded when the body already parses as plain QRC
  /// XML; anything else (encrypted bytes, an unknown shape, a failed request) is
  /// dropped silently and the plain LRC track is used. No error, no garbage line.
  @override
  Future<LyricsBundle?> getLyricsBundle(String songId) async {
    try {
      final tracks = await _api.getLyricTracks(songId);
      final qrc = await _readableQrcTrack(songId);
      final bundle = LyricsBundle(
        lrc: tracks.lyric,
        translation: tracks.translation,
        qrc: qrc,
      );
      if (bundle.isEmpty) {
        debugPrint('QQ getLyricsBundle: no lyric tracks for $songId');
        return null;
      }
      return bundle;
    } catch (e) {
      debugPrint('QQ getLyricsBundle error: $e');
      return null;
    }
  }

  /// The QRC body **only when it is plain, parseable QRC XML**.
  ///
  /// Checks the same way the loader does — by really parsing it — so an encrypted
  /// (or otherwise unrecognised) body can never reach the display as garbage.
  Future<String?> _readableQrcTrack(String songId) async {
    try {
      final res = await _api.getQrcLyric(songId);
      if (res == null) return null;
      final candidate =
          QqApi.decodeLyricField(res['lyric']) ??
          QqApi.decodeLyricField(res['qrc']);
      if (candidate == null || candidate.trim().isEmpty) return null;
      if (!LyricsDocument.parsesToLines(candidate, LyricsFormat.qrc)) {
        debugPrint(
          'QQ getLyricsBundle: qrc body is not readable QRC (encrypted?), '
          'falling back to lrc',
        );
        return null;
      }
      return candidate;
    } catch (_) {
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
      return songlist.map((s) => _parseSong(_songPayload(s))).toList();
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
      final res = await _api.addSongToPlaylist(playlistId, song.id);
      // This used to `return true` unconditionally, so a rejected write showed up
      // in the UI as a success. QQ answers `code == 0` / `result == 100` on
      // success (the same predicate `createPlaylist` below uses); anything else is
      // recorded so the reason is readable from the diagnostics log instead of
      // being swallowed by a debugPrint.
      final ok = res['code'] == 0 || res['result'] == 100;
      if (!ok) {
        DiagnosticsService.instance.record(
          'qq',
          'add_song_to_playlist_rejected',
          data: {
            'playlist_id': playlistId,
            'song_id': song.id,
            'code': res['code'],
            'subcode': res['subcode'],
            'message': res['msg'] ?? res['message'],
          },
        );
      }
      return ok;
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
      // The UI could only ever say "failed" with no reason. QQ answers with a
      // code/message; record it (codes only — no cookies, no tokens) so the next
      // attempt can be diagnosed from the diagnostics log.
      DiagnosticsService.instance.record(
        'qq',
        'create_playlist_rejected',
        data: {
          'code': res['code'],
          'subcode': res['subcode'],
          'result': res['result'],
          'message': res['msg'] ?? res['message'] ?? res['errmsg'],
        },
      );
      return null;
    } catch (e) {
      DiagnosticsService.instance.recordError('qq.createPlaylist', e, StackTrace.current);
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
    final result = await getDailyRecommendation();
    return result.songs;
  }

  /// QQ's daily recommendation plus its **provenance**.
  ///
  /// Two sources, in order:
  /// 1. the personalised 「今日私享」 playlist, which the PC page only renders for
  ///    a signed-in cookie (verified anonymously 2026-10: the page is 8269 bytes
  ///    and does not contain the 今日私享 marker at all) → [RecommendationKind
  ///    .personalPrivate];
  /// 2. an anonymous chart fallback (新歌榜, then 热歌榜) → [RecommendationKind
  ///    .fallbackToplist] with an explanatory note, because "QQ 推荐" is not the
  ///    same promise as "每日推荐".
  ///
  /// The old anonymous endpoint (`musicToplist.ChartInfo/GetDailyRecommend`) is
  /// gone: it answers `code 500003 / subcode 860100005` for every caller.
  @override
  Future<RecommendationResult> getDailyRecommendation() async {
    // A cookie — not just the in-memory user — is what unlocks 今日私享, and
    // skipping the probe when there is none also saves an anonymous caller the
    // page fetch (and its timeout) before the chart fallback.
    final hasSession = _api.cookie?.isNotEmpty ?? false;
    final loggedIn = hasSession || isLoggedIn;
    final private = hasSession ? await _personalisedDaily() : const <Song>[];
    if (private.isNotEmpty) {
      return RecommendationResult(
        songs: private,
        source: RecommendationSource(
          platform: platformType,
          kind: RecommendationKind.personalPrivate,
          label: '今日私享',
        ),
      );
    }

    for (final chart in const [
      (id: QqToplistIds.newSongs, name: QqToplistIds.newSongsName),
      (id: QqToplistIds.hot, name: QqToplistIds.hotName),
    ]) {
      final ranked = await getRankedSongs('${chart.id}', num: 30);
      if (ranked.isNotEmpty) {
        return RecommendationResult(
          songs: ranked.map((r) => r.song).toList(),
          source: RecommendationSource(
            platform: platformType,
            kind: RecommendationKind.fallbackToplist,
            label: chart.name,
            note: loggedIn
                ? '今日私享暂不可用，已回退到${chart.name}'
                : '未登录，已回退到${chart.name}',
          ),
        );
      }
    }

    return RecommendationResult(
      source: RecommendationSource(
        platform: platformType,
        kind: RecommendationKind.unavailable,
        label: '暂不可用',
        note: loggedIn ? '今日私享与榜单均无数据' : '未登录，且榜单无数据',
      ),
      error: 'QQ 每日推荐暂不可用',
    );
  }

  /// 「今日私享」 tracks, or an empty list when unavailable (any failure).
  Future<List<Song>> _personalisedDaily() async {
    try {
      final playlistId = await _api
          .getDailyPlaylistId()
          .timeout(const Duration(seconds: 12), onTimeout: () => null);
      if (playlistId == null || playlistId.isEmpty) return const [];
      final songs = await getPlaylistDetail(playlistId);
      return songs.take(30).toList();
    } catch (e) {
      debugPrint('QQ 今日私享 unavailable: $e');
      return const [];
    }
  }

  // --- Charts (榜单) ---

  @override
  Future<List<Toplist>> getToplists() async {
    final res = await _api.getToplistCatalogue();
    final data = QqApi.moduleOf(res, 'toplist')['data'];
    if (data is! Map) return const [];
    final groups = data['group'];
    if (groups is! List) return const [];

    final toplists = <Toplist>[];
    for (final group in groups) {
      if (group is! Map) continue;
      final groupName = group['groupName']?.toString();
      final items = group['toplist'];
      if (items is! List) continue;
      for (final item in items) {
        if (item is! Map) continue;
        final id = item['topId']?.toString();
        if (id == null || id.isEmpty) continue;
        toplists.add(
          Toplist(
            id: id,
            name: _firstText([item['title'], item['titleDetail']]) ?? 'QQ榜单',
            coverUrl: _firstText([
              item['frontPicUrl'],
              item['headPicUrl'],
              item['mbFrontPicUrl'],
            ]),
            updateFrequency: _firstText([item['updateTips']]),
            songCount: _asInt(item['totalNum']),
            period: _firstText([item['period'], item['updateTime']]),
            groupName: groupName,
            intro: _firstText([item['intro']]),
          ),
        );
      }
    }
    return _orderGroups(toplists);
  }

  /// Orders catalogue groups the way QQ's own 榜单中心 does (巅峰榜 first),
  /// keeping any group the constant list does not know about at the end.
  static List<Toplist> _orderGroups(List<Toplist> toplists) {
    if (toplists.length < 2) return toplists;
    final ordered = <Toplist>[];
    for (final group in QqToplistIds.groupOrder) {
      ordered.addAll(toplists.where((t) => t.groupName == group));
    }
    ordered.addAll(
      toplists.where((t) => !QqToplistIds.groupOrder.contains(t.groupName)),
    );
    return ordered;
  }

  /// One chart, with each song's position and movement.
  ///
  /// Two live paths, chosen by what the caller needs:
  /// * no [period] → the legacy `toplist_cp` endpoint, which is the only one
  ///   that reports the previous position (`old_count - cur_count`), and is
  ///   paged 50 tracks at a time to reach the 300-track 热歌榜;
  /// * with [period] (weekly history, e.g. `2026_40`) → the modern musicu
  ///   `GetDetail` module, whose `song[]` carries `rank` + `rankType`.
  ///
  /// Either path falls back to the other if it returns nothing. Failures
  /// degrade to an empty list (logged) like the rest of this adapter, so a
  /// chart page shows its empty state instead of crashing.
  @override
  Future<List<RankedSong>> getRankedSongs(
    String toplistId, {
    int offset = 0,
    int num = 100,
    String? period,
  }) async {
    final topId = int.tryParse(toplistId);
    if (topId == null || num <= 0 || offset < 0) return const [];
    final wantsPeriod = period != null && period.isNotEmpty;

    if (wantsPeriod) {
      final modern = await _rankedFromModernDetail(
        topId,
        offset: offset,
        num: num,
        period: period,
      );
      if (modern.isNotEmpty) return modern;
      return _rankedFromLegacyCp(topId, offset: offset, num: num);
    }

    final legacy = await _rankedFromLegacyCp(topId, offset: offset, num: num);
    if (legacy.isNotEmpty) return legacy;
    return _rankedFromModernDetail(
      topId,
      offset: offset,
      num: num,
      period: period,
    );
  }

  /// The 热歌榜 as reported by QQ's own endpoint, up to [num] tracks
  /// (default: all 300).
  Future<List<RankedSong>> getHotSongs({
    int offset = 0,
    int num = 300,
  }) async {
    return getRankedSongs('${QqToplistIds.hot}', offset: offset, num: num);
  }

  /// Legacy `toplist_cp` path: rank movement + `Franking_value`.
  Future<List<RankedSong>> _rankedFromLegacyCp(
    int topId, {
    required int offset,
    required int num,
  }) async {
    final ranked = <RankedSong>[];
    final end = offset + num;
    var begin = offset;
    while (begin < end) {
      final pageSize = (end - begin).clamp(1, QqToplistIds.pageSize);
      Map<String, dynamic> page;
      try {
        page = await _api.getToplistCp(
          topId: topId,
          offset: begin,
          num: pageSize,
        );
      } catch (e) {
        debugPrint('QQ getToplistCp($topId, $begin) error: $e');
        break;
      }
      final rows = page['songlist'];
      if (rows is! List || rows.isEmpty) break;

      // `cur_count` is the rank on rank-ordered charts (热歌榜/新歌榜) but a
      // *score* on score-ordered ones (流行指数/飙升榜), so rank-like pages are
      // detected instead of assumed.
      final rankLike = _isRankOrderedPage(rows, begin);
      var reportsMovement = false;
      if (rankLike) {
        for (final row in rows) {
          final previous = _asInt(_asMap(row)['old_count']);
          if (previous != null && previous > 0) {
            reportsMovement = true;
            break;
          }
        }
      }

      for (var i = 0; i < rows.length; i++) {
        final row = _asMap(rows[i]);
        final song = _parseSong(_songPayload(row));
        if (song.id.isEmpty) continue;
        final current = _asInt(row['cur_count']);
        final previous = _asInt(row['old_count']);
        final rank = rankLike && current != null && current > 0
            ? current
            : begin + i + 1;
        ranked.add(
          RankedSong(
            song: song,
            rank: rank,
            rankChange: reportsMovement && previous != null && current != null
                ? previous - current
                : null,
            isNew: reportsMovement ? previous == 0 : null,
            rankValue: _firstText([row['Franking_value']]),
          ),
        );
      }

      if (rows.length < pageSize) break;
      begin += rows.length;
    }
    return ranked;
  }

  /// Modern musicu `GetDetail` path: real `rank`/`rankType` per song.
  ///
  /// `rankType` (verified by diffing this endpoint against `toplist_cp` for
  /// 特色榜·说唱榜): 1 = moved **up** by `rankValue`, 2 = moved **down** by
  /// `rankValue`, 3 = unchanged, 4 = new entry, 6 = growth percentage (飙升榜,
  /// no rank movement).
  Future<List<RankedSong>> _rankedFromModernDetail(
    int topId, {
    required int offset,
    required int num,
    String? period,
  }) async {
    Map<String, dynamic> res;
    try {
      res = await _api.getToplistDetail(
        topId,
        offset: offset,
        num: num,
        period: period,
      );
    } catch (e) {
      debugPrint('QQ getToplistDetail($topId) error: $e');
      return const [];
    }
    final data = QqApi.moduleOf(res, 'toplist')['data'];
    if (data is! Map) return const [];
    final songs = data['songInfoList'];
    if (songs is! List) return const [];
    final inner = data['data'];
    final rankRows = inner is Map ? inner['song'] : null;

    final ranked = <RankedSong>[];
    for (var i = 0; i < songs.length; i++) {
      final song = _parseSong(_songPayload(songs[i]));
      if (song.id.isEmpty) continue;
      final rankRow = rankRows is List && i < rankRows.length
          ? _asMap(rankRows[i])
          : const <dynamic, dynamic>{};
      final rankType = _asInt(rankRow['rankType']);
      final value = _asInt(rankRow['rankValue']);
      final rank = _asInt(rankRow['rank']) ?? offset + i + 1;
      ranked.add(
        RankedSong(
          song: song,
          rank: rank,
          rankChange: switch (rankType) {
            1 => value,
            2 => value == null ? null : -value,
            3 => 0,
            _ => null,
          },
          isNew: rankType == null ? null : rankType == 4,
          rankValue: _firstText([rankRow['rankValue']]),
        ),
      );
    }
    return ranked;
  }

  /// True when the page's `cur_count` values are exactly `begin+1 … begin+n`,
  /// i.e. the field is a rank and not a score.
  static bool _isRankOrderedPage(List<dynamic> rows, int begin) {
    for (var i = 0; i < rows.length; i++) {
      final current = _asInt(_asMap(rows[i])['cur_count']);
      if (current == null || current != begin + i + 1) return false;
    }
    return true;
  }

  @override
  Future<List<Song>> getRankingList() async {
    try {
      final ranked = await getHotSongs(num: 100);
      return ranked.map((r) => r.song).toList();
    } catch (e) {
      debugPrint('QQ getRankingList error: $e');
      return [];
    }
  }

  // --- Artist / album / new songs ---

  @override
  Future<Artist?> getArtistDetail(String artistId) async {
    if (artistId.isEmpty) return null;
    final profile = await _singerProfile(artistId);
    if (profile == null) return null;
    final info = _asMap(profile['getSingerInfo']);
    final name = _firstText([
      info['Fsinger_name'],
      profile['singer_name'],
      artistId,
    ]);
    return Artist(
      id: _firstText([info['Fsinger_mid'], artistId]) ?? artistId,
      name: name ?? artistId,
      avatarUrl: await _artistAvatar(artistId, profile: profile),
      briefDesc: _firstText([profile['singerBrief']]),
      songCount: _asInt(profile['total_song']),
      albumCount: _asInt(profile['total_album']),
    );
  }

  /// Artist avatar. The legacy profile endpoint has no picture, so the
  /// canonical `singer_pmid` is fetched from musicu and used with QQ's cover
  /// template; the `pic` field is preferred when present.
  Future<String?> _artistAvatar(
    String artistId, {
    Map<String, dynamic>? profile,
  }) async {
    try {
      final res = await _api.getSingerProfile(artistId);
      final list = QqApi.moduleOf(res, 'singer')['data']?['singer_list'];
      if (list is List && list.isNotEmpty) {
        final entry = _asMap(list.first);
        final pic = _asMap(entry['pic']);
        final direct = _firstText([pic['pic'], pic['big_black']]);
        if (direct != null) return direct;
        final pmid = _firstText([
          _asMap(entry['basic_info'])['singer_pmid'],
          artistId,
        ]);
        if (pmid != null) return '${QqEndpoints.artistCover}$pmid.jpg';
      }
    } catch (e) {
      debugPrint('QQ getSingerProfile($artistId) error: $e');
    }
    // Last resort: QQ's generic artist-cover template accepts a singer mid.
    return '${QqEndpoints.artistCover}$artistId.jpg';
  }

  Future<Map<String, dynamic>?> _singerProfile(String artistId) async {
    try {
      final res = await _api.getSingerDetail(artistId);
      return res.isEmpty ? null : res;
    } catch (e) {
      debugPrint('QQ getSingerDetail($artistId) error: $e');
      return null;
    }
  }

  @override
  Future<List<Song>> getArtistTopSongs(
    String artistId, {
    int limit = 50,
  }) async {
    if (artistId.isEmpty || limit <= 0) return const [];
    final profile = await _singerProfile(artistId);
    final rows = profile?['getSongInfo'];
    if (rows is! List) return const [];
    final songs = <({Song song, int plays})>[];
    for (final row in rows) {
      final song = _parseSong(_songPayload(row));
      if (song.id.isEmpty) continue;
      final extra = _asMap(_asMap(row)['extra']);
      songs.add((song: song, plays: _asInt(extra['Flisten_count1']) ?? 0));
    }
    // QQ returns this list unordered; play counts make "top songs" meaningful.
    songs.sort((a, b) => b.plays.compareTo(a.plays));
    return songs.take(limit).map((e) => e.song).toList();
  }

  @override
  Future<List<Album>> getArtistAlbums(
    String artistId, {
    int page = 1,
    int limit = 30,
  }) async {
    if (artistId.isEmpty || limit <= 0) return const [];
    final begin = (page <= 1 ? 0 : page - 1) * limit;

    try {
      final res = await _api.getSingerAlbums(
        artistId,
        begin: begin,
        num: limit,
      );
      final module = QqApi.moduleOf(res, 'req_0');
      final data = module['data'];
      final rows = data is Map ? data['albumList'] : null;
      if (rows is List && rows.isNotEmpty) {
        return rows
            .map(_parseCatalogueAlbum)
            .where((album) => album.id.isNotEmpty)
            .toList();
      }
    } catch (e) {
      debugPrint('QQ getSingerAlbums($artistId) error: $e');
    }

    // Fallback: album search filtered down to this artist. The search rows do
    // not carry the artist mid (`singer_list[].mid` is empty), so filtering is
    // done on the numeric singer id / artist name.
    return _artistAlbumsFromSearch(artistId, limit: limit);
  }

  Future<List<Album>> _artistAlbumsFromSearch(
    String artistId, {
    required int limit,
  }) async {
    try {
      final profile = await _singerProfile(artistId);
      final info = _asMap(profile?['getSingerInfo']);
      final singerId = _firstText([info['Fsinger_id']]);
      final name = _firstText([info['Fsinger_name']]);
      final keyword = name ?? artistId;

      final res = await _api.searchAlbums(keyword, limit: limit);
      final body = QqApi.moduleOf(res, 'req_0')['data']?['body'];
      final rows = body is Map ? _asMap(body['item_album'])['list'] : null;
      if (rows is! List) return const [];
      return rows
          .map(_asMap)
          .where(
            (row) =>
                _artistMatchesSearchRow(row, singerId: singerId, name: name),
          )
          .map(_parseSearchedAlbum)
          .where((album) => album.id.isNotEmpty)
          .take(limit)
          .toList();
    } catch (e) {
      debugPrint('QQ album search fallback for $artistId error: $e');
      return const [];
    }
  }

  static bool _artistMatchesSearchRow(
    Map<dynamic, dynamic> row, {
    String? singerId,
    String? name,
  }) {
    if (singerId != null && singerId.isNotEmpty) {
      final rowSingerId = _firstText([row['singer_id']]);
      if (rowSingerId == singerId) return true;
    }
    if (name == null || name.isEmpty) return false;
    final singers = row['singer_list'];
    if (singers is List) {
      for (final singer in singers) {
        if (_firstText([_asMap(singer)['name']]) == name) return true;
      }
    }
    return _firstText([row['singer']]) == name;
  }

  @override
  Future<Album?> getAlbumDetail(String albumId) async {
    if (albumId.isEmpty) return null;
    Map<String, dynamic> res;
    try {
      res = await _api.getAlbumInfo(albumId);
    } catch (e) {
      debugPrint('QQ getAlbumInfo($albumId) error: $e');
      return null;
    }
    final data = _asMap(res['data']);
    if (data.isEmpty) return null;
    return _parseAlbumDetail(data);
  }

  @override
  Future<List<Song>> getAlbumSongs(String albumId) async {
    if (albumId.isEmpty) return const [];
    Map<String, dynamic> res;
    try {
      res = await _api.getAlbumInfo(albumId);
    } catch (e) {
      debugPrint('QQ getAlbumInfo($albumId) error: $e');
      return const [];
    }
    final rows = _asMap(res['data'])['list'];
    if (rows is! List) return const [];
    return rows
        .map((row) => _parseSong(_songPayload(row)))
        .where((song) => song.id.isNotEmpty)
        .toList();
  }

  @override
  Future<List<Song>> getNewSongs({
    int limit = 100,
    NewSongRegion region = NewSongRegion.all,
  }) async {
    if (limit <= 0) return const [];
    Map<String, dynamic> res;
    try {
      res = await _api.getNewSongs(type: _qqNewSongType(region));
    } catch (e) {
      debugPrint('QQ getNewSongs error: $e');
      return const [];
    }
    final rows = QqApi.moduleOf(res, 'newsong')['data']?['songlist'];
    if (rows is! List) return const [];
    // QQ ignores `num` (asking for 3 returns 32), so truncate here.
    return rows
        .map((row) => _parseSong(_songPayload(row)))
        .where((song) => song.id.isNotEmpty)
        .take(limit)
        .toList();
  }

  /// Maps [NewSongRegion] onto QQ's `type` ids
  /// (1 内地 / 2 欧美 / 3 日本 / 4 韩国 / 5 全部 / 6 港台).
  static int _qqNewSongType(NewSongRegion region) {
    return switch (region) {
      NewSongRegion.all => 5,
      NewSongRegion.chinese => 1,
      NewSongRegion.western => 2,
      NewSongRegion.japanese => 3,
      NewSongRegion.korean => 4,
      NewSongRegion.hongKongTaiwan => 6,
    };
  }

  @visibleForTesting
  static int qqNewSongTypeForTest(NewSongRegion region) =>
      _qqNewSongType(region);

  Album _parseCatalogueAlbum(dynamic raw) {
    final row = _asMap(raw);
    final mid = _firstText([row['albumMid'], row['albummid']]) ?? '';
    return Album(
      id: mid,
      name: _firstText([row['albumName'], row['albumTranName']]) ?? '未知专辑',
      artistName: _firstText([row['singerName']]),
      coverUrl: mid.isEmpty ? null : _albumCover(mid),
      releaseDate: DateTime.tryParse(
        _firstText([row['publishDate']]) ?? '',
      ),
    );
  }

  Album _parseSearchedAlbum(dynamic raw) {
    final row = _asMap(raw);
    final mid = _firstText([row['albummid'], row['albumMid']]) ?? '';
    return Album(
      id: mid,
      name: _firstText([row['name'], row['albumName']]) ?? '未知专辑',
      artistName: _firstText([row['singer']]),
      coverUrl: _firstText([row['pic']]) ??
          (mid.isEmpty ? null : _albumCover(mid)),
      releaseDate: DateTime.tryParse(_firstText([row['publish_date']]) ?? ''),
      songCount: _asInt(row['song_num']),
    );
  }

  Album _parseAlbumDetail(Map<dynamic, dynamic> data) {
    final mid = _firstText([data['mid']]) ?? '';
    return Album(
      id: mid,
      name: _firstText([data['name']]) ?? '未知专辑',
      artistName: _firstText([data['singername']]),
      artistId: _firstText([data['singermid']]),
      coverUrl: mid.isEmpty ? null : _albumCover(mid),
      releaseDate: DateTime.tryParse(_firstText([data['aDate']]) ?? ''),
      description: _firstText([data['desc']]),
      songCount: _asInt(data['total_song_num']) ?? _asInt(data['cur_song_num']),
      company: _firstText([data['company']]),
      genre: _firstText([data['genre']]),
      language: _firstText([data['lan']]),
    );
  }

  static String _albumCover(String albumMid) =>
      '${QqEndpoints.songCover}$albumMid.jpg';

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

  /// Unwraps the container some QQ endpoints put around a song object.
  ///
  /// Playlist detail wraps songs in `songInfo`, modern chart detail returns them
  /// bare, and the legacy `toplist_cp` chart endpoint wraps them in **`data`** —
  /// the case the pre-v1.4.0 code missed, which is why 热歌榜/排行榜 rows parsed
  /// as empty songs. The unwrap is guarded by a shape check so a genuine song
  /// that happens to carry a `data` field is not mistaken for a wrapper.
  dynamic _songPayload(dynamic value) {
    if (value is! Map) return value;
    for (final key in const ['songInfo', 'song', 'musicData', 'data']) {
      final inner = value[key];
      if (inner is Map && _looksLikeSong(inner)) return inner;
    }
    return value;
  }

  static bool _looksLikeSong(Map<dynamic, dynamic> value) {
    return value.containsKey('songmid') ||
        value.containsKey('songname') ||
        value.containsKey('mid') ||
        value.containsKey('songId') ||
        value.containsKey('singer');
  }

  static Map<dynamic, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return value;
    return const <dynamic, dynamic>{};
  }

  static int? _asInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  /// First non-empty, non-`"null"` value as text — the QQ payloads use several
  /// alternative key names for the same field and sprinkle empty strings.
  static String? _firstText(List<dynamic> values) {
    for (final value in values) {
      if (value == null) continue;
      final text = value.toString().trim();
      if (text.isNotEmpty && text != 'null') return text;
    }
    return null;
  }
}
