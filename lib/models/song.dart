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

  /// Album id on the owning platform, when the platform exposes one.
  ///
  /// Kept separate from [album] because `Album.id` is empty on records read
  /// back from the local database (see the `Album(id: '')` reconstruction in
  /// the library providers); this field carries the real id going forward.
  final String? albumId;

  /// Primary artist id on the owning platform, when the platform exposes one.
  final String? artistId;

  /// 1-based track number inside its album, when the platform exposes one.
  final int? trackNumber;

  /// Platform fee/pay flag (0 = free, 1 = VIP, 8 = SVIP …), when exposed.
  final int? fee;

  const Song({
    required this.id,
    required this.platform,
    required this.name,
    required this.artists,
    this.album,
    this.duration = Duration.zero,
    this.coverUrl,
    this.availableQualities = const [],
    this.albumId,
    this.artistId,
    this.trackNumber,
    this.fee,
  });

  String get fingerprint =>
      '${name.toLowerCase()}_${artists.map((a) => a.name.toLowerCase()).join(",")}_${duration.inSeconds}';

  /// Cross-platform dedupe key, used to merge the same song coming from
  /// different platforms (aggregate search, local vs. streaming libraries).
  ///
  /// Deliberately looser than [fingerprint]:
  /// * bracketed noise (`(Live)`, `(feat. X)`, `(Remastered)`, `- Live`) is
  ///   stripped so the same recording matches across platforms;
  /// * only the **primary** artist is used, because platforms disagree on
  ///   whether to list featured artists;
  /// * duration is bucketed into 4-second buckets, i.e. a ±2s tolerance,
  ///   because platforms round track lengths differently.
  ///
  /// [fingerprint] stays as-is: it is persisted in the database and changing
  /// its meaning would silently invalidate existing rows.
  String get dedupeKey {
    final title = _normalizeForDedupe(name);
    final primaryArtist = artists.isEmpty
        ? ''
        : _normalizeForDedupe(artists.first.name);
    final bucket = duration.inSeconds <= 0
        ? 0
        : (duration.inSeconds / 4).round();
    return '$title|$primaryArtist|$bucket';
  }

  /// Lowercase, strip known variant markers, then strip whitespace and
  /// punctuation so "甲乙丙丁 (Live)" and "甲乙丙丁" collapse together.
  static String _normalizeForDedupe(String raw) {
    var value = raw.toLowerCase();
    for (final pattern in _dedupeNoisePatterns) {
      value = value.replaceAll(pattern, ' ');
    }
    value = value.replaceAll(RegExp(r'\s+'), '');
    value = value.replaceAll(RegExp(r'''[’'"“”·、,，.。\-_/\\|~!！?？]+'''), '');
    return value;
  }

  static final List<RegExp> _dedupeNoisePatterns = <RegExp>[
    // (feat. X) / (ft. X) / （合唱：X）
    RegExp(r'[\(\（\[【]\s*(feat|ft)\b[^\)\）\]】]*[\)\）\]】]'),
    // (Live) / (现场版) / (演唱会)
    RegExp(r'[\(\（\[【][^\)\）\]】]*(live|现场|演唱会)[^\)\）\]】]*[\)\）\]】]'),
    // (Remastered) / (重制版) / (重置)
    RegExp(r'[\(\（\[【][^\)\）\]】]*(remaster|重制|重置)[^\)\）\]】]*[\)\）\]】]'),
    // trailing " - Live" / "- Remastered 2011" / "- Radio Edit"
    RegExp(r'\s*-\s*[^-]*\b(live|remaster(ed)?|radio edit|acoustic)\b[^-]*$'),
  ];

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
