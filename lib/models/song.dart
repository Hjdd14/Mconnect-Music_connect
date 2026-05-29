import 'platform_type.dart';
import 'artist.dart';
import 'album.dart';
import 'audio_quality.dart';

class Song {
  final String id;
  final PlatformType platform;
  final String name;
  final List<Artist> artists;
  final Album? album;
  final Duration duration;
  final String? coverUrl;
  final List<AudioQuality> availableQualities;

  const Song({
    required this.id,
    required this.platform,
    required this.name,
    required this.artists,
    this.album,
    this.duration = Duration.zero,
    this.coverUrl,
    this.availableQualities = const [],
  });

  String get fingerprint =>
      '${name.toLowerCase()}_${artists.map((a) => a.name.toLowerCase()).join(",")}_${duration.inSeconds}';

  String get artistNames => artists.map((a) => a.name).join(', ');

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Song &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          platform == other.platform;

  @override
  int get hashCode => id.hashCode ^ platform.hashCode;
}
