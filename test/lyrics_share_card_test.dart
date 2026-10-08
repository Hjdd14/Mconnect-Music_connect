import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/core/share/share_service.dart';
import 'package:mconnect/lyrics/lyrics_display_settings.dart';
import 'package:mconnect/lyrics/lyrics_progress.dart';
import 'package:mconnect/lyrics/lyrics_share.dart';
import 'package:mconnect/lyrics/models/lyrics_line.dart';
import 'package:mconnect/lyrics/widgets/lyrics_share_card.dart';

/// W2-A：歌词分享图（`RepaintBoundary` → PNG → `shareFiles`）。
///
/// **真实分享面板需要真机**（本机没有），所以 Dart 侧测的是：真能拍出 PNG 字节、
/// 真落到文件、真把那个文件交给分享通道。分享面板本身列【需真机】。
void main() {
  const lines = [
    LyricsLine(
      timestamp: Duration.zero,
      text: '第一句',
      translation: 'First line',
    ),
    LyricsLine(timestamp: Duration(seconds: 5), text: '第二句'),
    LyricsLine(timestamp: Duration(seconds: 10), text: '第三句'),
  ];

  const pngMagic = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

  group('currentLyricLineIndex', () {
    test('picks the last line that has already started', () {
      expect(currentLyricLineIndex(lines, const Duration(seconds: 6)), 1);
      expect(currentLyricLineIndex(lines, const Duration(seconds: 10)), 2);
    });

    test('before the first line it is the first visible line', () {
      expect(currentLyricLineIndex(lines, Duration.zero), 0);
    });

    test('an empty document has no active line', () {
      expect(currentLyricLineIndex(const [], const Duration(seconds: 1)), -1);
    });
  });

  group('LyricsShareCard', () {
    test('shows at most the fixed number of lines, centered on the active one', () {
      final many = List.generate(
        40,
        (index) => LyricsLine(
          timestamp: Duration(seconds: index),
          text: '第 $index 句',
        ),
      );
      final card = LyricsShareCard(
        title: '歌名',
        artists: '歌手',
        lines: many,
        activeIndex: 20,
      );

      final window = card.window;

      expect(window.lines, hasLength(lyricsShareCardLineCount));
      expect(window.lines[window.activeIndex].text, '第 20 句');
    });

    testWidgets('renders title, artists, source and the lyric lines', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: LyricsShareCard(
                title: '晚风',
                artists: '张三',
                source: LyricsSource.kugou,
                lines: lines,
                activeIndex: 1,
              ),
            ),
          ),
        ),
      );

      expect(find.text('晚风'), findsOneWidget);
      expect(find.text('张三'), findsOneWidget);
      expect(find.text('酷狗音乐'), findsOneWidget);
      expect(find.text('第一句'), findsOneWidget);
      // 双语模式：译文也在卡片上。
      expect(find.text('First line'), findsOneWidget);
      expect(find.text('第二句'), findsOneWidget);
    });

    testWidgets('original mode keeps the translation off the card', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: LyricsShareCard(
                title: '晚风',
                artists: '张三',
                lines: lines,
                mode: LyricsDisplayMode.original,
              ),
            ),
          ),
        ),
      );

      expect(find.text('第一句'), findsOneWidget);
      expect(find.text('First line'), findsNothing);
    });
  });

  group('capture → file → share', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('mconnect_lyrics_share_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    /// Pumps the card inside a keyed boundary and returns its key.
    Future<GlobalKey> pumpCard(WidgetTester tester) async {
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: RepaintBoundary(
                key: key,
                child: const LyricsShareCard(
                  title: '晚风',
                  artists: '张三',
                  lines: lines,
                ),
              ),
            ),
          ),
        ),
      );
      return key;
    }

    testWidgets('mounts the card offscreen, captures it, then removes it', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SizedBox.shrink())),
      );
      final handle = mountOffscreenCard(
        tester.element(find.byType(Scaffold)),
        const LyricsShareCard(title: '晚风', artists: '张三', lines: lines),
      );

      expect(handle, isNotNull);
      await tester.pump();
      // 屏幕外但确实在树上：这是"不遮挡界面也能截图"的前提。
      expect(find.byType(LyricsShareCard), findsOneWidget);

      Uint8List? bytes;
      await tester.runAsync(() async {
        bytes = await captureBoundaryPng(handle!.key, pixelRatio: 1);
      });

      expect(bytes, isNotNull);
      expect(
        bytes!.sublist(0, 8),
        pngMagic,
        reason: '屏幕外的卡片也必须被真实绘制（否则截图是空图）',
      );

      handle!.remove();
      await tester.pump();
      expect(find.byType(LyricsShareCard), findsNothing);
    });

    testWidgets('captures real PNG bytes from a boundary', (tester) async {
      final key = await pumpCard(tester);
      Uint8List? bytes;

      await tester.runAsync(() async {
        bytes = await captureBoundaryPng(key, pixelRatio: 1);
      });

      expect(bytes, isNotNull);
      expect(bytes!.length, greaterThan(100));
      expect(bytes!.sublist(0, 8), pngMagic, reason: '必须是真 PNG，不是空图');
    });

    testWidgets('writes the PNG to the injected directory', (tester) async {
      final key = await pumpCard(tester);
      Uint8List? bytes;
      // 真实文件 IO 必须在 runAsync 里跑：testWidgets 的 fake-async 时区里
      // dart:io 的 Future 永远不会完成。
      await tester.runAsync(() async {
        bytes = await captureBoundaryPng(key, pixelRatio: 1);

        final path = await writeLyricsCardPng(
          bytes!,
          directory: () async => tempDir,
        );

        expect(path, isNotNull);
        final file = File(path!);
        expect(await file.exists(), isTrue);
        expect(
          (await file.readAsBytes()).sublist(0, 8),
          pngMagic,
          reason: '落盘的内容必须是 PNG',
        );
      });

      expect(bytes, isNotNull);
    });

    testWidgets('hands exactly one existing PNG file to the share channel', (
      tester,
    ) async {
      final key = await pumpCard(tester);
      final channel = _RecordingChannel();
      String? sharedPath;
      bool exists = false;
      List<int> header = const [];

      await tester.runAsync(() async {
        sharedPath = await shareLyricsCard(
          tester.element(find.byType(Scaffold)),
          card: const LyricsShareCard(
            title: '晚风',
            artists: '张三',
            source: LyricsSource.kugou,
            lines: lines,
          ),
          shareService: ShareService(channel),
          subject: '晚风',
          text: '晚风 - 张三',
          directory: () async => tempDir,
          capture: (context, card) => captureBoundaryPng(key, pixelRatio: 1),
        );

        // 文件 IO 留在 runAsync 内：fake-async 时区里它不会完成。
        if (sharedPath != null) {
          final file = File(sharedPath!);
          exists = await file.exists();
          header = (await file.readAsBytes()).sublist(0, 8);
        }
      });

      expect(sharedPath, isNotNull);
      expect(channel.fileBatches, hasLength(1));
      expect(channel.fileBatches.single, [sharedPath]);
      expect(channel.subjects.single, '晚风');
      expect(exists, isTrue);
      expect(header, pngMagic, reason: '分享出去的必须是真 PNG 文件');
    });

    testWidgets('a failed capture shares nothing and does not throw', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SizedBox.shrink())),
      );
      final channel = _RecordingChannel();

      final path = await shareLyricsCard(
        tester.element(find.byType(Scaffold)),
        card: const LyricsShareCard(title: '晚风', artists: '张三', lines: lines),
        shareService: ShareService(channel),
        directory: () async => tempDir,
        capture: (context, card) async => null,
      );

      expect(path, isNull);
      expect(channel.fileBatches, isEmpty);
    });

    testWidgets('an empty capture result is not written to disk', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SizedBox.shrink())),
      );
      final channel = _RecordingChannel();

      final path = await shareLyricsCard(
        tester.element(find.byType(Scaffold)),
        card: const LyricsShareCard(title: '晚风', artists: '张三', lines: lines),
        shareService: ShareService(channel),
        directory: () async => tempDir,
        capture: (context, card) async => Uint8List(0),
      );

      expect(path, isNull);
      expect(channel.fileBatches, isEmpty);
    });

    testWidgets('a throwing share channel is reported, not propagated', (
      tester,
    ) async {
      final key = await pumpCard(tester);
      Object? thrown;

      await tester.runAsync(() async {
        try {
          await shareLyricsCard(
            tester.element(find.byType(Scaffold)),
            card: const LyricsShareCard(title: '晚风', artists: '张三', lines: lines),
            shareService: const ShareService(_ThrowingChannel()),
            directory: () async => tempDir,
            capture: (context, card) => captureBoundaryPng(key, pixelRatio: 1),
          );
        } catch (e) {
          thrown = e;
        }
      });

      expect(thrown, isNull, reason: '分享失败不该把异常抛进界面');
    });
  });
}

class _RecordingChannel implements ShareChannel {
  final List<List<String>> fileBatches = [];
  final List<String?> subjects = [];

  @override
  Future<void> shareText(String text, {String? subject, Rect? origin}) async {}

  @override
  Future<void> shareFiles(
    List<String> paths, {
    String? subject,
    String? text,
    Rect? origin,
  }) async {
    fileBatches.add(List.of(paths));
    subjects.add(subject);
  }
}

class _ThrowingChannel implements ShareChannel {
  const _ThrowingChannel();

  @override
  Future<void> shareText(String text, {String? subject, Rect? origin}) async {
    throw StateError('share unavailable');
  }

  @override
  Future<void> shareFiles(
    List<String> paths, {
    String? subject,
    String? text,
    Rect? origin,
  }) async {
    throw StateError('share unavailable');
  }
}
