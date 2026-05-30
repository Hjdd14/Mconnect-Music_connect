import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../models/platform_type.dart';
import '../../data/smart_playlist_repository.dart';
import '../../domain/smart_playlist_rule.dart';

@immutable
class SmartPlaylistsState {
  final List<SmartPlaylistRule> rules;
  final bool isLoading;
  final bool isSaving;
  final String? error;

  const SmartPlaylistsState({
    this.rules = const [],
    this.isLoading = false,
    this.isSaving = false,
    this.error,
  });

  SmartPlaylistsState copyWith({
    List<SmartPlaylistRule>? rules,
    bool? isLoading,
    bool? isSaving,
    String? Function()? error,
  }) {
    return SmartPlaylistsState(
      rules: rules ?? this.rules,
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
      );
    });

class SmartPlaylistsNotifier extends StateNotifier<SmartPlaylistsState> {
  final SmartPlaylistRepository _repository;
  late final Future<void> ready;

  SmartPlaylistsNotifier({required SmartPlaylistRepository repository})
    : _repository = repository,
      super(const SmartPlaylistsState(isLoading: true)) {
    ready = load();
  }

  Future<void> load() async {
    state = state.copyWith(isLoading: true, error: () => null);
    try {
      final rules = await _repository.loadRules();
      if (mounted) {
        state = state.copyWith(
          rules: rules,
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
  }

  Future<void> _persist(List<SmartPlaylistRule> rules) async {
    state = state.copyWith(isSaving: true, error: () => null);
    try {
      final sorted = List<SmartPlaylistRule>.from(rules)
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      await _repository.saveRules(sorted);
      if (mounted) {
        state = state.copyWith(
          rules: sorted,
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
