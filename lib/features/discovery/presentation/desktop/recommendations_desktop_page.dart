import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/desktop/desktop_empty_state.dart';
import '../../../../core/desktop/desktop_network_image.dart';
import '../../../../core/desktop/desktop_page_scaffold.dart';
import '../../../../core/desktop/desktop_tokens.dart';
import '../../../../core/theme/platform_accent.dart';
import '../../../../models/platform_type.dart';
import '../../../../models/song.dart';
import '../../../download/presentation/widgets/download_button.dart';
import '../../../player/presentation/providers/player_provider.dart';
import '../providers/playlist_recommendations_provider.dart';

/// The full 每日推荐 list, as a desktop page.
///
/// The discovery page only shows a teaser (12 cards) because a desktop page is
/// a grid of sections, not one endless feed. 「查看全部」 used to have no
/// destination at all, so the rest of the recommendations were unreachable.
/// This page is that destination: every song from every signed-in platform,
/// de-duplicated with the same [Song.dedupeKey] the discovery teaser uses,
/// with per-platform filtering and the usual row actions.
class RecommendationsDesktopPage extends ConsumerStatefulWidget {
  const RecommendationsDesktopPage({super.key});

  @override
  ConsumerState<RecommendationsDesktopPage> createState() =>
      _RecommendationsDesktopPageState();
}

class _RecommendationsDesktopPageState
    extends ConsumerState<RecommendationsDesktopPage> {
  /// null = 全部平台.
  PlatformType? _filter;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final state = ref.read(playlistRecommendationsProvider);
      if (state.songsByPlatform.isEmpty && !state.isLoading) {
        ref.read(playlistRecommendationsProvider.notifier).loadRecommendations();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(playlistRecommendationsProvider);
    final all = _flatten(state.songsByPlatform);
    final songs = _filter == null
        ? all
        : all.where((song) => song.platform == _filter).toList(growable: false);

    return DesktopPageScaffold(
      title: '每日推荐',
      subtitle: all.isEmpty
          ? '登录平台账号后会按你的口味生成推荐'
          : '共 ${all.length} 首 · 跨平台聚合，按平台优先顺序去重',
      actions: [
        IconButton(
          tooltip: '刷新',
          onPressed: state.isLoading
              ? null
              : () => ref
                    .read(playlistRecommendationsProvider.notifier)
                    .loadRecommendations(),
          icon: const Icon(Icons.refresh, size: 20),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _FilterRow(
            platforms: state.songsByPlatform.keys.toList(),
            selected: _filter,
            onSelected: (value) => setState(() => _filter = value),
            songCount: songs.length,
            onPlayAll: songs.isEmpty
                ? null
                : () => ref
                      .read(playerProvider.notifier)
                      .playPlaylist(songs, startIndex: 0),
          ),
          const SizedBox(height: DesktopSpacing.md),
          Expanded(child: _body(context, state, songs)),
        ],
      ),
    );
  }

  Widget _body(
    BuildContext context,
    PlaylistRecommendationsState state,
    List<Song> songs,
  ) {
    if (state.isLoading && state.songsByPlatform.isEmpty) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (songs.isEmpty) {
      final error = state.error;
      return DesktopEmptyState(
        icon: Icons.wb_sunny_outlined,
        title: error == null ? '暂无每日推荐' : '加载失败',
        message: error ?? '换一个平台筛选，或先去「账号与平台」登录',
        action: error == null
            ? null
            : FilledButton(
                onPressed: () => ref
                    .read(playlistRecommendationsProvider.notifier)
                    .loadRecommendations(),
                child: const Text('重试'),
              ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: DesktopSpacing.xxxl),
      itemCount: songs.length,
      separatorBuilder: (_, _) => const SizedBox(height: 2),
      itemBuilder: (context, index) => _SongRow(
        key: ValueKey(
          'recommendation-row-${songs[index].platform.name}-${songs[index].id}',
        ),
        index: index,
        song: songs[index],
        onPlay: () => ref
            .read(playerProvider.notifier)
            .playPlaylist(songs, startIndex: index),
      ),
    );
  }

  /// The same ordering and de-duplication the discovery teaser applies, so the
  /// first twelve rows here are exactly the twelve cards on the home page.
  static List<Song> _flatten(Map<PlatformType, List<Song>> byPlatform) {
    final result = <Song>[];
    final seen = <String>{};
    for (final platform in PlatformType.musicServices) {
      for (final song in byPlatform[platform] ?? const <Song>[]) {
        if (seen.add(song.dedupeKey)) result.add(song);
      }
    }
    return result;
  }
}

class _FilterRow extends StatelessWidget {
  final List<PlatformType> platforms;
  final PlatformType? selected;
  final ValueChanged<PlatformType?> onSelected;
  final int songCount;
  final VoidCallback? onPlayAll;

  const _FilterRow({
    required this.platforms,
    required this.selected,
    required this.onSelected,
    required this.songCount,
    required this.onPlayAll,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: Wrap(
            spacing: DesktopSpacing.sm,
            runSpacing: DesktopSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ChoiceChip(
                key: const ValueKey('recommendations-filter-all'),
                label: const Text('全部'),
                selected: selected == null,
                onSelected: (_) => onSelected(null),
              ),
              for (final platform in platforms)
                ChoiceChip(
                  key: ValueKey('recommendations-filter-${platform.name}'),
                  label: Text(platform.displayName),
                  selected: selected == platform,
                  onSelected: (_) => onSelected(platform),
                ),
              Padding(
                padding: const EdgeInsets.only(left: DesktopSpacing.xs),
                child: Text(
                  '$songCount 首',
                  style: DesktopText.caption.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: DesktopSpacing.md),
        FilledButton.icon(
          key: const ValueKey('recommendations-play-all'),
          onPressed: onPlayAll,
          icon: const Icon(Icons.play_arrow, size: 18),
          label: const Text('播放全部'),
        ),
      ],
    );
  }
}

class _SongRow extends StatelessWidget {
  final int index;
  final Song song;
  final VoidCallback onPlay;

  const _SongRow({
    super.key,
    required this.index,
    required this.song,
    required this.onPlay,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = PlatformAccent.colorOf(context, song.platform);
    return Material(
      color: Colors.transparent,
      borderRadius: DesktopRadii.mdAll,
      child: InkWell(
        onTap: onPlay,
        borderRadius: DesktopRadii.mdAll,
        hoverColor: scheme.onSurface.withValues(alpha: 0.05),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: DesktopSpacing.sm,
            vertical: DesktopSpacing.xs,
          ),
          child: Row(
            children: [
              SizedBox(
                width: 28,
                child: Text(
                  (index + 1).toString(),
                  textAlign: TextAlign.right,
                  style: DesktopText.caption.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: DesktopSpacing.md),
              ClipRRect(
                borderRadius: DesktopRadii.smAll,
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: song.coverUrl != null
                      ? DesktopNetworkImage(
                          url: song.coverUrl!,
                          cacheWidth: 96,
                          placeholder: _coverPlaceholder(scheme),
                          error: _coverPlaceholder(scheme),
                        )
                      : _coverPlaceholder(scheme),
                ),
              ),
              const SizedBox(width: DesktopSpacing.md),
              Expanded(
                flex: 3,
                child: Text(
                  song.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DesktopText.bodyStrong.copyWith(
                    color: scheme.onSurface,
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  song.artistNames,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DesktopText.body.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: DesktopRadii.smAll,
                ),
                child: Text(
                  song.platform.displayName,
                  style: DesktopText.caption.copyWith(color: accent),
                ),
              ),
              const SizedBox(width: DesktopSpacing.sm),
              DownloadButton(song: song, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _coverPlaceholder(ColorScheme scheme) {
    return ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: Icon(Icons.music_note, size: 18, color: scheme.onSurfaceVariant),
    );
  }
}
