import '../../../models/platform_type.dart';
import '../../../models/song.dart';

/// Merges the local library with streaming-library songs into a single list.
///
/// The same recording is routinely present twice — once as a file on disk and
/// once in the online library (a like, a playlist entry, a history row). Until
/// now the local page and the online pages each showed their own copy, so the
/// user saw the same song twice; `Song.fingerprint` was written on insert but
/// never queried (M-52).
///
/// Matching uses [Song.dedupeKey] (normalized title + primary artist + 4-second
/// duration bucket), which tolerates the things platforms disagree on:
/// `(Live)`/`(feat. X)` markers, featured artists and rounding of the length.
class LocalLibraryDedupe {
  /// Merges [local] and [online], keeping **one** row per dedupe key.
  ///
  /// With [preferLocal] the local entry wins, because when the user owns the
  /// file the local copy is the one that plays offline and costs no network.
  /// Online-only tracks keep their original order and are appended.
  static List<Song> mergeLocalWithOnline({
    required Iterable<Song> local,
    required Iterable<Song> online,
    bool preferLocal = true,
  }) {
    return preferLocal
        ? dedupe([...local, ...online])
        : dedupe([...online, ...local]);
  }

  /// Keeps the first occurrence of every dedupe key, preserving input order.
  static List<Song> dedupe(Iterable<Song> songs) {
    final seen = <String>{};
    final result = <Song>[];
    for (final song in songs) {
      final key = song.dedupeKey;
      if (seen.add(key)) result.add(song);
    }
    return result;
  }

  /// The dedupe key of every song in [songs], for "is this one also online?"
  /// lookups in the UI.
  static Set<String> keysOf(Iterable<Song> songs) =>
      {for (final song in songs) song.dedupeKey};

  /// Songs in [candidates] that are not already represented in [known].
  static List<Song> onlyMissing(
    Iterable<Song> candidates,
    Iterable<Song> known,
  ) {
    final keys = keysOf(known);
    return [
      for (final song in candidates)
        if (!keys.contains(song.dedupeKey)) song,
    ];
  }

  /// True when [song] is a local file entry.
  static bool isLocal(Song song) => song.platform == PlatformType.local;
}
