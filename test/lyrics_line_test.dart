import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/features/player/presentation/widgets/word_by_word_lyrics.dart';
import 'package:mconnect/lyrics/models/lyrics_line.dart';
import 'package:mconnect/platform/kugou/kugou_api.dart';

void main() {
  test('parses Kugou KRC lines without dropping the first lyric character', () {
    const raw = '[0,1200]<0,600,0>你<600,600,0>好';

    final doc = LyricsDocument.parse(raw, LyricsFormat.krc);

    expect(doc.lines, hasLength(1));
    expect(doc.lines.first.text, '你好');
    expect(doc.lines.first.words?.map((w) => w.word), ['你', '好']);
  });

  test('decodes base64 Kugou LRC download content before parsing', () {
    final api = KugouApi();
    final encoded = base64Encode(utf8.encode('[00:01.00]你好'));

    final decoded = api.decodeDownloadedLyricsForTest(
      encoded,
      format: 'lrc',
      contentType: 1,
    );
    final doc = LyricsDocument.parse(decoded!, LyricsFormat.lrc);

    expect(doc.lines.single.timestamp, const Duration(seconds: 1));
    expect(doc.lines.single.text, '你好');
  });

  test('decodes Kugou KRC content using the full inflated bytes', () {
    final api = KugouApi();
    const raw = '[0,1200]<0,600,0>你<600,600,0>好';
    final encoded = _encodeKrc(raw);

    final decoded = api.decodeDownloadedLyricsForTest(
      encoded,
      format: 'krc',
      contentType: 0,
    );

    expect(decoded, raw);
  });

  test('merges original and translated LRC lines on the same timestamp', () {
    const raw = '[00:01.00]Hello\n[00:01.00]Ni hao\n[00:03.00]World';

    final doc = LyricsDocument.parse(raw, LyricsFormat.lrc);

    expect(doc.lines, hasLength(2));
    expect(doc.lines.first.timestamp, const Duration(seconds: 1));
    expect(doc.lines.first.text, 'Hello');
    expect(doc.lines.first.translation, 'Ni hao');
    expect(doc.lines.first.hasTranslation, isTrue);
    expect(doc.lines.last.text, 'World');
  });

  testWidgets('word timing lyrics render official translation below original', (
    tester,
  ) async {
    const line = LyricsLine(
      timestamp: Duration(seconds: 1),
      text: 'Hello',
      translation: '你好',
      words: [
        WordTiming(
          word: 'Hello',
          start: Duration(seconds: 1),
          duration: Duration(milliseconds: 500),
        ),
      ],
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: WordByWordLine(
            line: line,
            currentPosition: Duration(seconds: 1),
            isCurrentLine: true,
          ),
        ),
      ),
    );

    expect(find.text('你好'), findsOneWidget);
  });

  testWidgets('word timing lyrics split the played prefix from the rest', (
    tester,
  ) async {
    const line = LyricsLine(
      timestamp: Duration(seconds: 1),
      text: 'Hello world',
      words: [
        WordTiming(
          word: 'Hello',
          start: Duration(seconds: 1),
          duration: Duration(milliseconds: 500),
        ),
      ],
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: WordByWordLine(
            line: line,
            currentPosition: Duration(milliseconds: 1400),
            playedCharacters: 3,
            isCurrentLine: true,
          ),
        ),
      ),
    );

    final richText = tester.widget<RichText>(
      find.text('Hello world', findRichText: true),
    );
    final leaves = _leafTextSpans(richText.text);

    expect(leaves.map((span) => span.text), ['Hel', 'lo world']);
    expect(leaves[0].style?.color, isNot(leaves[1].style?.color));
  });

  testWidgets('a fully played line collapses into a single colored run', (
    tester,
  ) async {
    const line = LyricsLine(
      timestamp: Duration(seconds: 1),
      text: 'Hello',
      words: [
        WordTiming(
          word: 'Hello',
          start: Duration(seconds: 1),
          duration: Duration(milliseconds: 500),
        ),
      ],
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: WordByWordLine(
            line: line,
            currentPosition: Duration(seconds: 2),
            playedCharacters: 5,
            isCurrentLine: true,
          ),
        ),
      ),
    );

    final richText = tester.widget<RichText>(
      find.text('Hello', findRichText: true),
    );
    final leaves = _leafTextSpans(richText.text);

    expect(leaves, hasLength(1));
    expect(leaves.single.text, 'Hello');
  });
}

/// Flattens a [Text]'s span tree down to its leaf spans (one per colored run).
List<TextSpan> _leafTextSpans(InlineSpan span) {
  final leaves = <TextSpan>[];
  void visit(InlineSpan node) {
    if (node is! TextSpan) return;
    if (node.text != null && node.text!.isNotEmpty) {
      leaves.add(node);
    }
    for (final child in node.children ?? const <InlineSpan>[]) {
      visit(child);
    }
  }

  visit(span);
  return leaves;
}

String _encodeKrc(String raw) {
  const key = [
    0x40,
    0x47,
    0x61,
    0x77,
    0x5e,
    0x32,
    0x74,
    0x47,
    0x51,
    0x36,
    0x31,
    0x2d,
    0xce,
    0xd2,
    0x6e,
    0x69,
  ];
  final compressed = zlib.encode(utf8.encode(raw));
  final encrypted = List<int>.generate(
    compressed.length,
    (i) => compressed[i] ^ key[i % key.length],
  );
  return base64Encode([0, 0, 0, 0, ...encrypted]);
}
