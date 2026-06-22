import '../../../../models/song.dart';
import '../../../../models/album.dart';
import '../../../../models/artist.dart';
import '../../../../models/audio_quality.dart';
import '../../../../models/platform_type.dart';

enum DownloadStatus { waiting, downloading, paused, completed, failed }

class DownloadTask {
  final String id;
  final Song song;
  final AudioLevel quality;
  final DownloadStatus status;
  final double progress;
  final int downloadedBytes;
  final int? totalBytes;
  final String? filePath;
  final String? error;
  final DateTime createdAt;
  final DateTime? completedAt;
  final bool isOfflineCache;

  const DownloadTask({
    required this.id,
    required this.song,
    required this.quality,
    this.status = DownloadStatus.waiting,
    this.progress = 0.0,
    this.downloadedBytes = 0,
    this.totalBytes,
    this.filePath,
    this.error,
    required this.createdAt,
    this.completedAt,
    this.isOfflineCache = false,
  });

  DownloadTask copyWith({
    DownloadStatus? status,
    double? progress,
    int? downloadedBytes,
    int? Function()? totalBytes,
    String? Function()? filePath,
    String? Function()? error,
    DateTime? Function()? completedAt,
    bool? isOfflineCache,
  }) {
    return DownloadTask(
      id: id,
      song: song,
      quality: quality,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      totalBytes: totalBytes != null ? totalBytes() : this.totalBytes,
      filePath: filePath != null ? filePath() : this.filePath,
      error: error != null ? error() : this.error,
      createdAt: createdAt,
      completedAt: completedAt != null ? completedAt() : this.completedAt,
      isOfflineCache: isOfflineCache ?? this.isOfflineCache,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'song': _songToJson(song),
      'quality': quality.name,
      'status': status.name,
      'progress': progress,
      'downloadedBytes': downloadedBytes,
      'totalBytes': totalBytes,
      'filePath': filePath,
      'error': error,
      'createdAt': createdAt.toIso8601String(),
      'completedAt': completedAt?.toIso8601String(),
      'isOfflineCache': isOfflineCache,
    };
  }

  static DownloadTask? fromJson(dynamic value) {
    if (value is! Map) return null;
    final id = value['id']?.toString() ?? '';
    final song = _songFromJson(value['song']);
    if (id.isEmpty || song == null) return null;

    return DownloadTask(
      id: id,
      song: song,
      quality: _audioLevelFromName(value['quality']),
      status: _downloadStatusFromName(value['status']),
      progress: _doubleValue(value['progress']).clamp(0, 1).toDouble(),
      downloadedBytes: _intValue(value['downloadedBytes']) ?? 0,
      totalBytes: _intValue(value['totalBytes']),
      filePath: value['filePath']?.toString(),
      error: value['error']?.toString(),
      createdAt: DateTime.tryParse(value['createdAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      completedAt: DateTime.tryParse(value['completedAt']?.toString() ?? ''),
      isOfflineCache: value['isOfflineCache'] == true,
    );
  }

  String get fileName {
    final sanitized = '${song.artistNames} - ${song.name}'.replaceAll(
      RegExp(r'[\\/:*?"<>|]'),
      '_',
    );
    return '$sanitized.${quality.isLossless ? 'flac' : 'mp3'}';
  }

  String get qualityLabel => quality.displayNameFor(song.platform);

  PlatformType get platform => song.platform;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DownloadTask &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

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
    final rawArtists = value['artists'];
    final artists = rawArtists is List
        ? rawArtists.map(_artistFromJson).whereType<Artist>().toList()
        : <Artist>[];
    return Song(
      id: id,
      platform: _platformFromName(value['platform']),
      name: name,
      artists: artists.isEmpty ? const [Artist(id: '', name: '')] : artists,
      album: _albumFromJson(value['album']),
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

  static DownloadStatus _downloadStatusFromName(dynamic value) {
    final name = value?.toString();
    return DownloadStatus.values.firstWhere(
      (status) => status.name == name,
      orElse: () => DownloadStatus.waiting,
    );
  }

  static int? _intValue(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '');
  }

  static double _doubleValue(dynamic value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }
}
