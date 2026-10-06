import 'package:drift/drift.dart' show Value;

import '../../models/album.dart';
import '../../models/artist.dart';
import '../../models/platform_type.dart';
import '../../models/song.dart';
import 'app_database.dart';

/// Shared mapping between the domain [Song] and the cached `Songs` row.
///
/// The three older call sites (`likes_provider`, `history_provider`,
/// `listening_stats_provider`) each carried their own copy, which is how the
/// `Album(id: '')` read-back bug survived in several places at once. New code
/// should use these two functions instead.
SongsCompanion songsCompanionFromSong(Song song) {
  return SongsCompanion.insert(
    id: song.id,
    platform: song.platform.name,
    name: song.name,
    // NOTE: `Songs.artists` holds the comma-joined artist **names**, not JSON.
    artists: song.artists.map((artist) => artist.name).join(','),
    albumName: Value(_nonEmpty(song.album?.name)),
    albumCover: Value(_nonEmpty(song.coverUrl) ?? _nonEmpty(song.album?.coverUrl)),
    durationMs: Value(song.duration.inMilliseconds),
    fingerprint: song.fingerprint,
    albumId: Value(_nonEmpty(song.albumId) ?? _nonEmpty(song.album?.id)),
    artistId: Value(
      _nonEmpty(song.artistId) ??
          _nonEmpty(song.artists.isEmpty ? null : song.artists.first.id),
    ),
    trackNumber: Value(song.trackNumber),
  );
}

/// Rebuilds a [Song] from a cached row, restoring the album/artist ids that
/// schema v2 added (the old read-back paths produced `Album(id: '')`).
Song songFromSongRecord(SongRecord record) {
  final platform =
      PlatformType.tryParse(record.platform) ?? PlatformType.netease;
  final names = record.artists.isEmpty
      ? const <String>[]
      : record.artists
            .split(',')
            .map((name) => name.trim())
            .where((name) => name.isNotEmpty)
            .toList();
  // `artistId` stores only the *primary* artist id (schema v2), so it can be
  // attached again when the row carries exactly one artist.
  final artists = <Artist>[
    for (var index = 0; index < names.length; index++)
      Artist(
        id: names.length == 1 && record.artistId != null
            ? record.artistId!
            : '',
        name: names[index],
      ),
  ];
  return Song(
    id: record.id,
    platform: platform,
    name: record.name,
    artists: artists,
    album: record.albumName == null
        ? null
        : Album(
            id: record.albumId ?? '',
            name: record.albumName!,
            coverUrl: record.albumCover,
          ),
    duration: Duration(milliseconds: record.durationMs),
    coverUrl: record.albumCover,
    albumId: record.albumId,
    artistId: record.artistId,
    trackNumber: record.trackNumber,
  );
}

String? _nonEmpty(String? value) =>
    (value == null || value.isEmpty) ? null : value;
