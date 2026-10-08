import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/features/local_music/data/local_lyrics_loader.dart';

/// W0-B 第 5 条：本地歌词文件的编码探测。
///
/// 策略固定为：UTF-8 BOM → UTF-8（严格，失败不静默替换）→ GB18030 回退。
void main() {
  test('strict UTF-8 wins over GB18030 for a UTF-8 file', () {
    // '中文歌词' 的 GBK 字节是 D6D0 CEC4 B8E8 B4CA；如果先跑 GB18030，
    // 上面这段合法 UTF-8 会变成乱码。
    const text = '[00:01.00]中文歌词';

    expect(LocalLyricsLoader.decodeBytes(utf8.encode(text)), text);
  });

  test('falls back to GB18030 when strict UTF-8 decoding fails', () {
    final bytes = <int>[
      ...'[00:01.00]'.codeUnits,
      0xD6, 0xD0, 0xCE, 0xC4, 0xB8, 0xE8, 0xB4, 0xCA,
    ];

    expect(LocalLyricsLoader.decodeBytes(bytes), '[00:01.00]中文歌词');
  });

  test('strips a UTF-8 BOM', () {
    final bytes = <int>[0xEF, 0xBB, 0xBF, ...utf8.encode('[00:01.00]带 BOM')];

    expect(LocalLyricsLoader.decodeBytes(bytes), '[00:01.00]带 BOM');
  });

  test('keeps ASCII untouched', () {
    expect(
      LocalLyricsLoader.decodeBytes('[00:01.00]plain ascii'.codeUnits),
      '[00:01.00]plain ascii',
    );
  });

  test('falls back to lenient UTF-8 on bytes that are neither encoding', () {
    // 坏文件不能让整次扫描崩掉：最后一个回退必须是**宽松 UTF-8 解码同一段字节**，
    // 而不是丢掉文件——所以这里断言具体结果，不只断言"不抛"。
    final bytes = <int>[0x00, 0xFF, 0xFE, 0x00, 0x41];

    // 先证明这段输入确实是坏 UTF-8（否则这条用例是空转）。
    expect(() => utf8.decode(bytes), throwsFormatException);

    final decoded = LocalLyricsLoader.decodeBytes(bytes);

    expect(decoded, utf8.decode(bytes, allowMalformed: true));
    expect(decoded, contains('A'));
    expect(decoded, contains('\u{FFFD}'));
    expect(decoded, isNot('[00:01.00]plain ascii'));
  });

  test('an empty byte list decodes to an empty string', () {
    expect(LocalLyricsLoader.decodeBytes(const []), '');
  });
}
