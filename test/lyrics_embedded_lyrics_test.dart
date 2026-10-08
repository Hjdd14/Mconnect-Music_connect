import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/features/local_music/data/local_metadata_reader.dart';
import 'package:mconnect/features/local_music/data/local_scan_snapshot.dart';
import 'package:path/path.dart' as p;

/// W0-B 第 4 条：音频容器里的内嵌歌词（ID3 `USLT` / MP4 `©lyr` …）。
///
/// `audio_metadata_reader.readMetadata` 无条件解析歌词，唯一缺的是把它从
/// `LocalAudioMetadata` 带出去、并在扫描记录（`embeddedLyrics`）里传给
/// reconciler。优先级由 reconciler 决定：同名外部 .lrc/.krc/.qrc 优先，
/// 内嵌只在没有外部歌词可用时兜底。
void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('mconnect_embedded_lyrics_');
  });

  tearDown(() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  test('reads the ID3 USLT lyrics of a real audio file', () {
    final path = p.join(root.path, 'embedded.mp3');
    File(path).writeAsBytesSync(_id3v24WithLyrics('[00:01.00]内嵌歌词'));

    final metadata = AudioMetadataReader().read(path);

    expect(metadata, isNotNull);
    expect(metadata!.lyrics, '[00:01.00]内嵌歌词');
  });

  test('a file without embedded lyrics reports none', () {
    final path = p.join(root.path, 'no-lyrics.mp3');
    File(path).writeAsBytesSync(_id3v24WithLyrics(null));

    expect(AudioMetadataReader().read(path)?.lyrics, isNull);
  });

  test('LocalAudioMetadata carries the embedded lyrics', () {
    const metadata = LocalAudioMetadata(lyrics: '[00:01.00]内嵌');

    expect(metadata.lyrics, '[00:01.00]内嵌');
    expect(LocalAudioMetadata.empty.lyrics, isNull);
  });

  test('the scan record round-trips the embeddedLyrics key', () {
    // 这个 key 名（`embeddedLyrics`）是 W0-B → W0-D 的交接契约，
    // reconciler 的 `_embeddedLyricsOf` 直接按名字取。
    final record = <String, Object?>{
      'path': '/music/a.mp3',
      'mtime': 1,
      'size': 2,
      'changed': true,
      'embeddedLyrics': '[00:01.00]内嵌',
    };

    final file = LocalScannedFile.fromMap(record);
    expect(file.embeddedLyrics, '[00:01.00]内嵌');
    expect(file.toMap()['embeddedLyrics'], '[00:01.00]内嵌');

    // 没有内嵌歌词时不写进 record，避免给 reconciler 一个空串。
    const withoutLyrics = LocalScannedFile(
      path: '/music/b.mp3',
      mtime: 1,
      size: 2,
      changed: true,
    );
    expect(withoutLyrics.embeddedLyrics, isNull);
    expect(withoutLyrics.toMap().containsKey('embeddedLyrics'), isFalse);
    expect(
      LocalScannedFile.fromMap(withoutLyrics.toMap()).embeddedLyrics,
      isNull,
    );
  });
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
