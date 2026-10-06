import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/features/local_music/data/android_local_music_service.dart';
import 'package:mconnect/features/local_music/data/local_lyrics_loader.dart';
import 'package:mconnect/lyrics/models/lyrics_line.dart';

import 'local_music_fixtures.dart';

/// Guards the method-channel contract between `MainActivity.kt` and Dart.
///
/// The Kotlin side cannot be exercised from a Dart test, but the payload shape
/// it produces can: the map below is exactly what `scanDocumentTree` returns
/// (`path/mtime/size/changed/title/artist/album/durationMs/trackNumber/
/// coverPath/lyrics[]`), so a silent rename on either side fails here instead of
/// on a phone.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.mconnect.mconnect/local_music');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  void mockChannel(Map<String, Object?> Function(MethodCall call) respond) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return respond(call);
        });
  }

  Map<String, Object?> payloadWith({
    required List<Object?> songs,
    List<Object?> skippedFiles = const [],
  }) => {
    'selectedDirectory': 'Music',
    'treeUri': 'content://com.android.externalstorage.documents/tree/primary%3AMusic',
    'songs': songs,
    'skippedFiles': skippedFiles,
  };

  test('pickAndScanDirectory sends the known index and parses real tags back', () async {
    final krcRaw = LocalLyricsLoader.encryptKrcForTest(krcFixture(lines: 1));
    mockChannel(
      (call) => payloadWith(
        songs: [
          {
            'path': 'content://tree/1.flac',
            'mtime': 111,
            'size': 222,
            'changed': true,
            'title': '真标题',
            'artist': '真歌手',
            'album': '真专辑',
            'durationMs': 195000,
            'trackNumber': 7,
            'coverPath': '/data/cache/local_covers/abc.img',
            'lyrics': [
              {'extension': '.krc', 'content': krcRaw},
            ],
          },
          {
            'path': 'content://tree/2.flac',
            'mtime': 333,
            'size': 444,
            'changed': false,
            'title': null,
            'durationMs': 0,
          },
        ],
        skippedFiles: ['content://tree/broken.flac'],
      ),
    );

    final service = AndroidLocalMusicService.test();
    final payload = await service.pickAndScanDirectory(
      known: {
        'content://tree/2.flac': [333, 444],
      },
    );

    // The index really crossed the boundary — that is what lets Kotlin skip
    // MediaMetadataRetriever for unchanged files.
    expect(calls.single.method, 'pickAndScanDirectory');
    expect(calls.single.arguments, {
      'known': {
        'content://tree/2.flac': [333, 444],
      },
    });

    expect(payload, isNotNull);
    expect(payload!.selectedDirectory, 'Music');
    expect(payload.treeUri, contains('tree/primary'));
    expect(payload.files, hasLength(2));

    final first = payload.files.first;
    expect(first.path, 'content://tree/1.flac');
    expect(first.title, '真标题');
    expect(first.artist, '真歌手');
    expect(first.album, '真专辑');
    expect(first.durationMs, 195000);
    expect(first.trackNumber, 7);
    expect(first.coverPath, '/data/cache/local_covers/abc.img');
    expect(first.changed, isTrue);
    expect(first.lyricCandidates, isEmpty, reason: 'Android 歌词走 rawLyrics，不是 dart:io 路径');

    expect(payload.files.last.changed, isFalse);
    expect(payload.files.last.title, isNull);
    expect(payload.skippedFiles, ['content://tree/broken.flac']);

    // Lyrics: ciphertext in, parsed word-timed lines out.
    final decoded = payload.decodeLyrics();
    expect(decoded.rejectedLyrics, isEmpty);
    final lyric = decoded.resolved['content://tree/1.flac'];
    expect(lyric, isNotNull);
    expect(lyric!.format, LyricsFormat.krc);
    expect(
      LyricsDocument.parse(lyric.content, lyric.format).lines.single.text,
      '词0第二段',
    );
  });

  test('an undecodable first lyric candidate falls back to the next one', () async {
    mockChannel(
      (call) => payloadWith(
        songs: [
          {
            'path': 'content://tree/song.flac',
            'mtime': 1,
            'size': 2,
            'changed': true,
            'lyrics': [
              {'extension': '.krc', 'content': '!!!not base64!!!'},
              {'extension': '.lrc', 'content': '[00:05.00]后备歌词'},
            ],
          },
        ],
      ),
    );

    final payload = await AndroidLocalMusicService.test().pickAndScanDirectory();
    final decoded = payload!.decodeLyrics();

    expect(decoded.rejectedLyrics, hasLength(1));
    expect(decoded.rejectedLyrics.single, endsWith('.krc'));
    expect(
      decoded.resolved['content://tree/song.flac']!.content,
      '[00:05.00]后备歌词',
    );
  });

  test('a rejected lyric is reported instead of being stored as text', () async {
    mockChannel(
      (call) => payloadWith(
        songs: [
          {
            'path': 'content://tree/only.flac',
            'mtime': 1,
            'size': 2,
            'changed': true,
            'lyrics': [
              {'extension': '.qrc', 'content': 'this is not qrc xml'},
            ],
          },
        ],
      ),
    );

    final decoded = (await AndroidLocalMusicService.test()
            .pickAndScanDirectory())!
        .decodeLyrics();

    expect(decoded.resolved, isEmpty);
    expect(decoded.rejectedLyrics.single, 'content://tree/only.flac.qrc');
  });

  test('rescanDirectory sends the persisted tree uri without a picker', () async {
    mockChannel(
      (call) => payloadWith(
        songs: const [],
        skippedFiles: const ['content://tree/gone.flac'],
      ),
    );

    final service = AndroidLocalMusicService.test();
    final payload = await service.rescanDirectory(
      'content://tree/primary%3AMusic',
      known: {
        'content://tree/a.flac': [1, 2],
      },
    );

    expect(payload, isNotNull);
    expect(payload!.skippedFiles, ['content://tree/gone.flac']);
    expect(calls.single.method, 'rescanDirectory');
    expect(calls.single.arguments, {
      'uri': 'content://tree/primary%3AMusic',
      'known': {
        'content://tree/a.flac': [1, 2],
      },
    });
  });

  test('a cancelled picker returns null', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return null;
        });

    expect(await AndroidLocalMusicService.test().pickAndScanDirectory(), isNull);
  });
}
