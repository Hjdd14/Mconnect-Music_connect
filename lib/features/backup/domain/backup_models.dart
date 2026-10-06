import '../../../models/album.dart';
import '../../../models/artist.dart';
import '../../../models/platform_type.dart';
import '../../../models/song.dart';

/// Current on-disk backup format. Bump when the JSON shape changes in a way an
/// older reader could misread; the importer rejects a newer version instead of
/// silently importing half of it.
const int backupFormatVersion = 1;

/// The first thing in every backup file, so a wrong/hostile file is rejected
/// before anything is written.
class BackupManifest {
  final int version;
  final DateTime exportedAt;
  final String appVersion;

  /// `AppDatabase.schemaVersion` at export time. Informational: the importer
  /// works on rows, not on schema versions.
  final int schemaVersion;

  const BackupManifest({
    required this.version,
    required this.exportedAt,
    required this.appVersion,
    required this.schemaVersion,
  });

  Map<String, dynamic> toJson() => {
    'version': version,
    'exportedAt': exportedAt.toIso8601String(),
    'appVersion': appVersion,
    'schemaVersion': schemaVersion,
  };

  static BackupManifest fromJson(dynamic value) {
    if (value is! Map) {
      throw const BackupFormatException('备份文件缺少 manifest 段');
    }
    final version = _int(value['version']);
    if (version == null) {
      throw const BackupFormatException('备份文件缺少 manifest.version');
    }
    if (version > backupFormatVersion) {
      throw BackupFormatException(
        '备份格式版本 $version 高于当前支持的 $backupFormatVersion，请升级应用后再导入',
      );
    }
    return BackupManifest(
      version: version,
      exportedAt:
          DateTime.tryParse(value['exportedAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      appVersion: value['appVersion']?.toString() ?? '',
      schemaVersion: _int(value['schemaVersion']) ?? 0,
    );
  }
}

class BackupSong {
  final String id;
  final String platform;
  final String name;
  final String artists;
  final String? albumName;
  final String? albumCover;
  final int durationMs;
  final String fingerprint;
  final String? albumId;
  final String? artistId;
  final int? trackNumber;

  const BackupSong({
    required this.id,
    required this.platform,
    required this.name,
    required this.artists,
    this.albumName,
    this.albumCover,
    this.durationMs = 0,
    this.fingerprint = '',
    this.albumId,
    this.artistId,
    this.trackNumber,
  });

  String get key => '$platform:$id';

  /// Serialises a domain song (used for the playlists section, which stores the
  /// full song rather than only a key so a restore does not depend on rows the
  /// local cache may have dropped).
  factory BackupSong.fromSong(Song song) {
    return BackupSong(
      id: song.id,
      platform: song.platform.name,
      name: song.name,
      artists: song.artists.map((artist) => artist.name).join(','),
      albumName: song.album?.name,
      albumCover: song.coverUrl ?? song.album?.coverUrl,
      durationMs: song.duration.inMilliseconds,
      fingerprint: song.fingerprint,
      albumId: song.albumId ?? _nullIfEmpty(song.album?.id),
      artistId:
          song.artistId ??
          (song.artists.isEmpty ? null : _nullIfEmpty(song.artists.first.id)),
      trackNumber: song.trackNumber,
    );
  }

  Song toSong() {
    final names = artists
        .split(',')
        .map((name) => name.trim())
        .where((name) => name.isNotEmpty)
        .toList();
    return Song(
      id: id,
      platform: PlatformType.tryParse(platform) ?? PlatformType.netease,
      name: name,
      artists: [
        for (final artistName in names)
          Artist(
            id: names.length == 1 ? (artistId ?? '') : '',
            name: artistName,
          ),
      ],
      album: albumName == null
          ? null
          : Album(id: albumId ?? '', name: albumName!, coverUrl: albumCover),
      duration: Duration(milliseconds: durationMs),
      coverUrl: albumCover,
      albumId: albumId,
      artistId: artistId,
      trackNumber: trackNumber,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'platform': platform,
    'name': name,
    'artists': artists,
    'albumName': albumName,
    'albumCover': albumCover,
    'durationMs': durationMs,
    'fingerprint': fingerprint,
    'albumId': albumId,
    'artistId': artistId,
    'trackNumber': trackNumber,
  };

  static BackupSong fromJson(dynamic value) {    if (value is! Map) {
      throw const BackupFormatException('backup.songs 里存在非法条目');
    }
    final id = value['id']?.toString() ?? '';
    final platform = value['platform']?.toString() ?? '';
    if (id.isEmpty || platform.isEmpty) {
      throw const BackupFormatException('backup.songs 条目缺少 id/platform');
    }
    return BackupSong(
      id: id,
      platform: platform,
      name: value['name']?.toString() ?? '',
      artists: value['artists']?.toString() ?? '',
      albumName: _string(value['albumName']),
      albumCover: _string(value['albumCover']),
      durationMs: _int(value['durationMs']) ?? 0,
      fingerprint: value['fingerprint']?.toString() ?? '',
      albumId: _string(value['albumId']),
      artistId: _string(value['artistId']),
      trackNumber: _int(value['trackNumber']),
    );
  }

  /// Cross-platform identity used to merge the same recording coming from two
  /// platforms. Mirrors `Song.dedupeKey` so the database path and the in-memory
  /// path agree.
  String get dedupeKey => Song(
    id: id,
    platform: PlatformType.tryParse(platform) ?? PlatformType.netease,
    name: name,
    artists: artists
        .split(',')
        .map((name) => name.trim())
        .where((name) => name.isNotEmpty)
        .map((name) => Artist(id: '', name: name))
        .toList(),
    duration: Duration(milliseconds: durationMs),
  ).dedupeKey;
}

class BackupLike {
  final String songId;
  final String platform;
  final int addedAt;

  const BackupLike({
    required this.songId,
    required this.platform,
    required this.addedAt,
  });

  String get key => '$platform:$songId';

  Map<String, dynamic> toJson() => {
    'songId': songId,
    'platform': platform,
    'addedAt': addedAt,
  };

  static BackupLike fromJson(dynamic value) {
    if (value is! Map) {
      throw const BackupFormatException('backup.likes 里存在非法条目');
    }
    final songId = value['songId']?.toString() ?? '';
    final platform = value['platform']?.toString() ?? '';
    if (songId.isEmpty || platform.isEmpty) {
      throw const BackupFormatException('backup.likes 条目缺少 songId/platform');
    }
    return BackupLike(
      songId: songId,
      platform: platform,
      addedAt: _int(value['addedAt']) ?? 0,
    );
  }
}

class BackupPlaylist {
  final String id;
  final String name;
  final int createdAt;
  final int updatedAt;
  final List<BackupSong> songs;

  const BackupPlaylist({
    required this.id,
    required this.name,
    this.createdAt = 0,
    this.updatedAt = 0,
    this.songs = const [],
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
    'songs': songs.map((song) => song.toJson()).toList(),
  };

  static BackupPlaylist fromJson(dynamic value) {
    if (value is! Map) {
      throw const BackupFormatException('backup.playlists 里存在非法条目');
    }
    final name = value['name']?.toString().trim() ?? '';
    if (name.isEmpty) {
      throw const BackupFormatException('backup.playlists 条目缺少 name');
    }
    final rawSongs = value['songs'];
    return BackupPlaylist(
      id: value['id']?.toString() ?? '',
      name: name,
      createdAt: _int(value['createdAt']) ?? 0,
      updatedAt: _int(value['updatedAt']) ?? 0,
      songs: rawSongs is List
          ? rawSongs.map(BackupSong.fromJson).toList()
          : const [],
    );
  }
}

class BackupPlayEvent {
  final String songId;
  final String platform;
  final int startedAt;
  final int? endedAt;
  final int durationListened;
  final double completedRatio;
  final String? source;

  const BackupPlayEvent({
    required this.songId,
    required this.platform,
    required this.startedAt,
    this.endedAt,
    this.durationListened = 0,
    this.completedRatio = 0,
    this.source,
  });

  Map<String, dynamic> toJson() => {
    'songId': songId,
    'platform': platform,
    'startedAt': startedAt,
    'endedAt': endedAt,
    'durationListened': durationListened,
    'completedRatio': completedRatio,
    'source': source,
  };

  static BackupPlayEvent fromJson(dynamic value) {
    if (value is! Map) {
      throw const BackupFormatException('backup.playEvents 里存在非法条目');
    }
    final songId = value['songId']?.toString() ?? '';
    final platform = value['platform']?.toString() ?? '';
    final startedAt = _int(value['startedAt']);
    if (songId.isEmpty || platform.isEmpty || startedAt == null) {
      throw const BackupFormatException(
        'backup.playEvents 条目缺少 songId/platform/startedAt',
      );
    }
    return BackupPlayEvent(
      songId: songId,
      platform: platform,
      startedAt: startedAt,
      endedAt: _int(value['endedAt']),
      durationListened: _int(value['durationListened']) ?? 0,
      completedRatio: (_num(value['completedRatio']) ?? 0).toDouble(),
      source: _string(value['source']),
    );
  }
}

/// Everything a backup file carries.
class BackupData {
  final List<BackupSong> songs;
  final List<BackupLike> likes;
  final List<BackupPlaylist> playlists;

  /// Smart-playlist rules, kept as their own JSON (the rule already owns its
  /// serialisation; duplicating the field list here would drift).
  final List<Map<String, dynamic>> smartRules;

  final List<BackupPlayEvent> playEvents;
  final Map<String, dynamic> settings;

  const BackupData({
    this.songs = const [],
    this.likes = const [],
    this.playlists = const [],
    this.smartRules = const [],
    this.playEvents = const [],
    this.settings = const {},
  });

  bool get isEmpty =>
      songs.isEmpty &&
      likes.isEmpty &&
      playlists.isEmpty &&
      smartRules.isEmpty &&
      playEvents.isEmpty &&
      settings.isEmpty;

  Map<String, dynamic> toJson() => {
    'songs': songs.map((song) => song.toJson()).toList(),
    'likes': likes.map((like) => like.toJson()).toList(),
    'playlists': playlists.map((playlist) => playlist.toJson()).toList(),
    'smartRules': smartRules,
    'playEvents': playEvents.map((event) => event.toJson()).toList(),
    'settings': settings,
  };

  static BackupData fromJson(dynamic value) {
    final json = _object(value);
    return BackupData(
      songs: _list(json['songs']).map(BackupSong.fromJson).toList(),
      likes: _list(json['likes']).map(BackupLike.fromJson).toList(),
      playlists: _list(json['playlists']).map(BackupPlaylist.fromJson).toList(),
      smartRules: _list(json['smartRules'])
          .map((item) => Map<String, dynamic>.from(_object(item)))
          .toList(),
      playEvents: _list(
        json['playEvents'],
      ).map(BackupPlayEvent.fromJson).toList(),
      settings: Map<String, dynamic>.from(_object(json['settings'])),
    );
  }
}

/// What an import actually did — shown to the user and asserted by tests.
class BackupImportReport {
  final int songs;
  final int likes;
  final int playEvents;
  final int playlistsCreated;
  final int playlistsMerged;
  final int smartRulesAdded;
  final int smartRulesUpdated;
  final int settingsKeys;

  const BackupImportReport({
    this.songs = 0,
    this.likes = 0,
    this.playEvents = 0,
    this.playlistsCreated = 0,
    this.playlistsMerged = 0,
    this.smartRulesAdded = 0,
    this.smartRulesUpdated = 0,
    this.settingsKeys = 0,
  });

  @override
  String toString() {
    return '歌曲 $songs · 收藏 $likes · 播放明细 $playEvents · '
        '自建歌单 $playlistsCreated 新增/$playlistsMerged 合并 · '
        '智能歌单 $smartRulesAdded 新增/$smartRulesUpdated 更新 · '
        '设置 $settingsKeys 项';
  }
}

class BackupFormatException implements Exception {
  final String message;
  const BackupFormatException(this.message);

  @override
  String toString() => message;
}

Map<String, dynamic> _object(dynamic value) {
  if (value is Map) return Map<String, dynamic>.from(value);
  return const {};
}

List<dynamic> _list(dynamic value) => value is List ? value : const [];

String? _string(dynamic value) {
  if (value == null) return null;
  final text = value.toString();
  return text.isEmpty ? null : text;
}

int? _int(dynamic value) {
  if (value is int) return value;
  return int.tryParse(value?.toString() ?? '');
}

num? _num(dynamic value) {
  if (value is num) return value;
  return num.tryParse(value?.toString() ?? '');
}

String? _nullIfEmpty(String? value) =>
    (value == null || value.isEmpty) ? null : value;
