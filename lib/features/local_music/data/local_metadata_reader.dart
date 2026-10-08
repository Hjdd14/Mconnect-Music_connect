import 'dart:convert';
import 'dart:io';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// Tags pulled out of one audio file.
///
/// Everything is nullable on purpose: a file may carry only some of the tags
/// (or none at all and still be perfectly playable), and the scanner falls back
/// to the file name / "未知歌手" rather than dropping the track.
class LocalAudioMetadata {
  final String? title;
  final String? artist;
  final String? album;
  final int durationMs;
  final int? trackNumber;
  final String? coverPath;

  /// Lyrics embedded in the file's own tag container (`ID3v2` `USLT`, MP4
  /// `©lyr`, Vorbis `LYRICS`, APEv2 `Lyrics`), or `null`.
  ///
  /// `audio_metadata_reader` parses this unconditionally; the value used to be
  /// read and thrown away. It ranks **below** a sidecar file with the same base
  /// name (`LocalLibraryReconciler`), so a hand-edited `.lrc` always wins.
  final String? lyrics;

  const LocalAudioMetadata({
    this.title,
    this.artist,
    this.album,
    this.durationMs = 0,
    this.trackNumber,
    this.coverPath,
    this.lyrics,
  });

  static const empty = LocalAudioMetadata();

  @override
  String toString() =>
      'LocalAudioMetadata(title=$title, artist=$artist, album=$album, '
      'durationMs=$durationMs, trackNumber=$trackNumber, cover=$coverPath, '
      // Never inline the lyrics themselves: they can be kilobytes long.
      'lyrics=${lyrics == null ? 'none' : '${lyrics!.length} chars'})';
}

/// Reads tags from a local audio file.
///
/// **Synchronous by design**: the desktop scan runs inside `Isolate.run`, where
/// an async API buys nothing but complicates the isolate boundary. The cover
/// cache directory is therefore resolved by the caller and passed in as a plain
/// path (see `LocalMusicRepository.scanDirectory`).
///
/// Abstract so the scanner's incremental behaviour can be asserted with a
/// counting double — what matters for "the second scan does not re-read
/// metadata" is *how many times this is called*, not what a real tag parser
/// returns.
abstract class LocalMetadataReader {
  /// Returns `null` when the file has no readable tag container at all.
  LocalAudioMetadata? read(String path, {bool coverArt = true});
}

/// [LocalMetadataReader] backed by `audio_metadata_reader` (pure Dart: ID3v1 /
/// ID3v2, FLAC+Vorbis, MP4, OGG, RIFF).
class AudioMetadataReader implements LocalMetadataReader {
  AudioMetadataReader({this.coverDirectoryPath, this.coverArtEnabled = true});

  /// Where embedded covers are written. When null, covers are skipped entirely
  /// rather than dropped somewhere unpredictable.
  final String? coverDirectoryPath;

  final bool coverArtEnabled;

  @override
  LocalAudioMetadata? read(String path, {bool coverArt = true}) {
    final file = File(path);
    // `readMetadata` opens the file and only closes it on the *success* path
    // (`parser.dart:18` + each parser's `reader.closeSync()`); for a file with no
    // matching parser it throws `NoMetadataParserException` with the handle
    // still open. On Windows that keeps the user's own music file locked until
    // the isolate exits, so the container is sniffed first and files the package
    // would reject are skipped without ever opening them for parsing.
    if (!_hasParseableContainer(file)) return null;
    try {
      final metadata = readMetadata(
        file,
        getImage: coverArtEnabled && coverArt,
      );
      return LocalAudioMetadata(
        title: _clean(metadata.title),
        artist: _clean(metadata.artist),
        album: _clean(metadata.album),
        durationMs: metadata.duration?.inMilliseconds ?? 0,
        trackNumber: metadata.trackNumber,
        coverPath: _writeCover(path, metadata.pictures),
        // Read unconditionally by the package, so this costs nothing extra. The
        // reconciler stores it with the `embedded` marker and only when no
        // sidecar lyric file next to the track decoded.
        lyrics: _clean(metadata.lyrics),
      );
    } on MetadataParserException {
      // A recognized-but-corrupt container. The package leaks the handle here
      // (there is no way to close it from the outside), which is why the scan
      // runs in a throwaway isolate: every leaked handle dies with it.
      return null;
    } on NoMetadataParserException {
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Mirrors the parser selection in `audio_metadata_reader`'s `readMetadata`:
  /// ID3v2 / FLAC / MP4 / OGG / RIFF, plus an MP3 carrying only an ID3v1 trailer.
  static bool _hasParseableContainer(File file) {
    final RandomAccessFile reader;
    try {
      reader = file.openSync();
    } catch (_) {
      return false;
    }
    try {
      final length = reader.lengthSync();
      if (length < 4) return false;

      final head = reader.readSync(length < 12 ? length : 12);
      if (head.length >= 3 &&
          head[0] == 0x49 &&
          head[1] == 0x44 &&
          head[2] == 0x33) {
        return true; // 'ID3'
      }
      if (head.length >= 4) {
        final marker = String.fromCharCodes(head.sublist(0, 4));
        if (marker == 'fLaC' || marker == 'RIFF' || marker == 'OggS') {
          return true;
        }
      }
      if (head.length >= 12 &&
          String.fromCharCodes(head.sublist(4, 8)) == 'ftyp') {
        return true; // MP4/M4A box
      }
      if (length >= 128) {
        reader.setPositionSync(length - 128);
        final trailer = reader.readSync(3);
        if (trailer.length == 3 &&
            String.fromCharCodes(trailer) == 'TAG') {
          return true; // ID3v1-only MP3
        }
      }
      return false;
    } catch (_) {
      return false;
    } finally {
      try {
        reader.closeSync();
      } catch (_) {}
    }
  }

  String? _writeCover(String audioPath, List<Picture> pictures) {
    final directory = coverDirectoryPath;
    if (!coverArtEnabled || directory == null || pictures.isEmpty) return null;
    final picture = pictures.first;
    if (picture.bytes.isEmpty) return null;
    try {
      final dir = Directory(directory);
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      final extension = _extensionForMime(picture.mimetype);
      final name = '${sha1.convert(utf8.encode(audioPath))}$extension';
      final file = File(p.join(dir.path, name));
      // Rewrite only when the size differs, so an unchanged embedded cover does
      // not churn the disk on every rescan.
      if (file.existsSync() && file.lengthSync() == picture.bytes.length) {
        return file.path;
      }
      file.writeAsBytesSync(picture.bytes, flush: false);
      return file.path;
    } catch (_) {
      return null;
    }
  }

  static String _extensionForMime(String mime) {
    switch (mime.toLowerCase()) {
      case 'image/png':
        return '.png';
      case 'image/webp':
        return '.webp';
      case 'image/gif':
        return '.gif';
      case 'image/bmp':
        return '.bmp';
      default:
        return '.jpg';
    }
  }

  static String? _clean(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
