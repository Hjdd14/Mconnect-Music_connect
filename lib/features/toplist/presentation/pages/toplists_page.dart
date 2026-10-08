import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/network/platform_http.dart';
import '../../../../core/theme/platform_accent.dart';
import '../../../../core/utils/snackbar_helper.dart';
import '../../../../core/widgets/app_scrollbar.dart';
import '../../../../core/widgets/async_state_view.dart';
import '../../../../models/audio_quality.dart';
import '../../../../models/platform_type.dart';
import '../../../../models/song.dart';
import '../../../../models/toplist.dart';
import '../../../download/presentation/providers/download_provider.dart';
import '../../../player/presentation/providers/player_provider.dart';
import '../providers/toplist_detail_provider.dart';
import '../providers/toplists_provider.dart';
import '../widgets/ranked_song_tile.dart';

/// 榜单中心 — every chart the platforms publish, grouped by platform and group.
///
/// Replaces the Wave 0 placeholder. Two things it fixes:
/// * **QQ 热歌榜 is pinned at the top** with `topId=26`. The adapter used to ask
///   for `topId=4` (巅峰榜·流行指数) while labelling it 热歌榜, so the real
///   300-track chart was unreachable — the reported "QQ 热歌榜没有入口";
/// * a platform that fails keeps its entry and shows its error instead of
///   silently disappearing.
class ToplistsPage extends ConsumerStatefulWidget {
  const ToplistsPage({super.key});

  @override
  ConsumerState<ToplistsPage> createState() => _ToplistsPageState();
}

class _ToplistsPageState extends ConsumerState<ToplistsPage> {
  @override
  void initState() {
    super.initState();
    final state = ref.read(toplistsProvider);
    if (!state.hasAnyData && !state.isLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(toplistsProvider.notifier).load();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(toplistsProvider);
    final platforms = _platformsToRender(state);

    return Scaffold(
      appBar: AppBar(
        title: const Text('榜单中心'),
        actions: [
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.read(toplistsProvider.notifier).refresh(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(toplistsProvider.notifier).refresh(),
        child: AppScrollbar(
          builder: (controller) => CustomScrollView(
            controller: controller,
            // `CustomScrollView` has no `padding` parameter (unlike `ListView`),
            // so the old list's 24 px bottom clearance is a trailing spacer
            // sliver instead.
            // Always scrollable: a viewport-sized child is not draggable under
            // the default physics, which would make the empty state's
            // 「下拉刷新重试」 an instruction the user cannot follow.
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: _HotChartCard(
                  meta: state.qqHotToplist,
                  onTap: () => _openChart(
                    PlatformType.qq,
                    qqHotToplistId,
                    state.qqHotToplist?.name ?? qqHotToplistName,
                  ),
                ),
              ),
              if (state.isLoading && !state.hasAnyData)
                // `hasScrollBody: true` is required, not cosmetic: the skeleton
                // is a `ListView`, and `SliverFillRemaining`'s non-scroll-body
                // variant asks its child for intrinsic dimensions during layout
                // — which a viewport cannot answer.
                const SliverAsyncStateView(
                  hasScrollBody: true,
                  child: AsyncStateView.loading(skeleton: true),
                ),
              for (final platform in platforms)
                SliverToBoxAdapter(
                  child: _PlatformSection(
                    platform: platform,
                    toplists: state.toplistsForPlatform(platform),
                    error: state.errorForPlatform(platform),
                    offline: state.isOffline(platform),
                    onRetry: () =>
                        ref.read(toplistsProvider.notifier).refresh(),
                    onOpen: (toplist) =>
                        _openChart(platform, toplist.id, toplist.name),
                  ),
                ),
              if (!state.isLoading &&
                  !state.hasAnyData &&
                  state.errorsByPlatform.isEmpty)
                const SliverAsyncStateView(
                  child: AsyncStateView.empty(
                    title: '暂无榜单数据',
                    message: '下拉刷新重试',
                  ),
                ),
              // 24 px bottom clearance, as the previous `ListView(padding: …)`
              // had (kept last so it also gives the empty/loading state a
              // scrollable extent).
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          ),
        ),
      ),
    );
  }

  List<PlatformType> _platformsToRender(ToplistsState state) {
    return PlatformType.musicServices.where((platform) {
      return state.toplistsForPlatform(platform).isNotEmpty ||
          state.errorForPlatform(platform) != null ||
          state.platforms.contains(platform);
    }).toList();
  }

  void _openChart(PlatformType platform, String toplistId, String? name) {
    final query = Uri(
      queryParameters: {
        if (name != null && name.isNotEmpty) 'name': name,
      },
    ).query;
    context.push(
      '/toplist/${platform.name}/${Uri.encodeComponent(toplistId)}'
      '${query.isEmpty ? '' : '?$query'}',
    );
  }
}

/// The pinned QQ 热歌榜 entry.
///
/// Rendered even when the catalogue has not answered yet: the chart id is
/// static (`26`), so the entry the user asked for can never be missing just
/// because the hub is offline.
class _HotChartCard extends StatelessWidget {
  const _HotChartCard({required this.meta, required this.onTap});

  final Toplist? meta;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final name = meta?.name ?? qqHotToplistName;
    final details = <String>[
      '${meta?.songCount ?? 300} 首',
      if (meta?.updateFrequency != null) meta!.updateFrequency!,
      if (meta?.period != null) meta!.period!,
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                _ChartCover(
                  coverUrl: meta?.coverUrl,
                  accent: PlatformAccent.qq,
                  size: 72,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: PlatformAccent.qq.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              '置顶',
                              style: TextStyle(
                                fontSize: 10,
                                color: PlatformAccent.qq,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Text(
                            'QQ音乐',
                            style: TextStyle(fontSize: 11, color: Colors.grey),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        details.join(' · '),
                        style: TextStyle(fontSize: 12, color: cs.outline),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '进入 300 首热歌榜',
                        style: TextStyle(
                          fontSize: 12,
                          color: PlatformAccent.qq,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PlatformSection extends StatelessWidget {
  const _PlatformSection({
    required this.platform,
    required this.toplists,
    required this.error,
    required this.offline,
    required this.onRetry,
    required this.onOpen,
  });

  final PlatformType platform;
  final List<Toplist> toplists;
  final String? error;
  final bool offline;
  final VoidCallback onRetry;
  final void Function(Toplist toplist) onOpen;

  @override
  Widget build(BuildContext context) {
    final accent = PlatformAccent.colorOf(context, platform);
    final groups = <String?, List<Toplist>>{};
    for (final toplist in toplists) {
      groups.putIfAbsent(toplist.groupName, () => []).add(toplist);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Text(
                platform.displayName,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (offline) ...[
                const SizedBox(width: 8),
                const _OfflineBadge(),
              ],
              const Spacer(),
              if (toplists.isNotEmpty)
                Text(
                  '${toplists.length} 个榜单',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
            ],
          ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: _PlatformError(
              platform: platform,
              message: error!,
              onRetry: onRetry,
            ),
          ),
        for (final entry in groups.entries) ...[
          if (entry.key != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                entry.key!,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
            ),
          for (final toplist in entry.value)
            _ToplistTile(
              toplist: toplist,
              accent: accent,
              onTap: () => onOpen(toplist),
            ),
        ],
      ],
    );
  }
}

class _ToplistTile extends StatelessWidget {
  const _ToplistTile({
    required this.toplist,
    required this.accent,
    required this.onTap,
  });

  final Toplist toplist;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final details = <String>[
      if (toplist.songCount != null) '${toplist.songCount} 首',
      if (toplist.updateFrequency != null) toplist.updateFrequency!,
      if (toplist.period != null) toplist.period!,
    ];
    return ListTile(
      onTap: onTap,
      leading: _ChartCover(coverUrl: toplist.coverUrl, accent: accent, size: 44),
      title: Text(
        toplist.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: details.isEmpty
          ? null
          : Text(
              details.join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
      trailing: const Icon(Icons.chevron_right, size: 20),
    );
  }
}

class _PlatformError extends StatelessWidget {
  const _PlatformError({
    required this.platform,
    required this.message,
    required this.onRetry,
  });

  final PlatformType platform;
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cs.errorContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 18, color: cs.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${platform.displayName}榜单加载失败：$message',
              style: TextStyle(fontSize: 12, color: cs.onErrorContainer),
            ),
          ),
          ElevatedButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }
}

class _OfflineBadge extends StatelessWidget {
  const _OfflineBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Text('离线缓存', style: TextStyle(fontSize: 10)),
    );
  }
}

class _ChartCover extends StatelessWidget {
  const _ChartCover({
    required this.coverUrl,
    required this.accent,
    required this.size,
  });

  final String? coverUrl;
  final Color accent;
  final double size;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: size,
      height: size,
      color: accent.withValues(alpha: 0.12),
      child: Icon(Icons.leaderboard, color: accent, size: size * 0.5),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: coverUrl == null || coverUrl!.isEmpty
          ? placeholder
          : CachedNetworkImage(
              imageUrl: coverUrl!,
              width: size,
              height: size,
              memCacheWidth: (size * 2).round(),
              fit: BoxFit.cover,
              placeholder: (_, _) => placeholder,
              errorWidget: (_, _, _) => placeholder,
            ),
    );
  }
}

/// One chart's songs, with 本期名次 + 涨跌.
///
/// QQ's 热歌榜 (`/toplist/qq/26`, also reachable from the pinned card) is the
/// reason this page exists: the adapter fetches all 300 tracks and reports each
/// song's movement, so the list renders rank + arrow instead of pretending the
/// chart is an ordinary playlist.
class ToplistDetailPage extends ConsumerStatefulWidget {
  const ToplistDetailPage({
    super.key,
    required this.platform,
    required this.toplistId,
    this.toplistName,
  });

  final PlatformType platform;
  final String toplistId;
  final String? toplistName;

  @override
  ConsumerState<ToplistDetailPage> createState() => _ToplistDetailPageState();
}

class _ToplistDetailPageState extends ConsumerState<ToplistDetailPage> {
  ToplistKey get _key =>
      (platform: widget.platform, toplistId: widget.toplistId);

  @override
  void initState() {
    super.initState();
    final state = ref.read(toplistsProvider);
    if (!state.hasAnyData && !state.isLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        // Only for the header metadata; the chart itself loads below.
        ref.read(toplistsProvider.notifier).load();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final meta = ref
        .watch(toplistsProvider)
        .findToplist(widget.platform, widget.toplistId);
    final async = ref.watch(toplistSongsProvider(_key));
    final accent = PlatformAccent.colorOf(context, widget.platform);
    final title = meta?.name ?? widget.toplistName ?? '榜单';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(toplistSongsProvider(_key)),
          ),
        ],
      ),
      body: async.when(
        loading: () => const AsyncStateView.loading(),
        error: (error, _) => AsyncStateView.error(
          title: '加载失败',
          message: apiExceptionOf(error).message,
          onRetry: () => ref.invalidate(toplistSongsProvider(_key)),
        ),
        data: (ranked) {
          if (ranked.isEmpty) {
            // An empty chart is not a failure: `AsyncStateView.empty` offers no
            // retry (the contract has no retry-less error), and the refresh
            // path stays the AppBar button plus pull-to-refresh below.
            return const AsyncStateView.empty(title: '该榜单暂无歌曲');
          }
          final songs = ranked.map((r) => r.song).toList();
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(toplistSongsProvider(_key)),
            child: AppScrollbar(
              builder: (controller) => ListView.builder(
                controller: controller,
                padding: const EdgeInsets.only(bottom: 24),
                itemCount: ranked.length + 1,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return _ChartHeader(
                      platform: widget.platform,
                      toplistId: widget.toplistId,
                      meta: meta,
                      fallbackName: title,
                      accent: accent,
                      songCount: ranked.length,
                      onPlayAll: () => ref
                          .read(playerProvider.notifier)
                          .playPlaylist(songs),
                      onCacheAll: () => _cacheAll(songs),
                    );
                  }
                  final i = index - 1;
                  return RankedSongTile(
                    ranked: ranked[i],
                    accent: accent,
                    playlist: songs,
                    index: i,
                    onTap: () => ref
                        .read(playerProvider.notifier)
                        .playPlaylist(songs, startIndex: i),
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _cacheAll(List<Song> songs) async {
    final report = await ref
        .read(downloadProvider.notifier)
        .cacheSongs(songs, quality: AudioLevel.low);
    if (!mounted) return;
    final started = report.started + report.queued;
    showSuccessSnackBar(
      context,
      '已加入离线缓存 $started 首'
      '${report.skipped > 0 ? '，跳过 ${report.skipped} 首' : ''}',
    );
  }
}

class _ChartHeader extends StatelessWidget {
  const _ChartHeader({
    required this.platform,
    required this.toplistId,
    required this.meta,
    required this.fallbackName,
    required this.accent,
    required this.songCount,
    required this.onPlayAll,
    required this.onCacheAll,
  });

  final PlatformType platform;
  final String toplistId;
  final Toplist? meta;
  final String fallbackName;
  final Color accent;
  final int songCount;
  final VoidCallback onPlayAll;
  final VoidCallback onCacheAll;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final chips = <String>[
      '$songCount 首',
      if (meta?.updateFrequency != null) meta!.updateFrequency!,
      if (meta?.period != null) meta!.period!,
      if (meta?.groupName != null) meta!.groupName!,
    ];
    final definition = _plainText(meta?.intro);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ChartCover(
                coverUrl: meta?.coverUrl,
                accent: accent,
                size: 96,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      meta?.name ?? fallbackName,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        for (final chip in chips)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              chip,
                              style: TextStyle(fontSize: 11, color: accent),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      platform.displayName,
                      style: TextStyle(fontSize: 12, color: cs.outline),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              FilledButton.icon(
                onPressed: onPlayAll,
                icon: const Icon(Icons.play_arrow, size: 18),
                label: const Text('播放全部'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: onCacheAll,
                icon: const Icon(Icons.download_for_offline_outlined, size: 18),
                label: const Text('整榜缓存'),
              ),
            ],
          ),
          if (definition != null) ...[
            const SizedBox(height: 12),
            Text(
              definition,
              style: TextStyle(fontSize: 12, color: cs.outline, height: 1.5),
            ),
          ],
          const Divider(height: 24),
          Text(
            '涨跌：↑ 上升 · ↓ 下降 · — 持平 · 新 新上榜',
            key: const Key('toplist-movement-legend'),
            style: TextStyle(fontSize: 11, color: cs.outline),
          ),
        ],
      ),
    );
  }

  /// QQ's 榜单定义 is HTML-ish (`1. …<br>2. …`), so tags are flattened for the
  /// plain-text header instead of showing raw markup.
  static String? _plainText(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    return raw
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .trim();
  }
}
