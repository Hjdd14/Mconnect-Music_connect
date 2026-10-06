import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/network/platform_http.dart';
import '../../../../models/platform_type.dart';
import '../../../../models/song.dart';
import '../../../../platform/base/music_platform.dart';
import '../../../../platform/base/platform_registry.dart';
import '../../data/search_history_store.dart';

/// One merged search hit: the primary song plus every other platform source of
/// the same recording.
///
/// Cross-platform search returns the same song three times (once per platform);
/// [Song.dedupeKey]-grouping collapses them so the list reads as "song × 3
/// platforms" and playback can pick whichever platform actually has a playable
/// URL.
class MergedSong {
  final Song primary;
  final List<Song> sources;

  const MergedSong({required this.primary, required this.sources});

  String get dedupeKey => primary.dedupeKey;

  int get sourceCount => sources.length;

  List<PlatformType> get platforms => sources.map((s) => s.platform).toList();
}

/// Groups songs by [Song.dedupeKey], keeping the best platform as primary.
///
/// `priority` is the platform order used to choose the primary source (default:
/// the app's service order, i.e. 网易云 first); the first-seen order of the keys
/// is preserved so results stay in the platforms' relevance order.
List<MergedSong> mergeSearchSongs(
  Iterable<Song> songs, {
  List<PlatformType> priority = PlatformType.musicServices,
}) {
  final byKey = <String, List<Song>>{};
  for (final song in songs) {
    byKey.putIfAbsent(song.dedupeKey, () => []).add(song);
  }

  int rank(PlatformType platform) {
    final index = priority.indexOf(platform);
    return index < 0 ? priority.length : index;
  }

  return [
    for (final entry in byKey.entries)
      MergedSong(
        primary: (List<Song>.from(entry.value)..sort(
              (a, b) => rank(a.platform).compareTo(rank(b.platform)),
            ))
            .first,
        sources: List<Song>.from(entry.value)..sort(
          (a, b) => rank(a.platform).compareTo(rank(b.platform)),
        ),
      ),
  ];
}

/// Aggregate ("全部平台") search state.
class AggregatedSearchState {
  final String query;
  final Map<PlatformType, String> errorsByPlatform;
  final Map<PlatformType, int> pageByPlatform;
  final Map<PlatformType, bool> hasMoreByPlatform;

  /// Merged results, deduped across platforms.
  final List<MergedSong> songs;

  /// Platform variants chosen by the user per [Song.dedupeKey].
  final Map<String, Song> chosenSourceByKey;

  final bool isLoading;
  final bool isLoadingMore;

  /// True when at least one platform failed with a transport error — used to
  /// tell "没有结果" apart from "网络不可用".
  final bool networkFailed;

  /// Set when *every* platform failed and nothing came back.
  final String? error;

  const AggregatedSearchState({
    this.query = '',
    this.errorsByPlatform = const {},
    this.pageByPlatform = const {},
    this.hasMoreByPlatform = const {},
    this.songs = const [],
    this.chosenSourceByKey = const {},
    this.isLoading = false,
    this.isLoadingMore = false,
    this.networkFailed = false,
    this.error,
  });

  AggregatedSearchState copyWith({
    String? query,
    Map<PlatformType, String>? errorsByPlatform,
    Map<PlatformType, int>? pageByPlatform,
    Map<PlatformType, bool>? hasMoreByPlatform,
    List<MergedSong>? songs,
    Map<String, Song>? chosenSourceByKey,
    bool? isLoading,
    bool? isLoadingMore,
    bool? networkFailed,
    String? Function()? error,
  }) {
    return AggregatedSearchState(
      query: query ?? this.query,
      errorsByPlatform: errorsByPlatform ?? this.errorsByPlatform,
      pageByPlatform: pageByPlatform ?? this.pageByPlatform,
      hasMoreByPlatform: hasMoreByPlatform ?? this.hasMoreByPlatform,
      songs: songs ?? this.songs,
      chosenSourceByKey: chosenSourceByKey ?? this.chosenSourceByKey,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      networkFailed: networkFailed ?? this.networkFailed,
      error: error != null ? error() : this.error,
    );
  }

  /// The song that should actually play for [merged]: the user's chosen source,
  /// otherwise the primary.
  Song sourceFor(MergedSong merged) =>
      chosenSourceByKey[merged.dedupeKey] ?? merged.primary;

  /// The playable list, in display order, using the chosen sources.
  List<Song> get playableSongs =>
      [for (final merged in songs) sourceFor(merged)];

  bool get hasMore => hasMoreByPlatform.values.any((more) => more);

  int get errorCount => errorsByPlatform.length;
}

class AggregatedSearchNotifier extends StateNotifier<AggregatedSearchState> {
  final List<PlatformType> Function() _supportedTypes;
  final MusicPlatform Function(PlatformType) _platformResolver;
  final Duration operationTimeout;
  final int _pageSize;
  /// Platforms already resolved for the current query (resolved once per
  /// search, so a resolver side effect cannot run per request).
  List<MusicPlatform> _implementations = const [];

  List<PlatformType> get _platforms =>
      [for (final impl in _implementations) impl.platformType];

  AggregatedSearchNotifier({
    List<PlatformType>? supportedTypes,
    MusicPlatform Function(PlatformType)? platformResolver,
    this.operationTimeout = const Duration(seconds: 12),
    this._pageSize = 30,
  }) : _supportedTypes = (() =>
           supportedTypes ?? PlatformRegistry.supportedTypes),
       _platformResolver = platformResolver ?? PlatformRegistry.get,
       super(const AggregatedSearchState());

  /// Page 1 of [query] across every supported platform.
  Future<void> search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      state = const AggregatedSearchState();
      return;
    }
    _implementations = _musicServices();
    state = AggregatedSearchState(query: trimmed, isLoading: true);

    final results = await Future.wait(
      _implementations.map((impl) => _searchPage(impl, trimmed, 1)),
    );
    if (!mounted) return;

    final songs = <PlatformType, List<Song>>{};
    final errors = <PlatformType, String>{};
    final pages = <PlatformType, int>{};
    final hasMore = <PlatformType, bool>{};
    var networkFailed = false;

    for (final result in results) {
      if (result.error != null) {
        errors[result.platform] = result.error!;
        if (result.networkError) networkFailed = true;
        continue;
      }
      songs[result.platform] = result.songs;
      pages[result.platform] = 1;
      hasMore[result.platform] = result.songs.length >= _pageSize;
    }

    final merged = mergeSearchSongs(_inPlatformOrder(songs));
    state = state.copyWith(
      songs: merged,
      errorsByPlatform: errors,
      pageByPlatform: pages,
      hasMoreByPlatform: hasMore,
      isLoading: false,
      networkFailed: networkFailed,
      error: () => merged.isEmpty && errors.isNotEmpty
          ? (networkFailed ? '网络连接失败，请检查网络后重试' : '搜索失败')
          : null,
    );
  }

  /// Appends the next page of every platform that still has more.
  Future<void> loadMore() async {
    final query = state.query;
    if (query.isEmpty || state.isLoading || state.isLoadingMore) return;
    final nextPages = <PlatformType, int>{};
    final nextImplementations = <MusicPlatform>[];
    for (final impl in _implementations) {
      if (state.hasMoreByPlatform[impl.platformType] != true) continue;
      nextImplementations.add(impl);
      nextPages[impl.platformType] =
          (state.pageByPlatform[impl.platformType] ?? 1) + 1;
    }
    if (nextPages.isEmpty) return;

    state = state.copyWith(isLoadingMore: true);

    final results = await Future.wait([
      for (final impl in nextImplementations)
        _searchPage(impl, query, nextPages[impl.platformType]!),
    ]);
    if (!mounted) return;

    final perPlatform = <PlatformType, List<Song>>{};
    final errors = Map<PlatformType, String>.from(state.errorsByPlatform);
    final pages = Map<PlatformType, int>.from(state.pageByPlatform);
    final hasMore = Map<PlatformType, bool>.from(state.hasMoreByPlatform);
    var networkFailed = state.networkFailed;

    for (final result in results) {
      if (result.error != null) {
        errors[result.platform] = result.error!;
        if (result.networkError) networkFailed = true;
        hasMore[result.platform] = false;
        continue;
      }
      perPlatform[result.platform] = result.songs;
      pages[result.platform] = nextPages[result.platform] ?? 1;
      hasMore[result.platform] = result.songs.length >= _pageSize;
    }

    // Existing page-1 songs stay first; each platform's new page is appended in
    // platform order, then the whole set is re-merged (dedupe keys already seen
    // keep their original position).
    final combined = <Song>[];
    for (final merged in state.songs) {
      combined.addAll(merged.sources);
    }
    for (final platform in _platforms) {
      combined.addAll(perPlatform[platform] ?? const []);
    }
    final remerged = mergeSearchSongs(combined);

    state = state.copyWith(
      songs: remerged,
      errorsByPlatform: errors,
      pageByPlatform: pages,
      hasMoreByPlatform: hasMore,
      isLoadingMore: false,
      networkFailed: networkFailed,
    );
  }

  /// Picks which platform's copy of a song should play.
  void chooseSource(Song song) {
    final chosen = Map<String, Song>.from(state.chosenSourceByKey);
    chosen[song.dedupeKey] = song;
    state = state.copyWith(chosenSourceByKey: chosen);
  }

  void clear() {
    state = const AggregatedSearchState();
  }

  List<MusicPlatform> _musicServices() {
    final platforms = <MusicPlatform>[];
    for (final type in _supportedTypes()) {
      if (!type.isMusicService) continue;
      try {
        platforms.add(_platformResolver(type));
      } catch (_) {
        continue;
      }
    }
    return platforms;
  }

  /// Keeps per-platform results in a stable platform order before merging, so
  /// the primary source of a song does not depend on which HTTP call finished
  /// first.
  List<Song> _inPlatformOrder(Map<PlatformType, List<Song>> byPlatform) {
    final songs = <Song>[];
    for (final platform in _platforms) {
      songs.addAll(byPlatform[platform] ?? const []);
    }
    return songs;
  }

  Future<_PlatformSearchPage> _searchPage(
    MusicPlatform impl,
    String query,
    int page,
  ) async {
    final platform = impl.platformType;
    try {
      final songs = await impl
          .search(query, page: page, limit: _pageSize)
          .timeout(operationTimeout);
      return _PlatformSearchPage(platform: platform, songs: songs);
    } on TimeoutException {
      return _PlatformSearchPage(
        platform: platform,
        error: '请求超时',
        networkError: true,
      );
    } catch (e) {
      final typed = apiExceptionOf(e);
      return _PlatformSearchPage(
        platform: platform,
        error: typed.message,
        networkError: typed is NetworkException,
      );
    }
  }
}

class _PlatformSearchPage {
  final PlatformType platform;
  final List<Song> songs;
  final String? error;
  final bool networkError;

  const _PlatformSearchPage({
    required this.platform,
    this.songs = const [],
    this.error,
    this.networkError = false,
  });
}

/// Whether the aggregate ("全部平台") mode is active.
final searchAcrossPlatformsProvider = StateProvider<bool>((ref) => false);

final aggregatedSearchProvider =
    StateNotifierProvider<AggregatedSearchNotifier, AggregatedSearchState>((
      ref,
    ) {
      return AggregatedSearchNotifier();
    });

final searchHistoryStoreProvider = Provider<SearchHistoryStore>(
  (ref) => SearchHistoryStore(),
);

/// Recent queries, newest first.
class SearchHistoryNotifier extends StateNotifier<List<String>> {
  SearchHistoryNotifier(this._store) : super(const []) {
    _restore();
  }

  final SearchHistoryStore _store;

  Future<void> _restore() async {
    final entries = await _store.load();
    if (!mounted) return;
    state = entries;
  }

  Future<void> record(String query) async {
    final next = await _store.add(query);
    if (!mounted) return;
    state = next;
  }

  Future<void> remove(String query) async {
    final next = await _store.remove(query);
    if (!mounted) return;
    state = next;
  }

  Future<void> clear() async {
    await _store.clear();
    if (!mounted) return;
    state = const [];
  }
}

final searchHistoryProvider =
    StateNotifierProvider<SearchHistoryNotifier, List<String>>(
      (ref) => SearchHistoryNotifier(ref.watch(searchHistoryStoreProvider)),
    );

/// Query suggestions: history entries first, then song names from the current
/// aggregated results. Pure so it can be tested without a widget.
List<String> searchSuggestions({
  required String query,
  required List<String> history,
  List<String> songNames = const [],
  int limit = 8,
}) {
  final trimmed = query.trim().toLowerCase();
  if (trimmed.isEmpty) return const [];
  final seen = <String>{};
  final suggestions = <String>[];
  for (final candidate in [...history, ...songNames]) {
    final value = candidate.trim();
    if (value.isEmpty) continue;
    if (value.toLowerCase() == trimmed) continue;
    if (!value.toLowerCase().contains(trimmed)) continue;
    if (!seen.add(value)) continue;
    suggestions.add(value);
    if (suggestions.length >= limit) break;
  }
  return suggestions;
}
