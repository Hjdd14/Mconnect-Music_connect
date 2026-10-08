import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/lyrics/lyrics_display_settings.dart';
import 'package:mconnect/lyrics/models/lyrics_line.dart';
import 'package:mconnect/lyrics/widgets/lyrics_options_section.dart';

/// W2-A 批次 3：播放页歌词控件（三态 / 字号 / 行距 / 缓存清理入口）。
///
/// 控件被抽成 `LyricsOptionsSection`，playback_options_sheet 只嵌入它 —— 这样既
/// 不碰 `player_screen.dart` 的布局契约，也让这些用例不必拉起整个播放器。
void main() {
  group('displayLineFor', () {
    const line = LyricsLine(
      timestamp: Duration(seconds: 1),
      text: 'Hello',
      translation: '你好',
      words: [
        WordTiming(word: 'Hello', start: Duration(seconds: 1), duration: Duration(milliseconds: 500)),
      ],
    );
    const noTranslation = LyricsLine(
      timestamp: Duration(seconds: 2),
      text: 'World',
    );

    test('bilingual keeps both texts', () {
      final shown = displayLineFor(line, LyricsDisplayMode.bilingual);

      expect(shown.text, 'Hello');
      expect(shown.translation, '你好');
      expect(shown.words, isNotNull);
    });

    test('original drops the translation but keeps the word timing', () {
      final shown = displayLineFor(line, LyricsDisplayMode.original);

      expect(shown.text, 'Hello');
      expect(shown.hasTranslation, isFalse);
      expect(shown.words, isNotNull);
    });

    test('translationOnly shows the translation as the main text', () {
      final shown = displayLineFor(line, LyricsDisplayMode.translationOnly);

      expect(shown.text, '你好');
      expect(shown.hasTranslation, isFalse);
      expect(
        shown.words,
        isNull,
        reason: '逐字时间轴属于原文，套到译文上会错位',
      );
    });

    test('translationOnly falls back to the original when there is none', () {
      final shown = displayLineFor(noTranslation, LyricsDisplayMode.translationOnly);

      expect(shown.text, 'World');
    });

    test('original mode never invents a translation', () {
      expect(
        displayLineFor(noTranslation, LyricsDisplayMode.original).hasTranslation,
        isFalse,
      );
    });
  });

  group('typography', () {
    test('clamps the range and keeps the defaults', () {
      const defaults = LyricsTypography();

      expect(defaults.fontSize, 16, reason: '默认值与改动前的硬编码一致');
      expect(defaults.lineHeight, 1.5);
      expect(defaults.copyWith(fontSize: 99).clamped().fontSize, LyricsTypography.maxFontSize);
      expect(defaults.copyWith(fontSize: 1).clamped().fontSize, LyricsTypography.minFontSize);
      expect(defaults.copyWith(lineHeight: 9).clamped().lineHeight, LyricsTypography.maxLineHeight);
      expect(defaults.copyWith(lineHeight: 0.1).clamped().lineHeight, LyricsTypography.minLineHeight);
    });
  });

  group('LyricsOptionsSection', () {
    Future<void> pump(
      WidgetTester tester, {
      Future<int> Function()? purge,
      LyricsDisplayMode mode = LyricsDisplayMode.bilingual,
      LyricsTypography typography = const LyricsTypography(),
    }) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            lyricsDisplayModeProvider.overrideWith(
              (ref) => LyricsDisplayModeNotifier(initial: mode),
            ),
            lyricsTypographyProvider.overrideWith(
              (ref) => LyricsTypographyNotifier(initial: typography),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: LyricsOptionsSection(
                purge: purge ?? () async => 0,
                cacheTtlDays: 14,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('the three display modes are offered and switch the mode', (
      tester,
    ) async {
      await pump(tester);

      expect(find.text('原文'), findsOneWidget);
      expect(find.text('双语'), findsOneWidget);
      expect(find.text('仅译文'), findsOneWidget);

      await tester.tap(find.text('仅译文'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '仅译文'))
            .selected,
        isTrue,
      );

      await tester.tap(find.text('原文'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '原文'))
            .selected,
        isTrue,
      );
    });

    testWidgets('font size can be raised and lowered within its range', (
      tester,
    ) async {
      await pump(tester);

      expect(find.text('16'), findsOneWidget);

      await tester.tap(find.byKey(const Key('lyrics-font-larger')));
      await tester.pumpAndSettle();
      expect(find.text('18'), findsOneWidget);

      await tester.tap(find.byKey(const Key('lyrics-font-smaller')));
      await tester.tap(find.byKey(const Key('lyrics-font-smaller')));
      await tester.pumpAndSettle();
      expect(find.text('14'), findsOneWidget);
    });

    testWidgets('line height can be raised and lowered within its range', (
      tester,
    ) async {
      await pump(tester);

      expect(find.text('1.5'), findsOneWidget);

      await tester.tap(find.byKey(const Key('lyrics-line-height-larger')));
      await tester.pumpAndSettle();
      expect(find.text('1.6'), findsOneWidget);

      await tester.tap(find.byKey(const Key('lyrics-line-height-smaller')));
      await tester.pumpAndSettle();
      expect(find.text('1.5'), findsOneWidget);
    });

    testWidgets('the purge entry reports how many rows were removed', (
      tester,
    ) async {
      var purges = 0;
      await pump(
        tester,
        purge: () async {
          purges++;
          return 3;
        },
      );

      await tester.tap(find.byKey(const Key('lyrics-cache-purge')));
      await tester.pumpAndSettle();

      expect(purges, 1);
      expect(find.textContaining('3'), findsWidgets);
      expect(find.byType(SnackBar), findsOneWidget);
    });

    testWidgets('the purge entry says so when there is nothing to clean', (
      tester,
    ) async {
      await pump(tester, purge: () async => 0);

      await tester.tap(find.byKey(const Key('lyrics-cache-purge')));
      await tester.pumpAndSettle();

      expect(find.textContaining('没有'), findsWidgets);
    });

    testWidgets('a failing purge is reported instead of crashing', (
      tester,
    ) async {
      await pump(tester, purge: () async => throw StateError('db closed'));

      await tester.tap(find.byKey(const Key('lyrics-cache-purge')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.textContaining('失败'), findsWidgets);
    });
  });
}
