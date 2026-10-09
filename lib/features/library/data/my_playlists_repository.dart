import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../models/album.dart';
import '../../../models/artist.dart';
import '../../../models/platform_type.dart';
import '../../../models/playlist.dart';
import '../../../models/song.dart';

class MyPlaylistsRepository {
  static const _fileName = 'my_playlists.json';
  static const _shareScheme = 'mconnect';
  static const _shareHost = 'playlist';
  final Directory? storageDirectory;

  const MyPlaylistsRepository({this.storageDirectory});

  Future<List<Playlist>> getPlaylists() async {
    final state = await _readState();
    final playlists = state.playlists.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return playlists.map(_entryToPlaylist).toList();
  }

  Future<Playlist> createPlaylist(String name) async {
    final trimmedName = name.trim().isEmpty ? '未命名歌单' : name.trim();
    final state = await _readState();
    final now = DateTime.now().millisecondsSinceEpoch;
    var id = 'my_$now';
    var suffix = 0;
    while (state.playlists.containsKey(id)) {
      suffix += 1;
      id = 'my_${now}_$suffix';
    }
    final entry = _StoredPlaylist(
      id: id,
      name: trimmedName,
      createdAt: now,
      updatedAt: now,
      songKeys: const [],
    );
    state.playlists[id] = entry;
    await _writeState(state);
    return _entryToPlaylist(entry);
  }

  Future<Playlist> importPlaylist({
    required String name,
    required List<Song> songs,
  }) async {
    final trimmedName = name.trim().isEmpty ? '未命名歌单' : name.trim();
    final state = await _readState();
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = _newPlaylistId(state, now);
    final songKeys = <String>[];
    for (final song in songs) {
      final key = _songKey(song);
      state.songs[key] = _songToStoredSong(song);
      if (!songKeys.contains(key)) songKeys.add(key);
    }
    final entry = _StoredPlaylist(
      id: id,
      name: trimmedName,
      createdAt: now,
      updatedAt: now,
      songKeys: songKeys,
    );
    state.playlists[id] = entry;
    await _writeState(state);
    return _entryToPlaylist(entry);
  }

  Future<Playlist?> getPlaylist(String playlistId) async {
    final state = await _readState();
    final entry = state.playlists[playlistId];
    return entry == null ? null : _entryToPlaylist(entry);
  }

  Future<List<Song>> getSongs(String playlistId) async {
    final state = await _readState();
    final playlist = state.playlists[playlistId];
    if (playlist == null) return const [];
    return playlist.songKeys
        .map((key) => state.songs[key])
        .whereType<_StoredSong>()
        .map(_storedSongToSong)
        .toList();
  }

  Future<bool> addSong(String playlistId, Song song) async {
    final state = await _readState();
    final playlist = state.playlists[playlistId];
    if (playlist == null) return false;

    final key = _songKey(song);
    state.songs[key] = _songToStoredSong(song);
    if (!playlist.songKeys.contains(key)) {
      playlist.songKeys.add(key);
      playlist.updatedAt = DateTime.now().millisecondsSinceEpoch;
    }
    await _writeState(state);
    return true;
  }

  Future<bool> removeSong(String playlistId, Song song) async {
    final state = await _readState();
    final playlist = state.playlists[playlistId];
    if (playlist == null) return false;
    final removed = playlist.songKeys.remove(_songKey(song));
    if (!removed) return false;
    playlist.updatedAt = DateTime.now().millisecondsSinceEpoch;
    _removeUnreferencedSongs(state);
    await _writeState(state);
    return true;
  }

  Future<bool> deletePlaylist(String playlistId) async {
    final state = await _readState();
    final removed = state.playlists.remove(playlistId);
    if (removed == null) return false;
    _removeUnreferencedSongs(state);
    await _writeState(state);
    return true;
  }

  /// Renames a local playlist. Returns false when it does not exist.
  ///
  /// An empty/whitespace name is rejected rather than silently becoming
  /// "未命名歌单": renaming to blank is almost certainly a mistake, and quietly
  /// substituting text the user did not type is worse than refusing.
  Future<bool> renamePlaylist(String playlistId, String newName) async {
    final trimmed = newName.trim();
    if (trimmed.isEmpty) return false;
    final state = await _readState();
    final playlist = state.playlists[playlistId];
    if (playlist == null) return false;
    playlist.name = trimmed;
    playlist.updatedAt = DateTime.now().millisecondsSinceEpoch;
    await _writeState(state);
    return true;
  }

  /// Copies a local playlist (songs included) under a new name.
  ///
  /// Reuses [importPlaylist] so the copy goes through exactly one code path for
  /// "materialise a playlist from a song list" — duplicating the song-key logic
  /// here would be a second way to get it wrong. Returns null when the source
  /// does not exist.
  ///
  /// [nameSuffix] is passed in by the caller rather than built here: this layer has
  /// no `BuildContext`, and the i18n ratchet counts hard-coded Chinese literals, so
  /// the visible suffix ("副本" / "copy") belongs to the presentation layer.
  Future<Playlist?> duplicatePlaylist(
    String playlistId, {
    String? newName,
    String nameSuffix = '',
  }) async {
    final source = await getPlaylist(playlistId);
    if (source == null) return null;
    final songs = await getSongs(playlistId);
    final name = (newName?.trim().isNotEmpty ?? false)
        ? newName!.trim()
        : '${source.name} $nameSuffix'.trim();
    return importPlaylist(name: name, songs: songs);
  }

  /// Persists a new song order for [playlistId] (drag-to-reorder).
  ///
  /// [ordered] is the full desired order. Keys that are not already in the
  /// playlist are ignored, duplicates collapse, and any song the caller left out
  /// keeps its relative position at the end — a partial or slightly wrong list
  /// must never lose a song. The whole playlist is replaced and written with the
  /// single atomic write of [_writeState], so a crash can leave the old order,
  /// never a half-applied one.
  ///
  /// Returns false when [playlistId] does not exist.
  Future<bool> reorderSongs(String playlistId, List<Song> ordered) async {
    final state = await _readState();
    final playlist = state.playlists[playlistId];
    if (playlist == null) return false;

    final existing = playlist.songKeys.toSet();
    final keys = <String>[];
    for (final song in ordered) {
      final key = _songKey(song);
      if (existing.contains(key) && !keys.contains(key)) {
        keys.add(key);
      }
    }
    for (final key in playlist.songKeys) {
      if (!keys.contains(key)) keys.add(key);
    }

    if (_sameOrder(playlist.songKeys, keys)) return true;

    // Replaced rather than mutated in place: `songKeys` may be the `const []`
    // created by [createPlaylist] (an unmodifiable list), and a caller holding
    // the old entry must keep seeing the old order.
    state.playlists[playlistId] = _StoredPlaylist(
      id: playlist.id,
      name: playlist.name,
      createdAt: playlist.createdAt,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
      songKeys: keys,
    );
    await _writeState(state);
    return true;
  }

  static bool _sameOrder(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Future<String?> exportPlaylistLink(String playlistId) async {
    final state = await _readState();
    final playlist = state.playlists[playlistId];
    if (playlist == null) return null;
    final songs = playlist.songKeys
        .map((key) => state.songs[key])
        .whereType<_StoredSong>()
        .map((song) => song.toJson())
        .toList(growable: false);
    return encodeShareLink(
      name: playlist.name,
      songsJson: songs,
    );
  }

  Future<Playlist?> importShareLink(String link) async {
    final decoded = decodeShareLink(link);
    if (decoded == null) return null;
    return importPlaylist(name: decoded.name, songs: decoded.songs);
  }

  static String encodeShareLink({
    required String name,
    required List<Map<String, dynamic>> songsJson,
  }) {
    final payload = {
      'version': 1,
      'name': name,
      'songs': songsJson,
    };
    final data = base64UrlEncode(utf8.encode(jsonEncode(payload)));
    return Uri(scheme: _shareScheme, host: _shareHost, queryParameters: {
      'data': data,
    }).toString();
  }

  static DecodedPlaylistShare? decodeShareLink(String link) {
    final uri = Uri.tryParse(link.trim());
    if (uri == null || uri.scheme != _shareScheme || uri.host != _shareHost) {
      return null;
    }
    final data = uri.queryParameters['data'];
    if (data == null || data.isEmpty) return null;
    try {
      final decoded = utf8.decode(base64Url.decode(data));
      final json = jsonDecode(decoded) as Map<String, dynamic>;
      final name = json['name']?.toString() ?? '导入歌单';
      final rawSongs = json['songs'] as List<dynamic>? ?? const [];
      final songs = rawSongs
          .whereType<Map<String, dynamic>>()
          .map(_StoredSong.fromJson)
          .map(_storedSongToSong)
          .toList(growable: false);
      return DecodedPlaylistShare(name: name, songs: songs);
    } catch (_) {
      return null;
    }
  }

  Future<File> _file() async {
    final dir =
        storageDirectory ?? await getApplicationDocumentsDirectory();
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return File(p.join(dir.path, _fileName));
  }

  Future<_MyPlaylistsState> _readState() async {
    final file = await _file();
    if (!await file.exists()) return _MyPlaylistsState.empty();
    try {
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return _MyPlaylistsState.empty();
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return _MyPlaylistsState.fromJson(json);
    } catch (_) {
      return _MyPlaylistsState.empty();
    }
  }

  Future<void> _writeState(_MyPlaylistsState state) async {
    final file = await _file();
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(jsonEncode(state.toJson()), flush: true);
    if (await file.exists()) {
      await file.delete();
    }
    await temp.rename(file.path);
  }

  Playlist _entryToPlaylist(_StoredPlaylist entry) {
    return Playlist(
      id: entry.id,
      name: entry.name,
      platform: PlatformType.local,
      songCount: entry.songKeys.length,
      editable: true,
      editId: entry.id,
    );
  }

  String _newPlaylistId(_MyPlaylistsState state, int now) {
    var id = 'my_$now';
    var suffix = 0;
    while (state.playlists.containsKey(id)) {
      suffix += 1;
      id = 'my_${now}_$suffix';
    }
    return id;
  }

  void _removeUnreferencedSongs(_MyPlaylistsState state) {
    final referenced = <String>{
      for (final playlist in state.playlists.values) ...playlist.songKeys,
    };
    state.songs.removeWhere((key, _) => !referenced.contains(key));
  }

  static String _songKey(Song song) => '${song.platform.name}:${song.id}';

  static _StoredSong _songToStoredSong(Song song) {
    return _StoredSong(
      id: song.id,
      platform: song.platform.name,
      name: song.name,
      artists: song.artists.map((a) => a.name).toList(),
      albumName: song.album?.name,
      albumCover: song.coverUrl ?? song.album?.coverUrl,
      durationMs: song.duration.inMilliseconds,
    );
  }

  static Song _storedSongToSong(_StoredSong song) {
    final platform = PlatformType.values.firstWhere(
      (p) => p.name == song.platform,
      orElse: () => PlatformType.netease,
    );
    return Song(
      id: song.id,
      platform: platform,
      name: song.name,
      artists: song.artists.isEmpty
          ? const [Artist(id: '', name: '未知歌手')]
          : song.artists.map((name) => Artist(id: '', name: name)).toList(),
      album: song.albumName == null
          ? null
          : Album(id: '', name: song.albumName!, coverUrl: song.albumCover),
      duration: Duration(milliseconds: song.durationMs),
      coverUrl: song.albumCover,
    );
  }
}

class DecodedPlaylistShare {
  final String name;
  final List<Song> songs;

  const DecodedPlaylistShare({required this.name, required this.songs});
}

class _MyPlaylistsState {
  final Map<String, _StoredPlaylist> playlists;
  final Map<String, _StoredSong> songs;

  _MyPlaylistsState({required this.playlists, required this.songs});

  factory _MyPlaylistsState.empty() {
    return _MyPlaylistsState(playlists: {}, songs: {});
  }

  factory _MyPlaylistsState.fromJson(Map<String, dynamic> json) {
    final playlistsJson = json['playlists'] as List<dynamic>? ?? const [];
    final songsJson = json['songs'] as Map<String, dynamic>? ?? const {};
    return _MyPlaylistsState(
      playlists: _parsePlaylists(playlistsJson),
      songs: {
        for (final entry in songsJson.entries)
          if (entry.value is Map<String, dynamic>)
            entry.key: _StoredSong.fromJson(entry.value as Map<String, dynamic>),
      },
    );
  }

  static Map<String, _StoredPlaylist> _parsePlaylists(List<dynamic> items) {
    final result = <String, _StoredPlaylist>{};
    for (final item in items) {
      if (item is! Map<String, dynamic>) continue;
      final playlist = _StoredPlaylist.fromJson(item);
      if (playlist.id.isNotEmpty) {
        result[playlist.id] = playlist;
      }
    }
    return result;
  }

  Map<String, dynamic> toJson() {
    return {
      'version': 1,
      'playlists': playlists.values.map((p) => p.toJson()).toList(),
      'songs': songs.map((key, value) => MapEntry(key, value.toJson())),
    };
  }
}

class _StoredPlaylist {
  final String id;

  /// Mutable so [MyPlaylistsRepository.renamePlaylist] can update it in place,
  /// the same way [updatedAt] is bumped on every mutation.
  String name;

  final int createdAt;
  int updatedAt;
  final List<String> songKeys;

  _StoredPlaylist({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    required this.songKeys,
  });

  factory _StoredPlaylist.fromJson(Map<String, dynamic> json) {
    return _StoredPlaylist(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '未命名歌单',
      createdAt: int.tryParse(json['createdAt']?.toString() ?? '') ?? 0,
      updatedAt: int.tryParse(json['updatedAt']?.toString() ?? '') ?? 0,
      songKeys: (json['songKeys'] as List<dynamic>? ?? const [])
          .map((key) => key.toString())
          .where((key) => key.isNotEmpty)
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'songKeys': songKeys,
    };
  }
}

class _StoredSong {
  final String id;
  final String platform;
  final String name;
  final List<String> artists;
  final String? albumName;
  final String? albumCover;
  final int durationMs;

  const _StoredSong({
    required this.id,
    required this.platform,
    required this.name,
    required this.artists,
    this.albumName,
    this.albumCover,
    required this.durationMs,
  });

  factory _StoredSong.fromJson(Map<String, dynamic> json) {
    return _StoredSong(
      id: json['id']?.toString() ?? '',
      platform: json['platform']?.toString() ?? PlatformType.netease.name,
      name: json['name']?.toString() ?? '',
      artists: (json['artists'] as List<dynamic>? ?? const [])
          .map((artist) => artist.toString())
          .where((artist) => artist.isNotEmpty)
          .toList(),
      albumName: json['albumName']?.toString(),
      albumCover: json['albumCover']?.toString(),
      durationMs: int.tryParse(json['durationMs']?.toString() ?? '') ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'platform': platform,
      'name': name,
      'artists': artists,
      'albumName': albumName,
      'albumCover': albumCover,
      'durationMs': durationMs,
    };
  }
}
