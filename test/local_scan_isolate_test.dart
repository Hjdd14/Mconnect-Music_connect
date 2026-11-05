import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/features/local_music/data/local_lyrics_store.dart';
import 'package:mconnect/features/local_music/data/local_music_repository.dart';
import 'package:mconnect/features/local_music/data/local_track_store.dart';
import 'package:path/path.dart' as p;

import 'local_music_fixtures.dart';

/// The desktop scan runs on a worker isolate (H-16). These tests pin the two
/// halves of that contract that are easy to lose:
///
/// * a real library scanned through `Isolate.run` keeps every tag and duration
///   - the isolate boundary only carries primitives, so a record that grows a
///   non-sendable field would silently drop tags instead of failing loudly;
/// * when the isolate cannot start at all, the scan degrades to an inline walk
///   rather than leaving the local page empty.
void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('mconnect_scan_isolate_');
  });

  tearDown(() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  LocalMusicRepository repository({
    bool? scanInIsolate,
    IsolateScanRunner? isolateRunner,
  }) {
    return LocalMusicRepository(
      trackStore: MemoryLocalTrackStore(),
      lyricsStore: MemoryLocalLyricsStore(),
      coverDirectoryPath: p.join(root.path, 'covers'),
      scanInIsolate: scanInIsolate,
      isolateRunner: isolateRunner,
    );
  }

  test(
    'a large library is scanned on the worker isolate with its tags',
    () async {
      const trackCount = 120;
      for (var i = 0; i < trackCount; i++) {
        await writeFlacFixture(
          Directory(p.join(root.path, 'album${i % 12}')),
          'track$i.flac',
          title: '曲目$i',
          artist: '歌手${i % 5}',
          album: '专辑${i % 12}',
          trackNumber: (i % 12) + 1,
          durationMs: 180000,
          paddingBytes: 1024,
        );
      }

      final result = await repository(scanInIsolate: true)
          .scanDirectory(root.path);

      expect(result.tracks, hasLength(trackCount));
      expect(result.parsedCount, trackCount);
      expect(
        result.tracks.map((track) => track.title),
        everyElement(isNotNull),
      );
      expect(
        result.tracks.map((track) => track.durationMs),
        everyElement(closeTo(180000, 200)),
      );
      expect(
        result.tracks.map((track) => track.artistName).toSet(),
        hasLength(5),
      );
    },
  );

  test(
    'an isolate that cannot start still produces the whole library',
    () async {
      await writeFlacFixture(
        root,
        'one.flac',
        title: '第一首',
        artist: '甲',
        album: '专辑',
        durationMs: 2000,
      );
      await writeFlacFixture(
        root,
        'two.flac',
        title: '第二首',
        artist: '乙',
        album: '专辑',
        durationMs: 3000,
      );
      final runner = _FailingIsolateRunner();

      final result = await repository(
        scanInIsolate: true,
        isolateRunner: runner.call,
      ).scanDirectory(root.path);

      expect(runner.attempts, 1, reason: 'the isolate is tried first');
      expect(result.tracks, hasLength(2));
      expect(
        result.songs.map((song) => song.name),
        containsAll(['第一首', '第二首']),
      );
    },
  );
}

/// Stands in for `Isolate.run` on a platform where spawning one fails.
class _FailingIsolateRunner {
  int attempts = 0;

  Future<List<Map<String, Object?>>> call(
    FutureOr<List<Map<String, Object?>>> Function() computation,
  ) async {
    attempts++;
    throw UnsupportedError('isolates are not available here');
  }
}
