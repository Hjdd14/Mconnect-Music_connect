import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../../../models/platform_type.dart';
import '../../../../models/song.dart';
import '../../data/smart_playlist_repository.dart';
import '../../data/smart_playlist_snapshot_repository.dart';
import '../../domain/smart_playlist_rule.dart';

@immutable
class SmartPlaylistsState {
  final List<SmartPlaylistRule> rules;
  final Map<String, SavedSmartPlaylist> snapshots;
  final bool isLoading;
  final bool isSaving;
  final String? error;

  const SmartPlaylistsState({
    this.rules = const [],
    this.snapshots = const {},
    this.isLoading = false,
    this.isSaving = false,
    this.error,
  });

  SavedSmartPlaylist? snapshotFor(String ruleId) => snapshots[ruleId];

  SmartPlaylistsState copyWith({
    List<SmartPlaylistRule>? rules,
    Map<String, SavedSmartPlaylist>? snapshots,
    bool? isLoading,
    bool? isSaving,
    String? Function()? error,
  }) {
    return SmartPlaylistsState(
      rules: rules ?? this.rules,
      snapshots: snapshots ?? this.snapshots,
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
      error: error != null ? error() : this.error,
    );
  }
}

final smartPlaylistsProvider =
    StateNotifierProvider<SmartPlaylistsNotifier, SmartPlaylistsState>((ref) {
      return SmartPlaylistsNotifier(
        repository: const HiveSmartPlaylistRepository(),
        snapshotRepository: DriftSmartPlaylistSnapshotRepository(database),
      );
    });

class SmartPlaylistsNotifier extends StateNotifier<SmartPlaylistsState> {
  SmartPlaylistsNotifier({
    required this.repository,
    this.snapshotRepository,
  }) : super(const SmartPlaylistsState(isLoading: true)) {
    ready = load();
  }

  final SmartPlaylistRepository repository;
  final SmartPlaylistSnapshotRepository? snapshotRepository;
  late final Future<void> ready;

  Future<void> load() async {
    state = state.copyWith(isLoading: true, error: () => null);
    try {
      final rules = await repository.loadRules();
      final snapshotStore = snapshotRepository;
      final snapshots = snapshotStore == null
          ? const <String, SavedSmartPlaylist>{}
          : await snapshotStore.loadAll();
      if (mounted) {
        state = state.copyWith(
          rules: rules,
          snapshots: snapshots,
          isLoading: false,
          error: () => null,
        );
      }
    } catch (e, s) {
      debugPrint('SmartPlaylistsNotifier load failed: $e');
      debugPrint('$s');
      if (mounted) {
        state = state.copyWith(isLoading: false, error: () => '智能歌单加载失败');
      }
    }
  }

  Future<SmartPlaylistRule> createRule({
    required String name,
    Set<PlatformType> platforms = const {},
    String keyword = '',
    int minPlayCount = 0,
    int recentlyPlayedDays = 0,
    bool likedOnly = false,
    bool cachedOnly = false,
    int maxSongs = 100,
    Set<String> artistIds = const {},
    Set<String> albumIds = const {},
    int minDurationMs = 0,
    int maxDurationMs = 0,
    int maxPlayCount = 0,
    int notPlayedSinceDays = 0,
    bool localOnly = false,
    bool downloadedOnly = false,
    bool excludeLiked = false,
    SmartPlaylistMatch match = SmartPlaylistMatch.all,
    SmartPlaylistSortOrder sortBy = SmartPlaylistSortOrder.mostListened,
  }) async {
    final rule = SmartPlaylistRule.create(
      name: name,
      platforms: platforms,
      keyword: keyword,
      minPlayCount: minPlayCount,
      recentlyPlayedDays: recentlyPlayedDays,
      likedOnly: likedOnly,
      cachedOnly: cachedOnly,
      maxSongs: maxSongs,
      artistIds: artistIds,
      albumIds: albumIds,
      minDurationMs: minDurationMs,
      maxDurationMs: maxDurationMs,
      maxPlayCount: maxPlayCount,
      notPlayedSinceDays: notPlayedSinceDays,
      localOnly: localOnly,
      downloadedOnly: downloadedOnly,
      excludeLiked: excludeLiked,
      match: match,
      sortBy: sortBy,
    );
    await _persist([rule, ...state.rules]);
    return rule;
  }

  Future<void> updateRule(SmartPlaylistRule rule) async {
    final rules = List<SmartPlaylistRule>.from(state.rules);
    final index = rules.indexWhere((item) => item.id == rule.id);
    if (index == -1) {
      rules.insert(0, rule);
    } else {
      rules[index] = rule;
    }
    await _persist(rules);
  }

  Future<void> deleteRule(String id) async {
    final rules = state.rules.where((rule) => rule.id != id).toList();
    await _persist(rules);
    // The snapshot is keyed by rule id; without this it would linger forever and
    // a future rule could never reuse the id.
    try {
      await snapshotRepository?.delete(id);
      if (mounted) {
        final snapshots = Map<String, SavedSmartPlaylist>.from(state.snapshots)
          ..remove(id);
        state = state.copyWith(snapshots: snapshots);
      }
    } catch (e) {
      debugPrint('SmartPlaylistsNotifier snapshot delete failed: $e');
    }
  }

  /// Persists a generated result so it can be reopened/played after a restart.
  ///
  /// Returns the saved record, or null when the snapshot repository is not
  /// configured or saving failed (the failure is surfaced in [state.error]
  /// instead of being swallowed, which was the old behaviour for every save).
  Future<SavedSmartPlaylist?> saveSnapshot(String ruleId, List<Song> songs) async {
    final repository = snapshotRepository;
    if (repository == null) return null;
    state = state.copyWith(isSaving: true, error: () => null);
    try {
      final saved = await repository.save(ruleId, songs);
      if (mounted) {
        final snapshots = Map<String, SavedSmartPlaylist>.from(state.snapshots)
          ..[ruleId] = saved;
        state = state.copyWith(
          snapshots: snapshots,
          isSaving: false,
          error: () => null,
        );
      }
      return saved;
    } catch (e, s) {
      debugPrint('SmartPlaylistsNotifier snapshot save failed: $e');
      debugPrint('$s');
      if (mounted) {
        state = state.copyWith(isSaving: false, error: () => '生成结果保存失败');
      }
      return null;
    }
  }

  Future<void> _persist(List<SmartPlaylistRule> rules) async {
    state = state.copyWith(isSaving: true, error: () => null);
    try {
      final sorted = List<SmartPlaylistRule>.from(rules)
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      await repository.saveRules(sorted);
      // Housekeeping: a deleted rule must not leave its snapshot behind.
      try {
        await snapshotRepository?.deleteMissing(
          sorted.map((rule) => rule.id).toSet(),
        );
      } catch (e) {
        debugPrint('SmartPlaylistsNotifier snapshot prune failed: $e');
      }
      if (mounted) {
        final snapshots = Map<String, SavedSmartPlaylist>.from(state.snapshots)
          ..removeWhere(
            (ruleId, _) => !sorted.any((rule) => rule.id == ruleId),
          );
        state = state.copyWith(
          rules: sorted,
          snapshots: snapshots,
          isSaving: false,
          error: () => null,
        );
      }
    } catch (e, s) {
      debugPrint('SmartPlaylistsNotifier save failed: $e');
      debugPrint('$s');
      if (mounted) {
        state = state.copyWith(isSaving: false, error: () => '智能歌单保存失败');
      }
    }
  }
}
