import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/features/local_music/data/local_lyrics_store.dart';
import 'package:mconnect/features/local_music/data/local_music_repository.dart';
import 'package:mconnect/features/local_music/data/local_scan_root_store.dart';
import 'package:mconnect/features/local_music/data/local_track_store.dart';
import 'package:mconnect/features/local_music/data/online_library_snapshot.dart';
import 'package:mconnect/features/local_music/data/track_ratings_store.dart';
import 'package:mconnect/features/local_music/domain/local_library_query.dart';
import 'package:mconnect/features/local_music/presentation/providers/local_music_provider.dart';
import 'package:mconnect/models/artist.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/song.dart';
import 'package:path/path.dart' as p;

void main() {
  test('picking a folder applies scanner results to state', () async {
    final song = _song('content://media/tree/song-1', 'Picked Song');
    final picker = _FakeLocalMusicPicker(
      result: LocalMusicPickResult(
        selectedDirectory: 'Music',
        scanResult: LocalMusicScanResult(
          songs: [song],
          lyricsBySongId: {song.id: '[00:01.00]Lyric'},
          tracks: [_entry(song.id, 'Picked Song')],
          parsedCount: 1,
        ),
      ),
    );
    final notifier = _notifier(picker: picker);
    addTearDown(notifier.dispose);

    await notifier.pickAndScanDirectory();

    expect(picker.calls, 1);
    expect(notifier.state.selectedDirectory, 'Music');
    expect(notifier.state.songs, [song]);
    expect(notifier.state.lyricsBySongId[song.id], '[00:01.00]Lyric');
    expect(notifier.state.isScanning, isFalse);
    expect(notifier.state.error, isNull);
    expect(notifier.state.lastScan?.parsedCount, 1);
  });

  test('cancelled folder picking leaves existing songs untouched', () async {
    final existing = _song('file:///music/existing.mp3', 'Existing Song');
    final scanner = _FakeLocalMusicScanner(
      result: LocalMusicScanResult(
        songs: [existing],
        tracks: [_entry(existing.id, 'Existing Song')],
      ),
    );
    final notifier = _notifier(picker: _FakeLocalMusicPicker(), scanner: scanner);
    addTearDown(notifier.dispose);
    await notifier.scanDirectory('C:/Music');

    await notifier.pickAndScanDirectory();

    expect(notifier.state.songs, [existing]);
    expect(notifier.state.selectedDirectory, 'C:/Music');
    expect(scanner.calls, 1);
  });

  test('scan failure clears loading and stores an error', () async {
    final notifier = _notifier(
      picker: _FakeLocalMusicPicker(),
      scanner: _FakeLocalMusicScanner(error: StateError('no access')),
    );
    addTearDown(notifier.dispose);

    await notifier.scanDirectory('content://denied');

    expect(notifier.state.isScanning, isFalse);
    expect(notifier.state.error, contains('no access'));
  });

  test('a successful desktop scan remembers the folder', () async {
    final rootStore = MemoryLocalScanRootStore();
    final notifier = _notifier(
      rootStore: rootStore,
      picker: _FakeLocalMusicPicker(
        result: const LocalMusicPickResult(
          selectedDirectory: 'D:/Music',
          scanResult: LocalMusicScanResult(),
        ),
      ),
    );
    addTearDown(notifier.dispose);

    await notifier.pickAndScanDirectory();

    expect(await rootStore.read(), 'D:/Music');
  });

  test('opening the page shows the persisted library without rescanning', () async {
    final tracks = MemoryLocalTrackStore([
      _entry('D:/Music/a.flac', '已入库', durationMs: 190000),
    ]);
    final lyrics = MemoryLocalLyricsStore();
    await lyrics.save('D:/Music/a.flac', '[00:01.00]存好的词', 'lrc');
    final scanner = _FakeLocalMusicScanner();
    final notifier = _notifier(
      scanner: scanner,
      trackStore: tracks,
      lyricsStore: lyrics,
      rootStore: MemoryLocalScanRootStore(),
    );
    addTearDown(notifier.dispose);

    await notifier.loadFromIndex();

    expect(scanner.calls, 0, reason: '打开页面不得触发扫描');
    expect(notifier.state.songs.single.name, '已入库');
    expect(notifier.state.lyricsBySongId['D:/Music/a.flac'], '[00:01.00]存好的词');
    expect(notifier.state.isLoading, isFalse);
  });

  test('initialize() rescans the remembered root through the picker', () async {
    final tracks = MemoryLocalTrackStore([_entry('D:/Music/a.flac', '旧')]);
    final picker = _FakeLocalMusicPicker(
      rescanResult: LocalMusicScanResult(
        songs: [_song('D:/Music/a.flac', '新')],
        tracks: [_entry('D:/Music/a.flac', '新')],
        reusedCount: 1,
      ),
    );
    final notifier = _notifier(
      picker: picker,
      trackStore: tracks,
      rootStore: MemoryLocalScanRootStore('D:/Music'),
    );
    addTearDown(notifier.dispose);

    await notifier.initialize();

    expect(picker.rescanCalls, 1);
    expect(notifier.state.songs.single.name, '新');
    expect(notifier.state.lastScan?.reusedCount, 1);
    expect(notifier.state.selectedDirectory, 'D:/Music');
  });

  test('rescan() falls back to the scanner when the picker cannot rescan', () async {
    final scanner = _FakeLocalMusicScanner(
      result: LocalMusicScanResult(
        songs: [_song('D:/Music/b.flac', '扫描结果')],
        tracks: [_entry('D:/Music/b.flac', '扫描结果')],
      ),
    );
    final notifier = _notifier(
      scanner: scanner,
      rootStore: MemoryLocalScanRootStore('D:/Music'),
    );
    addTearDown(notifier.dispose);

    await notifier.rescan();

    expect(scanner.calls, 1);
    expect(scanner.lastPath, 'D:/Music');
    expect(notifier.state.songs.single.name, '扫描结果');
  });

  test('view switching and grouping are exposed on the state', () async {
    final notifier = _notifier(
      trackStore: MemoryLocalTrackStore([
        _entry('D:/Music/a.flac', 'A', artist: '甲', album: '专辑一'),
        _entry('D:/Music/b.flac', 'B', artist: '乙', album: '专辑二'),
      ]),
      rootStore: MemoryLocalScanRootStore(),
    );
    addTearDown(notifier.dispose);
    await notifier.loadFromIndex();

    expect(notifier.state.view, LocalLibraryView.songs);
    expect(notifier.state.albumGroups, hasLength(2));
    expect(notifier.state.artistGroups, hasLength(2));
    expect(notifier.state.folderGroups, hasLength(1));

    notifier.setView(LocalLibraryView.albums);
    expect(notifier.state.view, LocalLibraryView.albums);
  });

  test('merge-with-online hides the duplicate and marks the local row', () async {
    final localSong = _song('D:/Music/same.flac', '同一首', seconds: 200);
    final onlineSong = Song(
      id: 'ne-1',
      platform: PlatformType.netease,
      name: '同一首',
      artists: const [Artist(id: 'a', name: 'local')],
      duration: const Duration(seconds: 201),
    );
    final notifier = _notifier(
      onlineSnapshot: MemoryOnlineLibrarySnapshot([onlineSong]),
      trackStore: MemoryLocalTrackStore([_entry('D:/Music/same.flac', '同一首')]),
      rootStore: MemoryLocalScanRootStore(),
    );
    addTearDown(notifier.dispose);
    await notifier.scanDirectory('D:/Music');
    // `scanDirectory` goes through the fake scanner; force the real local song.
    notifier.setView(LocalLibraryView.songs);
    await notifier.setMergeWithOnline(true);

    expect(notifier.state.mergeWithOnline, isTrue);
    expect(notifier.state.onlineSongs, [onlineSong]);
    expect(
      notifier.state.isAlsoOnline(localSong),
      isTrue,
      reason: '本地曲应与在线曲用 dedupeKey 匹配上',
    );
  });

  test('visibleSongs merges local and online with one row per song', () {
    const state = LocalMusicState(
      mergeWithOnline: true,
      songs: [
        Song(
          id: 'D:/Music/a.flac',
          platform: PlatformType.local,
          name: '歌',
          artists: [Artist(id: 'local', name: '甲')],
          duration: Duration(seconds: 200),
        ),
      ],
      onlineSongs: [
        Song(
          id: 'ne-9',
          platform: PlatformType.netease,
          name: '歌',
          artists: [Artist(id: 'x', name: '甲')],
          duration: Duration(seconds: 200),
        ),
        Song(
          id: 'ne-10',
          platform: PlatformType.netease,
          name: '别的歌',
          artists: [Artist(id: 'y', name: '乙')],
          duration: Duration(seconds: 200),
        ),
      ],
    );

    expect(state.visibleSongs, hasLength(2));
    expect(state.visibleSongs.first.platform, PlatformType.local);
  });

  // ---- W2-C: platform "the media store changed" -> rescan --------------------

  test('a media-store change triggers exactly one stamped rescan', () async {
    // Android de-bounces on the Kotlin side and sends one `mediaStoreChanged`;
    // the reaction must be the *same* stamped rescan as the manual refresh (so a
    // no-op folder opens no audio file), and one event must mean one rescan.
    final changes = StreamController<Object?>.broadcast();
    addTearDown(changes.close);
    final picker = _FakeLocalMusicPicker(
      rescanResult: LocalMusicScanResult(songs: const [], tracks: const []),
    );
    final notifier = LocalMusicNotifier(
      scanner: _FakeLocalMusicScanner(),
      picker: picker,
      trackStore: MemoryLocalTrackStore(),
      lyricsStore: MemoryLocalLyricsStore(),
      rootStore: MemoryLocalScanRootStore('D:/Music'),
      onlineSnapshot: MemoryOnlineLibrarySnapshot(),
      ratingsStore: MemoryTrackRatingsStore(),
      mediaStoreChanges: changes.stream,
    );
    addTearDown(notifier.dispose);

    changes.add(null);
    await pumpEventQueue();
    expect(picker.rescanCalls, 1, reason: '媒体库变化必须触发一次重扫');

    changes.add(null);
    await pumpEventQueue();
    expect(
      picker.rescanCalls,
      2,
      reason: '每一次事件对应一次重扫（去抖在 Kotlin 侧完成）',
    );
  });

  // ---- W2-C: search / sort / filter, ratings, multi-select batch ------------

  group('search, sort and filter', () {
    test('the keyword narrows the rendered songs', () async {
      final notifier = _notifier(
        trackStore: MemoryLocalTrackStore([
          _entry('D:/Music/稻香.flac', '稻香', artist: '周杰伦', album: '魔杰座'),
          _entry('D:/Music/青花瓷.flac', '青花瓷', artist: '周杰伦', album: '我很忙'),
        ]),
      );
      addTearDown(notifier.dispose);

      await notifier.loadFromIndex();
      expect(notifier.state.visibleSongs, hasLength(2));
      expect(notifier.state.isQueryActive, isFalse);

      notifier.setKeyword('稻香');
      expect(notifier.state.visibleSongs.single.name, '稻香');
      expect(notifier.state.isQueryActive, isTrue);

      notifier.clearQuery();
      expect(notifier.state.visibleSongs, hasLength(2));
      expect(notifier.state.isQueryActive, isFalse);
    });

    test('sorting by play count uses the aggregated counts', () async {
      final played = _entry('D:/Music/b.flac', 'b');
      final notifier = _notifier(
        ratingsStore: MemoryTrackRatingsStore(
          playCounts: {localTrackSongKey(played): 7},
        ),
        trackStore: MemoryLocalTrackStore([
          _entry('D:/Music/a.flac', 'a'),
          played,
        ]),
      );
      addTearDown(notifier.dispose);
      await notifier.loadFromIndex();

      expect(notifier.state.playCounts, isNotEmpty);
      notifier.setSort(LocalSortField.playCount);
      expect(notifier.state.queriedTracks.last.path, played.path);

      notifier.setSortDescending(true);
      expect(notifier.state.queriedTracks.first.path, played.path);
    });

    test('sorting by play count reads the aggregate, not a stale cache',
        () async {
      // The whole point of aggregating from `play_events` instead of trusting
      // `track_ratings.play_count`: a play that happened after the cache was last
      // refreshed must still order the list correctly.
      final played = _entry('D:/Music/b.flac', 'b');
      final store = MemoryTrackRatingsStore(
        playCounts: {localTrackSongKey(played): 0},
      );
      final notifier = _notifier(
        ratingsStore: store,
        trackStore: MemoryLocalTrackStore([
          _entry('D:/Music/a.flac', 'a'),
          played,
        ]),
      );
      addTearDown(notifier.dispose);
      await notifier.loadFromIndex();

      // Plays happened since the last read of the *cache*.
      store.setPlayCount(localTrackSongKey(played), 7);
      await notifier.refreshRatings();

      notifier.setSort(LocalSortField.playCount);
      expect(
        notifier.state.queriedTracks.last.path,
        played.path,
        reason: '排序必须用实时聚合，陈旧缓存不得影响顺序',
      );
    });

    test('the rated filter reads the ratings map, and filters are ANDed',
        () async {
      final rated = _entry('D:/Music/a.flac', 'a');
      final notifier = _notifier(
        ratingsStore: MemoryTrackRatingsStore(
          ratings: {localTrackSongKey(rated): 5},
        ),
        trackStore: MemoryLocalTrackStore([
          rated,
          _entry('D:/Music/b.flac', 'b'),
        ]),
      );
      addTearDown(notifier.dispose);
      await notifier.loadFromIndex();

      notifier.toggleFilter(LocalTrackFilter.rated, true);
      expect(notifier.state.queriedTracks.single.path, rated.path);

      notifier.toggleFilter(LocalTrackFilter.unrated, true);
      expect(
        notifier.state.queriedTracks,
        isEmpty,
        reason: '两个筛选是 AND：同一首不可能既已评分又未评分',
      );
    });

    test('the album and artist views are filtered by the same query', () async {
      final notifier = _notifier(
        trackStore: MemoryLocalTrackStore([
          _entry('D:/Music/a.flac', '稻香', artist: '甲', album: 'X'),
          _entry('D:/Music/b.flac', '青花瓷', artist: '乙', album: 'Y'),
        ]),
      );
      addTearDown(notifier.dispose);
      await notifier.loadFromIndex();
      expect(notifier.state.albumGroups, hasLength(2));

      notifier.setKeyword('稻香');
      expect(notifier.state.albumGroups.single.title, 'X');
      expect(notifier.state.artistGroups.single.title, '甲');
      expect(
        notifier.state.folderGroups.single.trackCount,
        1,
        reason: '筛选必须对每个视图都生效，不能只有歌曲列表生效',
      );
    });
  });

  group('ratings', () {
    test('setRating writes through the store and updates the state', () async {
      final track = _entry('D:/Music/a.flac', 'a');
      final store = MemoryTrackRatingsStore();
      final notifier = _notifier(
        ratingsStore: store,
        trackStore: MemoryLocalTrackStore([track]),
      );
      addTearDown(notifier.dispose);
      await notifier.loadFromIndex();

      expect(notifier.state.ratingOf(track), 0);
      await notifier.setRating(track, 4);

      expect(notifier.state.ratingOf(track), 4);
      expect(await store.loadRatings(), {localTrackSongKey(track): 4});

      await notifier.setRating(track, 0);
      expect(notifier.state.ratingOf(track), 0);
      expect(
        await store.loadRatings(),
        isEmpty,
        reason: '评为 0 等于取消评分，而不是存一个 0',
      );
    });

    test('refreshRatings picks up a rating written elsewhere', () async {
      final track = _entry('D:/Music/a.flac', 'a');
      final store = MemoryTrackRatingsStore();
      final notifier = _notifier(
        ratingsStore: store,
        trackStore: MemoryLocalTrackStore([track]),
      );
      addTearDown(notifier.dispose);
      await notifier.loadFromIndex();

      await store.setRating(localTrackSongKey(track), 2);
      await notifier.refreshRatings();

      expect(notifier.state.ratingOf(track), 2);
    });

    test('syncPlayStats recomputes and then re-reads', () async {
      final store = MemoryTrackRatingsStore();
      final notifier = _notifier(ratingsStore: store);
      addTearDown(notifier.dispose);

      await notifier.syncPlayStats();
      expect(store.syncCalls, 1);
    });

    test('a completed scan refreshes the play aggregate exactly once', () async {
      // The aggregate is recomputed at the scan boundary and nowhere else: doing
      // it per rebuild would run a whole `GROUP BY` per frame.
      final song = _song('content://media/tree/song-1', 'Picked Song');
      final store = MemoryTrackRatingsStore();
      final notifier = _notifier(
        ratingsStore: store,
        picker: _FakeLocalMusicPicker(
          result: LocalMusicPickResult(
            selectedDirectory: 'Music',
            scanResult: LocalMusicScanResult(
              songs: [song],
              tracks: [_entry(song.id, 'Picked Song')],
              parsedCount: 1,
            ),
          ),
        ),
      );
      addTearDown(notifier.dispose);

      await notifier.pickAndScanDirectory();

      expect(store.syncCalls, 1);
    });
  });

  group('multi-select and batch', () {
    test('select all ticks exactly what the query shows', () async {
      final notifier = _notifier(
        trackStore: MemoryLocalTrackStore([
          _entry('D:/Music/稻香.flac', '稻香'),
          _entry('D:/Music/青花瓷.flac', '青花瓷'),
          _entry('D:/Music/东风破.flac', '东风破'),
        ]),
      );
      addTearDown(notifier.dispose);
      await notifier.loadFromIndex();

      notifier.setKeyword('稻香');
      notifier.selectAllVisible();
      expect(notifier.state.selectedCount, 1);
      expect(notifier.state.isSelecting, isTrue);
      expect(notifier.state.selectedTracks.single.path, 'D:/Music/稻香.flac');

      notifier.clearSelection();
      expect(notifier.state.isSelecting, isFalse);
    });

    test('toggling a path twice unticks it', () async {
      final notifier = _notifier(
        trackStore: MemoryLocalTrackStore([_entry('D:/Music/a.flac', 'a')]),
      );
      addTearDown(notifier.dispose);
      await notifier.loadFromIndex();

      notifier.toggleSelected('D:/Music/a.flac');
      expect(notifier.state.selectedCount, 1);
      notifier.toggleSelected('D:/Music/a.flac');
      expect(notifier.state.selectedCount, 0);
    });

    test('removing the selection deletes records and never the audio files',
        () async {
      final dir = await Directory.systemTemp.createTemp('mconnect_local_batch_');
      addTearDown(() => dir.delete(recursive: true));
      final file = File(p.join(dir.path, 'keep-me.flac'));
      await file.writeAsBytes([1, 2, 3, 4]);

      final ticked = _entry(file.path, 'keep-me');
      final kept = _entry(p.join(dir.path, 'other.flac'), 'other');
      final lyrics = MemoryLocalLyricsStore();
      await lyrics.save(file.path, '[00:00.00]词', 'lrc');

      final notifier = _notifier(
        trackStore: MemoryLocalTrackStore([ticked, kept]),
        lyricsStore: lyrics,
      );
      addTearDown(notifier.dispose);
      await notifier.loadFromIndex();

      notifier.toggleSelected(ticked.path);
      final removed = await notifier.removeSelected();

      expect(removed, 1);
      expect(
        await file.exists(),
        isTrue,
        reason: '批量移出曲库只删记录，绝不能删用户的音频文件',
      );
      expect(await file.length(), 4);
      expect(notifier.state.tracks.single.path, kept.path);
      expect(notifier.state.songs.single.id, kept.path);
      expect(notifier.state.selectedPaths, isEmpty);
      expect(
        await lyrics.loadAll(),
        isEmpty,
        reason: '这条记录的缓存歌词要跟着记录一起清掉',
      );
    });

    test('removing with nothing ticked is a no-op', () async {
      final notifier = _notifier(
        trackStore: MemoryLocalTrackStore([_entry('D:/Music/a.flac', 'a')]),
      );
      addTearDown(notifier.dispose);
      await notifier.loadFromIndex();

      expect(await notifier.removeSelected(), 0);
      expect(notifier.state.tracks, hasLength(1));
    });
  });
}

LocalMusicNotifier _notifier({
  LocalMusicPicker? picker,
  LocalMusicScanner? scanner,
  LocalTrackStore? trackStore,
  LocalLyricsStore? lyricsStore,
  LocalScanRootStore? rootStore,
  OnlineLibrarySnapshot? onlineSnapshot,
  TrackRatingsStore? ratingsStore,
}) {
  return LocalMusicNotifier(
    picker: picker,
    scanner: scanner ?? _FakeLocalMusicScanner(),
    trackStore: trackStore ?? MemoryLocalTrackStore(),
    lyricsStore: lyricsStore ?? MemoryLocalLyricsStore(),
    rootStore: rootStore ?? MemoryLocalScanRootStore(),
    onlineSnapshot: onlineSnapshot ?? MemoryOnlineLibrarySnapshot(),
    // Injected explicitly even though the default is already an in-memory store
    // under `flutter test`: a test about ratings must not silently depend on that
    // default staying that way.
    ratingsStore: ratingsStore ?? MemoryTrackRatingsStore(),
  );
}

Song _song(String id, String name, {int seconds = 0}) => Song(
  id: id,
  platform: PlatformType.local,
  name: name,
  artists: const [Artist(id: 'local', name: 'local')],
  duration: Duration(seconds: seconds),
);

LocalTrackEntry _entry(
  String path,
  String title, {
  String? artist,
  String? album,
  int durationMs = 0,
}) => LocalTrackEntry(
  path: path,
  mtime: 1,
  size: 1,
  title: title,
  artistName: artist,
  albumName: album,
  durationMs: durationMs,
);

class _FakeLocalMusicPicker implements LocalMusicPicker {
  final LocalMusicPickResult? result;
  final LocalMusicScanResult? rescanResult;
  int calls = 0;
  int rescanCalls = 0;

  _FakeLocalMusicPicker({this.result, this.rescanResult});

  @override
  Future<LocalMusicPickResult?> pickAndScanDirectory() async {
    calls++;
    return result;
  }

  @override
  Future<LocalMusicScanResult?> rescanSavedRoot() async {
    rescanCalls++;
    return rescanResult;
  }
}

class _FakeLocalMusicScanner implements LocalMusicScanner {
  final LocalMusicScanResult result;
  final Object? error;
  int calls = 0;
  String? lastPath;

  _FakeLocalMusicScanner({
    this.result = const LocalMusicScanResult(),
    this.error,
  });

  @override
  Future<LocalMusicScanResult> scanDirectory(String rootPath) async {
    calls++;
    lastPath = rootPath;
    final error = this.error;
    if (error != null) throw error;
    return result;
  }
}
