import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../models/artist.dart';
import '../../../models/audio_quality.dart';
import '../../../models/platform_type.dart';
import '../../../models/song.dart';

abstract class LocalMusicScanner {
  Future<LocalMusicScanResult> scanDirectory(String rootPath);
}

class LocalMusicScanResult {
  final List<Song> songs;
  final Map<String, String> lyricsBySongId;
  final List<String> skippedFiles;

  const LocalMusicScanResult({
    this.songs = const [],
    this.lyricsBySongId = const {},
    this.skippedFiles = const [],
  });
}

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

  static const supportedLyricsExtensions = {'.lrc', '.krc', '.qrc', '.txt'};

  @override
  Future<LocalMusicScanResult> scanDirectory(String rootPath) async {
    final root = Directory(rootPath);
    if (!await root.exists()) {
      return LocalMusicScanResult(skippedFiles: [rootPath]);
    }

    final songs = <Song>[];
    final lyricsBySongId = <String, String>{};
    final skipped = <String>[];

    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final extension = p.extension(entity.path).toLowerCase();
      if (!supportedAudioExtensions.contains(extension)) continue;

      final song = _songFromFile(entity);
      songs.add(song);

      final lyrics = await _readSameNameLyrics(entity);
      if (lyrics != null && lyrics.trim().isNotEmpty) {
        lyricsBySongId[song.id] = lyrics;
      }
    }

    songs.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return LocalMusicScanResult(
      songs: songs,
      lyricsBySongId: lyricsBySongId,
      skippedFiles: skipped,
    );
  }

  Song _songFromFile(File file) {
    final name = p.basenameWithoutExtension(file.path).trim();
    return songFromLocalId(
      id: file.path,
      displayName: name.isEmpty ? p.basename(file.path) : name,
    );
  }

  static Song songFromLocalId({
    required String id,
    required String displayName,
  }) {
    final name = displayName.trim();
    return Song(
      id: id,
      platform: PlatformType.local,
      name: name.isEmpty ? id : name,
      artists: const [Artist(id: 'local', name: 'local')],
      availableQualities: const [
        AudioQuality(level: AudioLevel.low, bitrate: 0, format: 'local'),
      ],
    );
  }

  Future<String?> _readSameNameLyrics(File audioFile) async {
    final dir = p.dirname(audioFile.path);
    final baseName = p.basenameWithoutExtension(audioFile.path);
    for (final extension in supportedLyricsExtensions) {
      final sameFolder = File(p.join(dir, '$baseName$extension'));
      if (await sameFolder.exists()) return sameFolder.readAsString();

      final lyricsFolder = File(p.join(dir, 'lyrics', '$baseName$extension'));
      if (await lyricsFolder.exists()) return lyricsFolder.readAsString();
    }
    return null;
  }
}
