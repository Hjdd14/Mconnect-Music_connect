import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'local_lyrics_loader.dart';
import 'local_scan_snapshot.dart';

/// Raw sidecar lyrics as handed over by `MainActivity`.
///
/// The content is *undecoded*: `.krc` still has to be decrypted, which happens
/// here in Dart so the app keeps exactly one implementation of the KRC
/// algorithm (`LocalLyricsLoader.decryptKrc`).
class AndroidRawLyrics {
  final String content;
  final String extension;

  const AndroidRawLyrics({required this.content, required this.extension});
}

/// One Android scan, already carrying real tags from `MediaMetadataRetriever`.
class AndroidLocalMusicScanPayload {
  final String selectedDirectory;

  /// The SAF tree URI, persisted so the folder does not have to be re-picked.
  final String? treeUri;

  final List<LocalScannedFile> files;

  /// Sidecar lyric payloads per song path, highest preference first (`.lrc`
  /// before `.krc` before `.qrc` before `.txt`).
  final Map<String, List<AndroidRawLyrics>> rawLyrics;

  /// Files Kotlin could not read, plus lyric files whose content was rejected.
  final List<String> skippedFiles;

  const AndroidLocalMusicScanPayload({
    required this.selectedDirectory,
    this.treeUri,
    this.files = const [],
    this.rawLyrics = const {},
    this.skippedFiles = const [],
  });

  /// Decodes every raw lyric payload, dropping the ones that do not decode.
  ///
  /// An encrypted `.krc` that cannot be decrypted, or a `.qrc` that is not QRC,
  /// is reported in `rejectedLyrics` instead of being persisted as ciphertext
  /// (the old code read it with `readText()` and handed it to the LRC parser),
  /// and the next candidate for that track is tried.
  ({Map<String, LocalLyricsPayload> resolved, List<String> rejectedLyrics})
  decodeLyrics() {
    final resolved = <String, LocalLyricsPayload>{};
    final rejected = <String>[];
    rawLyrics.forEach((songPath, candidates) {
      for (final raw in candidates) {
        final payload = LocalLyricsLoader.decode(raw.content, raw.extension);
        if (payload == null) {
          rejected.add('$songPath${raw.extension}');
          continue;
        }
        resolved[songPath] = payload;
        return;
      }
    });
    return (resolved: resolved, rejectedLyrics: rejected);
  }
}

/// Method-channel bridge to the Android SAF scanner.
class AndroidLocalMusicService {
  static const MethodChannel _channel = MethodChannel(
    'com.mconnect.mconnect/local_music',
  );

  static final AndroidLocalMusicService instance = AndroidLocalMusicService._();

  AndroidLocalMusicService._();

  @visibleForTesting
  AndroidLocalMusicService.test();

  /// Opens the folder picker, then scans the picked tree.
  ///
  /// [known] is the `(path, mtime, size)` index: Kotlin uses it to skip
  /// `MediaMetadataRetriever` for unchanged files, which is the expensive part
  /// of an Android scan.
  Future<AndroidLocalMusicScanPayload?> pickAndScanDirectory({
    Map<String, List<int>> known = const {},
  }) async {
    final result = await _channel.invokeMapMethod<Object?, Object?>(
      'pickAndScanDirectory',
      {'known': known},
    );
    if (result == null) return null;
    return _parse(result);
  }

  /// Rescans a previously granted SAF tree without showing the picker.
  Future<AndroidLocalMusicScanPayload?> rescanDirectory(
    String treeUri, {
    Map<String, List<int>> known = const {},
  }) async {
    final result = await _channel.invokeMapMethod<Object?, Object?>(
      'rescanDirectory',
      {'uri': treeUri, 'known': known},
    );
    if (result == null) return null;
    return _parse(result);
  }

  AndroidLocalMusicScanPayload _parse(Map<Object?, Object?> map) {
    final files = <LocalScannedFile>[];
    final rawLyrics = <String, List<AndroidRawLyrics>>{};

    final songsRaw = map['songs'];
    if (songsRaw is List) {
      for (final item in songsRaw) {
        if (item is! Map) continue;
        final file = LocalScannedFile.fromMap(item);
        if (file.path.isEmpty) continue;
        files.add(file);

        final lyricsRaw = item['lyrics'];
        if (lyricsRaw is List) {
          final candidates = <AndroidRawLyrics>[];
          for (final candidate in lyricsRaw) {
            if (candidate is! Map) continue;
            final content = candidate['content']?.toString();
            final extension = candidate['extension']?.toString();
            if (content == null ||
                content.trim().isEmpty ||
                extension == null ||
                extension.trim().isEmpty) {
              continue;
            }
            candidates.add(
              AndroidRawLyrics(content: content, extension: extension),
            );
          }
          if (candidates.isNotEmpty) rawLyrics[file.path] = candidates;
        }
      }
    }

    final skippedRaw = map['skippedFiles'];
    final skippedFiles = <String>[
      if (skippedRaw is List)
        for (final item in skippedRaw)
          if (item != null) item.toString(),
    ];

    return AndroidLocalMusicScanPayload(
      selectedDirectory:
          map['selectedDirectory']?.toString() ?? 'Android media folder',
      treeUri: _nonEmpty(map['treeUri']),
      files: files,
      rawLyrics: rawLyrics,
      skippedFiles: skippedFiles,
    );
  }

  static String? _nonEmpty(Object? value) {
    final text = value?.toString().trim();
    return (text == null || text.isEmpty) ? null : text;
  }
}
