import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/features/local_music/data/local_music_repository.dart';
import 'package:mconnect/models/platform_type.dart';

void main() {
  test(
    'scans mainstream audio files and matches same-name timed lyrics',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'mconnect_local_music_',
      );
      addTearDown(() => root.delete(recursive: true));

      final songFile = File(
        '${root.path}${Platform.pathSeparator}Track One.mp3',
      );
      final flacFile = File(
        '${root.path}${Platform.pathSeparator}Track Two.flac',
      );
      final ignoredFile = File(
        '${root.path}${Platform.pathSeparator}cover.jpg',
      );
      final lyricsDir = Directory(
        '${root.path}${Platform.pathSeparator}lyrics',
      );

      await songFile.writeAsString('not real audio');
      await flacFile.writeAsString('not real audio');
      await ignoredFile.writeAsString('image');
      await lyricsDir.create();
      await File(
        '${root.path}${Platform.pathSeparator}Track One.lrc',
      ).writeAsString('[00:01.00]Hello');
      await File(
        '${lyricsDir.path}${Platform.pathSeparator}Track Two.qrc',
      ).writeAsString('[00:02.00]World');

      final result = await LocalMusicRepository().scanDirectory(root.path);

      expect(result.songs, hasLength(2));
      expect(result.songs.map((s) => s.platform).toSet(), {PlatformType.local});
      expect(
        result.songs.map((s) => s.name),
        containsAll(['Track One', 'Track Two']),
      );
      expect(result.lyricsBySongId[songFile.path], '[00:01.00]Hello');
      expect(result.lyricsBySongId[flacFile.path], '[00:02.00]World');
    },
  );
}
