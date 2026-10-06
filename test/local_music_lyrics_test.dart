import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/features/local_music/data/local_lyrics_loader.dart';
import 'package:mconnect/features/local_music/data/local_lyrics_store.dart';
import 'package:mconnect/lyrics/models/lyrics_line.dart';
import 'package:path/path.dart' as p;

import 'local_music_fixtures.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('mconnect_local_lyrics_');
  });

  tearDown(() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  test('KRC round-trips through the Kugou container into word-timed lines', () {
    final plain = krcFixture(lines: 2);
    final encrypted = LocalLyricsLoader.encryptKrcForTest(plain);

    // The container really is opaque: plaintext is not readable in it.
    expect(encrypted, isNot(contains('第二段')));

    final decrypted = LocalLyricsLoader.decryptKrc(encrypted);

    expect(decrypted, plain);
    final document = LyricsDocument.parse(decrypted!, LyricsFormat.krc);
    expect(document.lines, hasLength(2));
    expect(document.lines.first.text, '词0第二段');
    expect(document.lines.first.timestamp, const Duration(milliseconds: 1000));
    expect(document.lines.first.words, isNotNull);
    expect(document.lines.first.words!.first.word, '词0');
    expect(
      document.lines.first.words!.first.duration,
      const Duration(milliseconds: 200),
    );
  });

  test('a corrupted KRC payload is rejected, not returned as garbage', () {
    expect(LocalLyricsLoader.decryptKrc('!!!not base64!!!'), isNull);
    // Valid base64, but not a zlib+XOR payload.
    expect(LocalLyricsLoader.decryptKrc('YWJjZGVmZ2g='), isNull);
    // Empty payload.
    expect(LocalLyricsLoader.decryptKrc(''), isNull);
  });

  test('decode() dispatches on the extension', () {
    final krc = LocalLyricsLoader.decode(
      LocalLyricsLoader.encryptKrcForTest(krcFixture(lines: 1)),
      '.krc',
    );
    expect(krc?.format, LyricsFormat.krc);
    expect(krc?.content, contains('第二段'));

    final qrc = LocalLyricsLoader.decode(
      '<L T="1500" D="800"><P T="100" D="300">QQ 词</P></L>',
      '.qrc',
    );
    expect(qrc?.format, LyricsFormat.qrc);
    expect(
      LyricsDocument.parse(qrc!.content, qrc.format).lines.single.text,
      'QQ 词',
    );

    final lrc = LocalLyricsLoader.decode('[00:01.00]普通歌词', '.lrc');
    expect(lrc?.format, LyricsFormat.lrc);
    expect(lrc?.content, '[00:01.00]普通歌词');

    // Rejected shapes.
    expect(LocalLyricsLoader.decode('[00:01.00]伪装的 qrc', '.qrc'), isNull);
    expect(LocalLyricsLoader.decode('????', '.krc'), isNull);
    expect(LocalLyricsLoader.decode('   ', '.lrc'), isNull);
    // An unknown extension is not lyrics.
    expect(LocalLyricsLoader.decode('[00:01.00]x', '.md'), isNull);
  });

  test('load() reads a sidecar and rejects an undecodable one', () async {
    final loader = LocalLyricsLoader();
    final lrcPath = p.join(root.path, 'song.lrc');
    await File(lrcPath).writeAsString('[00:02.00]文件歌词');
    final payload = await loader.load(lrcPath);
    expect(payload?.content, '[00:02.00]文件歌词');

    final krcPath = p.join(root.path, 'song.krc');
    await File(krcPath).writeAsString('not-a-valid-krc');
    expect(await loader.load(krcPath), isNull);

    expect(await loader.load(p.join(root.path, 'missing.lrc')), isNull);
  });

  test('the drift-backed lyrics store keeps local rows separate per platform', () async {
    final store = MemoryLocalLyricsStore();
    await store.save('/music/a.flac', '[00:01.00]甲', 'lrc');
    await store.save('/music/b.flac', krcFixture(), 'krc');

    final all = await store.loadAll();
    final formats = await store.loadAllWithFormat();

    expect(all.keys, containsAll(['/music/a.flac', '/music/b.flac']));
    expect(formats['/music/b.flac'], 'krc');

    await store.removePaths(['/music/a.flac']);
    expect((await store.loadAll()).keys, ['/music/b.flac']);

    await store.clear();
    expect(await store.loadAll(), isEmpty);
  });
}
