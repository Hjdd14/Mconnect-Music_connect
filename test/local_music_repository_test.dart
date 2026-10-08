import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/core/database/app_database.dart';
import 'package:mconnect/features/local_music/data/android_local_music_service.dart';
import 'package:mconnect/features/local_music/data/local_library_reconciler.dart';
import 'package:mconnect/features/local_music/data/local_lyrics_loader.dart';
import 'package:mconnect/features/local_music/data/local_lyrics_store.dart';
import 'package:mconnect/features/local_music/data/local_metadata_reader.dart';
import 'package:mconnect/features/local_music/data/local_music_repository.dart';
import 'package:mconnect/features/local_music/data/local_scan_snapshot.dart';
import 'package:mconnect/features/local_music/data/local_track_store.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:path/path.dart' as p;

import 'local_music_fixtures.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('mconnect_local_music_');
  });

  tearDown(() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  LocalMusicRepository repository({
    LocalMetadataReader? reader,
    LocalTrackStore? tracks,
    LocalLyricsStore? lyrics,
    LocalLyricsLoader? lyricsLoader,
    bool? scanInIsolate,
  }) {
    return LocalMusicRepository(
      metadataReader: reader,
      trackStore: tracks ?? MemoryLocalTrackStore(),
      lyricsStore: lyrics ?? MemoryLocalLyricsStore(),
      lyricsLoader: lyricsLoader,
      coverDirectoryPath: p.join(root.path, 'covers'),
      scanInIsolate: scanInIsolate,
    );
  }

  group('Android SAF lyrics freshness', () {
    // Android cannot produce a `(mtime, size)` stamp: the sidecar is a
    // `content://` URI that `dart:io` cannot stat, so `MainActivity` hands over
    // the *content* instead and the reconciler has to compare that. Before W2-C
    // it short-circuited on "nothing to compare" (`no candidates` + stored lyrics)
    // and kept the stored row, so the freshly decoded text was thrown away and
    // replacing a same-named `.lrc` on the phone never refreshed anything.
    //
    // These tests drive the **real Android chain**, not a hand-built Dart record:
    // Kotlin's `{extension, content}` maps → `LocalScannedFile.fromMap` →
    // `AndroidLocalMusicScanPayload.decodeLyrics()` → `reconcile(resolvedLyrics:)`.

    const path = 'content://tree/primary%3AMusic/song.flac';
    const stored = '[00:01.00]旧词';
    const refreshed = '[00:01.00]新词';

    /// The record shape Kotlin sends for one track.
    Map<Object?, Object?> androidRecord({String? lyricContent}) => {
      'path': path,
      'mtime': 20,
      'size': 100,
      'changed': false,
      'title': '歌',
      if (lyricContent != null)
        'lyrics': [
          {'extension': '.lrc', 'content': lyricContent},
        ],
    };

    Future<(MemoryLocalTrackStore, MemoryLocalLyricsStore)>
    seededStores() async {
      final tracks = MemoryLocalTrackStore();
      final lyrics = MemoryLocalLyricsStore();
      await lyrics.save(path, stored, 'lrc');
      await tracks.upsertAll([
        LocalTrackEntry(path: path, mtime: 10, size: 100, title: '歌'),
      ]);
      return (tracks, lyrics);
    }

    /// What the app does with a scan payload: decode the raw lyric maps, then
    /// hand the decoded payloads to the reconciler.
    ({List<LocalScannedFile> files, Map<String, LocalLyricsPayload> resolved})
    androidScan(String? lyricContent) {
      final payload = AndroidLocalMusicScanPayload(
        selectedDirectory: 'content://tree/primary%3AMusic',
        files: [LocalScannedFile.fromMap(androidRecord(lyricContent: lyricContent))],
        rawLyrics: lyricContent == null
            ? const {}
            : {
                path: [
                  AndroidRawLyrics(content: lyricContent, extension: '.lrc'),
                ],
              },
      );
      return (files: payload.files, resolved: payload.decodeLyrics().resolved);
    }

    test('the map form really is the shape that produced the gap', () {
      // Pins the premise: the `{extension, content}` map never becomes a candidate
      // path, which is why "nothing to compare" was always true on Android and the
      // content comparison below is the only way the new text can win.
      final record = LocalScannedFile.fromMap(
        androidRecord(lyricContent: refreshed),
      );

      expect(record.lyricCandidates, isEmpty);
      expect(record.embeddedLyrics, isNull);
    });

    test('different content from the phone replaces the stored lyrics',
        () async {
      final (tracks, lyrics) = await seededStores();
      final reconciler = LocalLibraryReconciler(
        trackStore: tracks,
        lyricsStore: lyrics,
      );

      final scan = androidScan(refreshed);
      final result = await reconciler.reconcile(
        rootPath: 'content://tree/primary%3AMusic',
        files: scan.files,
        resolvedLyrics: scan.resolved,
      );

      expect(
        result.lyricsBySongId[path],
        refreshed,
        reason: 'SAF 下换掉同名 .lrc 必须采纳新内容，否则 Android 永远不刷新歌词',
      );
      expect(await lyrics.loadAll(), containsPair(path, refreshed));
    });

    test('identical content from the phone keeps the stored row', () async {
      final (tracks, lyrics) = await seededStores();
      final reconciler = LocalLibraryReconciler(
        trackStore: tracks,
        lyricsStore: lyrics,
      );

      final scan = androidScan(stored);
      final result = await reconciler.reconcile(
        rootPath: 'content://tree/primary%3AMusic',
        files: scan.files,
        resolvedLyrics: scan.resolved,
      );

      expect(result.lyricsBySongId[path], stored);
    });

    test('a deleted sidecar still keeps the stored lyrics', () async {
      // The desktop contract that must not regress while fixing the Android one:
      // no candidates and nothing freshly read means "keep what we have".
      final (tracks, lyrics) = await seededStores();
      final reconciler = LocalLibraryReconciler(
        trackStore: tracks,
        lyricsStore: lyrics,
      );

      final result = await reconciler.reconcile(
        rootPath: 'content://tree/primary%3AMusic',
        files: [LocalScannedFile.fromMap(androidRecord())],
      );

      expect(result.lyricsBySongId[path], stored);
    });
  });

  test('scans mainstream audio files and matches same-name timed lyrics', () async {
    final songFile = File(p.join(root.path, 'Track One.mp3'));
    final flacFile = File(p.join(root.path, 'Track Two.flac'));
    final ignoredFile = File(p.join(root.path, 'cover.jpg'));
    final lyricsDir = Directory(p.join(root.path, 'lyrics'));

    // Neither file is a real container, so both must fall back to the file name
    // rather than disappearing from the library.
    await songFile.writeAsString('not real audio');
    await flacFile.writeAsString('not real audio');
    await ignoredFile.writeAsString('image');
    await lyricsDir.create();
    await File(p.join(root.path, 'Track One.lrc')).writeAsString(
      '[00:01.00]Hello',
    );
    await File(p.join(lyricsDir.path, 'Track Two.qrc')).writeAsString(
      '<L T="2000" D="900"><P T="100" D="400">World</P></L>',
    );

    final result = await repository().scanDirectory(root.path);

    expect(result.songs, hasLength(2));
    expect(result.songs.map((s) => s.platform).toSet(), {PlatformType.local});
    expect(
      result.songs.map((s) => s.name),
      containsAll(['Track One', 'Track Two']),
    );
    expect(result.lyricsBySongId[songFile.path], '[00:01.00]Hello');
    expect(result.lyricsBySongId[flacFile.path], contains('World'));
  });

  test('finds a tagger-named sidecar when the file name differs', () async {
    // The shape most taggers write: the audio file is numbered, the lyric file is
    // named after the tags. The exact-basename lookup cannot see this pair.
    final songFile = File(p.join(root.path, '01. 稻香.mp3'));
    await songFile.writeAsString('not real audio');
    await File(p.join(root.path, '周杰伦 - 稻香.lrc')).writeAsString(
      '[00:01.00]稻香词',
    );

    final result = await repository().scanDirectory(root.path);

    expect(result.lyricsBySongId[songFile.path], '[00:01.00]稻香词');
  });

  test('finds a fuzzy sidecar inside a lyrics/ subdirectory too', () async {
    final songFile = File(p.join(root.path, '01. 稻香.mp3'));
    await songFile.writeAsString('not real audio');
    final lyricsDir = Directory(p.join(root.path, 'lyrics'));
    await lyricsDir.create();
    await File(p.join(lyricsDir.path, '周杰伦 - 稻香.lrc')).writeAsString(
      '[00:01.00]子目录词',
    );

    final result = await repository().scanDirectory(root.path);

    expect(result.lyricsBySongId[songFile.path], '[00:01.00]子目录词');
  });

  test('an exactly-named sidecar still beats a fuzzy one', () async {
    // Priority: the sidecar named after the audio file is what the user put
    // there on purpose, so it must win even when a tagger-named one exists.
    final songFile = File(p.join(root.path, '01. 稻香.mp3'));
    await songFile.writeAsString('not real audio');
    await File(p.join(root.path, '01. 稻香.lrc')).writeAsString('[00:01.00]精确');
    await File(p.join(root.path, '周杰伦 - 稻香.lrc')).writeAsString('[00:01.00]模糊');

    final result = await repository().scanDirectory(root.path);

    expect(result.lyricsBySongId[songFile.path], '[00:01.00]精确');
  });

  test('reads real tags, duration, track number and cover art', () async {
    final reader = CountingMetadataReader(
      inner: AudioMetadataReader(
        coverDirectoryPath: p.join(root.path, 'covers'),
      ),
    );
    await writeFlacFixture(
      root,
      'tagged.flac',
      title: '标题',
      artist: '歌手',
      album: '专辑',
      trackNumber: 3,
      durationMs: 3000,
      coverBytes: tinyPngBytes(),
    );

    final result = await repository(reader: reader).scanDirectory(root.path);

    expect(reader.calls, 1);
    final track = result.tracks.single;
    expect(track.title, '标题');
    expect(track.artistName, '歌手');
    expect(track.albumName, '专辑');
    expect(track.trackNumber, 3);
    expect(track.durationMs, closeTo(3000, 60));

    // Cover art is extracted to a real file, and Song.coverUrl stays null: the
    // app renders covers through CachedNetworkImage, which cannot read a path.
    expect(track.coverPath, isNotNull);
    expect(File(track.coverPath!).existsSync(), isTrue);
    expect(result.songs.single.coverUrl, isNull);
  });

  test(
    'the second scan reuses the persisted index and reads zero metadata',
    () async {
      for (var i = 0; i < 3; i++) {
        await writeFlacFixture(
          root,
          'track$i.flac',
          title: '曲目$i',
          artist: '歌手',
          album: '专辑',
          trackNumber: i + 1,
        );
      }
      final tracks = MemoryLocalTrackStore();
      final reader = CountingMetadataReader();
      final repo = repository(reader: reader, tracks: tracks);

      final first = await repo.scanDirectory(root.path);
      expect(first.parsedCount, 3);
      expect(first.reusedCount, 0);
      expect(reader.calls, 3);
      expect(first.songs.map((s) => s.name), contains('曲目1'));

      final second = await repo.scanDirectory(root.path);

      expect(second.parsedCount, 0, reason: '未变文件不得重新读取元数据');
      expect(second.reusedCount, 3);
      expect(reader.calls, 3, reason: '第二次扫描读取元数据的次数必须为 0');
      expect(second.wasFullyIncremental, isTrue);
      // Tags survive the reuse: they come from the database, not from the file.
      expect(second.songs.map((s) => s.name), contains('曲目1'));
      expect(second.tracks.map((t) => t.durationMs), everyElement(3000));
    },
  );

  test('only the modified file is re-read on a later scan', () async {
    final reader = CountingMetadataReader();
    final repo = repository(reader: reader);
    await writeFlacFixture(
      root,
      'a.flac',
      title: 'A',
      artist: '歌手',
      album: '专辑',
      durationMs: 3000,
    );
    await writeFlacFixture(
      root,
      'b.flac',
      title: 'B',
      artist: '歌手',
      album: '专辑',
      durationMs: 3000,
    );
    await repo.scanDirectory(root.path);
    expect(reader.calls, 2);

    // Same path, different content: `(mtime, size)` no longer matches.
    await writeFlacFixture(
      root,
      'a.flac',
      title: 'A2',
      artist: '歌手',
      album: '专辑',
      durationMs: 5000,
      paddingBytes: 8192,
    );

    final rescan = await repo.scanDirectory(root.path);

    expect(rescan.parsedCount, 1);
    expect(rescan.reusedCount, 1);
    expect(reader.calls, 3);
    expect(rescan.songs.map((s) => s.name), containsAll(['A2', 'B']));
  });

  test('deleted files are dropped from the index and their lyrics too', () async {
    final tracks = MemoryLocalTrackStore();
    final lyrics = MemoryLocalLyricsStore();
    final repo = repository(tracks: tracks, lyrics: lyrics);
    await writeFlacFixture(
      root,
      'gone.flac',
      title: 'Gone',
      artist: '歌手',
      album: '专辑',
    );
    await File(p.join(root.path, 'gone.lrc')).writeAsString('[00:01.00]词');

    final first = await repo.scanDirectory(root.path);
    expect(first.lyricsBySongId, hasLength(1));

    await File(p.join(root.path, 'gone.flac')).delete();
    await File(p.join(root.path, 'gone.lrc')).delete();
    final second = await repo.scanDirectory(root.path);

    expect(second.removedCount, 1);
    expect(second.tracks, isEmpty);
    expect(await tracks.loadAll(), isEmpty);
    expect(await lyrics.loadAll(), isEmpty);
  });

  test('same file name in two folders keeps its own lyrics (H-16 串词修复)', () async {
    final firstDir = Directory(p.join(root.path, 'A'))..createSync(recursive: true);
    final secondDir = Directory(p.join(root.path, 'B'))..createSync(recursive: true);
    await writeFlacFixture(
      firstDir,
      '01.flac',
      title: '甲',
      artist: '歌手',
      album: '专辑',
    );
    await writeFlacFixture(
      secondDir,
      '01.flac',
      title: '乙',
      artist: '歌手',
      album: '专辑',
    );
    await File(p.join(firstDir.path, '01.lrc')).writeAsString('[00:01.00]甲的词');
    await File(p.join(secondDir.path, '01.lrc')).writeAsString('[00:02.00]乙的词');

    final result = await repository().scanDirectory(root.path);

    final firstPath = p.join(firstDir.path, '01.flac');
    final secondPath = p.join(secondDir.path, '01.flac');
    expect(result.lyricsBySongId[firstPath], contains('甲的词'));
    expect(result.lyricsBySongId[secondPath], contains('乙的词'));
  });

  test('KRC lyrics are decrypted and parsed, not stored as ciphertext', () async {
    await writeFlacFixture(
      root,
      'kugou.flac',
      title: '酷狗',
      artist: '歌手',
      album: '专辑',
    );
    await File(p.join(root.path, 'kugou.krc')).writeAsString(
      LocalLyricsLoader.encryptKrcForTest(krcFixture()),
    );

    final result = await repository().scanDirectory(root.path);

    final stored = result.lyricsBySongId[p.join(root.path, 'kugou.flac')];
    expect(stored, isNotNull);
    expect(stored, contains('第二段'));
    expect(result.skippedLyrics, isEmpty);
  });

  test('an undecodable KRC is skipped instead of being stored as text', () async {
    await writeFlacFixture(
      root,
      'broken.flac',
      title: '坏歌词',
      artist: '歌手',
      album: '专辑',
    );
    final krcPath = p.join(root.path, 'broken.krc');
    await File(krcPath).writeAsString('!!!not-base64!!!');

    final result = await repository().scanDirectory(root.path);

    expect(result.lyricsBySongId, isEmpty);
    expect(result.skippedFiles, contains(krcPath));
  });

  test('a QRC file that is not QRC is rejected', () async {
    await writeFlacFixture(
      root,
      'plain.flac',
      title: '纯文本',
      artist: '歌手',
      album: '专辑',
    );
    final qrcPath = p.join(root.path, 'plain.qrc');
    await File(qrcPath).writeAsString('[00:01.00]not qrc at all');

    final result = await repository().scanDirectory(root.path);

    expect(result.lyricsBySongId, isEmpty);
    expect(result.skippedFiles, contains(qrcPath));
  });

  test('a .lrc sidecar is kept verbatim', () async {
    await writeFlacFixture(
      root,
      'lrc.flac',
      title: 'LRC',
      artist: '歌手',
      album: '专辑',
    );
    await File(p.join(root.path, 'lrc.lrc')).writeAsString('[00:01.00]原样保留');

    final result = await repository().scanDirectory(root.path);

    expect(
      result.lyricsBySongId[p.join(root.path, 'lrc.flac')],
      '[00:01.00]原样保留',
    );
  });

  test('lyrics are read only once: the second scan touches no lyric file', () async {
    await writeFlacFixture(
      root,
      'lyric.flac',
      title: '歌词',
      artist: '歌手',
      album: '专辑',
    );
    await File(p.join(root.path, 'lyric.lrc')).writeAsString('[00:01.00]词');
    final lyrics = MemoryLocalLyricsStore();
    final repo = repository(lyrics: lyrics);

    final first = await repo.scanDirectory(root.path);
    expect(first.lyricsBySongId, hasLength(1));

    // Even a file that disappears after being cached stays in the returned map
    // because it is served from the store, not re-read from disk.
    await File(p.join(root.path, 'lyric.lrc')).delete();
    final second = await repo.scanDirectory(root.path);

    expect(second.lyricsBySongId, hasLength(1));
    expect(second.skippedLyrics, isEmpty);
  });

  test('a sidecar is stamped once and an unchanged one is never re-read', () async {
    await writeFlacFixture(
      root,
      'stamped.flac',
      title: '标注',
      artist: '歌手',
      album: '专辑',
    );
    final lrc = File(p.join(root.path, 'stamped.lrc'));
    await lrc.writeAsString('[00:01.00]第一版');
    final tracks = MemoryLocalTrackStore();
    final lyrics = _CountingLyricsStore();
    final loader = _CountingLyricsLoader();
    final repo = repository(
      tracks: tracks,
      lyrics: lyrics,
      lyricsLoader: loader,
    );

    final first = await repo.scanDirectory(root.path);
    expect(first.lyricsBySongId, hasLength(1));
    expect(loader.loads, 1);
    expect(lyrics.saves, 1);

    // The index row records the stamp of the file the lyrics came from, which is
    // what makes the next scan able to tell "unchanged" from "replaced".
    final stat = lrc.statSync();
    final stampedRow = (await tracks.loadAll()).single;
    expect(stampedRow.lyricsMtime, stat.modified.millisecondsSinceEpoch);
    expect(stampedRow.lyricsSize, stat.size);

    final second = await repo.scanDirectory(root.path);
    expect(second.lyricsBySongId, hasLength(1));
    expect(loader.loads, 1, reason: '未变的 .lrc 不得再读一次');
    expect(lyrics.saves, 1, reason: '未变的歌词不得再落库');
    expect(second.reusedCount, 1);
  });

  test('replacing a sidecar in place is noticed and re-read', () async {
    await writeFlacFixture(
      root,
      'edited.flac',
      title: '编辑',
      artist: '歌手',
      album: '专辑',
    );
    final lrc = File(p.join(root.path, 'edited.lrc'));
    await lrc.writeAsString('[00:01.00]旧词');
    final lyrics = _CountingLyricsStore();
    final loader = _CountingLyricsLoader();
    final repo = repository(lyrics: lyrics, lyricsLoader: loader);

    await repo.scanDirectory(root.path);
    expect(loader.loads, 1);
    expect(lyrics.saves, 1);

    // Same path, different bytes: the `(mtime, size)` stamped on the row no
    // longer describes the file, so the stored lyrics are stale.
    await lrc.writeAsString('[00:01.00]新词，写长一些以便 size 必然不同');
    final rescan = await repo.scanDirectory(root.path);

    expect(loader.loads, 2, reason: '被替换的 .lrc 必须重读');
    expect(lyrics.saves, 2, reason: '新内容必须落库');
    expect(rescan.lyricsBySongId.values.single, contains('新词'));
    expect(rescan.lyricsBySongId.values.single, isNot(contains('旧词')));
  });

  test('a row from before v3 has no stamp and is read once, then stamped', () async {
    // A v2 library has the lyrics row but no `lyricsMtime`/`lyricsSize`, so the
    // first scan after the upgrade cannot prove the sidecar is unchanged and
    // re-reads it — exactly once. Every scan after that is a `stat` and nothing
    // more.
    await writeFlacFixture(
      root,
      'legacy.flac',
      title: '旧库',
      artist: '歌手',
      album: '专辑',
    );
    final audioPath = p.join(root.path, 'legacy.flac');
    await File(p.join(root.path, 'legacy.lrc')).writeAsString('[00:01.00]旧库词');
    final tracks = MemoryLocalTrackStore([
      LocalTrackEntry(path: audioPath, mtime: 0, size: 0),
    ]);
    final lyrics = _CountingLyricsStore();
    // What the pre-v3 build stored for this track, before stamps existed.
    await lyrics.save(audioPath, '[00:01.00]陈旧的词', 'lrc');
    lyrics.saves = 0;
    final loader = _CountingLyricsLoader();
    final repo = repository(
      tracks: tracks,
      lyrics: lyrics,
      lyricsLoader: loader,
    );

    final first = await repo.scanDirectory(root.path);
    expect(loader.loads, 1, reason: '无戳记的旧行需重读一次');
    expect(lyrics.saves, 1);
    expect(first.lyricsBySongId[audioPath], '[00:01.00]旧库词');
    expect((await tracks.loadAll()).single.lyricsMtime, isNotNull);
    expect((await tracks.loadAll()).single.lyricsSize, isNotNull);

    await repo.scanDirectory(root.path);
    expect(loader.loads, 1, reason: '补上戳记后不再重读');
    expect(lyrics.saves, 1);
  });

  test('falls back to the container lyrics when no sidecar decodes', () async {
    final audio = File(p.join(root.path, 'embedded.mp3'));
    await audio.writeAsBytes(_id3v24WithLyrics('[00:01.00]内嵌歌词'));
    final tracks = MemoryLocalTrackStore();
    final lyrics = MemoryLocalLyricsStore();
    final repo = LocalMusicRepository(
      // A real reader, so the container's `USLT` frame is what supplies the
      // fallback; injecting one also forces the inline (non-isolate) scan.
      metadataReader: AudioMetadataReader(),
      trackStore: tracks,
      lyricsStore: lyrics,
      scanInIsolate: false,
    );

    final result = await repo.scanDirectory(root.path);

    expect(result.lyricsBySongId[audio.path], '[00:01.00]内嵌歌词');
    expect(
      (await lyrics.loadAllWithFormat())[audio.path],
      LocalLibraryReconciler.embeddedLyricsFormat,
      reason: '内嵌来源必须被标成 embedded',
    );
    // No file stamp: these lyrics did not come from a sidecar, and stamping them
    // with one would let the embedded copy shadow a `.lrc` that appears later.
    expect((await tracks.loadAll()).single.lyricsMtime, isNull);
    expect((await tracks.loadAll()).single.lyricsSize, isNull);

    // The fallback is not re-read on every scan.
    final second = await repo.scanDirectory(root.path);
    expect(second.lyricsBySongId[audio.path], '[00:01.00]内嵌歌词');
  });

  test('a sidecar .lrc wins over the container lyrics', () async {
    final audio = File(p.join(root.path, 'embedded2.mp3'));
    await audio.writeAsBytes(_id3v24WithLyrics('[00:01.00]内嵌歌词'));
    await File(
      p.join(root.path, 'embedded2.lrc'),
    ).writeAsString('[00:02.00]外部词');
    final lyrics = MemoryLocalLyricsStore();
    final repo = LocalMusicRepository(
      metadataReader: AudioMetadataReader(),
      trackStore: MemoryLocalTrackStore(),
      lyricsStore: lyrics,
      scanInIsolate: false,
    );

    final result = await repo.scanDirectory(root.path);

    expect(
      result.lyricsBySongId[audio.path],
      '[00:02.00]外部词',
      reason: '外部文件优先于内嵌',
    );
    expect((await lyrics.loadAllWithFormat())[audio.path], 'lrc');
  });

  test('a sidecar added later takes over from the stored embedded lyrics', () async {
    // The upgrade path the "embedded rows carry no file stamp" decision exists
    // for: with a stamp recorded, the embedded copy would look "unchanged" and
    // never yield to the sidecar.
    final audio = File(p.join(root.path, 'embedded3.mp3'));
    await audio.writeAsBytes(_id3v24WithLyrics('[00:01.00]内嵌歌词'));
    final tracks = MemoryLocalTrackStore();
    final lyrics = MemoryLocalLyricsStore();
    final repo = LocalMusicRepository(
      metadataReader: AudioMetadataReader(),
      trackStore: tracks,
      lyricsStore: lyrics,
      scanInIsolate: false,
    );

    await repo.scanDirectory(root.path);
    expect(
      (await lyrics.loadAllWithFormat())[audio.path],
      LocalLibraryReconciler.embeddedLyricsFormat,
    );

    await File(
      p.join(root.path, 'embedded3.lrc'),
    ).writeAsString('[00:02.00]外部词');
    final result = await repo.scanDirectory(root.path);

    expect(result.lyricsBySongId[audio.path], '[00:02.00]外部词');
    expect((await lyrics.loadAllWithFormat())[audio.path], 'lrc');
    expect((await tracks.loadAll()).single.lyricsMtime, isNotNull);
  });

  test('the isolate scan path reads the same tags', () async {
    await writeFlacFixture(
      root,
      'isolated.flac',
      title: '隔离路径',
      artist: '歌手',
      album: '专辑',
      durationMs: 4000,
    );

    final result = await repository(scanInIsolate: true).scanDirectory(root.path);

    expect(result.tracks, hasLength(1));
    expect(result.tracks.single.title, '隔离路径');
    expect(result.tracks.single.durationMs, closeTo(4000, 60));
    expect(result.parsedCount, 1);
  });

  test('the drift-backed stores persist the index across repository instances', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

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
    await File(p.join(root.path, 'one.lrc')).writeAsString('[00:01.00]持久化');

    final firstReader = CountingMetadataReader();
    final first = await LocalMusicRepository(
      metadataReader: firstReader,
      trackStore: DriftLocalTrackStore(database: db),
      lyricsStore: DriftLocalLyricsStore(database: db),
      coverDirectoryPath: p.join(root.path, 'covers'),
    ).scanDirectory(root.path);
    expect(firstReader.calls, 2);
    expect(first.tracks, hasLength(2));

    // A brand-new repository over the same database — as when the page is
    // reopened — must not open a single audio file.
    final secondReader = CountingMetadataReader();
    final second = await LocalMusicRepository(
      metadataReader: secondReader,
      trackStore: DriftLocalTrackStore(database: db),
      lyricsStore: DriftLocalLyricsStore(database: db),
      coverDirectoryPath: p.join(root.path, 'covers'),
    ).scanDirectory(root.path);

    expect(secondReader.calls, 0);
    expect(second.reusedCount, 2);
    expect(second.songs.map((s) => s.name), containsAll(['第一首', '第二首']));
    expect(second.lyricsBySongId, hasLength(1));

    final rows = await db.select(db.localTracks).get();
    expect(rows, hasLength(2));
    expect(rows.map((r) => r.title), containsAll(['第一首', '第二首']));
    expect((await db.select(db.lyricsCache).get()), hasLength(1));
  });

  test('an index row outside the scanned root is left alone', () async {
    final other = Directory(p.join(root.path, 'other'))..createSync(recursive: true);
    final scanned = Directory(p.join(root.path, 'scanned'))..createSync();
    final tracks = MemoryLocalTrackStore([
      LocalTrackEntry(path: p.join(other.path, 'x.flac'), mtime: 1, size: 1),
    ]);
    await writeFlacFixture(
      scanned,
      'y.flac',
      title: 'Y',
      artist: '歌手',
      album: '专辑',
    );

    final result = await repository(tracks: tracks).scanDirectory(scanned.path);

    expect(result.removedCount, 0);
    expect(await tracks.loadAll(), hasLength(2));
  });
}

/// Lyrics store that counts how often content is written.
///
/// The schema-v3 contract is "an unchanged sidecar is not re-read and not
/// re-written", and a write is the observable half of it.
class _CountingLyricsStore extends MemoryLocalLyricsStore {
  int saves = 0;

  @override
  Future<void> save(
    String songId,
    String content,
    String format, {
    int? syncedAt,
  }) async {
    saves += 1;
    await super.save(songId, content, format, syncedAt: syncedAt);
  }
}

/// Lyrics loader that counts how often a sidecar file is actually opened.
class _CountingLyricsLoader extends LocalLyricsLoader {
  int loads = 0;

  @override
  Future<LocalLyricsPayload?> load(String lyricsPath) {
    loads += 1;
    return super.load(lyricsPath);
  }
}

/// A minimal ID3v2.4 tag holding one `USLT` (unsynchronised lyrics) frame.
///
/// The MP3 container only needs a leading `ID3` tag to be accepted by
/// `audio_metadata_reader` (`MP3Parser.hasID3v2Tag`), and it tolerates a file
/// with no MPEG audio frame at all (`_parseAudioFrames` returns early). The
/// lyrics parser requires a zero-length content descriptor, which is the `0x00`
/// after the three language bytes.
///
/// The header is `ID3` + version(2) + flags(1) + synchsafe size(4) = 10 bytes —
/// the flags byte is easy to forget and shifting the size by one byte makes the
/// parser read a garbage tag size and bail out.
List<int> _id3v24WithLyrics(String? lyrics) {
  final frames = <int>[
    if (lyrics != null)
      ..._frame('USLT', [
        0x03, // UTF-8
        0x65, 0x6E, 0x67, // 'eng'
        0x00, // empty descriptor, null-terminated
        ...utf8.encode(lyrics),
      ]),
  ];
  return [
    0x49, 0x44, 0x33, // 'ID3'
    0x04, 0x00, // v2.4
    0x00, // header flags
    ..._synchsafe(frames.length),
    ...frames,
  ];
}

List<int> _frame(String id, List<int> payload) => [
  ...id.codeUnits,
  ..._synchsafe(payload.length),
  0x00, 0x00, // frame flags
  ...payload,
];

/// ID3v2 sizes are 28-bit synchsafe integers (7 bits per byte).
List<int> _synchsafe(int value) => [
  (value >> 21) & 0x7F,
  (value >> 14) & 0x7F,
  (value >> 7) & 0x7F,
  value & 0x7F,
];
