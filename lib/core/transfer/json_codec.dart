import 'dart:convert';

import '../../models/song.dart';
import '../../models/platform_type.dart';
import 'transfer_format.dart';

/// This app's own JSON playlist document.
///
/// The song objects use **exactly** the key set `MyPlaylistsRepository` persists
/// and embeds in its `mconnect://playlist?data=…` share link
/// (`id`/`platform`/`name`/`artists`/`albumName`/`albumCover`/`durationMs`), so a
/// JSON export is directly re-importable and a future change to one has to
/// acknowledge the other. Unlike the share link it is not base64-wrapped, so it
/// is diff-able, hand-editable and usable as a backup.
///
/// No timestamp is written on purpose: the document is a pure function of its
/// input, which is what lets a test assert an exact round trip.
abstract final class PlaylistJsonCodec {
  /// Marker that identifies the document. An unrelated `.json` file is rejected
  /// rather than half-parsed into an empty playlist.
  static const String formatTag = 'mconnect.playlist';

  /// Schema version of the document envelope.
  static const int version = 1;

  static const String formatKey = 'format';
  static const String versionKey = 'version';
  static const String nameKey = 'name';
  static const String songsKey = 'songs';

  /// Pretty-printed so the export is readable and diff-able.
  static const String indent = '  ';

  static String encode({required String name, required List<Song> songs}) {
    final payload = <String, dynamic>{
      formatKey: formatTag,
      versionKey: version,
      nameKey: name.trim().isEmpty ? '未命名歌单' : name.trim(),
      songsKey: <Map<String, dynamic>>[
        for (final song in songs)
          // A song with no title has nothing to write and nothing to match on.
          if (song.name.trim().isNotEmpty) _songToJson(song),
      ],
    };
    return JsonEncoder.withIndent(indent).convert(payload);
  }

  /// Parses [text], or returns null when it is not our JSON.
  ///
  /// A malformed document returns null rather than throwing: a hand-edited
  /// export must not be able to crash the import page.
  static TransferDocument? decode(String text) {
    final trimmed = text.trim();
    // Cheap guard before the parser: a plain-text list must not reach
    // `jsonDecode` at all.
    if (!trimmed.startsWith('{')) return null;
    try {
      final json = jsonDecode(trimmed);
      if (json is! Map<String, dynamic>) return null;
      if (json[formatKey] != formatTag) return null;

      final rawSongs = json[songsKey];
      if (rawSongs is! List) return null;

      final entries = <TransferEntry>[];
      for (final item in rawSongs) {
        if (item is! Map) continue;
        final entry = _entryFromJson(item);
        if (entry != null) entries.add(entry);
      }

      final rawName = json[nameKey]?.toString().trim();
      return TransferDocument(
        name: rawName == null || rawName.isEmpty ? '导入歌单' : rawName,
        entries: entries,
        format: PlaylistTransferFormat.json,
      );
    } catch (_) {
      // `jsonDecode` throws on malformed input and the field reads would throw
      // on unexpected types; both mean "not our document".
      return null;
    }
  }

  /// The key set is exactly what `MyPlaylistsRepository` persists, so the two
  /// encodings of a song stay interchangeable.
  static Map<String, dynamic> _songToJson(Song song) => <String, dynamic>{
    'id': song.id,
    'platform': song.platform.name,
    'name': song.name,
    'artists': song.artists
        .map((artist) => artist.name)
        .toList(growable: false),
    'albumName': song.album?.name,
    'albumCover': song.coverUrl ?? song.album?.coverUrl,
    'durationMs': song.duration.inMilliseconds,
  };

  static TransferEntry? _entryFromJson(Map<dynamic, dynamic> json) {
    final title = json['name']?.toString().trim() ?? '';
    if (title.isEmpty) return null;

    final id = json['id']?.toString().trim();
    final rawArtists = json['artists'];
    final artists = <String>[
      if (rawArtists is List)
        for (final artist in rawArtists)
          if (artist.toString().trim().isNotEmpty) artist.toString().trim(),
    ];

    return TransferEntry(
      title: title,
      artists: artists,
      duration: Duration(
        milliseconds: int.tryParse(json['durationMs']?.toString() ?? '') ?? 0,
      ),
      platform: PlatformType.tryParse(json['platform']?.toString()),
      id: id == null || id.isEmpty ? null : id,
      albumName: _nonEmpty(json['albumName']?.toString()),
      albumCover: _nonEmpty(json['albumCover']?.toString()),
    );
  }

  static String? _nonEmpty(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
