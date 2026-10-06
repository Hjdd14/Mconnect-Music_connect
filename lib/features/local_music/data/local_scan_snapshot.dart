/// One audio file as produced by a scan, before it is written to the index.
///
/// Deliberately a plain value object with a map codec: the desktop walk runs in
/// an isolate and the Android walk runs in Kotlin, and both hand back the same
/// record shape.
class LocalScannedFile {
  final String path;
  final int mtime;
  final int size;

  /// False when the persisted index already had this `(path, mtime, size)`.
  final bool changed;

  final String? title;
  final String? artist;
  final String? album;
  final int durationMs;
  final int? trackNumber;
  final String? coverPath;

  /// Sidecar `.lrc`/`.krc`/`.qrc`/`.txt` files that exist for this track.
  final List<String> lyricCandidates;

  const LocalScannedFile({
    required this.path,
    required this.mtime,
    required this.size,
    required this.changed,
    this.title,
    this.artist,
    this.album,
    this.durationMs = 0,
    this.trackNumber,
    this.coverPath,
    this.lyricCandidates = const [],
  });

  Map<String, Object?> toMap() => {
    'path': path,
    'mtime': mtime,
    'size': size,
    'changed': changed,
    if (title != null) 'title': title,
    if (artist != null) 'artist': artist,
    if (album != null) 'album': album,
    if (durationMs != 0) 'durationMs': durationMs,
    if (trackNumber != null) 'trackNumber': trackNumber,
    if (coverPath != null) 'coverPath': coverPath,
    if (lyricCandidates.isNotEmpty) 'lyrics': lyricCandidates,
  };

  /// Tolerant by design: the map may come from the Dart isolate walk or from the
  /// Android method channel, and neither is a compile-time contract.
  factory LocalScannedFile.fromMap(Map<Object?, Object?> map) {
    return LocalScannedFile(
      path: map['path']?.toString() ?? '',
      mtime: _asInt(map['mtime']),
      size: _asInt(map['size']),
      changed: map['changed'] == true || map['changed']?.toString() == 'true',
      title: _asString(map['title']),
      artist: _asString(map['artist']),
      album: _asString(map['album']),
      durationMs: _asInt(map['durationMs']),
      trackNumber: map['trackNumber'] == null
          ? null
          : _asInt(map['trackNumber']),
      coverPath: _asString(map['coverPath']),
      lyricCandidates: _asStringList(map['lyrics']),
    );
  }

  static int _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static String? _asString(Object? value) {
    final text = value?.toString();
    if (text == null) return null;
    final trimmed = text.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// Only plain strings are accepted: the Android payload puts a list of
  /// `{extension, content}` maps under the same `lyrics` key, and those are
  /// decoded by the Android service, not by a `dart:io` file read.
  static List<String> _asStringList(Object? value) {
    if (value is List) {
      return [
        for (final item in value)
          if (item is String && item.trim().isNotEmpty) item,
      ];
    }
    return const [];
  }

  @override
  String toString() =>
      'LocalScannedFile($path, changed=$changed, mtime=$mtime, size=$size)';
}
