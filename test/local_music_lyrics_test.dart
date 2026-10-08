import 'dart:convert';
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

  test('load() decodes a GBK sidecar instead of dropping it', () async {
    // 用户自备的中文 .lrc 大量是 GBK/GB18030：`readAsString()` 严格 UTF-8 解码
    // 直接抛异常，整首歌变成"暂无歌词"。
    final loader = LocalLyricsLoader();
    final gbkPath = p.join(root.path, 'gbk.lrc');
    // '中文歌词' 的标准 GBK 编码：D6D0 CEC4 B8E8 B4CA。
    await File(gbkPath).writeAsBytes([
      ...'[00:01.00]'.codeUnits,
      0xD6, 0xD0, 0xCE, 0xC4, 0xB8, 0xE8, 0xB4, 0xCA,
    ]);

    final payload = await loader.load(gbkPath);

    expect(payload, isNotNull);
    expect(payload!.content, '[00:01.00]中文歌词');
    expect(payload.format, LyricsFormat.lrc);
    expect(
      LyricsDocument.parse(payload.content, payload.format).lines.single.text,
      '中文歌词',
    );
  });

  test('load() strips a UTF-8 BOM before storing the lyrics', () async {
    final loader = LocalLyricsLoader();
    final bomPath = p.join(root.path, 'bom.lrc');
    await File(bomPath).writeAsBytes([
      0xEF, 0xBB, 0xBF,
      ...utf8Bytes('[00:02.00]带 BOM 的歌词'),
    ]);

    final payload = await loader.load(bomPath);

    expect(payload?.content, '[00:02.00]带 BOM 的歌词');
  });

  test('load() keeps a strictly valid UTF-8 file as UTF-8', () async {
    final loader = LocalLyricsLoader();
    final utf8Path = p.join(root.path, 'utf8.lrc');
    // GBK 也能"解码"这段字节而不报错，所以必须先做严格 UTF-8 判定，否则中文
    // 会被二次解码成乱码。
    await File(utf8Path).writeAsBytes(utf8Bytes('[00:01.00]中文歌词'));

    expect((await loader.load(utf8Path))?.content, '[00:01.00]中文歌词');
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

List<int> utf8Bytes(String text) => utf8.encode(text);
