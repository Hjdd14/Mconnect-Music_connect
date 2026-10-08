import 'package:flutter/foundation.dart';

import '../../../core/database/app_database.dart' show songKeyOf;
import '../data/local_track_store.dart';

/// How the local library list is ordered.
enum LocalSortField {
  title('名称'),
  artist('歌手'),
  album('专辑'),
  duration('时长'),
  recentlyAdded('最近添加'),
  playCount('播放次数');

  const LocalSortField(this.label);

  /// User-facing name, kept next to the enum so a new field cannot be added
  /// without deciding what to call it.
  final String label;
}

/// A filter the user can switch on.
///
/// Several may be active at once and they are ANDed — "仅已评分 + 缺少元数据"
/// means both, which is what makes them worth having as switches instead of a
/// single-choice dropdown.
enum LocalTrackFilter {
  rated('仅已评分'),
  unrated('未评分'),
  missingMetadata('缺少元数据');

  const LocalTrackFilter(this.label);

  final String label;
}

/// The `track_ratings` key for a **local** track.
///
/// A local song carries its file path as `Song.id` (see [LocalTrackEntry.toSong]),
/// so its key is `local:<path>` — the shape [songKeyOf] produces for every other
/// source, which is what lets one ratings table serve them all.
String localTrackSongKey(LocalTrackEntry track) =>
    songKeyOf('local', track.path);

/// What the local library page is asking for: a keyword, a sort order and a set
/// of filters.
///
/// Pure and immutable so [apply] is unit-testable without a widget tree, a
/// database or Riverpod — the same reasoning as `LocalLibraryGrouping`.
@immutable
class LocalLibraryQuery {
  /// Whitespace-separated tokens; every token must match (see [_matchesKeyword]).
  final String keyword;

  final LocalSortField sort;

  /// Reverses [sort]: `title` desc is Z→A, `duration` desc is longest first,
  /// `playCount` desc is most played first.
  final bool descending;

  final Set<LocalTrackFilter> filters;

  const LocalLibraryQuery({
    this.keyword = '',
    this.sort = LocalSortField.title,
    this.descending = false,
    this.filters = const <LocalTrackFilter>{},
  });

  /// The untouched query — "no keyword, default order, no filters".
  static const LocalLibraryQuery none = LocalLibraryQuery();

  String get trimmedKeyword => keyword.trim();

  bool get hasKeyword => trimmedKeyword.isNotEmpty;

  /// True when [apply] would return its input unchanged (apart from the default
  /// name ordering). The page uses it to decide whether to show a "清除" action.
  bool get isDefault =>
      !hasKeyword &&
      filters.isEmpty &&
      sort == LocalSortField.title &&
      !descending;

  LocalLibraryQuery copyWith({
    String? keyword,
    LocalSortField? sort,
    bool? descending,
    Set<LocalTrackFilter>? filters,
  }) {
    return LocalLibraryQuery(
      keyword: keyword ?? this.keyword,
      sort: sort ?? this.sort,
      descending: descending ?? this.descending,
      filters: filters ?? this.filters,
    );
  }

  /// Toggles [filter]; the result always carries a **fresh** set, so a state
  /// object holding it can be compared by identity.
  LocalLibraryQuery withFilter(LocalTrackFilter filter, bool enabled) {
    final next = <LocalTrackFilter>{...filters};
    if (enabled) {
      next.add(filter);
    } else {
      next.remove(filter);
    }
    return copyWith(filters: next);
  }

  /// Keyword, then filters, then sort.
  ///
  /// [ratings] and [playCounts] are keyed by [localTrackSongKey]; an absent entry
  /// and a `0` both mean "not rated" / "never played".
  List<LocalTrackEntry> apply(
    Iterable<LocalTrackEntry> tracks, {
    Map<String, int> ratings = const <String, int>{},
    Map<String, int> playCounts = const <String, int>{},
  }) {
    final tokens = trimmedKeyword
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((token) => token.isNotEmpty)
        .toList();

    final matched = <LocalTrackEntry>[];
    for (final track in tracks) {
      if (!_matchesKeyword(track, tokens)) continue;
      if (!_matchesFilters(track, ratings)) continue;
      matched.add(track);
    }

    final sorted = [...matched]
      ..sort((a, b) {
        final result = _compare(
          a,
          b,
          playCounts: playCounts,
        );
        return descending ? -result : result;
      });
    return sorted;
  }

  /// Every token has to appear in the title, the artist or the album.
  ///
  /// All-tokens rather than any-token: `周杰伦 稻香` is meant to narrow to one
  /// song, not to return everything by 周杰伦 plus everything called 稻香.
  bool _matchesKeyword(LocalTrackEntry track, List<String> tokens) {
    if (tokens.isEmpty) return true;
    final haystack =
        '${track.displayTitle}\u0001${track.displayArtist}'
                '\u0001${track.albumName ?? ''}'
            .toLowerCase();
    for (final token in tokens) {
      if (!haystack.contains(token)) return false;
    }
    return true;
  }

  bool _matchesFilters(LocalTrackEntry track, Map<String, int> ratings) {
    if (filters.isEmpty) return true;
    final rating = ratings[localTrackSongKey(track)] ?? 0;
    for (final filter in filters) {
      switch (filter) {
        case LocalTrackFilter.rated:
          if (rating <= 0) return false;
        case LocalTrackFilter.unrated:
          if (rating > 0) return false;
        case LocalTrackFilter.missingMetadata:
          // A row is "missing metadata" when it lacks *any* of the three tags the
          // scanner can read; a file with only a title still needs attention.
          if (track.hasTitle && track.hasArtist && track.hasAlbum) return false;
      }
    }
    return true;
  }

  /// A **total** order, not just the selected field.
  ///
  /// `List.sort` is not stable in Dart, so a comparison that returns 0 for two
  /// different rows lets them swap places on every rebuild. Every branch ends in
  /// a tie-break that cannot tie (the path is the primary key).
  int _compare(
    LocalTrackEntry a,
    LocalTrackEntry b, {
    required Map<String, int> playCounts,
  }) {
    final primary = _primary(a, b, playCounts: playCounts);
    if (primary != 0) return primary;
    final byTitle = _text(a.displayTitle, b.displayTitle);
    if (byTitle != 0) return byTitle;
    return a.path.compareTo(b.path);
  }

  int _primary(
    LocalTrackEntry a,
    LocalTrackEntry b, {
    required Map<String, int> playCounts,
  }) {
    switch (sort) {
      case LocalSortField.title:
        return _text(a.displayTitle, b.displayTitle);
      case LocalSortField.artist:
        final byArtist = _text(a.displayArtist, b.displayArtist);
        if (byArtist != 0) return byArtist;
        return _text(a.displayTitle, b.displayTitle);
      case LocalSortField.album:
        final byAlbum = _text(a.displayAlbum, b.displayAlbum);
        if (byAlbum != 0) return byAlbum;
        return _trackOrder(a, b);
      case LocalSortField.duration:
        return a.durationMs.compareTo(b.durationMs);
      case LocalSortField.recentlyAdded:
        return _addedAt(a).compareTo(_addedAt(b));
      case LocalSortField.playCount:
        final aCount = playCounts[localTrackSongKey(a)] ?? 0;
        final bCount = playCounts[localTrackSongKey(b)] ?? 0;
        return aCount.compareTo(bCount);
    }
  }

  /// Track number, with "no number" last and the title as the tie-break.
  int _trackOrder(LocalTrackEntry a, LocalTrackEntry b) {
    final aTrack = a.trackNumber;
    final bTrack = b.trackNumber;
    if (aTrack != null && bTrack != null && aTrack != bTrack) {
      return aTrack.compareTo(bTrack);
    }
    if (aTrack == null && bTrack != null) return 1;
    if (aTrack != null && bTrack == null) return -1;
    return _text(a.displayTitle, b.displayTitle);
  }

  /// "Recently added" is the scan timestamp, falling back to the file mtime —
  /// a row written before [LocalTrackEntry.scannedAt] existed still has an order.
  static int _addedAt(LocalTrackEntry track) => track.scannedAt ?? track.mtime;

  static int _text(String a, String b) =>
      a.toLowerCase().compareTo(b.toLowerCase());
}
