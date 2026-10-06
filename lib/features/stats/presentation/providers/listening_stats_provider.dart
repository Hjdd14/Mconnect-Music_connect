import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../../../models/song.dart';
import '../../../player/presentation/providers/player_provider.dart';
import '../../data/listening_stats_repository.dart';
import '../../domain/listening_stats.dart';

export '../../data/listening_stats_repository.dart';
export '../../domain/listening_stats.dart';

/// Statistics for the whole app, backed by the `PlayEvents` detail table.
///
/// History of this file: until v1.4.0 the store was a Hive snapshot that kept
/// only the **top 100 songs** and rebuilt its index from that truncated list, so
/// the 101st distinct song permanently erased the least-played song's statistics
/// while `totalPlayCount`/`totalListenDuration` stayed global — the totals could
/// not be reconciled with the detail. Detail now lives in `PlayEvents` (with a
/// `DailyStats` roll-up); the ranked list below is only a view.
final listeningStatsProvider =
    StateNotifierProvider<ListeningStatsNotifier, ListeningStatsState>((ref) {
      return ListeningStatsNotifier(
        DriftListeningStatsRepository(database),
        legacyStore: const LegacyListeningStatsStore(),
      );
    });

/// Multi-dimensional report (artists / albums / platforms / days / hours).
final listeningStatsReportProvider = FutureProvider<ListeningStatsReport>((
  ref,
) async {
  // Re-read whenever the detail changes; otherwise the dimension sections would
  // keep showing the values from the first build.
  ref.watch(listeningStatsProvider.select((state) => state.totalPlayCount));
  final repository = DriftListeningStatsRepository(database);
  return repository.loadReport();
});

final listeningStatsTrackerProvider = Provider<ListeningStatsTracker>((ref) {
  final tracker = ListeningStatsTracker(
    notifier: ref.read(listeningStatsProvider.notifier),
  );
  // Data-layer half of the "history shows 0:00" fix. The history provider
  // records a row when playback starts and has no duration yet; this feeds the
  // elapsed time back into that same row. Kept here (not in the history
  // provider) so the statistics tracker stays the single source of listened
  // time.
  tracker.onListenedDuration = (songId, platform, duration) async {
    try {
      await database.historyDao.backfillListenedDuration(
        songId,
        platform,
        duration,
      );
    } catch (e) {
      debugPrint('history duration backfill failed: $e');
    }
  };
  ref.listen<PlayerState>(playerProvider, (previous, next) {
    unawaited(
      tracker.handlePlaybackSnapshot(
        previous: ListeningPlaybackSnapshot.fromPlayerState(previous),
        next: ListeningPlaybackSnapshot.fromPlayerState(next),
      ),
    );
  });
  ref.onDispose(() {
    unawaited(tracker.flush());
    tracker.dispose();
  });
  return tracker;
});

class ListeningStatsNotifier extends StateNotifier<ListeningStatsState> {
  ListeningStatsNotifier(
    this._repository, {
    this.legacyStore,
    this.importLegacySnapshot = true,
  }) : super(const ListeningStatsState(isLoading: true)) {
    ready = load();
  }

  final ListeningStatsRepository _repository;
  final LegacyStatsSource? legacyStore;

  /// Whether [load] should first move a v1.3.2 Hive snapshot into the event
  /// table. On by default in the app; tests that seed the repository directly
  /// turn it off.
  final bool importLegacySnapshot;

  late final Future<void> ready;

  ListeningStatsRepository get repository => _repository;

  Future<void> load() async {
    try {
      final legacy = legacyStore;
      if (importLegacySnapshot && legacy != null) {
        await ListeningStatsLegacyMigration(
          legacyStore: legacy,
          target: _repository,
        ).run();
      }
      final snapshot = await _repository.load();
      if (!mounted) return;
      state = snapshot.copyWith(isLoading: false, error: () => null);
    } catch (e, s) {
      debugPrint('ListeningStatsNotifier load failed: $e');
      debugPrint('$s');
      if (mounted) {
        state = state.copyWith(isLoading: false, error: () => '听歌统计加载失败');
      }
    }
  }

  Future<void> recordSongStarted(
    Song song, {
    PlayEventSource source = PlayEventSource.play,
  }) async {
    try {
      final snapshot = await _repository.recordSongStarted(
        song,
        source: source,
      );
      if (mounted) state = snapshot.copyWith(error: () => null);
    } catch (e, s) {
      debugPrint('ListeningStatsNotifier record start failed: $e');
      debugPrint('$s');
    }
  }

  Future<void> addListenedDuration(Song song, Duration duration) async {
    if (duration <= Duration.zero) return;
    try {
      final snapshot = await _repository.addListenedDuration(song, duration);
      if (mounted) state = snapshot.copyWith(error: () => null);
    } catch (e, s) {
      debugPrint('ListeningStatsNotifier add duration failed: $e');
      debugPrint('$s');
    }
  }

  Future<void> clear() async {
    await _repository.clear();
    if (mounted) state = const ListeningStatsState();
  }
}

/// The slice of `PlayerState` the tracker reacts to.
///
/// Lives here rather than in the domain layer so the statistics domain/data
/// layers stay free of any dependency on the player feature.
@immutable
class ListeningPlaybackSnapshot {
  final Song? song;
  final bool isPlaying;
  final Duration position;

  const ListeningPlaybackSnapshot({
    this.song,
    this.isPlaying = false,
    this.position = Duration.zero,
  });

  static ListeningPlaybackSnapshot fromPlayerState(PlayerState? state) {
    if (state == null) return const ListeningPlaybackSnapshot();
    return ListeningPlaybackSnapshot(
      song: state.currentSong,
      isPlaying: state.isPlaying,
      position: state.position,
    );
  }
}

/// Turns `PlayerState` transitions into play events.
class ListeningStatsTracker {  ListeningStatsTracker({
    required this.notifier,
    this.flushInterval = const Duration(seconds: 10),
  });

  /// A position this close to the start counts as "playing from the top".
  static const Duration restartThreshold = Duration(seconds: 5);

  /// A position delta larger than this is a seek, not listening.
  static const Duration maxProgressDelta = Duration(seconds: 10);

  final ListeningStatsNotifier notifier;
  final Duration flushInterval;
  final Map<String, _PendingDuration> _pendingDurations = {};
  Timer? _flushTimer;

  /// Feeds the elapsed time back into the history row as well, so the history
  /// page stops showing `0:00` for every entry.
  ///
  /// Set by the composition root to [HistoryDao.backfillListenedDuration]; left
  /// null in unit tests.
  Future<void> Function(String songId, String platform, Duration duration)?
  onListenedDuration;

  Future<void> handlePlaybackSnapshot({
    required ListeningPlaybackSnapshot previous,
    required ListeningPlaybackSnapshot next,
  }) async {
    final song = next.song;
    if (song == null) return;

    final sameSong =
        previous.song != null &&
        previous.song!.id == song.id &&
        previous.song!.platform == song.platform;
    // A pause-and-resume is NOT a new play. Only a different song, or playback
    // that actually restarted from the beginning, counts as one.
    final restarted =
        next.isPlaying &&
        sameSong &&
        next.position <= restartThreshold &&
        previous.position > restartThreshold;
    if (next.isPlaying && (!sameSong || restarted)) {
      await notifier.recordSongStarted(
        song,
        source: sameSong ? PlayEventSource.resume : PlayEventSource.play,
      );
    }

    final canCount =
        previous.isPlaying &&
        next.isPlaying &&
        sameSong &&
        previous.song != null;
    if (!canCount) return;

    final delta = next.position - previous.position;
    if (delta <= Duration.zero || delta > maxProgressDelta) {
      return;
    }
    _addPending(song, delta);
    if (flushInterval == Duration.zero) {
      await flush();
    } else {
      _flushTimer ??= Timer(flushInterval, () => unawaited(flush()));
    }
  }

  void _addPending(Song song, Duration duration) {
    final key = '${song.platform.name}_${song.id}';
    final current = _pendingDurations[key];
    _pendingDurations[key] = _PendingDuration(
      song: song,
      duration: (current?.duration ?? Duration.zero) + duration,
    );
  }

  Future<void> flush() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    if (_pendingDurations.isEmpty) return;
    final pending = List<_PendingDuration>.from(_pendingDurations.values);
    _pendingDurations.clear();
    for (final item in pending) {
      await notifier.addListenedDuration(item.song, item.duration);
      final backfill = onListenedDuration;
      if (backfill != null) {
        await backfill(item.song.id, item.song.platform.name, item.duration);
      }
    }
  }

  void dispose() {
    _flushTimer?.cancel();
  }
}

class _PendingDuration {
  final Song song;
  final Duration duration;

  const _PendingDuration({required this.song, required this.duration});
}
