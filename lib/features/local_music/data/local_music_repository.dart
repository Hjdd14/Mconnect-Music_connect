import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'local_library_reconciler.dart';
import 'local_lyrics_loader.dart';
import 'local_lyrics_store.dart';
import 'local_metadata_reader.dart';
import 'local_music_scan_result.dart';
import 'local_scan_snapshot.dart';
import 'local_track_store.dart';

export 'local_music_scan_result.dart' show LocalMusicScanResult, LocalMusicScanner;

/// Desktop / Dart-side local music scanner.
///
/// Incremental by design (H-16): the persisted index is keyed by absolute path
/// and compared on `(mtime, size)`, so the second visit to the local page reads
/// tags for **zero** unchanged files. The directory walk still happens — a
/// stat-only walk is what detects added and deleted files — but it never opens
/// an audio file, and lyric files are read only for tracks that have no stored
/// lyrics yet.
///
/// Android does not use this path: SAF URIs are opaque to `dart:io`, so
/// `AndroidLocalMusicService`/`MainActivity` do the equivalent work with
/// `MediaMetadataRetriever` and hand the same records to the same reconciler.
class LocalMusicRepository implements LocalMusicScanner {
  static const supportedAudioExtensions = {
    '.mp3',
    '.flac',
    '.wav',
    '.m4a',
    '.aac',
    '.ogg',
    '.opus',
    '.mp4',
    '.alac',
    '.aiff',
    '.aif',
  };

  static const supportedLyricsExtensions = LocalLyricsLoader.supportedExtensions;

  LocalMusicRepository({
    LocalMetadataReader? metadataReader,
    LocalTrackStore? trackStore,
    LocalLyricsStore? lyricsStore,
    LocalLyricsLoader? lyricsLoader,
    this.coverDirectoryPath,
    bool? scanInIsolate,
  }) : _metadataReader = metadataReader,
       _trackStore = trackStore ?? DriftLocalTrackStore(),
       _lyricsStore = lyricsStore ?? DriftLocalLyricsStore(),
       _lyricsLoader = lyricsLoader ?? LocalLyricsLoader(),
       // A stateful test double cannot cross an isolate boundary, so injecting
       // one forces the inline path.
       _scanInIsolate = scanInIsolate ?? metadataReader == null;

  final LocalMetadataReader? _metadataReader;
  final LocalTrackStore _trackStore;
  final LocalLyricsStore _lyricsStore;
  final LocalLyricsLoader _lyricsLoader;

  /// Where extracted covers are written; `null` disables cover extraction.
  final String? coverDirectoryPath;

  final bool _scanInIsolate;

  @override
  Future<LocalMusicScanResult> scanDirectory(String rootPath) async {
    final stopwatch = Stopwatch()..start();

    final index = await _trackStore.loadIndex();
    final knownSnapshot = <String, List<int>>{
      for (final entry in index.values) entry.path: [entry.mtime, entry.size],
    };

    final reader = _metadataReader;
    final List<Map<String, Object?>> walked;
    if (reader != null || !_scanInIsolate) {
      walked = _walkLocalMusic(
        rootPath,
        knownSnapshot,
        reader ?? AudioMetadataReader(coverDirectoryPath: coverDirectoryPath),
      );
    } else {
      // Tag parsing is file IO and CPU and must not run on the UI isolate
      // (H-16). Everything crossing the boundary is plain data.
      final coverDirectory = await _resolvedCoverDirectoryPath();
      walked = await Isolate.run(
        () => _walkLocalMusic(
          rootPath,
          knownSnapshot,
          AudioMetadataReader(coverDirectoryPath: coverDirectory),
        ),
      );
    }

    final reconciler = LocalLibraryReconciler(
      trackStore: _trackStore,
      lyricsStore: _lyricsStore,
      lyricsLoader: _lyricsLoader,
    );
    return reconciler.reconcile(
      rootPath: rootPath,
      files: [
        for (final record in walked) LocalScannedFile.fromMap(record),
      ],
      stopwatch: stopwatch,
    );
  }

  /// Where extracted covers are written. Resolved *before* the isolate starts
  /// because `path_provider` is asynchronous and the reader is not.
  Future<String> _resolvedCoverDirectoryPath() async {
    final explicit = coverDirectoryPath;
    if (explicit != null) return explicit;
    try {
      final support = await getApplicationSupportDirectory();
      return p.join(support.path, 'local_covers');
    } catch (_) {
      // No plugin (headless test run): a temp directory still lets the feature
      // work instead of silently dropping every cover.
      return p.join(Directory.systemTemp.path, 'mconnect', 'local_covers');
    }
  }
}

/// Walks [rootPath] and reads tags for every file that is new or changed.
///
/// Top-level and synchronous so it can run inside `Isolate.run`; returns only
/// primitives (see [LocalScannedFile.fromMap]).
List<Map<String, Object?>> _walkLocalMusic(
  String rootPath,
  Map<String, List<int>> known,
  LocalMetadataReader reader,
) {
  final root = Directory(rootPath);
  if (!root.existsSync()) return const [];

  final audioPaths = <String>[];
  // Lower-cased full path -> real path, so a lyric file matches its track
  // regardless of the casing the file system reports.
  final lyricIndex = <String, String>{};
  final lyricPaths = <String>[];

  for (final entity in root.listSync(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    final path = entity.path;
    final extension = p.extension(path).toLowerCase();
    if (LocalMusicRepository.supportedAudioExtensions.contains(extension)) {
      audioPaths.add(path);
    } else if (LocalLyricsLoader.supportedExtensions.contains(extension)) {
      lyricIndex[path.toLowerCase()] = path;
      lyricPaths.add(path);
    }
  }

  // Built once (O(number of lyric files)) so the fuzzy lookup below stays an O(1)
  // map hit per track: scanning the index per track would turn a 1000-track
  // library into a million string comparisons.
  final lyricStemIndex = _buildLyricStemIndex(lyricPaths);

  final records = <Map<String, Object?>>[];
  for (final path in audioPaths) {
    final FileStat stat;
    try {
      stat = File(path).statSync();
    } catch (_) {
      continue;
    }
    final mtime = stat.modified.millisecondsSinceEpoch;
    final size = stat.size;
    final previous = known[path];
    final unchanged =
        previous != null && previous[0] == mtime && previous[1] == size;

    final file = LocalScannedFile(
      path: path,
      mtime: mtime,
      size: size,
      changed: !unchanged,
      lyricCandidates: _lyricCandidates(path, lyricIndex, lyricStemIndex),
    );
    final record = file.toMap();

    if (!unchanged && size > 0) {
      final metadata = reader.read(path);
      if (metadata != null) {
        record['title'] = metadata.title;
        record['artist'] = metadata.artist;
        record['album'] = metadata.album;
        record['durationMs'] = metadata.durationMs;
        record['trackNumber'] = metadata.trackNumber;
        record['coverPath'] = metadata.coverPath;
        // The container's own lyrics tag (`USLT`, `©lyr`, …). The reconciler
        // keeps it only for tracks where no sidecar `.lrc`/`.krc`/`.qrc`
        // decoded, and stores it with the `embedded` source marker.
        record['embeddedLyrics'] = metadata.lyrics;
      }
    }
    records.add(record);
  }
  return records;
}

/// Existing lyric files for [audioPath], in preference order.
///
/// **Exact matches always come first**: a sidecar named after the audio file
/// (`稻香.lrc` next to `稻香.flac`, or in a `lyrics/` subdirectory) is the one the
/// user or their tag editor put there on purpose.
///
/// After those come the *tagger* shapes, which the exact lookup cannot see
/// because the stems differ — the common case being `01. 稻香.flac` with
/// `周杰伦 - 稻香.lrc`, or `歌手 - 歌名.flac` with `歌名.lrc`. Both are resolved
/// through [lyricStemIndex], so this stays a handful of map hits per track.
///
/// The lookups are index hits, not `exists()` calls, so a 1000-track library
/// pays no extra IO for lyrics it already has.
List<String> _lyricCandidates(
  String audioPath,
  Map<String, String> exactIndex,
  Map<String, String> lyricStemIndex,
) {
  final directory = p.dirname(audioPath);
  final baseName = p.basenameWithoutExtension(audioPath);
  final candidates = <String>[];
  for (final extension in LocalLyricsLoader.supportedExtensions) {
    for (final candidate in [
      p.join(directory, '$baseName$extension'),
      p.join(directory, 'lyrics', '$baseName$extension'),
    ]) {
      final real = exactIndex[candidate.toLowerCase()];
      if (real != null && !candidates.contains(real)) {
        candidates.add(real);
      }
    }
  }

  final directories = [
    directory.toLowerCase(),
    p.join(directory, 'lyrics').toLowerCase(),
  ];
  for (final extension in LocalLyricsLoader.supportedExtensions) {
    for (final stem in _fuzzyStemsFor(baseName)) {
      for (final candidateDirectory in directories) {
        final real =
            lyricStemIndex['$candidateDirectory\u0001'
                '${stem.toLowerCase()}\u0001$extension'];
        if (real != null && !candidates.contains(real)) {
          candidates.add(real);
        }
      }
    }
  }
  return candidates;
}

/// `<directory>\u0001<stem>\u0001<extension>` -> real lyric path.
///
/// Two keys are registered per lyric file so the common tagger shape matches in
/// O(1) instead of scanning the library per track: the file's own stem
/// (`01. 稻香`), and the tail after the last ` - ` (`周杰伦 - 稻香` also answers to
/// `稻香`). A collision keeps the **lexicographically smaller** path, so which one
/// wins does not depend on the order the file system listed the directory.
Map<String, String> _buildLyricStemIndex(Iterable<String> lyricPaths) {
  final index = <String, String>{};
  for (final path in lyricPaths) {
    final directory = p.dirname(path).toLowerCase();
    final extension = p.extension(path).toLowerCase();
    for (final stem in _stemsOf(p.basenameWithoutExtension(path))) {
      final key = '$directory\u0001${stem.toLowerCase()}\u0001$extension';
      final existing = index[key];
      if (existing == null || path.compareTo(existing) < 0) {
        index[key] = path;
      }
    }
  }
  return index;
}

/// The keys one lyric file answers to. `周杰伦 - 稻香` also answers to `稻香`, which
/// is what lets it be found next to a file named `01. 稻香.flac`.
List<String> _stemsOf(String stem) {
  final trimmed = stem.trim();
  if (trimmed.isEmpty) return const [];
  final keys = <String>{trimmed};
  final dash = trimmed.lastIndexOf(' - ');
  if (dash > 0 && dash + 3 < trimmed.length) {
    final tail = trimmed.substring(dash + 3).trim();
    if (tail.isNotEmpty) keys.add(tail);
  }
  return keys.toList();
}

/// The stems a track's own file name suggests, for lyric files whose name does
/// not match it exactly.
///
/// Strips up to two leading track numbers (`01. 稻香`, `1-01 稻香`, `[3] 稻香`) and
/// also offers the part after the last ` - ` (`歌手 - 歌名` next to `歌名.flac`).
List<String> _fuzzyStemsFor(String audioStem) {
  var stem = audioStem.trim();
  for (var attempt = 0; attempt < 2; attempt++) {
    final stripped = stem
        .replaceFirst(
          RegExp(r'^\s*(?:\[\d{1,3}\]|\d{1,3}\s*[-._)]\s*|\d{1,3}\s+)'),
          '',
        )
        .trim();
    if (stripped == stem) break;
    stem = stripped;
  }
  if (stem.isEmpty) return const [];
  return _stemsOf(stem);
}
