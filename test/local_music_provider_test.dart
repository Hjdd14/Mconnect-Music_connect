import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/features/local_music/data/local_lyrics_store.dart';
import 'package:mconnect/features/local_music/data/local_music_repository.dart';
import 'package:mconnect/features/local_music/data/local_scan_root_store.dart';
import 'package:mconnect/features/local_music/data/local_track_store.dart';
import 'package:mconnect/features/local_music/data/online_library_snapshot.dart';
import 'package:mconnect/features/local_music/presentation/providers/local_music_provider.dart';
import 'package:mconnect/models/artist.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/song.dart';

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
}

LocalMusicNotifier _notifier({
  LocalMusicPicker? picker,
  LocalMusicScanner? scanner,
  LocalTrackStore? trackStore,
  LocalLyricsStore? lyricsStore,
  LocalScanRootStore? rootStore,
  OnlineLibrarySnapshot? onlineSnapshot,
}) {
  return LocalMusicNotifier(
    picker: picker,
    scanner: scanner ?? _FakeLocalMusicScanner(),
    trackStore: trackStore ?? MemoryLocalTrackStore(),
    lyricsStore: lyricsStore ?? MemoryLocalLyricsStore(),
    rootStore: rootStore ?? MemoryLocalScanRootStore(),
    onlineSnapshot: onlineSnapshot ?? MemoryOnlineLibrarySnapshot(),
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
