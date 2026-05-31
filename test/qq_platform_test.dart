import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/core/storage/session_storage.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/user.dart';
import 'package:mconnect/platform/qq/qq_api.dart';
import 'package:mconnect/platform/qq/qq_platform.dart';

void main() {
  test('parses QQ profile homepage response into real user nickname', () {
    final user = QqPlatform.parseUserFromProfileForTest({
      'creator': {'encrypt_uin': 'abc'},
      'data': {
        'creator': {'nick': '周同学', 'headpic': 'https://example.test/a.jpg'},
      },
    }, fallbackUin: '123456');

    expect(user.id, '123456');
    expect(user.nickname, '周同学');
    expect(user.avatarUrl, 'https://example.test/a.jpg');
    expect(user.platform, PlatformType.qq);
  });

  test('parses nested QQ profile homepage response shapes', () {
    final user = QqPlatform.parseUserFromProfileForTest({
      'code': 0,
      'data': {
        'home': {
          'creator': {
            'nick': 'Nested Nick',
            'headpic': 'https://example.test/nested.jpg',
          },
        },
      },
    }, fallbackUin: '123456');

    expect(user.nickname, 'Nested Nick');
    expect(user.avatarUrl, 'https://example.test/nested.jpg');
  });

  test('extracts QQ uin from alternate cookie names', () {
    expect(
      QqPlatform.extractUinFromCookieForTest(
        'qqmusic_uin=123456; qm_keyst=abc',
      ),
      '123456',
    );
    expect(
      QqPlatform.extractUinFromCookieForTest('loginUin=o234567; p_skey=abc'),
      '234567',
    );
    expect(
      QqPlatform.extractUinFromCookieForTest('uin=o345678; p_skey=abc'),
      '345678',
    );
  });

  test('QQ user playlists use dissid for detail instead of dirid', () async {
    final api = _QqPlaylistApi();
    final platform = QqPlatform(api: api);
    await platform.restoreSession(
      _MemorySessionStorage(
        user: const User(
          id: '123456',
          nickname: 'QQ User',
          platform: PlatformType.qq,
        ),
      ),
    );

    final playlists = await platform.getUserPlaylists();
    final songs = await platform.getPlaylistDetail(playlists.single.id);

    expect(playlists.single.id, '888888');
    expect(playlists.single.songCount, 780);
    expect(api.requestedPlaylistIds, contains('888888'));
    expect(songs, hasLength(1));
    expect(songs.single.id, 'song-mid-1');
  });

  test(
    'QQ playlist detail parses cdlist song rows from legacy endpoint shape',
    () async {
      final platform = QqPlatform(api: _QqCdlistPlaylistApi());

      final songs = await platform.getPlaylistDetail('888888');

      expect(songs, hasLength(1));
      expect(songs.single.id, 'song-mid-legacy');
      expect(songs.single.name, 'Legacy Song');
      expect(songs.single.artists.single.name, 'Legacy Artist');
    },
  );

  test(
    'QQ create playlist keeps dirid editable and resolves dissid after refresh',
    () async {
      final api = _QqCreatePlaylistApi();
      final platform = QqPlatform(api: api);
      await platform.restoreSession(
        _MemorySessionStorage(
          user: const User(
            id: '123456',
            nickname: 'QQ User',
            platform: PlatformType.qq,
          ),
        ),
      );

      final playlist = await platform.createPlaylist('新歌单');

      expect(playlist, isNotNull);
      expect(playlist!.id, '999999');
      expect(playlist.editableId, '34');
      expect(playlist.name, '新歌单');
    },
  );

  test(
    'QQ create playlist returns null when only an unstable dirid is available',
    () async {
      final platform = QqPlatform(api: _QqCreateWithoutDissidApi());
      await platform.restoreSession(
        _MemorySessionStorage(
          user: const User(
            id: '123456',
            nickname: 'QQ User',
            platform: PlatformType.qq,
          ),
        ),
      );

      final playlist = await platform.createPlaylist('12');

      expect(playlist, isNull);
    },
  );

  test(
    'QQ import falls back to legacy public playlist detail endpoint',
    () async {
      final api = _QqLegacyImportApi();
      final platform = QqPlatform(api: api);

      final playlist = await platform.parseShareLink(
        'https://y.qq.com/n3/other/pages/details/playlist.html?platform=11'
        '&appshare=android_qq&id=9333150211&ADTAG=wxfshare',
      );
      final songs = await platform.getPlaylistDetail('9333150211');

      expect(api.primaryRequests, ['9333150211', '9333150211']);
      expect(api.legacyRequests, ['9333150211', '9333150211']);
      expect(playlist, isNotNull);
      expect(playlist!.id, '9333150211');
      expect(playlist.name, 'Legacy Imported QQ Playlist');
      expect(playlist.songCount, 779);
      expect(songs, hasLength(1));
      expect(songs.single.id, 'legacy-song-mid');
      expect(songs.single.name, 'Legacy QQ Song');
    },
  );

  test(
    'QQ import still uses legacy endpoint when modern detail throws',
    () async {
      final platform = QqPlatform(api: _QqThrowingModernLegacyApi());

      final playlist = await platform.parseShareLink(
        'https://y.qq.com/n3/other/pages/details/playlist.html?id=9333150211',
      );
      final songs = await platform.getPlaylistDetail('9333150211');

      expect(playlist, isNotNull);
      expect(playlist!.songCount, 1);
      expect(songs, hasLength(1));
      expect(songs.single.name, 'Legacy After Throw');
    },
  );

  test(
    'QQ playlist detail loads all modern pages beyond the first 200 songs',
    () async {
      final api = _QqPagedPlaylistApi(total: 450);
      final songs = await QqPlatform(api: api).getPlaylistDetail('450');

      expect(songs, hasLength(450));
      expect(songs.first.id, 'mid-0');
      expect(songs.last.id, 'mid-449');
      expect(api.requestedPages, [
        (begin: 0, count: 200),
        (begin: 200, count: 200),
        (begin: 400, count: 200),
      ]);
    },
  );
}

class _MemorySessionStorage extends SessionStorage {
  final User? user;

  _MemorySessionStorage({this.user});

  @override
  Future<String?> loadCookie(PlatformType platform) async => null;

  @override
  Future<User?> loadUser(PlatformType platform) async => user;
}

class _QqPlaylistApi extends QqApi {
  final requestedPlaylistIds = <String>[];

  @override
  Future<Map<String, dynamic>> getUserPlaylists(String uin) async {
    return {
      'data': {
        'disslist': [
          {
            'dirid': 12,
            'dissid': 888888,
            'diss_name': 'My QQ Playlist',
            'song_cnt': 780,
          },
        ],
      },
    };
  }

  @override
  Future<Map<String, dynamic>> getPlaylistDetail(
    String disstid, {
    int songBegin = 0,
    int songNum = 200,
  }) async {
    requestedPlaylistIds.add(disstid);
    if (disstid != '888888') {
      return {
        'req_0': {
          'data': {'songlist': []},
        },
      };
    }
    return {
      'req_0': {
        'data': {
          'songlist': [
            {
              'songInfo': {
                'mid': 'song-mid-1',
                'name': 'Song 1',
                'singer': [
                  {'mid': 'artist-mid-1', 'name': 'Artist 1'},
                ],
                'interval': 200,
              },
            },
          ],
        },
      },
    };
  }
}

class _QqCdlistPlaylistApi extends QqApi {
  @override
  Future<Map<String, dynamic>> getPlaylistDetail(
    String disstid, {
    int songBegin = 0,
    int songNum = 200,
  }) async {
    return {
      'cdlist': [
        {
          'songlist': [
            {
              'songmid': 'song-mid-legacy',
              'songname': 'Legacy Song',
              'singer': [
                {'mid': 'artist-mid-legacy', 'name': 'Legacy Artist'},
              ],
              'interval': 210,
            },
          ],
        },
      ],
    };
  }
}

class _QqCreatePlaylistApi extends QqApi {
  @override
  Future<Map<String, dynamic>> createPlaylist(String name) async {
    return {'code': 0, 'dirid': 34};
  }

  @override
  Future<Map<String, dynamic>> getUserPlaylists(String uin) async {
    return {
      'data': {
        'disslist': [
          {'dirid': 34, 'dissid': 999999, 'diss_name': '新歌单', 'song_cnt': 0},
        ],
      },
    };
  }
}

class _QqCreateWithoutDissidApi extends QqApi {
  @override
  Future<Map<String, dynamic>> createPlaylist(String name) async {
    return {'code': 0, 'dirid': 12};
  }

  @override
  Future<Map<String, dynamic>> getUserPlaylists(String uin) async {
    return {
      'data': {
        'disslist': [
          {'dirid': 12, 'dissid': '', 'diss_name': '12', 'song_cnt': 0},
        ],
      },
    };
  }
}

class _QqLegacyImportApi extends QqApi {
  final primaryRequests = <String>[];
  final legacyRequests = <String>[];

  @override
  Future<Map<String, dynamic>> getPlaylistDetail(
    String disstid, {
    int songBegin = 0,
    int songNum = 200,
  }) async {
    primaryRequests.add(disstid);
    return {
      'req_0': {
        'data': {
          'dirinfo': {'title': 'Empty Modern Detail'},
          'songlist': [],
        },
      },
    };
  }

  @override
  Future<Map<String, dynamic>> getLegacyPlaylistDetail(String disstid) async {
    legacyRequests.add(disstid);
    return {
      'code': 0,
      'cdlist': [
        {
          'dissname': 'Legacy Imported QQ Playlist',
          'songnum': 779,
          'logo': 'https://example.test/qq.jpg',
          'songlist': [
            {
              'songmid': 'legacy-song-mid',
              'songname': 'Legacy QQ Song',
              'singer': [
                {'mid': 'legacy-artist-mid', 'name': 'Legacy QQ Artist'},
              ],
              'interval': 180,
            },
          ],
        },
      ],
    };
  }
}

class _QqThrowingModernLegacyApi extends QqApi {
  @override
  Future<Map<String, dynamic>> getPlaylistDetail(
    String disstid, {
    int songBegin = 0,
    int songNum = 200,
  }) async {
    throw Exception('modern detail unavailable');
  }

  @override
  Future<Map<String, dynamic>> getLegacyPlaylistDetail(String disstid) async {
    return {
      'cdlist': [
        {
          'dissname': 'Legacy Fallback',
          'songnum': 1,
          'songlist': [
            {
              'songmid': 'legacy-after-throw',
              'songname': 'Legacy After Throw',
              'singer': [
                {'mid': 'artist-mid', 'name': 'Artist'},
              ],
            },
          ],
        },
      ],
    };
  }
}

class _QqPagedPlaylistApi extends QqApi {
  final int total;
  final requestedPages = <({int begin, int count})>[];

  _QqPagedPlaylistApi({required this.total});

  @override
  Future<Map<String, dynamic>> getPlaylistDetail(
    String disstid, {
    int songBegin = 0,
    int songNum = 200,
  }) async {
    requestedPages.add((begin: songBegin, count: songNum));
    final end = (songBegin + songNum).clamp(0, total);
    return {
      'req_0': {
        'data': {
          'dirinfo': {'songnum': total, 'title': 'Paged QQ Playlist'},
          'songlist': [
            for (var i = songBegin; i < end; i++)
              {
                'songInfo': {
                  'mid': 'mid-$i',
                  'name': 'Song $i',
                  'singer': [
                    {'mid': 'artist', 'name': 'Artist'},
                  ],
                  'interval': 180,
                },
              },
          ],
        },
      },
    };
  }
}
