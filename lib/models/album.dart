class Album {
  final String id;
  final String name;
  final String? artistName;
  final String? coverUrl;
  final DateTime? releaseDate;

  /// Owning-platform artist id, used to navigate from an album page to the
  /// artist page without a second lookup.
  final String? artistId;

  /// Album description / 简介, exposed by 网易云 and QQ 音乐.
  final String? description;

  /// Number of tracks on the album.
  final int? songCount;

  /// Record company (发行公司).
  final String? company;

  /// Genre (流派), mostly 网易云/QQ.
  final String? genre;

  /// Language (语言), mostly QQ 音乐.
  final String? language;

  const Album({
    required this.id,
    required this.name,
    this.artistName,
    this.coverUrl,
    this.releaseDate,
    this.artistId,
    this.description,
    this.songCount,
    this.company,
    this.genre,
    this.language,
  });

  factory Album.fromJson(Map<String, dynamic> json) {
    return Album(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      artistName: json['artistName']?.toString(),
      coverUrl: json['coverUrl']?.toString(),
      releaseDate: _parseDate(json['releaseDate']),
      artistId: json['artistId']?.toString(),
      description: json['description']?.toString(),
      songCount: _parseInt(json['songCount']),
      company: json['company']?.toString(),
      genre: json['genre']?.toString(),
      language: json['language']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    if (artistName != null) 'artistName': artistName,
    if (coverUrl != null) 'coverUrl': coverUrl,
    if (releaseDate != null) 'releaseDate': releaseDate!.toIso8601String(),
    if (artistId != null) 'artistId': artistId,
    if (description != null) 'description': description,
    if (songCount != null) 'songCount': songCount,
    if (company != null) 'company': company,
    if (genre != null) 'genre': genre,
    if (language != null) 'language': language,
  };

  Album copyWith({
    String? id,
    String? name,
    String? artistName,
    String? coverUrl,
    DateTime? releaseDate,
    String? artistId,
    String? description,
    int? songCount,
    String? company,
    String? genre,
    String? language,
  }) {
    return Album(
      id: id ?? this.id,
      name: name ?? this.name,
      artistName: artistName ?? this.artistName,
      coverUrl: coverUrl ?? this.coverUrl,
      releaseDate: releaseDate ?? this.releaseDate,
      artistId: artistId ?? this.artistId,
      description: description ?? this.description,
      songCount: songCount ?? this.songCount,
      company: company ?? this.company,
      genre: genre ?? this.genre,
      language: language ?? this.language,
    );
  }

  static DateTime? _parseDate(Object? value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    return DateTime.tryParse(value.toString());
  }

  static int? _parseInt(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    return int.tryParse(value.toString());
  }
}
