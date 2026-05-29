class Album {
  final String id;
  final String name;
  final String? artistName;
  final String? coverUrl;
  final DateTime? releaseDate;

  const Album({
    required this.id,
    required this.name,
    this.artistName,
    this.coverUrl,
    this.releaseDate,
  });
}
