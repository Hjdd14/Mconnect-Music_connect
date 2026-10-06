import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/features/local_music/data/local_lyrics_store.dart';
import 'package:mconnect/features/local_music/data/local_metadata_reader.dart';
import 'package:mconnect/features/local_music/data/local_music_repository.dart';
import 'package:mconnect/features/local_music/data/local_track_store.dart';
import 'package:path/path.dart' as p;

import 'local_music_fixtures.dart';

/// Measures a realistic 1000-track library: real FLAC files with real tags.
///
/// This is a measurement, not a micro-benchmark of the tag parser: the claim
/// being checked is "the second visit reads tags for zero unchanged files",
/// and the wall-clock numbers show what that is worth. Numbers are printed so
/// the report can quote them; only the counters are asserted (a wall-clock
/// assertion would be flaky on a loaded CI machine).
void main() {
  test(
    '1000-track library: first scan parses every file, second scan parses none',
    () async {
      const trackCount = 1000;
      final root = await Directory.systemTemp.createTemp('mconnect_bench_');
      addTearDown(() async {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });

      final writeWatch = Stopwatch()..start();
      for (var i = 0; i < trackCount; i++) {
        final folder = p.join(root.path, 'album${i % 20}');
        await writeFlacFixture(
          Directory(folder),
          'track$i.flac',
          title: '曲目$i',
          artist: '歌手${i % 50}',
          album: '专辑${i % 20}',
          trackNumber: (i % 20) + 1,
          durationMs: 180000,
          paddingBytes: 8192,
        );
      }
      writeWatch.stop();

      final tracks = MemoryLocalTrackStore();
      final lyrics = MemoryLocalLyricsStore();

      // First scan: every file is new, so every tag container is opened.
      final firstReader = CountingMetadataReader();
      final firstRepo = LocalMusicRepository(
        metadataReader: firstReader,
        trackStore: tracks,
        lyricsStore: lyrics,
        coverDirectoryPath: p.join(root.path, 'covers'),
        scanInIsolate: false,
      );
      final first = await firstRepo.scanDirectory(root.path);

      // Second scan: identical tree, nothing modified.
      final secondReader = CountingMetadataReader();
      final secondRepo = LocalMusicRepository(
        metadataReader: secondReader,
        trackStore: tracks,
        lyricsStore: lyrics,
        coverDirectoryPath: p.join(root.path, 'covers'),
        scanInIsolate: false,
      );
      final second = await secondRepo.scanDirectory(root.path);

      // ignore: avoid_print
      print(
        '[WS-J benchmark] 1000 tracks | build=${writeWatch.elapsedMilliseconds}ms | '
        'first scan=${first.elapsed.inMilliseconds}ms '
        '(tag reads=${firstReader.calls}, reused=${first.reusedCount}) | '
        'second scan=${second.elapsed.inMilliseconds}ms '
        '(tag reads=${secondReader.calls}, reused=${second.reusedCount})',
      );

      expect(first.tracks, hasLength(trackCount));
      expect(firstReader.calls, trackCount);
      expect(second.tracks, hasLength(trackCount));
      expect(secondReader.calls, 0, reason: '第二次扫描不得读取任何元数据');
      expect(second.reusedCount, trackCount);
      expect(second.parsedCount, 0);
      expect(second.songs.first.duration, const Duration(milliseconds: 180000));

      // The incremental pass must not be slower than the full one.
      expect(
        second.elapsed.inMilliseconds,
        lessThanOrEqualTo(first.elapsed.inMilliseconds),
        reason: '增量扫描应当快于首次全量扫描',
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test(
    'the real tag parser cost is what the skip avoids (per-file measurement)',
    () async {
      final root = await Directory.systemTemp.createTemp('mconnect_bench_one_');
      addTearDown(() async {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });
      const samples = 200;
      for (var i = 0; i < samples; i++) {
        await writeFlacFixture(
          root,
          'sample$i.flac',
          title: '样本$i',
          artist: '歌手',
          album: '专辑',
          durationMs: 120000,
          paddingBytes: 8192,
        );
      }

      final reader = AudioMetadataReader(
        coverDirectoryPath: p.join(root.path, 'covers'),
      );

      // Warm the OS file cache so the number reflects parsing, not disk.
      for (var i = 0; i < samples; i++) {
        reader.read(p.join(root.path, 'sample$i.flac'));
      }

      final watch = Stopwatch()..start();
      for (var i = 0; i < samples; i++) {
        reader.read(p.join(root.path, 'sample$i.flac'));
      }
      watch.stop();

      final perFileMicros = watch.elapsedMicroseconds / samples;
      // ignore: avoid_print
      print(
        '[WS-J benchmark] real readMetadata cost = '
        '${(perFileMicros / 1000).toStringAsFixed(3)}ms/file '
        '($samples files in ${watch.elapsedMilliseconds}ms) '
        '=> skipping 1000 unchanged files saves ~'
        '${(perFileMicros).toStringAsFixed(0)}ms per scan',
      );

      expect(perFileMicros, greaterThan(0));
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
