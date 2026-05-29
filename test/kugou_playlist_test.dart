import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/platform/kugou/kugou_api.dart';
import 'package:mconnect/platform/kugou/kugou_platform.dart';

void main() {
  test('Kugou user playlists parse list_create_list style responses', () async {
    final platform = KugouPlatform(api: _KugouPlaylistApi());

    final playlists = await platform.getUserPlaylists();

    expect(playlists, hasLength(1));
    expect(playlists.single.id, '456789');
    expect(playlists.single.name, 'My Kugou Playlist');
    expect(playlists.single.songCount, 23);
    expect(playlists.single.editable, isTrue);
  });

  test(
    'Kugou playlist detail parses songs from alternate list containers',
    () async {
      final platform = KugouPlatform(api: _KugouPlaylistApi());

      final songs = await platform.getPlaylistDetail('456789');

      expect(songs, hasLength(1));
      expect(songs.single.id, 'HASH1');
      expect(songs.single.name, 'Song 1');
      expect(songs.single.artists.single.name, 'Artist 1');
    },
  );

  test(
    'Kugou user playlists keep global id for detail and listid for editing',
    () async {
      final platform = KugouPlatform(api: _KugouMixedPlaylistApi());

      final playlists = await platform.getUserPlaylists();
      final songs = await platform.getPlaylistDetail(playlists.single.id);

      expect(playlists.single.id, 'global-123');
      expect(playlists.single.editableId, 'list-456');
      expect(songs, hasLength(1));
      expect(songs.single.id, 'HASH_GLOBAL');
    },
  );

  test('Kugou user playlists merge created and collected containers', () async {
    final platform = KugouPlatform(api: _KugouCreatedAndCollectedApi());

    final playlists = await platform.getUserPlaylists();

    expect(playlists.map((p) => p.id), ['created-global', 'collected-global']);
    expect(playlists.map((p) => p.name), ['创建歌单', '收藏歌单']);
  });

  test('Kugou user playlists parse nested list containers', () async {
    final platform = KugouPlatform(api: _KugouNestedPlaylistContainersApi());

    final playlists = await platform.getUserPlaylists();

    expect(playlists.map((p) => p.id), ['nested-created', 'nested-collected']);
    expect(playlists.map((p) => p.name), ['nested create', 'nested collect']);
  });

  test('Kugou playlist detail falls back to user listid endpoint', () async {
    final platform = KugouPlatform(api: _KugouUserListIdApi());

    final songs = await platform.getPlaylistDetail('list-456');

    expect(songs, hasLength(1));
    expect(songs.single.id, 'HASH_LISTID');
  });

  test(
    'Kugou playlist detail extracts listid from collection id when public detail is empty',
    () async {
      final api = _KugouCollectionFallbackApi();
      final songs = await KugouPlatform(
        api: api,
      ).getPlaylistDetail('collection_3_10001_456_0');

      expect(api.userListIds, ['456']);
      expect(songs, hasLength(1));
      expect(songs.single.id, 'HASH_COLLECTION_FALLBACK');
    },
  );

  test(
    'Kugou created playlist refreshes user list instead of returning transient empty id',
    () async {
      final platform = KugouPlatform(api: _KugouCreatePlaylistApi());

      final playlist = await platform.createPlaylist('新建酷狗歌单');

      expect(playlist, isNotNull);
      expect(playlist!.id, 'global-new');
      expect(playlist.editableId, 'list-new');
      expect(playlist.name, '新建酷狗歌单');
    },
  );

  test(
    'Kugou create playlist returns null when no stable detail id is available',
    () async {
      final platform = KugouPlatform(api: _KugouCreateWithoutStableIdApi());

      final playlist = await platform.createPlaylist('12');

      expect(playlist, isNull);
    },
  );

  test(
    'Kugou create playlist does not expose transient listid when refresh misses',
    () async {
      final platform = KugouPlatform(api: _KugouCreateRefreshMissApi());

      final playlist = await platform.createPlaylist('missing after refresh');

      expect(playlist, isNull);
    },
  );

  test(
    'Kugou create playlist does not return a stale playlist with another name',
    () async {
      final platform = KugouPlatform(api: _KugouCreateStaleRefreshApi());

      final playlist = await platform.createPlaylist('new target playlist');

      expect(playlist, isNull);
    },
  );

  test(
    'Kugou create playlist accepts errcode zero success responses',
    () async {
      final platform = KugouPlatform(api: _KugouCreateErrcodeZeroApi());

      final playlist = await platform.createPlaylist('errcode zero playlist');

      expect(playlist, isNotNull);
      expect(playlist!.id, 'global-errcode-zero');
      expect(playlist.editableId, 'list-errcode-zero');
    },
  );

  test(
    'Kugou import resolves t1 short links and loads shared playlist songs',
    () async {
      final api = _KugouShortLinkImportApi();
      final platform = KugouPlatform(api: api);

      final playlist = await platform.parseShareLink(
        'https://t1.kugou.com/9Y4aX8fG1V2',
      );
      final songs = await platform.getPlaylistDetail(
        'collection_3_839387662_2_0',
      );

      expect(api.resolvedUrls, ['https://t1.kugou.com/9Y4aX8fG1V2']);
      expect(api.sharedPlaylistRequests, [
        'collection_3_839387662_2_0',
        'collection_3_839387662_2_0',
      ]);
      expect(playlist, isNotNull);
      expect(playlist!.id, 'collection_3_839387662_2_0');
      expect(playlist.name, 'Kugou Shared Playlist');
      expect(playlist.songCount, 23);
      expect(songs, hasLength(1));
      expect(songs.single.id, 'KUGOUHASH');
      expect(songs.single.name, '花之舞');
      expect(songs.single.artists.single.name, '纯音乐');
    },
  );

  test(
    'Kugou shared playlist detail loads every page beyond the first 100 songs',
    () async {
      final api = _KugouPagedSharedPlaylistApi(total: 250);
      final songs = await KugouPlatform(
        api: api,
      ).getPlaylistDetail('collection_large');

      expect(songs, hasLength(250));
      expect(songs.first.id, 'HASH_0');
      expect(songs.last.id, 'HASH_249');
      expect(api.requests, [
        (page: 1, limit: 100),
        (page: 2, limit: 100),
        (page: 3, limit: 100),
      ]);
    },
  );

  test(
    'Kugou user playlist fallback loads every page beyond the first 100 songs',
    () async {
      final api = _KugouPagedUserPlaylistApi(total: 230);
      final songs = await KugouPlatform(
        api: api,
      ).getPlaylistDetail('list-large');

      expect(songs, hasLength(230));
      expect(songs.first.id, 'USER_HASH_0');
      expect(songs.last.id, 'USER_HASH_229');
      expect(api.publicRequests, [(page: 1, limit: 100)]);
      expect(api.userRequests, [
        (page: 1, limit: 100),
        (page: 2, limit: 100),
        (page: 3, limit: 100),
      ]);
    },
  );
}

class _KugouPlaylistApi extends KugouApi {
  @override
  Future<Map<String, dynamic>> getUserPlaylists({
    int page = 1,
    int limit = 50,
  }) async {
    return {
      'status': 1,
      'data': {
        'list_create_list': [
          {
            'listid': 456789,
            'name': 'My Kugou Playlist',
            'count': 23,
            'pic': 'https://example.test/{size}.jpg',
          },
        ],
      },
    };
  }

  @override
  Future<Map<String, dynamic>> getPlaylistSongs(
    String specialid, {
    int page = 1,
    int limit = 100,
  }) async {
    return {
      'status': 1,
      'data': {
        'songs': [
          {
            'hash': 'HASH1',
            'filename': 'Artist 1 - Song 1',
            'songname': 'Song 1',
            'singername': 'Artist 1',
            'duration': 188,
          },
        ],
      },
    };
  }
}

class _KugouMixedPlaylistApi extends KugouApi {
  @override
  Future<Map<String, dynamic>> getUserPlaylists({
    int page = 1,
    int limit = 50,
  }) async {
    return {
      'status': 1,
      'data': {
        'list_collect_list': [
          {
            'global_collection_id': 'global-123',
            'listid': 'list-456',
            'listname': '收藏歌单',
            'song_num': 1,
          },
        ],
      },
    };
  }

  @override
  Future<Map<String, dynamic>> getPlaylistSongs(
    String specialid, {
    int page = 1,
    int limit = 100,
  }) async {
    expect(specialid, 'global-123');
    return {
      'status': 1,
      'data': {
        'info': [
          {
            'hash': 'HASH_GLOBAL',
            'songname': 'Global Song',
            'singername': 'Global Artist',
          },
        ],
      },
    };
  }
}

class _KugouUserListIdApi extends KugouApi {
  @override
  Future<Map<String, dynamic>> getPlaylistSongs(
    String specialid, {
    int page = 1,
    int limit = 100,
  }) async {
    return {
      'status': 1,
      'data': {'info': []},
    };
  }

  @override
  Future<Map<String, dynamic>> getUserPlaylistSongs(
    String listid, {
    int page = 1,
    int limit = 100,
  }) async {
    expect(listid, 'list-456');
    return {
      'status': 1,
      'data': {
        'list': [
          {
            'hash': 'HASH_LISTID',
            'songname': 'List Song',
            'singername': 'List Artist',
          },
        ],
      },
    };
  }
}

class _KugouCollectionFallbackApi extends KugouApi {
  final userListIds = <String>[];

  @override
  Future<Map<String, dynamic>> getSharedPlaylistSongs(
    String globalCollectionId, {
    int page = 1,
    int limit = 100,
  }) async {
    return {
      'status': 1,
      'data': {'info': []},
    };
  }

  @override
  Future<Map<String, dynamic>> getUserPlaylistSongs(
    String listid, {
    int page = 1,
    int limit = 100,
  }) async {
    userListIds.add(listid);
    return {
      'status': 1,
      'data': {
        'list': [
          {
            'hash': 'HASH_COLLECTION_FALLBACK',
            'songname': 'Collection Fallback Song',
            'singername': 'Collection Artist',
          },
        ],
      },
    };
  }
}

class _KugouCreatedAndCollectedApi extends KugouApi {
  @override
  Future<Map<String, dynamic>> getUserPlaylists({
    int page = 1,
    int limit = 50,
  }) async {
    return {
      'status': 1,
      'data': {
        'list_create_list': [
          {
            'global_collection_id': 'created-global',
            'listid': 'created-list',
            'listname': '创建歌单',
          },
        ],
        'list_collect_list': [
          {
            'global_collection_id': 'collected-global',
            'listid': 'collected-list',
            'listname': '收藏歌单',
          },
        ],
      },
    };
  }
}

class _KugouNestedPlaylistContainersApi extends KugouApi {
  @override
  Future<Map<String, dynamic>> getUserPlaylists({
    int page = 1,
    int limit = 50,
  }) async {
    return {
      'status': 1,
      'data': {
        'list': {
          'list_create_list': [
            {
              'global_collection_id': 'nested-created',
              'listid': 'nested-created-list',
              'listname': 'nested create',
            },
          ],
          'list_collect_list': [
            {
              'global_collection_id': 'nested-collected',
              'listid': 'nested-collected-list',
              'listname': 'nested collect',
            },
          ],
        },
      },
    };
  }
}

class _KugouCreatePlaylistApi extends KugouApi {
  @override
  Future<Map<String, dynamic>> createPlaylist(String name) async {
    return {
      'status': 1,
      'data': {'listid': 'transient-id'},
    };
  }

  @override
  Future<Map<String, dynamic>> getUserPlaylists({
    int page = 1,
    int limit = 50,
  }) async {
    return {
      'status': 1,
      'data': {
        'list_create_list': [
          {
            'global_collection_id': 'global-new',
            'listid': 'list-new',
            'listname': '新建酷狗歌单',
          },
        ],
      },
    };
  }
}

class _KugouCreateWithoutStableIdApi extends KugouApi {
  @override
  Future<Map<String, dynamic>> createPlaylist(String name) async {
    return {
      'status': 1,
      'data': {'listid': ''},
    };
  }

  @override
  Future<Map<String, dynamic>> getUserPlaylists({
    int page = 1,
    int limit = 50,
  }) async {
    return {
      'status': 1,
      'data': {
        'list_create_list': [
          {'global_collection_id': '', 'listid': '', 'listname': '12'},
        ],
      },
    };
  }
}

class _KugouCreateRefreshMissApi extends KugouApi {
  @override
  Future<Map<String, dynamic>> createPlaylist(String name) async {
    return {
      'status': 1,
      'data': {'listid': 'transient-only'},
    };
  }

  @override
  Future<Map<String, dynamic>> getUserPlaylists({
    int page = 1,
    int limit = 50,
  }) async {
    return {
      'status': 1,
      'data': {'list_create_list': []},
    };
  }
}

class _KugouCreateStaleRefreshApi extends KugouApi {
  @override
  Future<Map<String, dynamic>> createPlaylist(String name) async {
    return {
      'status': 1,
      'data': {'listid': 'transient-only'},
    };
  }

  @override
  Future<Map<String, dynamic>> getUserPlaylists({
    int page = 1,
    int limit = 50,
  }) async {
    return {
      'status': 1,
      'data': {
        'list_create_list': [
          {
            'global_collection_id': 'old-global',
            'listid': 'old-list',
            'listname': 'old playlist',
          },
        ],
      },
    };
  }
}

class _KugouCreateErrcodeZeroApi extends KugouApi {
  @override
  Future<Map<String, dynamic>> createPlaylist(String name) async {
    return {
      'errcode': 0,
      'data': {'listid': 'transient-id'},
    };
  }

  @override
  Future<Map<String, dynamic>> getUserPlaylists({
    int page = 1,
    int limit = 50,
  }) async {
    return {
      'status': 1,
      'data': {
        'list_create_list': [
          {
            'global_collection_id': 'global-errcode-zero',
            'listid': 'list-errcode-zero',
            'listname': 'errcode zero playlist',
          },
        ],
      },
    };
  }
}

class _KugouShortLinkImportApi extends KugouApi {
  final resolvedUrls = <String>[];
  final sharedPlaylistRequests = <String>[];

  @override
  Future<String?> resolveShareUrl(String url) async {
    resolvedUrls.add(url);
    return 'https://activity.kugou.com/share/v-a00a45b0/index.html'
        '?u=839387662&specialid=-2147483648'
        '&global_specialid=collection_3_839387662_2_0&cType=0';
  }

  @override
  Future<Map<String, dynamic>> getSharedPlaylistSongs(
    String globalCollectionId, {
    int page = 1,
    int limit = 100,
  }) async {
    sharedPlaylistRequests.add(globalCollectionId);
    return {
      'status': 1,
      'data': {
        'count': 23,
        'specialname': 'Kugou Shared Playlist',
        'info': [
          {
            'hash': 'KUGOUHASH',
            'name': '纯音乐 - 花之舞',
            'singerinfo': [
              {'name': '纯音乐'},
            ],
            'timelen': 178000,
            'cover': 'https://example.test/kugou.jpg',
          },
        ],
      },
    };
  }
}

class _KugouPagedSharedPlaylistApi extends KugouApi {
  final int total;
  final requests = <({int page, int limit})>[];

  _KugouPagedSharedPlaylistApi({required this.total});

  @override
  Future<Map<String, dynamic>> getSharedPlaylistSongs(
    String globalCollectionId, {
    int page = 1,
    int limit = 100,
  }) async {
    requests.add((page: page, limit: limit));
    final start = (page - 1) * limit;
    final end = (start + limit).clamp(0, total);
    return {
      'status': 1,
      'data': {
        'count': total,
        'info': [
          for (var i = start; i < end; i++)
            {'hash': 'HASH_$i', 'songname': 'Song $i', 'singername': 'Artist'},
        ],
      },
    };
  }
}

class _KugouPagedUserPlaylistApi extends KugouApi {
  final int total;
  final publicRequests = <({int page, int limit})>[];
  final userRequests = <({int page, int limit})>[];

  _KugouPagedUserPlaylistApi({required this.total});

  @override
  Future<Map<String, dynamic>> getPlaylistSongs(
    String specialid, {
    int page = 1,
    int limit = 100,
  }) async {
    publicRequests.add((page: page, limit: limit));
    return {
      'status': 1,
      'data': {'info': []},
    };
  }

  @override
  Future<Map<String, dynamic>> getUserPlaylistSongs(
    String listid, {
    int page = 1,
    int limit = 100,
  }) async {
    userRequests.add((page: page, limit: limit));
    final start = (page - 1) * limit;
    final end = (start + limit).clamp(0, total);
    return {
      'status': 1,
      'data': {
        'total': total,
        'list': [
          for (var i = start; i < end; i++)
            {
              'hash': 'USER_HASH_$i',
              'songname': 'User Song $i',
              'singername': 'User Artist',
            },
        ],
      },
    };
  }
}
