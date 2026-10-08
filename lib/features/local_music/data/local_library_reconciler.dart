import 'dart:io';

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

  /// `format` marker stored for lyrics that came out of the audio container
  /// rather than a `.lrc`/`.krc`/`.qrc` sidecar.
  ///
  /// The `LyricsCache.format` column is the only per-row provenance slot the
  /// lyrics store has, and for a local row nothing parses by it: the player
  /// hands `content` alone to the resolver (`lyrics_provider.dart:64-66`), and
  /// `getCachedLyricsWithFormat` is deliberately never called for
  /// `PlatformType.local`. So the marker cannot mislabel a decoder.
  static const String embeddedLyricsFormat = 'embedded';

  /// Reconciles [files] against the persisted index for [rootPath].
  ///
  /// * unchanged files reuse their stored row (no tag read happens here at all —
  ///   the caller already decided, via `changed`, which files to read);
  /// * lyrics are read from disk **only** when the stored copy is missing or its
  ///   sidecar's `(mtime, size)` no longer matches the row's stamp, so an
  ///   unchanged sidecar costs one `stat` and no read;
  /// * lyrics fall back to the container's embedded tag when no sidecar decodes
  ///   (external file first, embedded second);
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
    final entriesToWrite = <LocalTrackEntry>[];
    final lyricsBySongId = <String, String>{};
    final skippedLyrics = <String>[];
    var parsedCount = 0;
    var reusedCount = 0;
    final scannedAt = DateTime.now().millisecondsSinceEpoch;

    for (final file in files) {
      final knownEntry = known[file.path];
      final storedLyricsForFile = storedLyrics[file.path];
      final hasStoredLyrics =
          storedLyricsForFile != null && storedLyricsForFile.isNotEmpty;

      // --- Do the stored lyrics still describe the files on disk? -----------
      //
      // `file.lyricCandidates` is an index of paths that exist (see
      // `LocalMusicRepository._lyricCandidates`), so stat'ing them costs one or
      // two syscalls per track and never opens a lyric file.
      final sidecarStamps = _sidecarStamps(file.lyricCandidates);
      final recordedMtime = knownEntry?.lyricsMtime;
      final recordedSize = knownEntry?.lyricsSize;

      // Reusable when a sidecar we already read is still stamped the same, or
      // when there is nothing to compare against at all: a `content://` sidecar
      // (Android, opaque to `dart:io`) and a sidecar that was deleted both keep
      // the stored row, which is the pre-v3 behaviour and never loses lyrics.
      final stampMatches = hasStoredLyrics &&
          recordedMtime != null &&
          sidecarStamps.any(
            (stamp) =>
                stamp.mtime == recordedMtime && stamp.size == recordedSize,
          );
      final nothingToCompare = hasStoredLyrics && sidecarStamps.isEmpty;

      String? lyrics = (stampMatches || nothingToCompare)
          ? storedLyricsForFile
          : null;
      var stampMtime = recordedMtime;
      var stampSize = recordedSize;

      if (lyrics == null) {
        // Android: `MainActivity` already read the sidecar file (a `content://`
        // URI that `dart:io` cannot open) and the caller decoded it. There is no
        // stamp to record, so the next scan reuses the stored row via
        // `nothingToCompare`.
        final preResolved = resolvedLyrics[file.path];
        if (preResolved != null) {
          lyrics = preResolved.content;
          await lyricsStore.save(
            file.path,
            preResolved.content,
            preResolved.formatName,
          );
        } else {
          for (final lyricsPath in file.lyricCandidates) {
            final payload = await lyricsLoader.load(lyricsPath);
            if (payload != null) {
              lyrics = payload.content;
              await lyricsStore.save(
                file.path,
                payload.content,
                payload.formatName,
              );
              // Stamp the file that actually decoded, so a later scan can tell
              // "unchanged" from "replaced in place". A candidate list can hold
              // several files (`.lrc` then `.krc` then …), and the preferred one
              // is not necessarily the one that decoded.
              final used = _sidecarStampOf(lyricsPath);
              stampMtime = used?.mtime;
              stampSize = used?.size;
              break;
            }
            // A lyric file that is present but undecodable (an encrypted `.krc`,
            // a `.qrc` holding something else) is reported instead of being
            // stored as ciphertext — the UI can finally show a non-empty "跳过文件".
            skippedLyrics.add(lyricsPath);
          }
        }

        // --- Fallback 2: lyrics embedded in the audio container -------------
        //
        // Priority is deliberately external-file-first: a sidecar next to the
        // track is what the user or their tag editor put there on purpose, and
        // it is often better timed than the container's tag. Embedded lyrics only
        // fill the gap when no candidate decoded — which is the common case, since
        // most files have no `.lrc` at all.
        //
        // The row records no file stamp (`() => null`): there is no sidecar whose
        // `(mtime, size)` these lyrics came from, and a stale stamp left over from
        // an earlier external read would make the embedded copy shadow a valid
        // sidecar that appears later.
        if (lyrics == null) {
          final embedded = _embeddedLyricsOf(file);
          if (embedded != null && embedded.trim().isNotEmpty) {
            lyrics = embedded;
            await lyricsStore.save(
              file.path,
              embedded,
              LocalLibraryReconciler.embeddedLyricsFormat,
            );
            stampMtime = null;
            stampSize = null;
          }
        }

        // A re-read that failed *and* has no embedded fallback must not drop
        // lyrics that are already stored: fall back to them and keep the old
        // stamp, so the next scan tries again.
        if (lyrics == null && hasStoredLyrics) {
          lyrics = storedLyricsForFile;
          stampMtime = recordedMtime;
          stampSize = recordedSize;
        }
      }

      if (lyrics != null && lyrics.isNotEmpty) {
        lyricsBySongId[file.path] = lyrics;
      }

      final LocalTrackEntry entry;
      if (file.changed) {
        parsedCount++;
        entry = LocalTrackEntry(
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
          lyricsMtime: stampMtime,
          lyricsSize: stampSize,
        );
      } else {
        reusedCount++;
        entry = (knownEntry ??
                LocalTrackEntry(
                  path: file.path,
                  mtime: file.mtime,
                  size: file.size,
                  scannedAt: scannedAt,
                ))
            .copyWith(
              lyricsMtime: () => stampMtime,
              lyricsSize: () => stampSize,
            );
      }
      entries.add(entry);

      // Write only the rows whose *content* changed: a track that was already in
      // the index and whose lyric stamp did not move is left untouched instead
      // of being re-serialised on every scan.
      final stampChanged = knownEntry == null ||
          knownEntry.lyricsMtime != entry.lyricsMtime ||
          knownEntry.lyricsSize != entry.lyricsSize;
      if (file.changed || stampChanged) {
        entriesToWrite.add(entry);
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

    if (entriesToWrite.isNotEmpty) {
      await trackStore.upsertAll(entriesToWrite);
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

/// Lyrics embedded in the audio container, or null when the scan did not carry
/// any.
///
/// The producer (`LocalMusicRepository._walkLocalMusic` →
/// `metadata.lyrics`) puts the container's lyrics into the scan record as
/// `LocalScannedFile.embeddedLyrics`; the record key is `embeddedLyrics`. The
/// fallback branch in [LocalLibraryReconciler.reconcile] decides *whether* it is
/// used — it only fills the gap when no sidecar decoded, and it records no file
/// stamp because these lyrics came from the track itself, not from a `.lrc`.
String? _embeddedLyricsOf(LocalScannedFile file) => file.embeddedLyrics;

/// `(mtime, size)` of one sidecar lyric file, or null when it cannot be stat'ed.
///
/// Deliberately a **stat and nothing else**: reading, decoding and storing lyric
/// content belongs to the lyrics loader; the reconciler only decides whether a
/// read is needed at all.
({int mtime, int size})? _sidecarStampOf(String path) {
  try {
    final stat = File(path).statSync();
    return (mtime: stat.modified.millisecondsSinceEpoch, size: stat.size);
  } catch (_) {
    // Both a SAF `content://` path (opaque to `dart:io` on Android) and a file
    // that vanished between the walk and this call land here, and both mean the
    // same thing: there is no stamp to compare against.
    return null;
  }
}

/// The stamps of every sidecar in [paths] that can be stat'ed.
List<({int mtime, int size})> _sidecarStamps(List<String> paths) {
  if (paths.isEmpty) return const [];
  final stamps = <({int mtime, int size})>[];
  for (final path in paths) {
    final stamp = _sidecarStampOf(path);
    if (stamp != null) stamps.add(stamp);
  }
  return stamps;
}
