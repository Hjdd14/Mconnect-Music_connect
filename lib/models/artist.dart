class Artist {
  final String id;
  final String name;
  final String? avatarUrl;

  /// Short biography / 简介.
  final String? briefDesc;

  /// Number of songs, when the platform exposes it.
  final int? songCount;

  /// Number of albums, when the platform exposes it.
  final int? albumCount;

  /// Follower / fan count, when the platform exposes it.
  final int? fansCount;

  const Artist({
    required this.id,
    required this.name,
    this.avatarUrl,
    this.briefDesc,
    this.songCount,
    this.albumCount,
    this.fansCount,
  });

  factory Artist.fromJson(Map<String, dynamic> json) {
    return Artist(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      avatarUrl: json['avatarUrl']?.toString(),
      briefDesc: json['briefDesc']?.toString(),
      songCount: _parseInt(json['songCount']),
      albumCount: _parseInt(json['albumCount']),
      fansCount: _parseInt(json['fansCount']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    if (avatarUrl != null) 'avatarUrl': avatarUrl,
    if (briefDesc != null) 'briefDesc': briefDesc,
    if (songCount != null) 'songCount': songCount,
    if (albumCount != null) 'albumCount': albumCount,
    if (fansCount != null) 'fansCount': fansCount,
  };

  Artist copyWith({
    String? id,
    String? name,
    String? avatarUrl,
    String? briefDesc,
    int? songCount,
    int? albumCount,
    int? fansCount,
  }) {
    return Artist(
      id: id ?? this.id,
      name: name ?? this.name,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      briefDesc: briefDesc ?? this.briefDesc,
      songCount: songCount ?? this.songCount,
      albumCount: albumCount ?? this.albumCount,
      fansCount: fansCount ?? this.fansCount,
    );
  }

  static int? _parseInt(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    return int.tryParse(value.toString());
  }
}
