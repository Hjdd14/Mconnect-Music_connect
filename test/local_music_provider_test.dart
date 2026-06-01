import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/features/local_music/data/local_music_repository.dart';
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
        ),
      ),
    );
    final notifier = LocalMusicNotifier(
      picker: picker,
      scanner: _FakeLocalMusicScanner(),
    );
    addTearDown(notifier.dispose);

    await notifier.pickAndScanDirectory();

    expect(picker.calls, 1);
    expect(notifier.state.selectedDirectory, 'Music');
    expect(notifier.state.songs, [song]);
    expect(notifier.state.lyricsBySongId[song.id], '[00:01.00]Lyric');
    expect(notifier.state.isScanning, isFalse);
    expect(notifier.state.error, isNull);
  });

  test('cancelled folder picking leaves existing songs untouched', () async {
    final existing = _song('file:///music/existing.mp3', 'Existing Song');
    final scanner = _FakeLocalMusicScanner(
      result: LocalMusicScanResult(songs: [existing]),
    );
    final notifier = LocalMusicNotifier(
      picker: _FakeLocalMusicPicker(),
      scanner: scanner,
    );
    addTearDown(notifier.dispose);
    await notifier.scanDirectory('C:/Music');

    await notifier.pickAndScanDirectory();

    expect(notifier.state.songs, [existing]);
    expect(notifier.state.selectedDirectory, 'C:/Music');
    expect(scanner.calls, 1);
  });

  test('scan failure clears loading and stores an error', () async {
    final notifier = LocalMusicNotifier(
      picker: _FakeLocalMusicPicker(),
      scanner: _FakeLocalMusicScanner(error: StateError('no access')),
    );
    addTearDown(notifier.dispose);

    await notifier.scanDirectory('content://denied');

    expect(notifier.state.isScanning, isFalse);
    expect(notifier.state.error, contains('no access'));
  });
}

Song _song(String id, String name) => Song(
  id: id,
  platform: PlatformType.local,
  name: name,
  artists: const [Artist(id: 'local', name: 'local')],
);

class _FakeLocalMusicPicker implements LocalMusicPicker {
  final LocalMusicPickResult? result;
  int calls = 0;

  _FakeLocalMusicPicker({this.result});

  @override
  Future<LocalMusicPickResult?> pickAndScanDirectory() async {
    calls++;
    return result;
  }
}

class _FakeLocalMusicScanner implements LocalMusicScanner {
  final LocalMusicScanResult result;
  final Object? error;
  int calls = 0;

  _FakeLocalMusicScanner({
    this.result = const LocalMusicScanResult(),
    this.error,
  });

  @override
  Future<LocalMusicScanResult> scanDirectory(String rootPath) async {
    calls++;
    final error = this.error;
    if (error != null) throw error;
    return result;
  }
}
