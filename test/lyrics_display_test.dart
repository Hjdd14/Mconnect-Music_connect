import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart' as just_audio;
import 'package:mconnect/features/player/presentation/providers/lyrics_offset_provider.dart';
import 'package:mconnect/features/player/presentation/providers/lyrics_provider.dart';
import 'package:mconnect/features/player/presentation/providers/player_provider.dart';
import 'package:mconnect/features/player/presentation/widgets/lyrics_display.dart';
import 'package:mconnect/lyrics/lyrics_display_settings.dart';
import 'package:mconnect/lyrics/models/lyrics_line.dart';
import 'package:mconnect/models/artist.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/song.dart';

void main() {
  testWidgets('a manual lyrics offset shifts which line is current', (
    tester,
  ) async {
    final notifier = _LyricsTestPlayerNotifier();
    const document = LyricsDocument(
      lines: [
        LyricsLine(timestamp: Duration.zero, text: 'First line'),
        LyricsLine(timestamp: Duration(seconds: 4), text: 'Next line'),
      ],
      format: LyricsFormat.lrc,
    );

    await _pumpLyricsDisplayWithOffset(
      tester,
      notifier,
      document,
      const Duration(seconds: 3),
    );
    notifier.setProgress(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();

    // 播放位置 2s + 偏移 3s = 5s，应当已经落在 4s 的第二行（当前行字号更大）。
    expect(
      _nearestAnimatedTextStyle(tester, 'Next line').style.fontSize,
      20,
    );
  });

  testWidgets('lyrics display splits the current line at the played boundary', (
    tester,
  ) async {
    final notifier = _LyricsTestPlayerNotifier();
    const document = LyricsDocument(
      lines: [
        LyricsLine(timestamp: Duration.zero, text: '1234567890'),
        LyricsLine(timestamp: Duration(seconds: 4), text: 'Next line'),
      ],
      format: LyricsFormat.lrc,
    );

    await _pumpLyricsDisplay(tester, notifier, document);
    notifier.setProgress(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();

    final richText = tester.widget<RichText>(
      find.text('1234567890', findRichText: true),
    );
    final leaves = _leafTextSpans(richText.text);

    expect(leaves, hasLength(2));
    // Half of the four second line has been played.
    expect(leaves[0].text, '12345');
    expect(leaves[1].text, '67890');
    expect(leaves[0].style?.color, isNotNull);
    expect(leaves[0].style?.color, isNot(leaves[1].style?.color));
  });

  testWidgets('lyrics display leaves unplayed lines in a single color', (
    tester,
  ) async {
    final notifier = _LyricsTestPlayerNotifier();
    const document = LyricsDocument(
      lines: [
        LyricsLine(timestamp: Duration.zero, text: '1234567890'),
        LyricsLine(timestamp: Duration(seconds: 4), text: 'Next line'),
      ],
      format: LyricsFormat.lrc,
    );

    await _pumpLyricsDisplay(tester, notifier, document);

    // Nothing played yet: the current line stays one unbroken span, so a line
    // that wraps onto several rows can never colour every row at once.
    final richText = tester.widget<RichText>(
      find.text('1234567890', findRichText: true),
    );
    final leaves = _leafTextSpans(richText.text);

    expect(leaves, hasLength(1));
    expect(leaves.single.text, '1234567890');
  });

  testWidgets('a wrapped current line colours row by row, not all at once', (
    tester,
  ) async {
    final notifier = _LyricsTestPlayerNotifier();
    const text =
        '我会买下所有难得一见的笑脸让所有可怜的孩子不再胆怯勇敢的向前';
    const document = LyricsDocument(
      lines: [
        LyricsLine(timestamp: Duration.zero, text: text),
        LyricsLine(timestamp: Duration(seconds: 8), text: 'Next line'),
      ],
      format: LyricsFormat.lrc,
    );

    // Narrow width forces the line to wrap onto several rows.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playerProvider.overrideWith((ref) => notifier),
          lyricsProvider.overrideWith((ref) async => document),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 200,
                height: 400,
                child: LyricsDisplay(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    notifier.setProgress(const Duration(seconds: 4));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();

    final richText = tester.widget<RichText>(
      find.text(text, findRichText: true),
    );
    final leaves = _leafTextSpans(richText.text);

    // The played run is a strict prefix of the line, so the rows after the
    // boundary stay in the base colour instead of lighting up together.
    expect(leaves, hasLength(2));
    expect(leaves.first.text, text.substring(0, leaves.first.text!.length));
    expect(leaves.first.text!.length, greaterThan(0));
    expect(leaves.first.text!.length, lessThan(text.length));
    expect(leaves.last.text, text.substring(leaves.first.text!.length));
    expect(leaves.first.style?.color, isNot(leaves.last.style?.color));
  });

  testWidgets('lyrics display scrolls down when playback reaches later lines', (
    tester,
  ) async {
    final notifier = _LyricsTestPlayerNotifier();
    final document = LyricsDocument(
      lines: List.generate(
        40,
        (index) => LyricsLine(
          timestamp: Duration(seconds: index),
          text: 'Line $index',
        ),
      ),
      format: LyricsFormat.lrc,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playerProvider.overrideWith((ref) => notifier),
          lyricsProvider.overrideWith((ref) async => document),
        ],
        child: const MaterialApp(
          home: Scaffold(body: SizedBox(height: 240, child: LyricsDisplay())),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(scrollable.position.pixels, 0);

    notifier.setProgress(const Duration(seconds: 24));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();

    expect(scrollable.position.pixels, greaterThan(0));
  });

  testWidgets(
    'lyrics display keeps auto-following after programmatic scrolls',
    (tester) async {
      final notifier = _LyricsTestPlayerNotifier();
      final document = LyricsDocument(
        lines: List.generate(
          80,
          (index) => LyricsLine(
            timestamp: Duration(seconds: index),
            text: 'Line $index',
          ),
        ),
        format: LyricsFormat.lrc,
      );

      await _pumpLyricsDisplay(tester, notifier, document);
      final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));

      notifier.setProgress(const Duration(seconds: 24));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      final firstAutoScrollOffset = scrollable.position.pixels;
      expect(firstAutoScrollOffset, greaterThan(0));

      notifier.setProgress(const Duration(seconds: 56));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();

      expect(scrollable.position.pixels, greaterThan(firstAutoScrollOffset));
    },
  );

  testWidgets('lyrics display highlights first visible line before it starts', (
    tester,
  ) async {
    final notifier = _LyricsTestPlayerNotifier();
    final document = const LyricsDocument(
      lines: [
        LyricsLine(timestamp: Duration(seconds: 10), text: 'First lyric'),
        LyricsLine(timestamp: Duration(seconds: 20), text: 'Second lyric'),
      ],
      format: LyricsFormat.lrc,
    );

    await _pumpLyricsDisplay(tester, notifier, document);

    final firstStyle = _nearestAnimatedTextStyle(tester, 'First lyric');
    final secondStyle = _nearestAnimatedTextStyle(tester, 'Second lyric');

    expect(firstStyle.style.fontSize, 20);
    expect(secondStyle.style.fontSize, 16);
  });

  testWidgets('lyrics display skips empty timestamp lines for current lyric', (
    tester,
  ) async {
    final notifier = _LyricsTestPlayerNotifier();
    final document = const LyricsDocument(
      lines: [
        LyricsLine(timestamp: Duration.zero, text: ''),
        LyricsLine(timestamp: Duration(seconds: 5), text: 'Visible lyric'),
        LyricsLine(timestamp: Duration(seconds: 10), text: 'Next lyric'),
      ],
      format: LyricsFormat.lrc,
    );

    await _pumpLyricsDisplay(tester, notifier, document);

    final visibleStyle = _nearestAnimatedTextStyle(tester, 'Visible lyric');
    expect(visibleStyle.style.fontSize, 20);
  });

  testWidgets('manual lyrics scroll pauses auto-follow then recovers', (
    tester,
  ) async {
    final notifier = _LyricsTestPlayerNotifier();
    final document = LyricsDocument(
      lines: List.generate(
        80,
        (index) => LyricsLine(
          timestamp: Duration(seconds: index),
          text: 'Line $index',
        ),
      ),
      format: LyricsFormat.lrc,
    );

    await _pumpLyricsDisplay(tester, notifier, document);
    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));

    notifier.setProgress(const Duration(seconds: 24));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    final followedOffset = scrollable.position.pixels;

    await tester.drag(find.byType(ListView), const Offset(0, 120));
    await tester.pump();
    notifier.setProgress(const Duration(seconds: 48));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle(const Duration(milliseconds: 50));
    expect(scrollable.position.pixels, lessThanOrEqualTo(followedOffset));

    await tester.pump(const Duration(seconds: 3));
    notifier.setProgress(const Duration(seconds: 56));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(scrollable.position.pixels, greaterThan(followedOffset));
  });

  testWidgets('song changes reset manual lyrics scroll lock', (tester) async {
    final notifier = _LyricsTestPlayerNotifier();
    final document = LyricsDocument(
      lines: List.generate(
        80,
        (index) => LyricsLine(
          timestamp: Duration(seconds: index),
          text: 'Line $index',
        ),
      ),
      format: LyricsFormat.lrc,
    );

    await _pumpLyricsDisplay(tester, notifier, document);
    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));

    await tester.drag(find.byType(ListView), const Offset(0, -160));
    await tester.pump();
    notifier.switchSong(
      _songWithId('lyrics-song-2'),
      const Duration(seconds: 48),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();

    expect(scrollable.position.pixels, greaterThan(0));
  });

  testWidgets('lyrics display centers current line when it becomes visible', (
    tester,
  ) async {
    final notifier = _LyricsTestPlayerNotifier();
    final document = LyricsDocument(
      lines: List.generate(
        80,
        (index) => LyricsLine(
          timestamp: Duration(seconds: index),
          text: 'Line $index',
        ),
      ),
      format: LyricsFormat.lrc,
    );

    await _pumpLyricsDisplay(tester, notifier, document, isVisible: false);

    notifier.setProgress(const Duration(seconds: 42));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();

    await _pumpLyricsDisplay(tester, notifier, document);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();

    _expectTextCenteredInScrollable(tester, 'Line 42');
  });

  testWidgets(
    'lyrics display centers variable height translated current line',
    (tester) async {
      final notifier = _LyricsTestPlayerNotifier();
      final document = LyricsDocument(
        lines: List.generate(
          80,
          (index) => LyricsLine(
            timestamp: Duration(seconds: index),
            text: index == 37
                ? 'A much longer current lyric line that wraps across rows'
                : 'Line $index',
            translation: index == 37
                ? 'Translated lyric that makes this item taller than neighbors'
                : null,
          ),
        ),
        format: LyricsFormat.lrc,
      );

      await _pumpLyricsDisplay(tester, notifier, document);

      notifier.setProgress(const Duration(seconds: 37));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();

      _expectTextCenteredInScrollable(
        tester,
        'A much longer current lyric line that wraps across rows',
      );
    },
  );

  // --- W2-A 批次 3：三态 / 字号行距 / 来源角标 -------------------------------

  const translatedDocument = LyricsDocument(
    lines: [
      LyricsLine(
        timestamp: Duration.zero,
        text: 'Hello',
        translation: '你好',
      ),
      LyricsLine(timestamp: Duration(seconds: 4), text: 'World'),
    ],
    format: LyricsFormat.lrc,
  );

  testWidgets('bilingual mode shows both the original and the translation', (
    tester,
  ) async {
    final notifier = _LyricsTestPlayerNotifier();

    await _pumpLyricsDisplay(
      tester,
      notifier,
      translatedDocument,
      extraOverrides: [
        lyricsDisplayModeProvider.overrideWith(
          (ref) => LyricsDisplayModeNotifier(
            initial: LyricsDisplayMode.bilingual,
          ),
        ),
      ],
    );

    expect(find.text('你好'), findsOneWidget);
    expect(find.text('World'), findsOneWidget);
    expect(find.text('Hello', findRichText: true), findsWidgets);
  });

  testWidgets('original mode hides the translation row entirely', (
    tester,
  ) async {
    final notifier = _LyricsTestPlayerNotifier();

    await _pumpLyricsDisplay(
      tester,
      notifier,
      translatedDocument,
      extraOverrides: [
        lyricsDisplayModeProvider.overrideWith(
          (ref) => LyricsDisplayModeNotifier(
            initial: LyricsDisplayMode.original,
          ),
        ),
      ],
    );

    expect(find.text('你好'), findsNothing);
    expect(find.text('Hello', findRichText: true), findsWidgets);
    expect(find.text('World'), findsOneWidget);
  });

  testWidgets('translation-only mode promotes the translation to the main line', (
    tester,
  ) async {
    final notifier = _LyricsTestPlayerNotifier();

    await _pumpLyricsDisplay(
      tester,
      notifier,
      translatedDocument,
      extraOverrides: [
        lyricsDisplayModeProvider.overrideWith(
          (ref) => LyricsDisplayModeNotifier(
            initial: LyricsDisplayMode.translationOnly,
          ),
        ),
      ],
    );

    expect(find.text('Hello', findRichText: true), findsNothing);
    expect(find.text('你好', findRichText: true), findsWidgets);
    expect(
      find.text('World'),
      findsOneWidget,
      reason: '没有译文的行必须退回原文，不能变成空行',
    );
  });

  testWidgets('the typography setting drives the line text size and height', (
    tester,
  ) async {
    final notifier = _LyricsTestPlayerNotifier();

    await _pumpLyricsDisplay(
      tester,
      notifier,
      translatedDocument,
      extraOverrides: [
        lyricsTypographyProvider.overrideWith(
          (ref) => LyricsTypographyNotifier(
            initial: const LyricsTypography(fontSize: 24, lineHeight: 1.8),
          ),
        ),
      ],
    );

    // 当前行 = base + 4，非当前行 = base；行距直接用设定值。
    expect(
      _nearestAnimatedTextStyle(tester, 'Hello').style.fontSize,
      28,
    );
    expect(
      _nearestAnimatedTextStyle(tester, 'World').style.fontSize,
      24,
    );
    expect(_nearestAnimatedTextStyle(tester, 'World').style.height, 1.8);
  });

  testWidgets('the default typography keeps the previous hard-coded sizes', (
    tester,
  ) async {
    final notifier = _LyricsTestPlayerNotifier();

    await _pumpLyricsDisplay(tester, notifier, translatedDocument);

    expect(_nearestAnimatedTextStyle(tester, 'Hello').style.fontSize, 20);
    expect(_nearestAnimatedTextStyle(tester, 'World').style.fontSize, 16);
    expect(_nearestAnimatedTextStyle(tester, 'World').style.height, 1.5);
  });

  testWidgets('a known source is shown as a badge', (tester) async {
    final notifier = _LyricsTestPlayerNotifier();

    await _pumpLyricsDisplay(
      tester,
      notifier,
      const LyricsDocument(
        lines: [LyricsLine(timestamp: Duration.zero, text: 'Hello')],
        format: LyricsFormat.lrc,
        source: LyricsSource.kugou,
      ),
    );

    expect(find.text('酷狗音乐'), findsOneWidget);
  });

  testWidgets('an unknown source shows no badge', (tester) async {
    final notifier = _LyricsTestPlayerNotifier();

    await _pumpLyricsDisplay(
      tester,
      notifier,
      const LyricsDocument(
        lines: [LyricsLine(timestamp: Duration.zero, text: 'Hello')],
        format: LyricsFormat.lrc,
      ),
    );

    expect(find.text('酷狗音乐'), findsNothing);
    expect(find.text('网易云音乐'), findsNothing);
  });
}

const _song = Song(
  id: 'lyrics-song',
  platform: PlatformType.netease,
  name: 'Lyrics Song',
  artists: [Artist(id: 'artist', name: 'Artist')],
);

Song _songWithId(String id) => Song(
  id: id,
  platform: PlatformType.netease,
  name: 'Lyrics Song $id',
  artists: const [Artist(id: 'artist', name: 'Artist')],
);

Future<void> _pumpLyricsDisplay(
  WidgetTester tester,
  _LyricsTestPlayerNotifier notifier,
  LyricsDocument document, {
  bool isVisible = true,
  List<Override> extraOverrides = const [],
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        playerProvider.overrideWith((ref) => notifier),
        lyricsProvider.overrideWith((ref) async => document),
        ...extraOverrides,
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 240,
            child: LyricsDisplay(isVisible: isVisible),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpLyricsDisplayWithOffset(
  WidgetTester tester,
  _LyricsTestPlayerNotifier notifier,
  LyricsDocument document,
  Duration offset,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        playerProvider.overrideWith((ref) => notifier),
        lyricsProvider.overrideWith((ref) async => document),
        lyricsOffsetProvider.overrideWith(
          (ref) => LyricsOffsetNotifier(initial: offset),
        ),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: SizedBox(height: 240, child: LyricsDisplay()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void _expectTextCenteredInScrollable(WidgetTester tester, String text) {
  final textCenter = tester.getCenter(find.text(text));
  final scrollableCenter = tester.getCenter(find.byType(Scrollable));

  expect((textCenter.dy - scrollableCenter.dy).abs(), lessThanOrEqualTo(16));
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

AnimatedDefaultTextStyle _nearestAnimatedTextStyle(
  WidgetTester tester,
  String text,
) {
  // The current line renders as rich text once part of it has been played, so
  // match either a plain Text or a RichText node.
  final textElement = tester.element(find.text(text, findRichText: true));
  AnimatedDefaultTextStyle? style;
  textElement.visitAncestorElements((element) {
    final widget = element.widget;
    if (widget is AnimatedDefaultTextStyle) {
      style = widget;
      return false;
    }
    return true;
  });
  return style!;
}

class _LyricsTestPlayerNotifier extends PlayerNotifier {
  _LyricsTestPlayerNotifier()
    : super(
        audioController: _IdleAudioController(),
        audioControllerFactory: () => _IdleAudioController(),
      ) {
    state = state.copyWith(
      currentSong: _song,
      playlist: const [_song],
      currentIndex: 0,
      position: Duration.zero,
      duration: const Duration(minutes: 3),
    );
  }

  void setProgress(Duration position) {
    state = state.copyWith(position: position);
  }

  void switchSong(Song song, Duration position) {
    state = state.copyWith(
      currentSong: song,
      playlist: [song],
      currentIndex: 0,
      position: position,
    );
  }
}

class _IdleAudioController implements PlayerAudioController {
  final _positionController = StreamController<Duration>.broadcast();
  final _durationController = StreamController<Duration?>.broadcast();
  final _playerStateController =
      StreamController<AudioPlaybackState>.broadcast();

  @override
  bool get playing => false;

  @override
  Duration get position => Duration.zero;

  @override
  double get volume => 1.0;

  @override
  Stream<Duration> get positionStream => _positionController.stream;

  @override
  Stream<Duration?> get durationStream => _durationController.stream;

  @override
  Stream<AudioPlaybackState> get playerStateStream =>
      _playerStateController.stream;

  @override
  Future<void> stop() async {}

  @override
  Future<void> setUrl(String url) async {}

  @override
  Future<void> play() async {
    _playerStateController.add(
      const AudioPlaybackState(
        playing: true,
        processingState: just_audio.ProcessingState.ready,
      ),
    );
  }

  @override
  Future<void> pause() async {}

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> applyEqualizer({
    required bool enabled,
    required List<double> bandGains,
  }) async {}

  @override
  Future<void> dispose() async {
    await _positionController.close();
    await _durationController.close();
    await _playerStateController.close();
  }
}
