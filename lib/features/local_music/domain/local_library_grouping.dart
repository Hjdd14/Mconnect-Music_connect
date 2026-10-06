import 'package:path/path.dart' as p;

import '../data/local_track_store.dart';

/// One row of the album / artist / folder views.
class LocalTrackGroup {
  /// Grouping key: album name, artist name, or the folder path.
  final String id;

  /// Display title (`未知专辑` / `未知歌手` fallbacks, or the folder name).
  final String title;

  /// Secondary line (album artist, track count, folder path…).
  final String? subtitle;

  /// Cover of the first track in the group that has one, if any.
  final String? coverPath;

  final List<LocalTrackEntry> tracks;

  const LocalTrackGroup({
    required this.id,
    required this.title,
    required this.tracks,
    this.subtitle,
    this.coverPath,
  });

  int get trackCount => tracks.length;

  Duration get totalDuration => Duration(
    milliseconds: tracks.fold(0, (sum, track) => sum + track.durationMs),
  );

  @override
  String toString() => 'LocalTrackGroup($title, ${tracks.length} tracks)';
}

/// Groups the persisted local index into the three library views.
///
/// Pure functions over [LocalTrackEntry] so the views can be unit-tested
/// without a widget tree and without a database.
class LocalLibraryGrouping {
  static const unknownAlbum = LocalTrackEntry.unknownAlbum;
  static const unknownArtist = LocalTrackEntry.unknownArtist;

  /// Album view: one group per album name, tracks in album order.
  static List<LocalTrackGroup> byAlbum(Iterable<LocalTrackEntry> tracks) {
    final buckets = <String, List<LocalTrackEntry>>{};
    for (final track in tracks) {
      buckets.putIfAbsent(track.displayAlbum, () => []).add(track);
    }
    final groups = buckets.entries.map((entry) {
      final sorted = _inAlbumOrder(entry.value);
      final artists = <String>{for (final track in sorted) track.displayArtist};
      return LocalTrackGroup(
        id: entry.key,
        title: entry.key,
        subtitle: artists.length == 1
            ? artists.first
            : '${artists.length} 位歌手',
        coverPath: _firstCover(sorted),
        tracks: sorted,
      );
    }).toList();
    return _sortedByName(groups);
  }

  /// Artist view: one group per artist name, tracks alphabetically.
  static List<LocalTrackGroup> byArtist(Iterable<LocalTrackEntry> tracks) {
    final buckets = <String, List<LocalTrackEntry>>{};
    for (final track in tracks) {
      buckets.putIfAbsent(track.displayArtist, () => []).add(track);
    }
    final groups = buckets.entries.map((entry) {
      final sorted = _byTitle(entry.value);
      final albums = <String>{
        for (final track in sorted)
          if (track.hasAlbum) track.displayAlbum,
      };
      return LocalTrackGroup(
        id: entry.key,
        title: entry.key,
        subtitle: albums.length == 1 ? albums.first : '${albums.length} 张专辑',
        coverPath: _firstCover(sorted),
        tracks: sorted,
      );
    }).toList();
    return _sortedByName(groups);
  }

  /// Folder view: one group per containing directory, tracks by file name.
  static List<LocalTrackGroup> byFolder(Iterable<LocalTrackEntry> tracks) {
    final buckets = <String, List<LocalTrackEntry>>{};
    for (final track in tracks) {
      buckets.putIfAbsent(track.folderPath, () => []).add(track);
    }
    final groups = buckets.entries.map((entry) {
      final sorted = [...entry.value]
        ..sort(
          (a, b) => p
              .basename(a.path)
              .toLowerCase()
              .compareTo(p.basename(b.path).toLowerCase()),
        );
      return LocalTrackGroup(
        id: entry.key,
        title: p.basename(entry.key).isEmpty ? entry.key : p.basename(entry.key),
        subtitle: entry.key,
        coverPath: _firstCover(sorted),
        tracks: sorted,
      );
    }).toList();
    groups.sort((a, b) => a.id.toLowerCase().compareTo(b.id.toLowerCase()));
    return groups;
  }

  static List<LocalTrackGroup> _sortedByName(List<LocalTrackGroup> groups) {
    groups.sort((a, b) {
      // "未知…" sinks to the bottom instead of leading the list.
      final aUnknown = a.title == unknownAlbum || a.title == unknownArtist;
      final bUnknown = b.title == unknownAlbum || b.title == unknownArtist;
      if (aUnknown != bUnknown) return aUnknown ? 1 : -1;
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });
    return groups;
  }

  static List<LocalTrackEntry> _inAlbumOrder(List<LocalTrackEntry> tracks) {
    final sorted = [...tracks];
    sorted.sort((a, b) {
      final aTrack = a.trackNumber;
      final bTrack = b.trackNumber;
      if (aTrack != null && bTrack != null && aTrack != bTrack) {
        return aTrack.compareTo(bTrack);
      }
      if (aTrack != null && bTrack == null) return -1;
      if (aTrack == null && bTrack != null) return 1;
      return a.displayTitle.toLowerCase().compareTo(b.displayTitle.toLowerCase());
    });
    return sorted;
  }

  static List<LocalTrackEntry> _byTitle(List<LocalTrackEntry> tracks) {
    final sorted = [...tracks];
    sorted.sort(
      (a, b) => a.displayTitle.toLowerCase().compareTo(b.displayTitle.toLowerCase()),
    );
    return sorted;
  }

  static String? _firstCover(List<LocalTrackEntry> tracks) {
    for (final track in tracks) {
      if (track.coverPath != null && track.coverPath!.isNotEmpty) {
        return track.coverPath;
      }
    }
    return null;
  }
}
