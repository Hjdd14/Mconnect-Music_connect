import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../../models/song.dart';
import 'local_music_repository.dart';

class AndroidLocalMusicService {
  static const MethodChannel _channel = MethodChannel(
    'com.mconnect.mconnect/local_music',
  );

  static final AndroidLocalMusicService instance = AndroidLocalMusicService._();

  AndroidLocalMusicService._();

  @visibleForTesting
  AndroidLocalMusicService.test();

  Future<AndroidLocalMusicPickResult?> pickAndScanDirectory() async {
    final result = await _channel.invokeMapMethod<String, Object?>(
      'pickAndScanDirectory',
    );
    if (result == null) return null;
    return AndroidLocalMusicPickResult(
      selectedDirectory:
          result['selectedDirectory']?.toString() ?? 'Android media folder',
      scanResult: _scanResultFromMap(result),
    );
  }

  LocalMusicScanResult _scanResultFromMap(Map<String, Object?> map) {
    final songsRaw = map['songs'];
    final songs = <Song>[];
    if (songsRaw is List) {
      for (final item in songsRaw.whereType<Map>()) {
        final id = item['id']?.toString() ?? '';
        final name = item['name']?.toString() ?? id;
        if (id.isEmpty) continue;
        songs.add(
          LocalMusicRepository.songFromLocalId(id: id, displayName: name),
        );
      }
    }

    final lyricsRaw = map['lyricsBySongId'];
    final lyricsBySongId = <String, String>{
      if (lyricsRaw is Map)
        for (final entry in lyricsRaw.entries)
          if (entry.key != null && entry.value != null)
            entry.key.toString(): entry.value.toString(),
    };

    final skippedRaw = map['skippedFiles'];
    final skippedFiles = <String>[
      if (skippedRaw is List)
        for (final item in skippedRaw) item.toString(),
    ];

    return LocalMusicScanResult(
      songs: songs,
      lyricsBySongId: lyricsBySongId,
      skippedFiles: skippedFiles,
    );
  }
}

class AndroidLocalMusicPickResult {
  final String selectedDirectory;
  final LocalMusicScanResult scanResult;

  const AndroidLocalMusicPickResult({
    required this.selectedDirectory,
    required this.scanResult,
  });
}
