import 'package:hive_flutter/hive_flutter.dart';

import '../../../models/album.dart';
import '../../../models/artist.dart';
import '../../../models/audio_quality.dart';
import '../../../models/platform_type.dart';
import '../../../models/song.dart';

class PlayerPlaybackMemory {
  final Song currentSong;
  final List<Song> playlist;
  final int currentIndex;
  final Duration position;
  final Duration duration;
  final AudioLevel currentQuality;
  final DateTime savedAt;

  PlayerPlaybackMemory({
    required this.currentSong,
    required this.playlist,
    required this.currentIndex,
    required this.position,
    required this.duration,
    required this.currentQuality,
    DateTime? savedAt,
  }) : savedAt = savedAt ?? DateTime.now();

  Map<String, dynamic> toJson() {
    return {
      'currentSong': _songToJson(currentSong),
      'playlist': playlist.map(_songToJson).toList(),
      'currentIndex': currentIndex,
      'positionMs': position.inMilliseconds,
      'durationMs': duration.inMilliseconds,
      'currentQuality': currentQuality.name,
      'savedAt': savedAt.toIso8601String(),
    };
  }

  static PlayerPlaybackMemory? fromJson(dynamic value) {
    if (value is! Map) return null;
    final song = _songFromJson(value['currentSong']);
    if (song == null) return null;
    final rawPlaylist = value['playlist'];
    final playlist = rawPlaylist is List
        ? rawPlaylist.map(_songFromJson).whereType<Song>().toList()
        : <Song>[];
    final effectivePlaylist = playlist.isEmpty ? [song] : playlist;
    final index = _intValue(value['currentIndex']) ?? 0;
    return PlayerPlaybackMemory(
      currentSong: song,
      playlist: effectivePlaylist,
      currentIndex: index.clamp(0, effectivePlaylist.length - 1),
      position: Duration(milliseconds: _intValue(value['positionMs']) ?? 0),
      duration: Duration(milliseconds: _intValue(value['durationMs']) ?? 0),
      currentQuality: _audioLevelFromName(value['currentQuality']),
      savedAt: DateTime.tryParse(value['savedAt']?.toString() ?? ''),
    );
  }

  static Map<String, dynamic> _songToJson(Song song) {
    return {
      'id': song.id,
      'platform': song.platform.name,
      'name': song.name,
      'artists': song.artists
          .map(
            (artist) => {
              'id': artist.id,
              'name': artist.name,
              'avatarUrl': artist.avatarUrl,
            },
          )
          .toList(),
      'album': song.album == null
          ? null
          : {
              'id': song.album!.id,
              'name': song.album!.name,
              'artistName': song.album!.artistName,
              'coverUrl': song.album!.coverUrl,
              'releaseDate': song.album!.releaseDate?.toIso8601String(),
            },
      'durationMs': song.duration.inMilliseconds,
      'coverUrl': song.coverUrl,
      'availableQualities': song.availableQualities
          .map(
            (quality) => {
              'level': quality.level.name,
              'bitrate': quality.bitrate,
              'format': quality.format,
              'size': quality.size,
            },
          )
          .toList(),
    };
  }

  static Song? _songFromJson(dynamic value) {
    if (value is! Map) return null;
    final id = value['id']?.toString() ?? '';
    final name = value['name']?.toString() ?? '';
    if (id.isEmpty || name.isEmpty) return null;
    final platform = _platformFromName(value['platform']);
    final rawArtists = value['artists'];
    final artists = rawArtists is List
        ? rawArtists.map(_artistFromJson).whereType<Artist>().toList()
        : <Artist>[];
    final album = _albumFromJson(value['album']);
    return Song(
      id: id,
      platform: platform,
      name: name,
      artists: artists.isEmpty ? const [Artist(id: '', name: '')] : artists,
      album: album,
      duration: Duration(milliseconds: _intValue(value['durationMs']) ?? 0),
      coverUrl: value['coverUrl']?.toString(),
      availableQualities: _qualitiesFromJson(value['availableQualities']),
    );
  }

  static Artist? _artistFromJson(dynamic value) {
    if (value is! Map) return null;
    return Artist(
      id: value['id']?.toString() ?? '',
      name: value['name']?.toString() ?? '',
      avatarUrl: value['avatarUrl']?.toString(),
    );
  }

  static Album? _albumFromJson(dynamic value) {
    if (value is! Map) return null;
    final id = value['id']?.toString() ?? '';
    final name = value['name']?.toString() ?? '';
    if (id.isEmpty && name.isEmpty) return null;
    return Album(
      id: id,
      name: name,
      artistName: value['artistName']?.toString(),
      coverUrl: value['coverUrl']?.toString(),
      releaseDate: DateTime.tryParse(value['releaseDate']?.toString() ?? ''),
    );
  }

  static List<AudioQuality> _qualitiesFromJson(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map(
          (quality) => AudioQuality(
            level: _audioLevelFromName(quality['level']),
            bitrate: _intValue(quality['bitrate']) ?? 0,
            format: quality['format']?.toString() ?? '',
            size: _intValue(quality['size']),
          ),
        )
        .toList();
  }

  static PlatformType _platformFromName(dynamic value) {
    final name = value?.toString();
    return PlatformType.values.firstWhere(
      (platform) => platform.name == name,
      orElse: () => PlatformType.netease,
    );
  }

  static AudioLevel _audioLevelFromName(dynamic value) {
    final name = value?.toString();
    return AudioLevel.values.firstWhere(
      (level) => level.name == name,
      orElse: () => AudioLevel.low,
    );
  }

  static int? _intValue(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '');
  }
}

abstract class PlayerPlaybackMemoryStore {
  Future<PlayerPlaybackMemory?> load();
  Future<void> save(PlayerPlaybackMemory memory);
  Future<void> clear();
}

class NoopPlayerPlaybackMemoryStore implements PlayerPlaybackMemoryStore {
  const NoopPlayerPlaybackMemoryStore();

  @override
  Future<PlayerPlaybackMemory?> load() async => null;

  @override
  Future<void> save(PlayerPlaybackMemory memory) async {}

  @override
  Future<void> clear() async {}
}

class HivePlayerPlaybackMemoryStore implements PlayerPlaybackMemoryStore {
  static const _boxName = 'player_memory';
  static const _lastPlaybackKey = 'last_playback';

  @override
  Future<PlayerPlaybackMemory?> load() async {
    final box = await Hive.openBox(_boxName);
    return PlayerPlaybackMemory.fromJson(box.get(_lastPlaybackKey));
  }

  @override
  Future<void> save(PlayerPlaybackMemory memory) async {
    final box = await Hive.openBox(_boxName);
    await box.put(_lastPlaybackKey, memory.toJson());
  }

  @override
  Future<void> clear() async {
    final box = await Hive.openBox(_boxName);
    await box.delete(_lastPlaybackKey);
  }
}
