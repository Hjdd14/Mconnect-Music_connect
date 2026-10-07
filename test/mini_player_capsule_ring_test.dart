import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/core/theme/ui_style_provider.dart';
import 'package:mconnect/core/widgets/miuix_bottom_layout.dart';
import 'package:mconnect/features/player/presentation/providers/player_provider.dart';
import 'package:mconnect/features/player/presentation/widgets/mini_player_bar.dart';
import 'package:mconnect/models/artist.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/song.dart';

const _song = Song(
  id: 'song-1',
  platform: PlatformType.netease,
  name: 'Song 1',
  artists: [Artist(id: 'a1', name: 'Artist 1')],
  duration: Duration(seconds: 200),
);

class _UiStyle extends UiStyleNotifier {
  _UiStyle() : super(initialStyle: UiStyle.miuix);
}

/// Seeds a song plus an arbitrary playback position.
class _Player extends PlayerNotifier {
  _Player({
    Duration position = Duration.zero,
    Duration duration = const Duration(seconds: 200),
    bool playing = false,
  }) : super(
         audioController: _Idle(),
         audioControllerFactory: _Idle.new,
       ) {
    state = state.copyWith(
      currentSong: _song,
      playlist: const [_song],
      currentIndex: 0,
      position: position,
      duration: duration,
      isPlaying: playing,
    );
  }

  void setPosition(Duration position) {
    state = state.copyWith(position: position);
  }

  void setPlaying(bool playing) {
    state = state.copyWith(isPlaying: playing);
  }
}

class _Idle implements PlayerAudioController {
  @override
  bool get playing => false;
  @override
  Duration get position => Duration.zero;
  @override
  double get volume => 1.0;
  @override
  Stream<Duration> get positionStream => const Stream.empty();
  @override
  Stream<Duration?> get durationStream => const Stream.empty();
  @override
  Stream<AudioPlaybackState> get playerStateStream => const Stream.empty();
  @override
  Future<void> stop() async {}
  @override
  Future<void> setUrl(String url) async {}
  @override
  Future<void> play() async {}
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
  Future<void> dispose() async {}
}

void main() {
  Widget host({
    Duration position = Duration.zero,
    Duration duration = const Duration(seconds: 200),
    _Player? player,
  }) {
    return ProviderScope(
      overrides: [
        uiStyleProvider.overrideWith((ref) => _UiStyle()),
        playerProvider.overrideWith(
          (ref) =>
              player ?? _Player(position: position, duration: duration),
        ),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 360,
              child: MiniPlayerBar(floating: true),
            ),
          ),
        ),
      ),
    );
  }

  CustomPainter ringPainter(WidgetTester tester) {
    final paint = tester.widget<CustomPaint>(
      find.byKey(capsuleProgressRingKey),
    );
    expect(paint.foregroundPainter, isNotNull);
    return paint.foregroundPainter!;
  }

  double ringProgress(WidgetTester tester) {
    return (ringPainter(tester) as dynamic).progress as double;
  }

  group('capsule perimeter progress geometry', () {
    test('the start offset is the top centre, not a corner', () {
      // `StadiumBorder`'s path starts at the left-most point and runs clockwise, so
      // the top centre is a quarter circle PLUS half the straight top edge along.
      // For 200x48: pi*24/2 + (200 - 48)/2 = 37.7 + 76 = 113.7.
      expect(
        CapsuleProgressGeometry.startOffsetFor(200, 48),
        closeTo(113.70, 0.01),
      );
      // A capsule taller than wide has no straight top edge, so only the cap counts.
      expect(
        CapsuleProgressGeometry.startOffsetFor(40, 48),
        closeTo(3.141592653589793 * 24 / 2, 0.01),
      );
      // The two shortcuts that look plausible must NOT match.
      expect(
        CapsuleProgressGeometry.startOffsetFor(200, 48),
        isNot(closeTo(100, 0.5)),
        reason: 'width/2 starts the trace past the top centre',
      );
    });

    test('the stadium perimeter is 2 straight runs plus the two caps', () {
      // Independently derived: the probe below must agree with this formula, so a
      // change in how the path is built cannot silently shift the start point.
      const width = 200.0;
      const height = 48.0;
      final expected = 2 * (width - height) + 3.141592653589793 * height;
      expect(
        CapsuleProgressGeometry.perimeterFor(width, height),
        closeTo(expected, 0.001),
      );
      expect(CapsuleProgressGeometry.perimeterFor(width, height), closeTo(454.8, 1.0));
    });

    testWidgets('the start offset lands on the top centre of the real path', (
      tester,
    ) async {
      // Build the same path the painter builds and probe where the start offset
      // lands. This is what caught the `width / 2` mistake, which had already
      // reached a build.
      const width = 200.0;
      const height = MiuixBottomLayout.playerHeight;
      final path = const StadiumBorder().getOuterPath(
        const Rect.fromLTWH(0, 0, width, height),
        textDirection: TextDirection.ltr,
      );
      final metric = path.computeMetrics().first;
      final start = CapsuleProgressGeometry.startOffsetFor(width, height);

      final atStart = metric.getTangentForOffset(start)!;
      expect(
        atStart.position.dx,
        closeTo(width / 2, 0.5),
        reason: 'the trace must begin at the top centre',
      );
      expect(atStart.position.dy, closeTo(0, 0.5));

      // Moving forward from there must head right (clockwise), not left.
      final ahead = metric.getTangentForOffset(start + 2)!;
      expect(ahead.position.dx, greaterThan(atStart.position.dx));

      // And half a perimeter later it must be on the bottom centre, i.e. the shape
      // is traced as one closed loop.
      final halfway = metric.getTangentForOffset(
        (start + metric.length / 2) % metric.length,
      )!;
      expect(halfway.position.dx, closeTo(width / 2, 0.5));
      expect(halfway.position.dy, closeTo(height, 0.5));
    });
  });

  group('the capsule paints progress as a ring', () {
    testWidgets('the clipped linear bar is gone from the capsule', (
      tester,
    ) async {
      // The linear bar had to live inside the capsule's `ClipRRect`, so its ends
      // were cut off by the 24 dp corners — the reported defect.
      await tester.pumpWidget(host());
      await tester.pump();

      expect(find.byKey(capsuleProgressRingKey), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(MiniPlayerBar),
          matching: find.byType(LinearProgressIndicator),
        ),
        findsNothing,
      );
    });

    testWidgets('the ring tracks the playback position', (tester) async {
      await tester.pumpWidget(host(position: const Duration(seconds: 50)));
      await tester.pump();

      final painter = ringPainter(tester);
      expect(painter, isA<CustomPainter>());
      // 50 of 200 seconds.
      expect((painter as dynamic).progress, closeTo(0.25, 0.02));
    });

    testWidgets('a zero duration draws no progress instead of dividing by zero', (
      tester,
    ) async {
      await tester.pumpWidget(host(duration: Duration.zero));
      await tester.pump();

      expect((ringPainter(tester) as dynamic).progress, 0.0);
    });

    testWidgets('progress past the end is clamped', (tester) async {
      await tester.pumpWidget(
        host(
          position: const Duration(seconds: 400),
          duration: const Duration(seconds: 200),
        ),
      );
      await tester.pump();

      expect(
        (ringPainter(tester) as dynamic).progress,
        greaterThanOrEqualTo(1.0),
      );
    });
  });

  group('capsule progress interpolation', () {
    const duration = Duration(seconds: 200);
    const position = Duration(seconds: 40);

    double progressOf(
      CapsuleProgressInterpolation interpolation, {
      Duration at = position,
      bool isPlaying = true,
      required Duration elapsed,
    }) {
      return interpolation.progress(
        position: at,
        duration: duration,
        isPlaying: isPlaying,
        elapsed: elapsed,
        reducedMotion: false,
      );
    }

    test('a pause followed by a resume never collapses the ring', () {
      // 采样点就是锚点（权威 position 刚发布），progress = 40/200。
      final interpolation = CapsuleProgressInterpolation(
        position: position,
        elapsed: const Duration(milliseconds: 40500),
      );
      final before = progressOf(
        interpolation,
        elapsed: const Duration(milliseconds: 40500),
      );
      expect(before, closeTo(0.2, 0.0001));

      // 暂停 → 恢复。单调时钟在此期间走了 39 秒。
      interpolation.update(
        position: position,
        elapsed: const Duration(milliseconds: 40500),
        isPlaying: false,
        wasPlaying: true,
      );
      interpolation.update(
        position: position,
        elapsed: const Duration(milliseconds: 79500),
        isPlaying: true,
        wasPlaying: false,
      );
      final after = progressOf(
        interpolation,
        elapsed: const Duration(milliseconds: 79516),
      );

      expect(after, greaterThanOrEqualTo(before));
      expect(after, closeTo(0.2, 0.001));
      // 旧实现（ticker 累计时钟在 stop→repeat 后回零）会在这里塌到 ≈0.003。
      expect(after, greaterThan(0.15), reason: '恢复后不得塌向 0');
    });

    test('a transient playing:false frame does not rewind the ring', () {
      // Android 在缓冲/过渡时会短暂上报 playing:false（见 player_provider 的
      // `_shouldKeepPlayingThroughTransientState`），同样会 stop→repeat ticker。
      final interpolation = CapsuleProgressInterpolation(
        position: position,
        elapsed: const Duration(milliseconds: 40500),
      );
      final before = progressOf(
        interpolation,
        elapsed: const Duration(milliseconds: 40500),
      );

      interpolation.update(
        position: position,
        elapsed: const Duration(milliseconds: 40516),
        isPlaying: false,
        wasPlaying: true,
      );
      interpolation.update(
        position: position,
        elapsed: const Duration(milliseconds: 40532),
        isPlaying: true,
        wasPlaying: false,
      );
      final after = progressOf(
        interpolation,
        elapsed: const Duration(milliseconds: 40548),
      );

      expect(after, greaterThanOrEqualTo(before));
      expect(after, greaterThan(0.15));
    });

    test('resuming after a long pause does not jump forward', () {
      final interpolation = CapsuleProgressInterpolation(
        position: position,
        elapsed: const Duration(seconds: 40),
      );

      interpolation.update(
        position: position,
        elapsed: const Duration(seconds: 40),
        isPlaying: false,
        wasPlaying: true,
      );
      // 暂停 60 秒后恢复：单调时钟已经走过 100 秒。
      interpolation.update(
        position: position,
        elapsed: const Duration(seconds: 100),
        isPlaying: true,
        wasPlaying: false,
      );

      final after = progressOf(
        interpolation,
        elapsed: const Duration(seconds: 100),
      );
      // 不重锚会是 (40s + 60s) / 200s = 0.5，即凭空前跳。
      expect(after, closeTo(0.2, 0.001));
    });

    test('a backwards seek drops immediately and a forward seek rises', () {
      final interpolation = CapsuleProgressInterpolation(
        position: const Duration(seconds: 100),
        elapsed: const Duration(seconds: 100),
      );
      final before = progressOf(
        interpolation,
        at: const Duration(seconds: 100),
        elapsed: const Duration(seconds: 100, milliseconds: 500),
      );
      expect(before, closeTo(0.5025, 0.001));

      // 向后 seek 到 20s：必须立刻变小（旧实现把 anchorElapsed 清零，会大跳到 0.6）。
      interpolation.update(
        position: const Duration(seconds: 20),
        elapsed: const Duration(seconds: 101),
        isPlaying: true,
        wasPlaying: true,
      );
      final afterBackwards = progressOf(
        interpolation,
        at: const Duration(seconds: 20),
        elapsed: const Duration(seconds: 101),
      );
      expect(afterBackwards, lessThan(before));
      expect(afterBackwards, closeTo(0.1, 0.001));

      // 向前 seek 到 180s：必须立刻变大。
      interpolation.update(
        position: const Duration(seconds: 180),
        elapsed: const Duration(seconds: 102),
        isPlaying: true,
        wasPlaying: true,
      );
      final afterForwards = progressOf(
        interpolation,
        at: const Duration(seconds: 180),
        elapsed: const Duration(seconds: 102),
      );
      expect(afterForwards, greaterThan(afterBackwards));
      expect(afterForwards, closeTo(0.9, 0.001));
    });

    test('the interpolation never falls behind the authoritative position', () {
      // 旧 bug 的形态：锚点偏移远大于此刻的时钟值。
      expect(
        CapsuleProgressInterpolation.progressFor(
          position: position,
          duration: duration,
          isPlaying: true,
          elapsed: const Duration(seconds: 1),
          anchorPosition: position,
          anchorElapsed: const Duration(seconds: 39, milliseconds: 500),
          reducedMotion: false,
        ),
        closeTo(0.2, 0.0001),
      );
    });

    testWidgets('resuming in the real widget does not collapse the ring', (
      tester,
    ) async {
      final player = _Player(position: position, playing: true);
      await tester.pumpWidget(host(player: player));
      await tester.pump();

      // 让 ticker 累计出可观的时间，并在一次整秒 position 更新时捕获锚点偏移。
      await tester.pump(const Duration(seconds: 39));
      player.setPosition(const Duration(seconds: 41));
      await tester.pump(const Duration(milliseconds: 500));

      player.setPlaying(false);
      await tester.pump(const Duration(milliseconds: 200));
      expect(ringProgress(tester), closeTo(0.205, 0.01));

      player.setPlaying(true);
      await tester.pump(const Duration(milliseconds: 16));

      final resumed = ringProgress(tester);
      expect(resumed, closeTo(0.205, 0.01));
      expect(resumed, greaterThan(0.15), reason: '恢复后不得塌向 0');
    });
  });
}
