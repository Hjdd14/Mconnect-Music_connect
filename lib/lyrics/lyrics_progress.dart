import 'models/lyrics_line.dart';

/// Progress helpers shared by the floating lyrics overlay and the in-app
/// player lyrics, so both highlight the already-sung part of a line the same
/// way.

/// Applies the user's manual calibration to a playback position.
///
/// This is the single definition of "which lyric line is current" for both
/// screens: `lyrics_display.dart` matches its lines against `position + offset`
/// and the floating overlay shifts the position the same way before it picks a
/// line. Keeping it in one function is what stops the overlay from drifting
/// behind the player page whenever the user calibrates.
Duration applyLyricsOffset(Duration position, Duration offset) =>
    position + offset;

/// How many leading characters of [line] playback has already reached.
///
/// Word-timed formats (QRC/KRC) accumulate whole words plus the elapsed part
/// of the word being sung; plain LRC lines are swept proportionally between
/// this line and the next one.
int playedCharacterCount(
  LyricsLine line,
  Duration position, {
  Duration? nextTimestamp,
  Duration fallbackLineDuration = const Duration(seconds: 4),
}) {
  final textLength = line.text.length;
  if (textLength == 0) return 0;

  final words = line.words;
  if (words != null && words.isNotEmpty) {
    final played = StringBuffer();
    for (final word in words) {
      if (position >= word.start + word.duration) {
        played.write(word.word);
        continue;
      }
      if (position >= word.start &&
          word.duration > Duration.zero &&
          word.word.isNotEmpty) {
        final elapsed = (position - word.start).inMilliseconds;
        final fraction = (elapsed / word.duration.inMilliseconds).clamp(
          0.0,
          1.0,
        );
        final characters = (fraction * word.word.length).round();
        if (characters > 0) {
          played.write(word.word.substring(0, characters));
        }
      }
      break;
    }

    final playedText = played.toString();
    if (playedText.isEmpty) return 0;
    if (line.text.startsWith(playedText)) {
      return playedText.length.clamp(0, textLength);
    }
    // Some word streams keep separators the display text drops, so fall back to
    // a proportional mapping instead of trusting raw offsets.
    final totalWordCharacters = words.fold<int>(
      0,
      (sum, word) => sum + word.word.length,
    );
    if (totalWordCharacters <= 0) return 0;
    return ((playedText.length / totalWordCharacters) * textLength)
        .floor()
        .clamp(0, textLength);
  }

  final start = line.timestamp;
  final end = (nextTimestamp != null && nextTimestamp > start)
      ? nextTimestamp
      : start + fallbackLineDuration;
  final total = (end - start).inMilliseconds;
  if (total <= 0) return textLength;
  final fraction = ((position - start).inMilliseconds / total).clamp(0.0, 1.0);
  return (fraction * textLength).floor().clamp(0, textLength);
}

/// Extrapolates the played position between the player's coarse state updates.
///
/// `PlayerNotifier` only publishes a new position about once per second, so a
/// character-level highlight driven by that alone would jump a second at a
/// time. Callers use this estimate for the highlight only and keep the raw
/// position for line switching, so a lyric line can never advance early.
class LyricsProgressEstimator {
  LyricsProgressEstimator({DateTime Function()? now}) : _now = now ?? DateTime.now;

  final DateTime Function() _now;
  Duration? _lastPosition;
  DateTime? _lastPositionAt;

  Duration estimate(
    Duration position, {
    required bool isPlaying,
    Duration duration = Duration.zero,
  }) {
    final now = _now();
    if (!isPlaying || _lastPosition == null || position != _lastPosition) {
      _lastPosition = position;
      _lastPositionAt = now;
      return position;
    }
    final changedAt = _lastPositionAt;
    if (changedAt == null) return position;
    final elapsed = now.difference(changedAt);
    if (elapsed <= Duration.zero) return position;
    final estimated = position + elapsed;
    if (duration > Duration.zero && estimated > duration) return duration;
    return estimated;
  }

  void reset() {
    _lastPosition = null;
    _lastPositionAt = null;
  }
}

/// Continuous (0..1) progress of the already-sung part of a line.
///
/// Unlike [playedCharacterCount] this keeps the fraction of the character being
/// sung, which is what lets the highlight sweep smoothly instead of jumping a
/// whole character at a time.
double playedFraction(
  LyricsLine line,
  Duration position, {
  Duration? nextTimestamp,
  Duration fallbackLineDuration = const Duration(seconds: 4),
}) {
  final textLength = line.text.length;
  if (textLength == 0) return 0;

  final words = line.words;
  if (words != null && words.isNotEmpty) {
    var playedCharacters = 0.0;
    final played = StringBuffer();
    for (final word in words) {
      if (position >= word.start + word.duration) {
        playedCharacters += word.word.length;
        played.write(word.word);
        continue;
      }
      if (position >= word.start &&
          word.duration > Duration.zero &&
          word.word.isNotEmpty) {
        final elapsed = (position - word.start).inMilliseconds;
        final fraction = (elapsed / word.duration.inMilliseconds).clamp(
          0.0,
          1.0,
        );
        playedCharacters += fraction * word.word.length;
        final characters = (fraction * word.word.length).floor();
        if (characters > 0) {
          played.write(word.word.substring(0, characters));
        }
      }
      break;
    }

    if (playedCharacters <= 0) return 0;
    final playedText = played.toString();
    if (line.text.startsWith(playedText)) {
      return (playedCharacters / textLength).clamp(0.0, 1.0);
    }
    final totalWordCharacters = words.fold<int>(
      0,
      (sum, word) => sum + word.word.length,
    );
    if (totalWordCharacters <= 0) return 0;
    return (playedCharacters / totalWordCharacters).clamp(0.0, 1.0);
  }

  final start = line.timestamp;
  final end = (nextTimestamp != null && nextTimestamp > start)
      ? nextTimestamp
      : start + fallbackLineDuration;
  final total = (end - start).inMilliseconds;
  if (total <= 0) return 1;
  return ((position - start).inMilliseconds / total).clamp(0.0, 1.0);
}

/// Smoothed progress-per-millisecond, used to keep the native overlay sweeping
/// between the ~200ms anchors it receives from Dart.
class PlayedProgressRate {
  PlayedProgressRate({this.smoothing = 0.35, this.maxRatePerMs = 0.01})
    : assert(smoothing > 0 && smoothing <= 1);

  final double smoothing;
  final double maxRatePerMs;

  double _ratePerMs = 0;
  double? _lastProgress;
  DateTime? _lastAt;

  double get ratePerMs => _ratePerMs;

  double update(double progress, DateTime now, {required bool isPlaying}) {
    if (!isPlaying) {
      reset();
      return 0;
    }
    final lastProgress = _lastProgress;
    final lastAt = _lastAt;
    if (lastProgress == null || lastAt == null || progress < lastProgress) {
      // First sample, or the line changed / the user seeked backwards.
      _lastProgress = progress;
      _lastAt = now;
      _ratePerMs = 0;
      return 0;
    }
    final elapsedMs = now.difference(lastAt).inMicroseconds / 1000.0;
    if (elapsedMs <= 0) {
      _lastProgress = progress;
      _lastAt = now;
      return _ratePerMs;
    }
    final instantaneous = ((progress - lastProgress) / elapsedMs).clamp(
      0.0,
      maxRatePerMs,
    );
    _ratePerMs += (instantaneous - _ratePerMs) * smoothing;
    _lastProgress = progress;
    _lastAt = now;
    return _ratePerMs;
  }

  void reset() {
    _ratePerMs = 0;
    _lastProgress = null;
    _lastAt = null;
  }
}
