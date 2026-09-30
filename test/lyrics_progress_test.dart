import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/lyrics/lyrics_progress.dart';
import 'package:mconnect/lyrics/models/lyrics_line.dart';

void main() {
  group('playedCharacterCount', () {
    test('follows word timings including the word being sung', () {
      const line = LyricsLine(
        timestamp: Duration(seconds: 10),
        text: 'ABCD EF',
        words: [
          WordTiming(
            word: 'ABCD',
            start: Duration(seconds: 10),
            duration: Duration(seconds: 1),
          ),
          WordTiming(
            word: ' EF',
            start: Duration(seconds: 11),
            duration: Duration(seconds: 1),
          ),
        ],
      );

      expect(
        playedCharacterCount(line, const Duration(seconds: 10)),
        0,
      );
      expect(
        playedCharacterCount(line, const Duration(milliseconds: 10500)),
        2,
      );
      expect(
        playedCharacterCount(line, const Duration(milliseconds: 11500)),
        6,
      );
      expect(
        playedCharacterCount(line, const Duration(seconds: 12)),
        7,
      );
    });

    test('never exceeds the lyric length', () {
      const line = LyricsLine(
        timestamp: Duration(seconds: 5),
        text: 'short',
        words: [
          WordTiming(
            word: 'a much longer word stream than the text',
            start: Duration(seconds: 5),
            duration: Duration(seconds: 1),
          ),
        ],
      );

      expect(
        playedCharacterCount(line, const Duration(seconds: 30)),
        line.text.length,
      );
    });

    test('sweeps plain lines between timestamps', () {
      const line = LyricsLine(
        timestamp: Duration(seconds: 5),
        text: '1234567890',
      );

      expect(
        playedCharacterCount(
          line,
          const Duration(seconds: 5),
          nextTimestamp: const Duration(seconds: 10),
        ),
        0,
      );
      expect(
        playedCharacterCount(
          line,
          const Duration(milliseconds: 7500),
          nextTimestamp: const Duration(seconds: 10),
        ),
        5,
      );
      expect(
        playedCharacterCount(
          line,
          const Duration(seconds: 10),
          nextTimestamp: const Duration(seconds: 10),
        ),
        10,
      );
      // Without a following line the sweep falls back to a four second line.
      expect(playedCharacterCount(line, const Duration(seconds: 8)), 7);
    });

    test('returns zero for an empty lyric', () {
      const line = LyricsLine(timestamp: Duration.zero, text: '');

      expect(playedCharacterCount(line, const Duration(seconds: 3)), 0);
    });
  });

  group('playedFraction', () {
    test('keeps the fraction of the word being sung', () {
      const line = LyricsLine(
        timestamp: Duration(seconds: 10),
        text: 'ABCD EF',
        words: [
          WordTiming(
            word: 'ABCD',
            start: Duration(seconds: 10),
            duration: Duration(seconds: 1),
          ),
          WordTiming(
            word: ' EF',
            start: Duration(seconds: 11),
            duration: Duration(seconds: 1),
          ),
        ],
      );

      expect(playedFraction(line, const Duration(seconds: 10)), 0);
      // Half of the first four character word has been sung.
      expect(
        playedFraction(line, const Duration(milliseconds: 10500)),
        closeTo(2 / 7, 0.0001),
      );
      // The first word is done and half of the three character word being sung
      // has elapsed: the boundary sits *inside* a character.
      expect(
        playedFraction(line, const Duration(milliseconds: 11500)),
        closeTo(5.5 / 7, 0.0001),
      );
      expect(playedFraction(line, const Duration(seconds: 12)), 1);
    });

    test('sweeps plain lines between timestamps', () {
      const line = LyricsLine(
        timestamp: Duration(seconds: 5),
        text: '1234567890',
      );

      expect(
        playedFraction(
          line,
          const Duration(milliseconds: 7500),
          nextTimestamp: const Duration(seconds: 10),
        ),
        closeTo(0.5, 0.0001),
      );
      expect(
        playedFraction(
          line,
          const Duration(seconds: 10),
          nextTimestamp: const Duration(seconds: 10),
        ),
        1,
      );
      // Before the line starts and after the fallback window has elapsed.
      expect(playedFraction(line, const Duration(seconds: 1)), 0);
      expect(playedFraction(line, const Duration(seconds: 30)), 1);
    });
  });

  group('PlayedProgressRate', () {
    test('reports a smoothed rate while the progress advances', () {
      var now = DateTime(2026, 1, 1, 12);
      final rate = PlayedProgressRate();

      // First sample only anchors.
      expect(rate.update(0.1, now, isPlaying: true), 0);
      now = now.add(const Duration(milliseconds: 200));
      final value = rate.update(0.2, now, isPlaying: true);

      expect(value, greaterThan(0));
      expect(value, lessThanOrEqualTo(0.01));
    });

    test('drops to zero while paused or after a backwards seek', () {
      var now = DateTime(2026, 1, 1, 12);
      final rate = PlayedProgressRate();
      rate.update(0.1, now, isPlaying: true);
      now = now.add(const Duration(milliseconds: 200));
      expect(rate.update(0.3, now, isPlaying: true), greaterThan(0));

      now = now.add(const Duration(milliseconds: 200));
      expect(rate.update(0.4, now, isPlaying: false), 0);
      expect(rate.ratePerMs, 0);

      // Backwards progress (seek or new line) re-anchors instead of jumping.
      now = now.add(const Duration(milliseconds: 200));
      expect(rate.update(0.9, now, isPlaying: true), 0);
      expect(rate.ratePerMs, 0);
    });
  });

  group('LyricsProgressEstimator', () {
    test('extrapolates between coarse player state updates', () {
      var now = DateTime(2026, 1, 1, 12);
      final estimator = LyricsProgressEstimator(now: () => now);

      // Paused: the raw position is used.
      expect(
        estimator.estimate(const Duration(seconds: 5), isPlaying: false),
        const Duration(seconds: 5),
      );
      // First observation while playing anchors the clock.
      expect(
        estimator.estimate(const Duration(seconds: 5), isPlaying: true),
        const Duration(seconds: 5),
      );

      now = now.add(const Duration(milliseconds: 400));
      expect(
        estimator.estimate(const Duration(seconds: 5), isPlaying: true),
        const Duration(seconds: 5, milliseconds: 400),
      );

      // A new state position re-anchors instead of jumping forward.
      now = now.add(const Duration(milliseconds: 100));
      expect(
        estimator.estimate(const Duration(seconds: 6), isPlaying: true),
        const Duration(seconds: 6),
      );

      // Never runs past the song duration.
      now = now.add(const Duration(seconds: 30));
      expect(
        estimator.estimate(
          const Duration(seconds: 6),
          isPlaying: true,
          duration: const Duration(seconds: 10),
        ),
        const Duration(seconds: 10),
      );
    });

    test('reset clears the anchor', () {
      var now = DateTime(2026, 1, 1, 12);
      final estimator = LyricsProgressEstimator(now: () => now);
      estimator.estimate(const Duration(seconds: 5), isPlaying: true);
      now = now.add(const Duration(seconds: 2));
      estimator.reset();

      expect(
        estimator.estimate(const Duration(seconds: 5), isPlaying: true),
        const Duration(seconds: 5),
      );
    });
  });
}
