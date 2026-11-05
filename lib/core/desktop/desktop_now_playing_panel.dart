import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/download/presentation/widgets/download_button.dart';
import '../../features/library/presentation/providers/likes_provider.dart';
import '../../features/player/presentation/providers/player_provider.dart';
import '../../features/player/presentation/widgets/lyrics_display.dart';
import '../../features/player/presentation/widgets/quality_bottom_sheet.dart';
import '../../models/song.dart';
import 'desktop_empty_state.dart';
import 'desktop_network_image.dart';
import 'desktop_panel_provider.dart';
import 'desktop_tokens.dart';

class DesktopNowPlayingPanel extends ConsumerWidget {
  const DesktopNowPlayingPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final tab =
        ref.watch(desktopPanelTabProvider) ?? DesktopPanelTab.nowPlaying;
    final song = ref.watch(playerProvider.select((s) => s.currentSong));

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow.withValues(alpha: 0.86),
        borderRadius: DesktopRadii.xlAll,
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.42),
        ),
        boxShadow: DesktopShadows.panel,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              DesktopSpacing.lg,
              DesktopSpacing.md,
              DesktopSpacing.sm,
              DesktopSpacing.sm,
            ),
            child: Row(
              children: [
                Text(
                  '正在播放',
                  style: DesktopText.title.copyWith(color: scheme.onSurface),
                ),
                const Spacer(),
                IconButton(
                  tooltip: '收起面板',
                  onPressed: () =>
                      ref.read(desktopPanelTabProvider.notifier).state = null,
                  icon: const Icon(Icons.chevron_right, size: 20),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: DesktopSpacing.sm),
            child: _PanelTabs(tab: tab),
          ),
          const SizedBox(height: DesktopSpacing.sm),
          Expanded(
            child: switch (tab) {
              DesktopPanelTab.nowPlaying =>
                song == null
                    ? const DesktopEmptyState(
                        icon: Icons.music_note,
                        title: '还没有播放歌曲',
                        message: '从发现、搜索或音乐库选择一首歌',
                      )
                    : _NowPlaying(song: song),
              DesktopPanelTab.lyrics => const Padding(
                padding: EdgeInsets.fromLTRB(
                  DesktopSpacing.sm,
                  0,
                  DesktopSpacing.sm,
                  DesktopSpacing.sm,
                ),
                child: LyricsDisplay(),
              ),
              DesktopPanelTab.queue => const _QueuePanel(),
            },
          ),
        ],
      ),
    );
  }
}

class _PanelTabs extends ConsumerWidget {
  final DesktopPanelTab tab;

  const _PanelTabs({required this.tab});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 34,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: DesktopRadii.smAll,
      ),
      child: Row(
        children: [
          for (final item in DesktopPanelTab.values)
            Expanded(
              child: InkWell(
                onTap: () =>
                    ref.read(desktopPanelTabProvider.notifier).state = item,
                borderRadius: DesktopRadii.smAll,
                child: AnimatedContainer(
                  duration: DesktopDurations.hover,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: item == tab ? scheme.surface : Colors.transparent,
                    borderRadius: DesktopRadii.smAll,
                    boxShadow: item == tab
                        ? const [
                            BoxShadow(
                              color: Color(0x14000000),
                              blurRadius: 3,
                              offset: Offset(0, 1),
                            ),
                          ]
                        : null,
                  ),
                  child: Text(
                    item.label,
                    style: DesktopText.caption.copyWith(
                      color: item == tab
                          ? scheme.onSurface
                          : scheme.onSurfaceVariant,
                      fontWeight: item == tab
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _NowPlaying extends ConsumerWidget {
  final Song song;

  const _NowPlaying({required this.song});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;

    final liked = ref.watch(
      likesProvider.select(
        (s) => s.songs.any(
          (item) => item.id == song.id && item.platform == song.platform,
        ),
      ),
    );
    final quality = ref.watch(playerProvider.select((s) => s.currentQuality));
    final position = ref.watch(playerProvider.select((s) => s.position));
    final duration = ref.watch(playerProvider.select((s) => s.duration));
    final notifier = ref.read(playerProvider.notifier);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        DesktopSpacing.lg,
        DesktopSpacing.sm,
        DesktopSpacing.lg,
        DesktopSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: ClipRRect(
              borderRadius: DesktopRadii.lgAll,
              child: song.coverUrl != null
                  ? DesktopNetworkImage(
                      url: song.coverUrl!,
                      cacheWidth: 720,
                      placeholder: _coverPlaceholder(scheme),
                      error: _coverPlaceholder(scheme),
                    )
                  : _coverPlaceholder(scheme),
            ),
          ),
          const SizedBox(height: DesktopSpacing.lg),
          Text(
            song.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: DesktopText.headline.copyWith(color: scheme.onSurface),
          ),
          const SizedBox(height: 4),
          Text(
            song.artistNames,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: DesktopText.body.copyWith(color: scheme.onSurfaceVariant),
          ),
          if (song.album?.name != null &&
              song.album!.name.trim().isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              song.album!.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: DesktopText.caption.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: DesktopSpacing.md),
          Row(
            children: [
              InkWell(
                onTap: () => showQualitySheet(context),
                borderRadius: DesktopRadii.smAll,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: DesktopSpacing.sm,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.1),
                    borderRadius: DesktopRadii.smAll,
                  ),
                  child: Text(
                    quality.displayNameFor(song.platform),
                    style: DesktopText.caption.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: liked ? '取消喜欢' : '喜欢',
                onPressed: () => unawaited(
                  ref.read(likesProvider.notifier).toggleLike(song),
                ),
                icon: Icon(
                  liked ? Icons.favorite : Icons.favorite_border,
                  size: 20,
                  color: liked ? scheme.error : scheme.onSurfaceVariant,
                ),
              ),
              DownloadButton(song: song),
            ],
          ),
          const SizedBox(height: DesktopSpacing.md),
          Slider(
            value: duration.inMilliseconds > 0
                ? (position.inMilliseconds / duration.inMilliseconds).clamp(
                    0.0,
                    1.0,
                  )
                : 0,
            onChanged: duration.inMilliseconds > 0
                ? (value) => notifier.seek(
                    Duration(
                      milliseconds: (value * duration.inMilliseconds).round(),
                    ),
                  )
                : null,
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _format(position),
                style: DesktopText.caption.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              Text(
                _format(duration),
                style: DesktopText.caption.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: DesktopSpacing.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                tooltip: '上一首',
                onPressed: notifier.skipToPrevious,
                icon: const Icon(Icons.skip_previous, size: 24),
              ),
              const SizedBox(width: DesktopSpacing.md),
              SizedBox(
                width: 44,
                height: 44,
                child: Material(
                  color: scheme.primary,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: notifier.togglePlay,
                    child: Icon(
                      Icons.play_arrow,
                      size: 26,
                      color: scheme.onPrimary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: DesktopSpacing.md),
              IconButton(
                tooltip: '下一首',
                onPressed: notifier.skipToNext,
                icon: const Icon(Icons.skip_next, size: 24),
              ),
            ],
          ),
          const SizedBox(height: DesktopSpacing.sm),
          OutlinedButton.icon(
            onPressed: () => context.push('/player'),
            icon: const Icon(Icons.open_in_full, size: 16),
            label: const Text('沉浸播放'),
          ),
        ],
      ),
    );
  }

  Widget _coverPlaceholder(ColorScheme scheme) {
    return ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: Icon(Icons.music_note, size: 64, color: scheme.onSurfaceVariant),
    );
  }

  String _format(Duration value) {
    final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

class _QueuePanel extends ConsumerWidget {
  const _QueuePanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final queue = ref.watch(playerProvider.select((s) => s.playlist));
    final currentIndex = ref.watch(
      playerProvider.select((s) => s.currentIndex),
    );
    final notifier = ref.read(playerProvider.notifier);

    if (queue.isEmpty) {
      return const DesktopEmptyState(
        icon: Icons.queue_music,
        title: '队列是空的',
        message: '播放歌曲，或在歌曲菜单里加入播放队列',
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: DesktopSpacing.lg),
          child: Row(
            children: [
              Text(
                '共 ${queue.length} 首',
                style: DesktopText.caption.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => notifier.clearQueue(),
                child: const Text('清空'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(
              DesktopSpacing.sm,
              0,
              DesktopSpacing.sm,
              DesktopSpacing.sm,
            ),
            itemCount: queue.length,
            itemBuilder: (context, index) {
              final song = queue[index];
              final selected = index == currentIndex;
              return Material(
                color: selected
                    ? scheme.primary.withValues(alpha: 0.1)
                    : Colors.transparent,
                borderRadius: DesktopRadii.smAll,
                child: InkWell(
                  onTap: () => notifier.playAtIndex(index),
                  borderRadius: DesktopRadii.smAll,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: DesktopSpacing.sm,
                      vertical: 6,
                    ),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.all(DesktopRadii.xs),
                          child: SizedBox(
                            width: 34,
                            height: 34,
                            child: song.coverUrl != null
                                ? DesktopNetworkImage(
                                    url: song.coverUrl!,
                                    cacheWidth: 100,
                                    placeholder: _miniPlaceholder(scheme),
                                    error: _miniPlaceholder(scheme),
                                  )
                                : _miniPlaceholder(scheme),
                          ),
                        ),
                        const SizedBox(width: DesktopSpacing.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                song.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: DesktopText.caption.copyWith(
                                  color: selected
                                      ? scheme.primary
                                      : scheme.onSurface,
                                  fontWeight: selected
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                ),
                              ),
                              Text(
                                song.artistNames,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: DesktopText.caption.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: '移出队列',
                          onPressed: () =>
                              notifier.removeFromQueue(song.dedupeKey),
                          icon: Icon(
                            Icons.close,
                            size: 15,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _miniPlaceholder(ColorScheme scheme) {
    return ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: Icon(Icons.music_note, size: 16, color: scheme.onSurfaceVariant),
    );
  }
}
