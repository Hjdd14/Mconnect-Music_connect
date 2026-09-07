import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart' as just_audio;
import 'package:mconnect/features/player/presentation/providers/lyrics_provider.dart';
import 'package:mconnect/features/player/presentation/providers/player_provider.dart';
import 'package:mconnect/features/player/presentation/widgets/lyrics_display.dart';
import 'package:mconnect/lyrics/models/lyrics_line.dart';
import 'package:mconnect/models/artist.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/song.dart';

void main() {
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
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        playerProvider.overrideWith((ref) => notifier),
        lyricsProvider.overrideWith((ref) async => document),
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

void _expectTextCenteredInScrollable(WidgetTester tester, String text) {
  final textCenter = tester.getCenter(find.text(text));
  final scrollableCenter = tester.getCenter(find.byType(Scrollable));

  expect((textCenter.dy - scrollableCenter.dy).abs(), lessThanOrEqualTo(16));
}

AnimatedDefaultTextStyle _nearestAnimatedTextStyle(
  WidgetTester tester,
  String text,
) {
  final textElement = tester.element(find.text(text));
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
