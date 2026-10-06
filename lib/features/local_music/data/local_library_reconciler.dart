import 'package:path/path.dart' as p;

import 'local_lyrics_loader.dart';
import 'local_lyrics_store.dart';
import 'local_music_scan_result.dart';
import 'local_scan_snapshot.dart';
import 'local_track_store.dart';

/// Turns a raw scan (a list of [LocalScannedFile]) into the persisted index and
/// the UI-facing [LocalMusicScanResult].
///
/// Shared by the desktop/Dart scanner and the Android SAF scanner: the file
/// discovery differs completely between the two (a `dart:io` walk vs.
/// `DocumentFile` + `MediaMetadataRetriever`), but the incremental rules must
/// not diverge, and neither must the lyrics rules.
class LocalLibraryReconciler {
  LocalLibraryReconciler({
    required this.trackStore,
    required this.lyricsStore,
    LocalLyricsLoader? lyricsLoader,
  }) : lyricsLoader = lyricsLoader ?? LocalLyricsLoader();

  final LocalTrackStore trackStore;
  final LocalLyricsStore lyricsStore;
  final LocalLyricsLoader lyricsLoader;

  /// Reconciles [files] against the persisted index for [rootPath].
  ///
  /// * unchanged files reuse their stored row (no tag read happens here at all —
  ///   the caller already decided, via `changed`, which files to read);
  /// * lyrics are read from disk **only** for tracks that have no stored
  ///   lyrics yet, so the second scan performs zero lyric IO;
  /// * rows and lyric rows for files that disappeared under [rootPath] are
  ///   deleted; anything outside the root is untouched.
  Future<LocalMusicScanResult> reconcile({
    required String rootPath,
    required List<LocalScannedFile> files,
    List<String> skippedFiles = const [],
    Map<String, LocalLyricsPayload> resolvedLyrics = const {},
    Stopwatch? stopwatch,
  }) async {
    stopwatch ??= Stopwatch()..start();

    final known = await trackStore.loadIndex();
    final storedLyrics = await lyricsStore.loadAll();

    final entries = <LocalTrackEntry>[];
    final changedEntries = <LocalTrackEntry>[];
    final lyricsBySongId = <String, String>{};
    final skippedLyrics = <String>[];
    var parsedCount = 0;
    var reusedCount = 0;
    final scannedAt = DateTime.now().millisecondsSinceEpoch;

    for (final file in files) {
      if (file.changed) {
        parsedCount++;
        final entry = LocalTrackEntry(
          path: file.path,
          mtime: file.mtime,
          size: file.size,
          title: file.title,
          artistName: file.artist,
          albumName: file.album,
          durationMs: file.durationMs,
          trackNumber: file.trackNumber,
          coverPath: file.coverPath,
          scannedAt: scannedAt,
        );
        entries.add(entry);
        changedEntries.add(entry);
      } else {
        reusedCount++;
        entries.add(
          known[file.path] ??
              LocalTrackEntry(
                path: file.path,
                mtime: file.mtime,
                size: file.size,
                scannedAt: scannedAt,
              ),
        );
      }

      final stored = storedLyrics[file.path];
      if (stored != null && stored.isNotEmpty) {
        lyricsBySongId[file.path] = stored;
        continue;
      }

      // Android: `MainActivity` already read the sidecar file (a `content://`
      // URI that `dart:io` cannot open) and the caller decoded it.
      final preResolved = resolvedLyrics[file.path];
      if (preResolved != null) {
        lyricsBySongId[file.path] = preResolved.content;
        await lyricsStore.save(
          file.path,
          preResolved.content,
          preResolved.formatName,
        );
        continue;
      }

      for (final lyricsPath in file.lyricCandidates) {
        final payload = await lyricsLoader.load(lyricsPath);
        if (payload != null) {
          lyricsBySongId[file.path] = payload.content;
          await lyricsStore.save(file.path, payload.content, payload.formatName);
          break;
        }
        // A lyric file that is present but undecodable (an encrypted `.krc`,
        // a `.qrc` holding something else) is reported instead of being stored
        // as ciphertext — the UI can finally show a non-empty "跳过文件".
        skippedLyrics.add(lyricsPath);
      }
    }

    final presentPaths = {for (final entry in entries) entry.path};
    final removedPaths = <String>[
      for (final path in known.keys)
        if (!presentPaths.contains(path) && isUnderRoot(rootPath, path)) path,
    ];
    final removedLyrics = <String>[
      for (final songId in storedLyrics.keys)
        if (!presentPaths.contains(songId) && isUnderRoot(rootPath, songId))
          songId,
    ];

    if (changedEntries.isNotEmpty) {
      await trackStore.upsertAll(changedEntries);
    }
    if (removedPaths.isNotEmpty) {
      await trackStore.removePaths(removedPaths);
    }
    if (removedLyrics.isNotEmpty) {
      await lyricsStore.removePaths(removedLyrics);
    }

    entries.sort(
      (a, b) =>
          a.displayTitle.toLowerCase().compareTo(b.displayTitle.toLowerCase()),
    );

    stopwatch.stop();
    return LocalMusicScanResult(
      songs: [for (final entry in entries) entry.toSong()],
      lyricsBySongId: lyricsBySongId,
      skippedFiles: [...skippedFiles, ...skippedLyrics],
      tracks: entries,
      parsedCount: parsedCount,
      reusedCount: reusedCount,
      removedCount: removedPaths.length,
      skippedLyrics: skippedLyrics,
      elapsed: stopwatch.elapsed,
      rootPath: rootPath,
    );
  }

  /// True when [path] is inside [root] (case-insensitive: Windows and SAF
  /// disagree on the casing they report).
  static bool isUnderRoot(String root, String path) {
    final normalizedRoot = p.normalize(root).toLowerCase();
    final normalizedPath = p.normalize(path).toLowerCase();
    if (normalizedPath == normalizedRoot) return true;
    return normalizedPath.startsWith(
      normalizedRoot.endsWith(p.separator)
          ? normalizedRoot
          : '$normalizedRoot${p.separator}',
    );
  }
}
