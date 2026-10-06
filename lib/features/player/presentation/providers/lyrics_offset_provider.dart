import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

const _settingsBoxName = 'settings';
const _lyricsOffsetKey = 'lyrics_offset_ms';

/// Manual lyrics calibration range: how far the lyrics may be shifted against
/// the audio (positive = lyrics shown earlier than the audio, i.e. the offset
/// is added to the playback position).
const Duration minLyricsOffset = Duration(seconds: -5);
const Duration maxLyricsOffset = Duration(seconds: 5);

/// Step used by the +/- controls.
const Duration lyricsOffsetStep = Duration(milliseconds: 500);

Duration clampLyricsOffset(Duration offset) {
  if (offset < minLyricsOffset) return minLyricsOffset;
  if (offset > maxLyricsOffset) return maxLyricsOffset;
  return offset;
}

/// Manual lyrics offset, persisted so calibration survives a restart.
///
/// The offset is deliberately kept in the player feature (not on
/// `LyricsLine`): the model is a pure parse result and is cached per platform,
/// while the offset is a user preference that belongs with playback.
class LyricsOffsetNotifier extends StateNotifier<Duration> {
  final Future<void> Function(int milliseconds)? _persist;

  LyricsOffsetNotifier({
    Duration initial = Duration.zero,
    this._persist,
  }) : super(clampLyricsOffset(initial));

  Future<void> setOffset(Duration offset) async {
    final clamped = clampLyricsOffset(offset);
    state = clamped;
    final persist = _persist;
    if (persist == null) return;
    try {
      await persist(clamped.inMilliseconds);
    } catch (e, s) {
      debugPrint('LyricsOffsetNotifier persist failed: $e');
      debugPrint('$s');
    }
  }

  Future<void> adjust(Duration delta) => setOffset(state + delta);

  Future<void> reset() => setOffset(Duration.zero);
}

/// Backed by the shared `settings` Hive box; a missing/unopenable box degrades
/// to the in-memory default rather than crashing the player.
final lyricsOffsetProvider =
    StateNotifierProvider<LyricsOffsetNotifier, Duration>((ref) {
      return LyricsOffsetNotifier(
        initial: _readPersistedOffset() ?? Duration.zero,
        persist: (milliseconds) async {
          final box = await Hive.openBox(_settingsBoxName);
          await box.put(_lyricsOffsetKey, milliseconds);
        },
      );
    });

Duration? _readPersistedOffset() {
  try {
    // `Hive.box` throws when the box was never opened — e.g. in widget tests.
    // Reading through `isBoxOpen` keeps that a silent default instead of a
    // debugPrint on every build.
    if (!Hive.isBoxOpen(_settingsBoxName)) return null;
    final raw = Hive.box(_settingsBoxName).get(_lyricsOffsetKey);
    if (raw is int) return Duration(milliseconds: raw);
    return null;
  } catch (e) {
    debugPrint('LyricsOffsetNotifier load failed: $e');
    return null;
  }
}
