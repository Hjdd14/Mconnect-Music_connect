import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../../../models/platform_type.dart';
import '../../../../models/song.dart';
import '../../../player/presentation/providers/player_provider.dart';

const _statsBoxName = 'listening_stats';
const _statsSnapshotKey = 'snapshot';

@immutable
class ListeningStatsSongEntry {
  final String songId;
  final PlatformType platform;
  final String songName;
  final String artistNames;
  final int playCount;
  final Duration listenDuration;
  final DateTime lastListenedAt;

  const ListeningStatsSongEntry({
    required this.songId,
    required this.platform,
    required this.songName,
    required this.artistNames,
    required this.playCount,
    required this.listenDuration,
    required this.lastListenedAt,
  });

  String get key => '${platform.name}_$songId';

  ListeningStatsSongEntry copyWith({
    String? songName,
    String? artistNames,
    int? playCount,
    Duration? listenDuration,
    DateTime? lastListenedAt,
  }) {
    return ListeningStatsSongEntry(
      songId: songId,
      platform: platform,
      songName: songName ?? this.songName,
      artistNames: artistNames ?? this.artistNames,
      playCount: playCount ?? this.playCount,
      listenDuration: listenDuration ?? this.listenDuration,
      lastListenedAt: lastListenedAt ?? this.lastListenedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'songId': songId,
      'platform': platform.name,
      'songName': songName,
      'artistNames': artistNames,
      'playCount': playCount,
      'listenDurationMs': listenDuration.inMilliseconds,
      'lastListenedAt': lastListenedAt.toIso8601String(),
    };
  }

  static ListeningStatsSongEntry? fromJson(dynamic value) {
    if (value is! Map) return null;
    final songId = value['songId']?.toString() ?? '';
    if (songId.isEmpty) return null;
    final platformName = value['platform']?.toString();
    final platform = PlatformType.values.firstWhere(
      (item) => item.name == platformName,
      orElse: () => PlatformType.netease,
    );
    return ListeningStatsSongEntry(
      songId: songId,
      platform: platform,
      songName: value['songName']?.toString() ?? '',
      artistNames: value['artistNames']?.toString() ?? '',
      playCount: _intValue(value['playCount']) ?? 0,
      listenDuration: Duration(
        milliseconds: _intValue(value['listenDurationMs']) ?? 0,
      ),
      lastListenedAt:
          DateTime.tryParse(value['lastListenedAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

@immutable
class ListeningStatsState {
  final bool isLoading;
  final String? error;
  final int totalPlayCount;
  final Duration totalListenDuration;
  final List<ListeningStatsSongEntry> topSongs;

  const ListeningStatsState({
    this.isLoading = false,
    this.error,
    this.totalPlayCount = 0,
    this.totalListenDuration = Duration.zero,
    this.topSongs = const [],
  });

  ListeningStatsState copyWith({
    bool? isLoading,
    String? Function()? error,
    int? totalPlayCount,
    Duration? totalListenDuration,
    List<ListeningStatsSongEntry>? topSongs,
  }) {
    return ListeningStatsState(
      isLoading: isLoading ?? this.isLoading,
      error: error != null ? error() : this.error,
      totalPlayCount: totalPlayCount ?? this.totalPlayCount,
      totalListenDuration: totalListenDuration ?? this.totalListenDuration,
      topSongs: topSongs ?? this.topSongs,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'totalPlayCount': totalPlayCount,
      'totalListenMs': totalListenDuration.inMilliseconds,
      'topSongs': topSongs.map((song) => song.toJson()).toList(),
    };
  }

  static ListeningStatsState fromJson(dynamic value) {
    if (value is! Map) return const ListeningStatsState();
    final rawSongs = value['topSongs'];
    final songs = rawSongs is List
        ? rawSongs
              .map(ListeningStatsSongEntry.fromJson)
              .whereType<ListeningStatsSongEntry>()
              .toList()
        : <ListeningStatsSongEntry>[];
    songs.sort(_sortSongEntries);
    return ListeningStatsState(
      totalPlayCount: _intValue(value['totalPlayCount']) ?? 0,
      totalListenDuration: Duration(
        milliseconds: _intValue(value['totalListenMs']) ?? 0,
      ),
      topSongs: songs,
    );
  }
}

abstract class ListeningStatsRepository {
  Future<ListeningStatsState> load();
  Future<ListeningStatsState> recordSongStarted(Song song);
  Future<ListeningStatsState> addListenedDuration(Song song, Duration duration);
  Future<void> clear();
}

class HiveListeningStatsRepository implements ListeningStatsRepository {
  Future<Box<dynamic>> _box() => Hive.openBox(_statsBoxName);

  @override
  Future<ListeningStatsState> load() async {
    final box = await _box();
    return ListeningStatsState.fromJson(box.get(_statsSnapshotKey));
  }

  @override
  Future<ListeningStatsState> recordSongStarted(Song song) async {
    final current = await load();
    final next = _recordSongStarted(current, song);
    await _save(next);
    return next;
  }

  @override
  Future<ListeningStatsState> addListenedDuration(
    Song song,
    Duration duration,
  ) async {
    final current = await load();
    final next = _addListenedDuration(current, song, duration);
    await _save(next);
    return next;
  }

  @override
  Future<void> clear() async {
    final box = await _box();
    await box.delete(_statsSnapshotKey);
  }

  Future<void> _save(ListeningStatsState state) async {
    final box = await _box();
    await box.put(_statsSnapshotKey, state.toJson());
  }
}

class MemoryListeningStatsRepository implements ListeningStatsRepository {
  ListeningStatsState _state = const ListeningStatsState();

  @override
  Future<ListeningStatsState> load() async => _state;

  @override
  Future<ListeningStatsState> recordSongStarted(Song song) async {
    _state = _recordSongStarted(_state, song);
    return _state;
  }

  @override
  Future<ListeningStatsState> addListenedDuration(
    Song song,
    Duration duration,
  ) async {
    _state = _addListenedDuration(_state, song, duration);
    return _state;
  }

  @override
  Future<void> clear() async {
    _state = const ListeningStatsState();
  }
}

final listeningStatsProvider =
    StateNotifierProvider<ListeningStatsNotifier, ListeningStatsState>((ref) {
      return ListeningStatsNotifier(HiveListeningStatsRepository());
    });

final listeningStatsTrackerProvider = Provider<ListeningStatsTracker>((ref) {
  final tracker = ListeningStatsTracker(
    notifier: ref.read(listeningStatsProvider.notifier),
  );
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
  final ListeningStatsRepository _repository;
  late final Future<void> ready;

  ListeningStatsNotifier(this._repository)
    : super(const ListeningStatsState(isLoading: true)) {
    ready = load();
  }

  Future<void> load() async {
    try {
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

  Future<void> recordSongStarted(Song song) async {
    try {
      final snapshot = await _repository.recordSongStarted(song);
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

class ListeningStatsTracker {
  final ListeningStatsNotifier notifier;
  final Duration flushInterval;
  final Map<String, _PendingDuration> _pendingDurations = {};
  Timer? _flushTimer;

  ListeningStatsTracker({
    required this.notifier,
    this.flushInterval = const Duration(seconds: 10),
  });

  Future<void> handlePlaybackSnapshot({
    required ListeningPlaybackSnapshot previous,
    required ListeningPlaybackSnapshot next,
  }) async {
    final song = next.song;
    if (song == null) return;

    final changedSong =
        previous.song?.id != song.id ||
        previous.song?.platform != song.platform;
    if (next.isPlaying && (!previous.isPlaying || changedSong)) {
      await notifier.recordSongStarted(song);
    }

    final canCount =
        previous.isPlaying &&
        next.isPlaying &&
        !changedSong &&
        previous.song != null;
    if (!canCount) return;

    final delta = next.position - previous.position;
    if (delta <= Duration.zero || delta > const Duration(seconds: 10)) {
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

ListeningStatsState _recordSongStarted(ListeningStatsState state, Song song) {
  final entries = _entriesByKey(state);
  final key = '${song.platform.name}_${song.id}';
  final now = DateTime.now();
  final existing = entries[key];
  entries[key] = existing == null
      ? ListeningStatsSongEntry(
          songId: song.id,
          platform: song.platform,
          songName: song.name,
          artistNames: song.artistNames,
          playCount: 1,
          listenDuration: Duration.zero,
          lastListenedAt: now,
        )
      : existing.copyWith(
          songName: song.name,
          artistNames: song.artistNames,
          playCount: existing.playCount + 1,
          lastListenedAt: now,
        );
  final songs = _sortedEntries(entries);
  return state.copyWith(
    totalPlayCount: state.totalPlayCount + 1,
    topSongs: songs,
    error: () => null,
  );
}

ListeningStatsState _addListenedDuration(
  ListeningStatsState state,
  Song song,
  Duration duration,
) {
  if (duration <= Duration.zero) return state;
  final entries = _entriesByKey(state);
  final key = '${song.platform.name}_${song.id}';
  final existing = entries[key];
  entries[key] = existing == null
      ? ListeningStatsSongEntry(
          songId: song.id,
          platform: song.platform,
          songName: song.name,
          artistNames: song.artistNames,
          playCount: 0,
          listenDuration: duration,
          lastListenedAt: DateTime.now(),
        )
      : existing.copyWith(
          songName: song.name,
          artistNames: song.artistNames,
          listenDuration: existing.listenDuration + duration,
          lastListenedAt: DateTime.now(),
        );
  return state.copyWith(
    totalListenDuration: state.totalListenDuration + duration,
    topSongs: _sortedEntries(entries),
    error: () => null,
  );
}

Map<String, ListeningStatsSongEntry> _entriesByKey(ListeningStatsState state) {
  return {for (final entry in state.topSongs) entry.key: entry};
}

List<ListeningStatsSongEntry> _sortedEntries(
  Map<String, ListeningStatsSongEntry> entries,
) {
  final songs = entries.values.toList()..sort(_sortSongEntries);
  return songs.take(100).toList();
}

int _sortSongEntries(
  ListeningStatsSongEntry left,
  ListeningStatsSongEntry right,
) {
  final durationCompare = right.listenDuration.compareTo(left.listenDuration);
  if (durationCompare != 0) return durationCompare;
  final playCompare = right.playCount.compareTo(left.playCount);
  if (playCompare != 0) return playCompare;
  return right.lastListenedAt.compareTo(left.lastListenedAt);
}

int? _intValue(dynamic value) {
  if (value is int) return value;
  return int.tryParse(value?.toString() ?? '');
}
