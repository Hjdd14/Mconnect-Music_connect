import '../../../models/song.dart';
import 'local_track_store.dart';

abstract class LocalMusicScanner {
  Future<LocalMusicScanResult> scanDirectory(String rootPath);
}

/// Outcome of one (incremental) scan.
///
/// Beyond the song list it carries the counters that make the "metadata really
/// was not re-read" claim checkable: [parsedCount] is the number of files whose
/// tags were read, [reusedCount] the number skipped because `(path, mtime,
/// size)` was already in the index.
class LocalMusicScanResult {
  final List<Song> songs;
  final Map<String, String> lyricsBySongId;
  final List<String> skippedFiles;

  /// The persisted rows this scan produced/reused, in display order.
  final List<LocalTrackEntry> tracks;

  /// Files whose tags were read on this pass.
  final int parsedCount;

  /// Files skipped because the index already had their `(mtime, size)`.
  final int reusedCount;

  /// Index rows dropped because the file disappeared.
  final int removedCount;

  /// Lyric files that were found but could not be decoded (encrypted/unknown).
  final List<String> skippedLyrics;

  final Duration elapsed;
  final String? rootPath;

  const LocalMusicScanResult({
    this.songs = const [],
    this.lyricsBySongId = const {},
    this.skippedFiles = const [],
    this.tracks = const [],
    this.parsedCount = 0,
    this.reusedCount = 0,
    this.removedCount = 0,
    this.skippedLyrics = const [],
    this.elapsed = Duration.zero,
    this.rootPath,
  });

  int get totalCount => tracks.length;

  /// True when this scan did not have to open a single audio file.
  bool get wasFullyIncremental => parsedCount == 0 && tracks.isNotEmpty;

  @override
  String toString() =>
      'LocalMusicScanResult(${songs.length} songs, parsed=$parsedCount, '
      'reused=$reusedCount, removed=$removedCount, ${elapsed.inMilliseconds}ms)';
}
