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
  final AudioQualityPreference qualityPreference;
  final DateTime savedAt;

  /// 播放倍速（Wave 0-A / A-2）。
  final double playbackSpeed;

  /// 是否跳过静音段。
  final bool skipSilence;

  /// 随机播放开关。
  final bool isShuffle;

  /// 循环模式，存 [RepeatMode] 的 `name`。
  ///
  /// 存字符串而不是枚举，是为了让这个数据层文件不必 import presentation 层的
  /// `player_provider.dart`（那会形成本文件 → provider → 本文件的循环依赖）。
  /// 未知/脏值由读取方回落到 `off`。
  final String repeatMode;

  /// A-B 循环区间；两者都存在且 `end > start` 时才有效。
  final Duration? abLoopStart;
  final Duration? abLoopEnd;

  PlayerPlaybackMemory({
    required this.currentSong,
    required this.playlist,
    required this.currentIndex,
    required this.position,
    required this.duration,
    required this.currentQuality,
    this.qualityPreference = AudioQualityPreference.fixed,
    this.playbackSpeed = 1.0,
    this.skipSilence = false,
    this.isShuffle = false,
    this.repeatMode = 'off',
    this.abLoopStart,
    this.abLoopEnd,
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
      'qualityPreference': qualityPreference.name,
      'playbackSpeed': playbackSpeed,
      'skipSilence': skipSilence,
      'isShuffle': isShuffle,
      'repeatMode': repeatMode,
      'abLoopStartMs': abLoopStart?.inMilliseconds,
      'abLoopEndMs': abLoopEnd?.inMilliseconds,
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
    final abLoopStart = _durationOrNull(value['abLoopStartMs']);
    final abLoopEnd = _durationOrNull(value['abLoopEndMs']);
    // 只有 A、B 都在且 B 晚于 A 时才认这个区间：单个端点是脏数据，恢复出来会
    // 变成一个永远不生效（或立刻回跳）的"循环"。
    final hasValidAbLoop =
        abLoopStart != null && abLoopEnd != null && abLoopEnd > abLoopStart;
    return PlayerPlaybackMemory(
      currentSong: song,
      playlist: effectivePlaylist,
      currentIndex: index.clamp(0, effectivePlaylist.length - 1),
      position: Duration(milliseconds: _intValue(value['positionMs']) ?? 0),
      duration: Duration(milliseconds: _intValue(value['durationMs']) ?? 0),
      currentQuality: _audioLevelFromName(value['currentQuality']),
      qualityPreference: _qualityPreferenceFromName(value['qualityPreference']),
      playbackSpeed: _playbackSpeed(value['playbackSpeed']),
      skipSilence: _boolValue(value['skipSilence']) ?? false,
      isShuffle: _boolValue(value['isShuffle']) ?? false,
      repeatMode: value['repeatMode']?.toString() ?? 'off',
      abLoopStart: hasValidAbLoop ? abLoopStart : null,
      abLoopEnd: hasValidAbLoop ? abLoopEnd : null,
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
    // 未知/已删除的平台名 → 丢弃这一行。以前这里回落 netease，会把别家平台的歌
    // 伪装成网易云的歌去取流（恢复到错误平台）。
    final platform = PlatformType.tryParse(value['platform']?.toString());
    if (platform == null) return null;
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

  static AudioLevel _audioLevelFromName(dynamic value) {
    final name = value?.toString();
    return AudioLevel.values.firstWhere(
      (level) => level.name == name,
      orElse: () => AudioLevel.low,
    );
  }

  static AudioQualityPreference _qualityPreferenceFromName(dynamic value) {
    final name = value?.toString();
    return AudioQualityPreference.values.firstWhere(
      (preference) => preference.name == name,
      orElse: () => AudioQualityPreference.fixed,
    );
  }

  static int? _intValue(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '');
  }

  static bool? _boolValue(dynamic value) {
    if (value is bool) return value;
    if (value is String) {
      if (value == 'true') return true;
      if (value == 'false') return false;
    }
    return null;
  }

  static Duration? _durationOrNull(dynamic value) {
    final milliseconds = _intValue(value);
    return milliseconds == null ? null : Duration(milliseconds: milliseconds);
  }

  /// 倍速必须是有限值且落在播放器支持的区间内，否则回落到原速。
  static double _playbackSpeed(dynamic value) {
    final raw = value is num ? value.toDouble() : double.tryParse(value?.toString() ?? '');
    if (raw == null || !raw.isFinite) return 1.0;
    return raw.clamp(0.5, 2.0).toDouble();
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
