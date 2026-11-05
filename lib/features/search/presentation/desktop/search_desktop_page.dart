import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/desktop/desktop_empty_state.dart';
import '../../../../core/desktop/desktop_page_scaffold.dart';
import '../../../../core/desktop/desktop_song_table.dart';
import '../../../../core/desktop/desktop_tokens.dart';
import '../../../../core/network/platform_http.dart';
import '../../../../core/theme/platform_accent.dart';
import '../../../../core/widgets/app_scrollbar.dart';
import '../../../../models/platform_type.dart';
import '../../../../models/playlist.dart';
import '../../../download/presentation/widgets/download_button.dart';
import '../../../player/presentation/providers/player_provider.dart';
import '../providers/aggregated_search_provider.dart';
import '../screens/search_screen.dart'
    show
        SearchMode,
        playlistSearchResultsProvider,
        searchModeProvider,
        searchQueryProvider,
        searchResultsProvider,
        selectedPlatformProvider;

/// Desktop search.
///
/// Same providers as the phone screen (search_screen.dart), so the two entry
/// points cannot disagree about which query is active — only the layout differs.
class SearchDesktopPage extends ConsumerStatefulWidget {
  const SearchDesktopPage({super.key});

  @override
  ConsumerState<SearchDesktopPage> createState() => _SearchDesktopPageState();
}

class _SearchDesktopPageState extends ConsumerState<SearchDesktopPage> {
  static const Duration _debounceDelay = Duration(milliseconds: 280);

  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  Timer? _debounce;

  /// Sorting is local to the single-platform mode: the aggregate result order is
  /// the platforms' relevance order (and is what the source picker indexes into),
  /// so it is deliberately not re-sortable.
  String _sortKey = DesktopSongColumn.title;
  bool _sortAscending = true;

  @override
  void initState() {
    super.initState();
    // Do not steal focus from the sidebar on entry: a focused TextField can
    // swallow the first outside tap, and desktop users expect the sidebar to be
    // clickable immediately. The field still gets focus when clicked.
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _scheduleSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(_debounceDelay, () {
      if (!mounted) return;
      ref.read(searchQueryProvider.notifier).state = value.trim();
    });
  }

  void _submit({String? value}) {
    _debounce?.cancel();
    final query = (value ?? _controller.text).trim();
    if (value != null) {
      _controller.value = TextEditingValue(
        text: value,
        selection: TextSelection.collapsed(offset: value.length),
      );
    }
    ref.read(searchQueryProvider.notifier).state = query;
    _focusNode.unfocus();
  }

  void _clear() {
    _debounce?.cancel();
    _controller.clear();
    ref.read(searchQueryProvider.notifier).state = '';
    _focusNode.requestFocus();
  }

  void _reload() {
    final query = ref.read(searchQueryProvider).trim();
    if (query.isEmpty) return;
    if (ref.read(searchAcrossPlatformsProvider)) {
      unawaited(ref.read(aggregatedSearchProvider.notifier).search(query));
      return;
    }
    ref.invalidate(searchResultsProvider);
    ref.invalidate(playlistSearchResultsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(searchModeProvider);
    final aggregate = ref.watch(searchAcrossPlatformsProvider);
    final query = ref.watch(searchQueryProvider).trim();
    final selectedPlatform = ref.watch(selectedPlatformProvider);
    final aggregated = ref.watch(aggregatedSearchProvider);

    // History is recorded once per query, exactly like the phone screen, and
    // aggregate mode re-runs its own search because that notifier is not fed by
    // a FutureProvider watching searchQueryProvider.
    ref.listen<String>(searchQueryProvider, (previous, next) {
      final trimmed = next.trim();
      if (trimmed.isEmpty) {
        ref.read(aggregatedSearchProvider.notifier).clear();
        return;
      }
      unawaited(ref.read(searchHistoryProvider.notifier).record(trimmed));
      if (ref.read(searchAcrossPlatformsProvider)) {
        unawaited(ref.read(aggregatedSearchProvider.notifier).search(trimmed));
      }
    });
    ref.listen<bool>(searchAcrossPlatformsProvider, (previous, next) {
      if (!next) return;
      final current = ref.read(searchQueryProvider).trim();
      if (current.isEmpty) return;
      unawaited(ref.read(aggregatedSearchProvider.notifier).search(current));
    });

    return DesktopPageScaffold(
      title: '搜索',
      subtitle: aggregate
          ? '全部平台聚合搜索，同一首歌只出现一次'
          : '在 ${selectedPlatform.displayName} 中搜索',
      actions: [
        if (query.isNotEmpty)
          TextButton.icon(
            onPressed: _reload,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('重新搜索'),
          ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildToolbar(
            mode: mode,
            aggregate: aggregate,
            selectedPlatform: selectedPlatform,
          ),
          const SizedBox(height: DesktopSpacing.md),
          Expanded(
            child: mode == SearchMode.songs
                ? (aggregate
                      ? _buildAggregated(aggregated)
                      : _buildSinglePlatform())
                : _buildPlaylists(),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar({
    required SearchMode mode,
    required bool aggregate,
    required PlatformType selectedPlatform,
  }) {
    final searchField = ValueListenableBuilder<TextEditingValue>(
      valueListenable: _controller,
      builder: (context, value, _) => TextField(
        controller: _controller,
        focusNode: _focusNode,
        autofocus: false,
        textInputAction: TextInputAction.search,
        onChanged: _scheduleSearch,
        onSubmitted: (_) => _submit(),
        style: DesktopText.body,
        decoration: InputDecoration(
          hintText: mode == SearchMode.songs ? '搜索歌曲、歌手、专辑…' : '搜索歌单…',
          prefixIcon: const Icon(Icons.search, size: 18),
          suffixIcon: value.text.isEmpty
              ? null
              : IconButton(
                  tooltip: '清空',
                  onPressed: _clear,
                  icon: const Icon(Icons.close, size: 16),
                ),
        ),
      ),
    );

    final modeTabs = DesktopTabStrip<SearchMode>(
      tabs: const [
        DesktopTabItem(
          value: SearchMode.songs,
          label: '歌曲',
          icon: Icons.music_note,
        ),
        DesktopTabItem(
          value: SearchMode.playlists,
          label: '歌单',
          icon: Icons.queue_music,
        ),
      ],
      selected: mode,
      onSelected: (value) {
        ref.read(searchModeProvider.notifier).state = value;
        // Playlist search is per-platform on every service; claiming "全部平台"
        // there would show one platform's results under an aggregate label.
        if (value == SearchMode.playlists) {
          ref.read(searchAcrossPlatformsProvider.notifier).state = false;
        }
      },
    );

    final platformChips = DesktopTabStrip<PlatformType?>(
      tabs: [
        const DesktopTabItem<PlatformType?>(value: null, label: '全部平台'),
        for (final platform in PlatformType.musicServices)
          DesktopTabItem<PlatformType?>(
            value: platform,
            label: platform.displayName,
            icon: PlatformAccent.iconOf(platform),
          ),
      ],
      selected: aggregate ? null : selectedPlatform,
      onSelected: (value) {
        if (value == null) {
          ref.read(searchAcrossPlatformsProvider.notifier).state = true;
          return;
        }
        ref.read(searchAcrossPlatformsProvider.notifier).state = false;
        ref.read(selectedPlatformProvider.notifier).state = value;
      },
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth >= 720) {
              return Row(
                children: [
                  Expanded(child: searchField),
                  const SizedBox(width: DesktopSpacing.xl),
                  modeTabs,
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                searchField,
                const SizedBox(height: DesktopSpacing.sm),
                modeTabs,
              ],
            );
          },
        ),
        const SizedBox(height: DesktopSpacing.sm),
        platformChips,
      ],
    );
  }

  Widget _buildSinglePlatform() {
    if (ref.watch(searchQueryProvider).trim().isEmpty) return _buildIdle();
    final results = ref.watch(searchResultsProvider);
    final currentSong = ref.watch(playerProvider.select((s) => s.currentSong));

    return results.when(
      loading: () => const DesktopInlineLoading(label: '正在搜索…'),
      error: (error, stackTrace) => DesktopInlineError(
        message: apiExceptionOf(error).message,
        onRetry: () => ref.invalidate(searchResultsProvider),
      ),
      data: (songs) {
        final sorted = sortDesktopSongs(
          songs,
          key: _sortKey,
          ascending: _sortAscending,
        );
        return DesktopSongTable(
          songs: sorted,
          currentSong: currentSong,
          sortKey: _sortKey,
          sortAscending: _sortAscending,
          onSort: _toggleSort,
          actionsLabel: '操作',
          onPlay: (index) => unawaited(
            ref
                .read(playerProvider.notifier)
                .playPlaylist(sorted, startIndex: index),
          ),
          trailingBuilder: (song, index) => [
            DownloadButton(song: song, size: 18),
          ],
          emptyState: const DesktopEmptyState(
            icon: Icons.search_off,
            title: '未找到相关内容',
            message: '换个关键词，或者切到「全部平台」再搜一次',
          ),
        );
      },
    );
  }

  Widget _buildAggregated(AggregatedSearchState state) {
    if (ref.watch(searchQueryProvider).trim().isEmpty) return _buildIdle();
    final currentSong = ref.watch(playerProvider.select((s) => s.currentSong));

    if (state.isLoading) {
      return const DesktopInlineLoading(label: '正在跨平台搜索…');
    }
    if (state.songs.isEmpty) {
      final error = state.error;
      if (error != null) {
        return DesktopInlineError(
          message: error,
          onRetry: () => unawaited(
            ref.read(aggregatedSearchProvider.notifier).search(state.query),
          ),
        );
      }
      return const DesktopEmptyState(
        icon: Icons.search_off,
        title: '未找到相关内容',
        message: '换个关键词，或者换一个平台再搜一次',
      );
    }

    final songs = state.playableSongs;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.errorCount > 0)
          _PlatformErrorStrip(
            errors: state.errorsByPlatform,
            networkFailed: state.networkFailed,
          ),
        Expanded(
          child: DesktopSongTable(
            songs: songs,
            currentSong: currentSong,
            actionsLabel: '操作',
            onPlay: (index) => unawaited(
              ref
                  .read(playerProvider.notifier)
                  .playPlaylist(songs, startIndex: index),
            ),
            trailingBuilder: (song, index) {
              final merged = state.songs[index];
              return [
                if (merged.sourceCount > 1) _sourcePicker(state, index),
                DownloadButton(song: song, size: 18),
              ];
            },
            footer: state.hasMore ? _buildLoadMore(state) : null,
            emptyState: const DesktopEmptyState(
              icon: Icons.search_off,
              title: '未找到相关内容',
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLoadMore(AggregatedSearchState state) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: DesktopSpacing.lg),
      child: Center(
        child: state.isLoadingMore
            ? const DesktopInlineLoading(label: '加载更多…')
            : OutlinedButton.icon(
                onPressed: () => unawaited(
                  ref.read(aggregatedSearchProvider.notifier).loadMore(),
                ),
                icon: const Icon(Icons.expand_more, size: 16),
                label: const Text('加载更多'),
              ),
      ),
    );
  }

  /// Picks which platform's copy of a merged song should play.
  Widget _sourcePicker(AggregatedSearchState state, int index) {
    final merged = state.songs[index];
    final chosen = state.sourceFor(merged);
    return PopupMenuButton<int>(
      tooltip: '${merged.sourceCount} 个来源，选择播放来源',
      icon: const Icon(Icons.swap_horiz, size: 16),
      padding: const EdgeInsets.all(4),
      onSelected: (sourceIndex) => ref
          .read(aggregatedSearchProvider.notifier)
          .chooseSource(merged.sources[sourceIndex]),
      itemBuilder: (context) => [
        for (var i = 0; i < merged.sources.length; i++)
          PopupMenuItem<int>(
            value: i,
            height: 36,
            child: Row(
              children: [
                Icon(
                  PlatformAccent.iconOf(merged.sources[i].platform),
                  size: 14,
                ),
                const SizedBox(width: DesktopSpacing.sm),
                Expanded(
                  child: Text(
                    merged.sources[i].platform.displayName,
                    style: DesktopText.body,
                  ),
                ),
                if (merged.sources[i].id == chosen.id &&
                    merged.sources[i].platform == chosen.platform)
                  const Icon(Icons.check, size: 14),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildPlaylists() {
    if (ref.watch(searchQueryProvider).trim().isEmpty) return _buildIdle();
    final results = ref.watch(playlistSearchResultsProvider);

    return results.when(
      loading: () => const DesktopInlineLoading(label: '正在搜索歌单…'),
      error: (error, stackTrace) => DesktopInlineError(
        message: apiExceptionOf(error).message,
        onRetry: () => ref.invalidate(playlistSearchResultsProvider),
      ),
      data: (playlists) {
        if (playlists.isEmpty) {
          return const DesktopEmptyState(
            icon: Icons.queue_music,
            title: '未找到歌单',
            message: '换个关键词或平台试试',
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: DesktopSpacing.sm),
              child: Text(
                '共 ${playlists.length} 个歌单',
                style: DesktopText.caption.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Expanded(
              child: AppScrollbar(
                builder: (controller) => ListView.separated(
                  controller: controller,
                  itemCount: playlists.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 2),
                  itemBuilder: (context, index) =>
                      _PlaylistResultRow(playlist: playlists[index]),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildIdle() {
    final history = ref.watch(searchHistoryProvider);
    return Align(
      alignment: Alignment.topLeft,
      child: AppScrollbar(
        builder: (controller) => SingleChildScrollView(
          controller: controller,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (history.isEmpty)
                  const SizedBox(
                    height: 320,
                    child: DesktopEmptyState(
                      icon: Icons.search,
                      title: '搜索想听的歌',
                      message: '网易云、QQ音乐、酷狗都能搜；选「全部平台」可一次搜完',
                    ),
                  )
                else ...[
                  Row(
                    children: [
                      Text(
                        '最近搜索',
                        style: DesktopText.title.copyWith(
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () => unawaited(
                          ref.read(searchHistoryProvider.notifier).clear(),
                        ),
                        child: const Text('清空历史'),
                      ),
                    ],
                  ),
                  const SizedBox(height: DesktopSpacing.xs),
                  Wrap(
                    spacing: DesktopSpacing.sm,
                    runSpacing: DesktopSpacing.sm,
                    children: [
                      for (final entry in history)
                        _HistoryChip(
                          label: entry,
                          onTap: () => _submit(value: entry),
                          onRemove: () => unawaited(
                            ref
                                .read(searchHistoryProvider.notifier)
                                .remove(entry),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: DesktopSpacing.xl),
                  Text(
                    '提示：输入关键词后会自动搜索；回车立即搜索。',
                    style: DesktopText.caption.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _toggleSort(String key) {
    setState(() {
      if (_sortKey == key) {
        _sortAscending = !_sortAscending;
      } else {
        _sortKey = key;
        _sortAscending = true;
      }
    });
  }
}

class _PlatformErrorStrip extends StatelessWidget {
  final Map<PlatformType, String> errors;
  final bool networkFailed;

  const _PlatformErrorStrip({
    required this.errors,
    required this.networkFailed,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = networkFailed ? scheme.error : scheme.onSurfaceVariant;
    return Container(
      margin: const EdgeInsets.only(bottom: DesktopSpacing.sm),
      padding: const EdgeInsets.symmetric(
        horizontal: DesktopSpacing.md,
        vertical: DesktopSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: DesktopRadii.smAll,
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            networkFailed ? Icons.wifi_off : Icons.info_outline,
            size: 15,
            color: color,
          ),
          const SizedBox(width: DesktopSpacing.sm),
          Expanded(
            child: Text(
              errors.entries
                  .map((entry) => '${entry.key.displayName}：${entry.value}')
                  .join('   '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: DesktopText.caption.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const _HistoryChip({
    required this.label,
    required this.onTap,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHigh.withValues(alpha: 0.55),
      borderRadius: DesktopRadii.smAll,
      child: InkWell(
        borderRadius: DesktopRadii.smAll,
        hoverColor: scheme.onSurface.withValues(alpha: 0.05),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.only(left: DesktopSpacing.md, right: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: DesktopText.caption.copyWith(color: scheme.onSurface),
              ),
              IconButton(
                tooltip: '移除',
                onPressed: onRemove,
                iconSize: 14,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlaylistResultRow extends StatelessWidget {
  final Playlist playlist;

  const _PlaylistResultRow({required this.playlist});

  String _route() {
    final query = Uri(
      queryParameters: {
        'name': playlist.name,
        if (playlist.coverUrl != null && playlist.coverUrl!.isNotEmpty)
          'cover': playlist.coverUrl!,
      },
    ).query;
    final id = Uri.encodeComponent(playlist.id);
    return '/playlist/${playlist.platform.name}/$id'
        '${query.isEmpty ? '' : '?$query'}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      borderRadius: DesktopRadii.smAll,
      child: InkWell(
        borderRadius: DesktopRadii.smAll,
        hoverColor: scheme.onSurface.withValues(alpha: 0.05),
        onTap: () => context.push(_route()),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: DesktopSpacing.sm,
            vertical: 6,
          ),
          child: Row(
            children: [
              DesktopCoverArt(
                url: playlist.coverUrl,
                size: 44,
                radius: 8,
                icon: Icons.queue_music,
              ),
              const SizedBox(width: DesktopSpacing.md),
              Expanded(
                flex: 4,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      playlist.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DesktopText.bodyStrong.copyWith(
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      '${playlist.songCount} 首'
                      '${playlist.creatorName == null ? '' : ' · ${playlist.creatorName}'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DesktopText.caption.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: DesktopSpacing.md),
              SizedBox(
                width: 74,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: DesktopPlatformBadge(platform: playlist.platform),
                ),
              ),
              TextButton(
                onPressed: () => context.push(_route()),
                child: const Text('打开'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
