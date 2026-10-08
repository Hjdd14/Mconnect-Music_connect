import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../../../models/song.dart';
import 'player_provider.dart';

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

/// The database key for one song's calibration.
///
/// Matches `LyricsOffsets.songKey` / `TrackRatings.songKey`: `"<platform>:<id>"`.
/// Local tracks use their absolute path as the id, which already distinguishes
/// two files with the same name in different folders.
String lyricsOffsetSongKey(Song song) => '${song.platform.name}:${song.id}';

/// Reads one song's saved offset. `null` key means "no song is bound".
typedef LyricsOffsetLoad = Future<Duration> Function(String songKey);

/// Writes (or clears, on a zero offset) one song's calibration. The key is null
/// when no song is bound — the store then has nothing to write.
typedef LyricsOffsetPersist =
    Future<void> Function(String? songKey, int milliseconds);

/// Where the per-song calibration is stored.
///
/// A seam rather than a direct `database` access so the mapping from a playing
/// song to its row is testable without the app's sqlite file.
abstract class LyricsOffsetStore {
  Future<Duration> load(String songKey);

  /// Saves [offset]; a zero offset removes the row.
  Future<void> save(String songKey, Duration offset);
}

/// Drift-backed store over `LyricsOffsetDao` (schema v3).
class DriftLyricsOffsetStore implements LyricsOffsetStore {
  const DriftLyricsOffsetStore();

  @override
  Future<Duration> load(String songKey) => database.lyricsOffsetDao.get(songKey);

  @override
  Future<void> save(String songKey, Duration offset) =>
      database.lyricsOffsetDao.set(songKey, offset);
}

final lyricsOffsetStoreProvider = Provider<LyricsOffsetStore>(
  (ref) => const DriftLyricsOffsetStore(),
);

/// Manual lyrics offset for the **current song**, persisted per song so
/// calibration survives a restart.
///
/// The offset is deliberately kept in the player feature (not on `LyricsLine`):
/// the model is a pure parse result and is cached per platform, while the offset
/// is a user preference that belongs with playback.
class LyricsOffsetNotifier extends StateNotifier<Duration> {
  final LyricsOffsetPersist? _persist;
  final LyricsOffsetLoad? _load;

  String? _songKey;

  LyricsOffsetNotifier({
    Duration initial = Duration.zero,
    this._persist,
    this._load,
  }) : super(clampLyricsOffset(initial));

  /// The song this calibration belongs to, or null when none is bound.
  String? get songKey => _songKey;

  /// Binds the calibration to [songKey] and loads that song's value.
  ///
  /// The state is reset to zero **before** the read: the previous song's offset
  /// must never be applied to this one while the read is in flight, nor survive
  /// a failed read (a −5s calibration leaking across songs is exactly the bug
  /// the global key used to cause).
  Future<void> bindSong(String? songKey) async {
    _songKey = songKey;
    state = Duration.zero;
    if (songKey == null) return;

    final load = _load;
    if (load == null) return;
    try {
      final loaded = clampLyricsOffset(await load(songKey));
      // A newer bind (or a dispose) wins: this read is stale.
      if (!mounted || _songKey != songKey) return;
      state = loaded;
    } catch (e, s) {
      debugPrint('LyricsOffsetNotifier load failed: $e');
      debugPrint('$s');
    }
  }

  Future<void> setOffset(Duration offset) async {
    final clamped = clampLyricsOffset(offset);
    state = clamped;
    final persist = _persist;
    if (persist == null) return;
    try {
      await persist(_songKey, clamped.inMilliseconds);
    } catch (e, s) {
      debugPrint('LyricsOffsetNotifier persist failed: $e');
      debugPrint('$s');
    }
  }

  Future<void> adjust(Duration delta) => setOffset(state + delta);

  Future<void> reset() => setOffset(Duration.zero);
}

/// Backed by `lyrics_offsets` for the song `playerProvider` is playing.
///
/// A missing/unopenable database degrades to the in-memory default rather than
/// crashing the player, and switching songs reloads the calibration.
final lyricsOffsetSongKeyProvider = Provider<String?>((ref) {
  final song = ref.watch(playerProvider.select((state) => state.currentSong));
  return song == null ? null : lyricsOffsetSongKey(song);
});

final lyricsOffsetProvider =
    StateNotifierProvider<LyricsOffsetNotifier, Duration>((ref) {
      final store = ref.watch(lyricsOffsetStoreProvider);
      final notifier = LyricsOffsetNotifier(
        load: store.load,
        persist: (songKey, milliseconds) async {
          if (songKey == null) return;
          await store.save(songKey, Duration(milliseconds: milliseconds));
        },
      );
      unawaited(notifier.bindSong(ref.read(lyricsOffsetSongKeyProvider)));
      ref.listen<String?>(
        lyricsOffsetSongKeyProvider,
        (previous, next) => unawaited(notifier.bindSong(next)),
      );
      return notifier;
    });
