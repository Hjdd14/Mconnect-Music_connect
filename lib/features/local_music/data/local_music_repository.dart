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

  for (final entity in root.listSync(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    final path = entity.path;
    final extension = p.extension(path).toLowerCase();
    if (LocalMusicRepository.supportedAudioExtensions.contains(extension)) {
      audioPaths.add(path);
    } else if (LocalLyricsLoader.supportedExtensions.contains(extension)) {
      lyricIndex[path.toLowerCase()] = path;
    }
  }

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
      lyricCandidates: _lyricCandidates(path, lyricIndex),
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
      }
    }
    records.add(record);
  }
  return records;
}

/// Existing lyric files for [audioPath], in preference order.
///
/// The lookups are index hits, not `exists()` calls, so a 1000-track library
/// pays no extra IO for lyrics it already has.
List<String> _lyricCandidates(String audioPath, Map<String, String> index) {
  final directory = p.dirname(audioPath);
  final baseName = p.basenameWithoutExtension(audioPath);
  final candidates = <String>[];
  for (final extension in LocalLyricsLoader.supportedExtensions) {
    for (final candidate in [
      p.join(directory, '$baseName$extension'),
      p.join(directory, 'lyrics', '$baseName$extension'),
    ]) {
      final real = index[candidate.toLowerCase()];
      if (real != null && !candidates.contains(real)) {
        candidates.add(real);
      }
    }
  }
  return candidates;
}
