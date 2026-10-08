import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/network/api_error_l10n.dart';
import '../../../../core/network/platform_http.dart';
import '../../../../core/share/song_actions.dart';
import '../../../../core/theme/platform_accent.dart';
import '../../../../core/utils/snackbar_helper.dart';
import '../../../../core/widgets/app_scrollbar.dart';
import '../../../../core/widgets/async_state_view.dart';
import '../../../../models/playlist.dart';
import '../../../../models/song.dart';
import '../../../../models/platform_type.dart';
import '../../../../platform/base/platform_registry.dart';
import '../../../download/presentation/widgets/download_button.dart';
import '../../../player/presentation/providers/player_provider.dart';
import '../providers/aggregated_search_provider.dart';
import '../widgets/search_skeleton.dart';

final selectedPlatformProvider = StateProvider<PlatformType>(
  (ref) => PlatformType.netease,
);

final searchQueryProvider = StateProvider<String>((ref) => '');

enum SearchMode { songs, playlists }

final searchModeProvider = StateProvider<SearchMode>((ref) => SearchMode.songs);

/// Single-platform song results (page 1).
///
/// Kept as the authoritative first page of the single-platform mode; pages ≥ 2
/// are appended by the screen through [SearchScreenState._loadMoreSingle], which
/// passes the real `page` to the platform instead of always asking for page 1.
final searchResultsProvider = FutureProvider.autoDispose<List<Song>>((
  ref,
) async {
  final query = ref.watch(searchQueryProvider);
  if (query.isEmpty) return [];
  if (ref.watch(searchModeProvider) != SearchMode.songs) return [];
  final platformType = ref.watch(selectedPlatformProvider);
  final platform = PlatformRegistry.get(platformType);
  return platform.search(query);
});

final playlistSearchResultsProvider =
    FutureProvider.autoDispose<List<Playlist>>((ref) async {
      final query = ref.watch(searchQueryProvider);
      if (query.isEmpty) return [];
      if (ref.watch(searchModeProvider) != SearchMode.playlists) return [];
      final platformType = ref.watch(selectedPlatformProvider);
      final platform = PlatformRegistry.get(platformType);
      return platform.searchPlaylists(query);
    });

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _hasText = ValueNotifier<bool>(false);
  Timer? _debounce;

  /// Pages 2+ of the single-platform mode, accumulated locally so page 1 keeps
  /// coming from [searchResultsProvider] (which other code and tests override).
  final List<Song> _extraSongs = [];
  int _page = 1;
  bool _exhausted = false;
  bool _loadingMore = false;

  static const int _pageSize = 30;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    _hasText.dispose();
    super.dispose();
  }

  void _scheduleSearch() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      ref.read(searchQueryProvider.notifier).state = _controller.text.trim();
    });
  }

  void _submitSearch({String? value}) {
    _debounce?.cancel();
    final query = (value ?? _controller.text).trim();
    if (value != null) _controller.text = value;
    _hasText.value = query.isNotEmpty;
    ref.read(searchQueryProvider.notifier).state = query;
    _focusNode.unfocus();
  }

  void _clearSearch() {
    _debounce?.cancel();
    _controller.clear();
    _hasText.value = false;
    ref.read(searchQueryProvider.notifier).state = '';
  }

  void _resetPaging() {
    _extraSongs.clear();
    _page = 1;
    _exhausted = false;
  }

  /// Loads the next page for whichever mode is active.
  Future<void> _loadMore() async {
    final query = ref.read(searchQueryProvider).trim();
    if (query.isEmpty) return;
    if (ref.read(searchModeProvider) != SearchMode.songs) return;

    if (ref.read(searchAcrossPlatformsProvider)) {
      await ref.read(aggregatedSearchProvider.notifier).loadMore();
      return;
    }
    if (_loadingMore || _exhausted) return;
    _loadingMore = true;
    try {
      final platform = PlatformRegistry.get(ref.read(selectedPlatformProvider));
      final next = await platform
          .search(query, page: _page + 1, limit: _pageSize)
          .timeout(const Duration(seconds: 12));
      if (!mounted) return;
      setState(() {
        if (next.isEmpty) {
          _exhausted = true;
        } else {
          _page += 1;
          for (final song in next) {
            final already = _extraSongs.any(
              (existing) =>
                  existing.id == song.id && existing.platform == song.platform,
            );
            if (!already) _extraSongs.add(song);
          }
          if (next.length < _pageSize) _exhausted = true;
        }
      });
    } catch (_) {
      // A failed extra page must not break the results already on screen.
      if (mounted) setState(() => _exhausted = true);
    } finally {
      _loadingMore = false;
    }
  }

  bool _onScroll(ScrollNotification notification) {
    final metrics = notification.metrics;
    if (metrics.maxScrollExtent - metrics.pixels < 400) {
      unawaited(_loadMore());
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final selectedPlatform = ref.watch(selectedPlatformProvider);
    final aggregate = ref.watch(searchAcrossPlatformsProvider);
    final mode = ref.watch(searchModeProvider);
    final query = ref.watch(searchQueryProvider);
    final results = ref.watch(searchResultsProvider);
    final playlistResults = ref.watch(playlistSearchResultsProvider);
    final aggregated = ref.watch(aggregatedSearchProvider);
    final history = ref.watch(searchHistoryProvider);

    // A new query (or platform/mode switch) restarts paging and, in aggregate
    // mode, the cross-platform search; history is recorded once per query.
    ref.listen<String>(searchQueryProvider, (previous, next) {
      _resetPaging();
      if (next.trim().isEmpty) {
        ref.read(aggregatedSearchProvider.notifier).clear();
        return;
      }
      ref.read(searchHistoryProvider.notifier).record(next.trim());
      if (ref.read(searchAcrossPlatformsProvider)) {
        ref.read(aggregatedSearchProvider.notifier).search(next);
      }
    });
    ref.listen<bool>(searchAcrossPlatformsProvider, (previous, next) {
      _resetPaging();
      final current = ref.read(searchQueryProvider).trim();
      if (next && current.isNotEmpty) {
        ref.read(aggregatedSearchProvider.notifier).search(current);
      }
    });
    ref.listen<PlatformType>(selectedPlatformProvider, (previous, next) {
      _resetPaging();
    });

    final suggestions = searchSuggestions(
      query: query,
      history: history,
      songNames: aggregate
          ? aggregated.songs.map((merged) => merged.primary.name).toList()
          : const [],
    );

    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                SizedBox(
                  height: 40,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: PlatformType.musicServices.length + 1,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return ChoiceChip(
                          label: const Text('全部平台'),
                          selected: aggregate,
                          onSelected: (_) => ref
                              .read(searchAcrossPlatformsProvider.notifier)
                              .state = true,
                        );
                      }
                      final type = PlatformType.musicServices[index - 1];
                      final isSelected = !aggregate && type == selectedPlatform;
                      return ChoiceChip(
                        label: Text(type.displayName),
                        selected: isSelected,
                        onSelected: (_) {
                          ref
                              .read(searchAcrossPlatformsProvider.notifier)
                              .state = false;
                          ref.read(selectedPlatformProvider.notifier).state =
                              type;
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<SearchMode>(
                    segments: const [
                      ButtonSegment(
                        value: SearchMode.songs,
                        icon: Icon(Icons.music_note),
                        label: Text('歌曲'),
                      ),
                      ButtonSegment(
                        value: SearchMode.playlists,
                        icon: Icon(Icons.queue_music),
                        label: Text('歌单'),
                      ),
                    ],
                    selected: {mode},
                    onSelectionChanged: (values) {
                      ref.read(searchModeProvider.notifier).state =
                          values.first;
                    },
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  decoration: InputDecoration(
                    hintText: mode == SearchMode.songs
                        ? '搜索歌曲、歌手、专辑'
                        : '搜索歌单',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: ValueListenableBuilder<bool>(
                      valueListenable: _hasText,
                      builder: (_, hasText, _) => hasText
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: _clearSearch,
                            )
                          : const SizedBox.shrink(),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _submitSearch(),
                  onChanged: (v) {
                    _hasText.value = v.isNotEmpty;
                    _scheduleSearch();
                  },
                ),
                if (mode == SearchMode.songs && suggestions.isNotEmpty)
                  SizedBox(
                    height: 36,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.only(top: 8),
                      itemCount: suggestions.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (context, index) => ActionChip(
                        label: Text(
                          suggestions[index],
                          style: const TextStyle(fontSize: 12),
                        ),
                        onPressed: () =>
                            _submitSearch(value: suggestions[index]),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: mode == SearchMode.songs
                ? (aggregate
                      ? _buildAggregated(aggregated)
                      : _buildSinglePlatform(results, query))
                : _buildPlaylists(playlistResults, query),
          ),
        ],
      ),
    );
  }

  Widget _buildSinglePlatform(AsyncValue<List<Song>> results, String query) {
    if (query.trim().isEmpty) {
      return _buildIdleState();
    }
    return results.when(
      data: (songs) {
        final all = [
          ...songs,
          ..._extraSongs.where(
            (extra) => !songs.any(
              (song) => song.id == extra.id && song.platform == extra.platform,
            ),
          ),
        ];
        if (all.isEmpty) {
          return const _SearchEmptyState();
        }
        return RefreshIndicator(
          onRefresh: () async {
            _resetPaging();
            ref.invalidate(searchResultsProvider);
          },
          child: NotificationListener<ScrollNotification>(
            onNotification: _onScroll,
            child: AppScrollbar(
              builder: (controller) => ListView.builder(
                controller: controller,
                itemCount: all.length + (_loadingMore ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index >= all.length) {
                    return const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    );
                  }
                  return _SongTile(songs: all, index: index);
                },
              ),
            ),
          ),
        );
      },
      loading: () => const SearchResultsSkeleton(),
      error: (e, _) => _ErrorState(error: e, onRetry: () {
        ref.invalidate(searchResultsProvider);
      }),
    );
  }

  Widget _buildAggregated(AggregatedSearchState state) {
    if (state.query.trim().isEmpty) {
      return _buildIdleState();
    }
    if (state.isLoading) {
      return const SearchResultsSkeleton();
    }
    if (state.songs.isEmpty) {
      if (state.error != null) {
        return _ErrorState(
          error: _MessageException(state.error!),
          onRetry: () => ref
              .read(aggregatedSearchProvider.notifier)
              .search(state.query),
        );
      }
      return const _SearchEmptyState();
    }

    final songs = state.playableSongs;
    return RefreshIndicator(
      onRefresh: () =>
          ref.read(aggregatedSearchProvider.notifier).search(state.query),
      child: NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        child: AppScrollbar(
          builder: (controller) => ListView.builder(
            controller: controller,
            itemCount:
                state.songs.length +
                (state.errorCount > 0 ? 1 : 0) +
                (state.isLoadingMore ? 1 : 0),
            itemBuilder: (context, index) {
              if (state.errorCount > 0 && index == 0) {
                return _PlatformErrorStrip(errors: state.errorsByPlatform);
              }
              final offset = state.errorCount > 0 ? 1 : 0;
              final songIndex = index - offset;
              if (songIndex >= state.songs.length) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                );
              }
              final merged = state.songs[songIndex];
              return _MergedSongTile(
                merged: merged,
                song: state.sourceFor(merged),
                playlist: songs,
                index: songIndex,
                onChooseSource: merged.sourceCount > 1
                    ? () => _pickSource(merged)
                    : null,
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildPlaylists(AsyncValue<List<Playlist>> results, String query) {
    if (query.trim().isEmpty) {
      return _buildIdleState();
    }
    return results.when(
      data: (playlists) {
        if (playlists.isEmpty) return const _SearchEmptyState();
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(playlistSearchResultsProvider),
          child: AppScrollbar(
            builder: (controller) => ListView.builder(
              controller: controller,
              itemCount: playlists.length,
              itemBuilder: (context, index) =>
                  _PlaylistTile(playlist: playlists[index]),
            ),
          ),
        );
      },
      loading: () => const SearchResultsSkeleton(),
      error: (e, _) => _ErrorState(error: e, onRetry: () {
        ref.invalidate(playlistSearchResultsProvider);
      }),
    );
  }

  /// What the page shows before anything is typed: recent queries (tap to
  /// search, long-press to forget), or the shared empty state when there is no
  /// history to show yet.
  Widget _buildIdleState() {
    final history = ref.watch(searchHistoryProvider);
    if (history.isEmpty) {
      // Was a bare `Center(Text('请输入关键词'))` coloured with `outline`, which
      // is a border role. `AsyncStateView` supplies the contrast-correct copy
      // (rule 2) plus an icon, like every other empty state in the app.
      return const AsyncStateView.empty(
        title: '请输入关键词',
        icon: Icons.search,
      );
    }
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        Row(
          children: [
            const Text(
              '搜索历史',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            TextButton(
              onPressed: () => ref.read(searchHistoryProvider.notifier).clear(),
              child: const Text('清空'),
            ),
          ],
        ),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final entry in history)
              InputChip(
                label: Text(entry),
                onPressed: () => _submitSearch(value: entry),
                onDeleted: () =>
                    ref.read(searchHistoryProvider.notifier).remove(entry),
              ),
          ],
        ),
      ],
    );
  }

  Future<void> _pickSource(MergedSong merged) async {
    final state = ref.read(aggregatedSearchProvider);
    final current = state.sourceFor(merged);
    final chosen = await showModalBottomSheet<Song>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              dense: true,
              title: Text('选择播放来源'),
            ),
            for (final source in merged.sources)
              ListTile(
                leading: Icon(PlatformAccent.iconOf(source.platform)),
                title: Text(source.platform.displayName),
                subtitle: Text(
                  source.album?.name ?? source.artistNames,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing:
                    source.id == current.id &&
                        source.platform == current.platform
                    ? const Icon(Icons.check)
                    : null,
                onTap: () => Navigator.of(sheetContext).pop(source),
              ),
          ],
        ),
      ),
    );
    if (chosen != null) {
      ref.read(aggregatedSearchProvider.notifier).chooseSource(chosen);
    }
  }
}

/// A plain [Exception] wrapper so [_ErrorState] can render a message that did
/// not come from a thrown object.
class _MessageException implements Exception {
  _MessageException(this.message);

  final String message;

  @override
  String toString() => message;
}

class _PlatformErrorStrip extends StatelessWidget {
  const _PlatformErrorStrip({required this.errors});

  final Map<PlatformType, String> errors;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      key: const Key('aggregated-search-errors'),
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cs.errorContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.wifi_off, size: 16, color: cs.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              errors.entries
                  .map((entry) => '${entry.key.displayName}：${entry.value}')
                  .join('\n'),
              style: TextStyle(fontSize: 12, color: cs.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchEmptyState extends StatelessWidget {
  /// Only ever rendered for a *completed* search that matched nothing: the
  /// "nothing typed yet" prompt lives in `_buildIdleState`, which owns the
  /// search-history list too.
  const _SearchEmptyState();

  @override
  Widget build(BuildContext context) {
    // "Nothing matched" is not a failure, so this is an empty state with no
    // retry — and the copy is unchanged from the hand-rolled version.
    return const AsyncStateView.empty(
      title: '未找到相关内容',
      icon: Icons.search_off,
    );
  }
}

/// A failed search, rendered through the shared error state.
///
/// The message is normalised with [apiExceptionOf] so the user sees the app's
/// translated text rather than a raw `Exception.toString()`.
class _ErrorState extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;

  const _ErrorState({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final typed = apiExceptionOf(error);
    // Note: the old inline version swapped in `Icons.wifi_off` for network
    // failures. The shared contract pins the error icon to `Icons.error_outline`
    // for every page, so the network case is carried by the message
    // ("网络连接失败，请检查网络后重试") instead of by a second icon.
    return AsyncStateView.error(
      title: apiErrorText(context, typed),
      message: typed.details,
      onRetry: onRetry,
    );
  }
}

class _MergedSongTile extends ConsumerWidget {
  const _MergedSongTile({
    required this.merged,
    required this.song,
    required this.playlist,
    required this.index,
    required this.onChooseSource,
  });

  final MergedSong merged;
  final Song song;
  final List<Song> playlist;
  final int index;
  final VoidCallback? onChooseSource;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      leading: _Cover(url: song.coverUrl, icon: Icons.music_note),
      title: Text(song.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: PlatformAccent.neutralColorOf(
                song.platform,
              ).withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              song.platform.displayName,
              style: TextStyle(
                fontSize: 10,
                color: PlatformAccent.neutralColorOf(song.platform),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              song.artistNames,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: cs.outline),
            ),
          ),
          if (onChooseSource != null)
            TextButton(
              key: ValueKey('source-picker-${merged.dedupeKey}'),
              onPressed: onChooseSource,
              child: Text(
                '${merged.sourceCount} 个来源',
                style: const TextStyle(fontSize: 11),
              ),
            ),
        ],
      ),
      trailing: DownloadButton(song: song, size: 22),
      onTap: () => ref
          .read(playerProvider.notifier)
          .playPlaylist(playlist, startIndex: index),
      onLongPress: () => showSongActionsMenu(context, ref, song: song),
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.url, required this.icon});

  final String? url;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: url != null && url!.isNotEmpty
          ? CachedNetworkImage(
              imageUrl: url!,
              width: 48,
              height: 48,
              memCacheWidth: 96,
              fit: BoxFit.cover,
              placeholder: (_, _) => _ArtPlaceholder(icon: icon),
              errorWidget: (_, _, _) => _ArtPlaceholder(icon: icon),
            )
          : _ArtPlaceholder(icon: icon),
    );
  }
}

class _SongTile extends ConsumerWidget {
  final List<Song> songs;
  final int index;
  final Song song;

  _SongTile({required this.songs, required this.index}) : song = songs[index];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      leading: _Cover(url: song.coverUrl, icon: Icons.music_note),
      title: Text(song.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        song.album?.name != null
            ? '${song.artistNames} - ${song.album!.name}'
            : song.artistNames,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: Theme.of(context).colorScheme.outline,
          fontSize: 13,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              song.platform.displayName.substring(0, 2),
              style: TextStyle(
                fontSize: 10,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
          const SizedBox(width: 4),
          DownloadButton(song: song, size: 22),
          const SizedBox(width: 2),
          IconButton(
            icon: const Icon(Icons.play_circle_outline),
            onPressed: () {
              ref
                  .read(playerProvider.notifier)
                  .playPlaylist(songs, startIndex: index);
            },
          ),
        ],
      ),
      onTap: () {
        ref
            .read(playerProvider.notifier)
            .playPlaylist(songs, startIndex: index);
      },
      onLongPress: () => showSongActionsMenu(context, ref, song: song),
    );
  }
}

class _PlaylistTile extends StatelessWidget {
  final Playlist playlist;
  const _PlaylistTile({required this.playlist});

  String _route() {
    final query = Uri(
      queryParameters: {
        'name': playlist.name,
        if (playlist.coverUrl != null && playlist.coverUrl!.isNotEmpty)
          'cover': playlist.coverUrl!,
      },
    ).query;
    return '/playlist/${playlist.platform.name}/${Uri.encodeComponent(playlist.id)}'
        '${query.isEmpty ? '' : '?$query'}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      leading: _Cover(url: playlist.coverUrl, icon: Icons.queue_music),
      title: Text(playlist.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${playlist.songCount} 首${playlist.creatorName == null ? '' : ' - ${playlist.creatorName}'}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: cs.outline, fontSize: 13),
      ),
      trailing: IconButton(
        icon: Icon(playlist.collected ? Icons.bookmark : Icons.bookmark_border),
        onPressed: () async {
          final ok = await PlatformRegistry.get(playlist.platform)
              .collectPlaylist(playlist.id)
              .timeout(const Duration(seconds: 12), onTimeout: () => false);
          if (!context.mounted) return;
          // Was a bare `SnackBar`, which painted success and failure with the
          // same colour and was not `floating` (so the bottom capsules covered
          // it). The helper gives the failure the theme's error colour and both
          // the floating behaviour every other toast in the app has.
          if (ok) {
            showSuccessSnackBar(context, '已收藏歌单');
          } else {
            showErrorSnackBar(context, '收藏失败');
          }
        },
      ),
      onTap: () => context.push(_route()),
    );
  }
}

class _ArtPlaceholder extends StatelessWidget {
  final IconData icon;
  const _ArtPlaceholder({required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Icon(icon, size: 20),
    );
  }
}
