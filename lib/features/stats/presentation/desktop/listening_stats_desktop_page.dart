import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/desktop/desktop_empty_state.dart';
import '../../../../core/desktop/desktop_page_scaffold.dart';
import '../../../../core/desktop/desktop_section_header.dart';
import '../../../../core/desktop/desktop_stat_card.dart';
import '../../../../core/desktop/desktop_song_table.dart';
import '../../../../core/desktop/desktop_tokens.dart';
import '../providers/listening_stats_provider.dart';

/// 听歌统计桌面页。
///
/// The numbers come from the same providers the phone page uses
/// ([listeningStatsProvider] for the totals/ranking and
/// [listeningStatsReportProvider] for the artist / day dimensions); only the
/// presentation is desktop — metric cards plus bars instead of a vertical list
/// of ListTiles.
class ListeningStatsDesktopPage extends ConsumerWidget {
  const ListeningStatsDesktopPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(listeningStatsProvider);
    final report = ref.watch(listeningStatsReportProvider);
    final notifier = ref.read(listeningStatsProvider.notifier);
    final reportValue = report.valueOrNull;
    final topArtist = reportValue == null || reportValue.artists.isEmpty
        ? null
        : reportValue.artists.first;
    final topSong = state.allSongs.isEmpty ? null : state.allSongs.first;

    return DesktopPageScaffold(
      title: '听歌统计',
      subtitle: '播放次数、收听时长与常听排行',
      actions: [
        IconButton(
          tooltip: '重新加载统计',
          onPressed: () => unawaited(notifier.load()),
          icon: const Icon(Icons.refresh, size: 20),
        ),
        if (state.hasData)
          OutlinedButton.icon(
            onPressed: () => _confirmClear(context, notifier),
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text('清空统计'),
          ),
      ],
      child: _buildBody(context, state, report, notifier, topArtist, topSong),
    );
  }

  Widget _buildBody(
    BuildContext context,
    ListeningStatsState state,
    AsyncValue<ListeningStatsReport> report,
    ListeningStatsNotifier notifier,
    ListeningStatsDimension? topArtist,
    ListeningStatsSongEntry? topSong,
  ) {
    if (state.isLoading && !state.hasData) {
      return const DesktopInlineLoading(label: '正在加载听歌统计');
    }
    if (state.error != null && !state.hasData) {
      return DesktopEmptyState(
        icon: Icons.error_outline,
        title: '听歌统计加载失败',
        message: state.error,
        action: FilledButton(
          onPressed: () => unawaited(notifier.load()),
          child: const Text('重试'),
        ),
      );
    }
    if (!state.hasData) {
      return const DesktopEmptyState(
        icon: Icons.insights_outlined,
        title: '还没有听歌记录',
        message: '播放几首歌之后，这里会出现播放次数、收听时长和常听排行',
      );
    }

    final reportValue = report.valueOrNull;
    final artists = reportValue?.artists ?? const <ListeningStatsDimension>[];
    final days = reportValue?.days ?? const <ListeningStatsDay>[];
    final topSongs = state.allSongs.take(10).toList();

    return ListView(
      padding: const EdgeInsets.only(bottom: DesktopSpacing.xxxl),
      children: [
        _StatGrid(
          cards: [
            DesktopStatCard(
              icon: Icons.play_circle_outline,
              label: '播放次数',
              value: '${state.totalPlayCount}',
              hint: '累计播放',
            ),
            DesktopStatCard(
              icon: Icons.schedule,
              label: '听歌时长',
              value: formatDesktopTotalDuration(state.totalListenDuration),
              hint: '累计收听',
            ),
            DesktopStatCard(
              icon: Icons.mic_none,
              label: '常听歌手',
              value: topArtist?.label ?? '—',
              hint: topArtist == null ? '暂无数据' : '${topArtist.playCount} 次播放',
            ),
            DesktopStatCard(
              icon: Icons.music_note,
              label: '常听歌曲',
              value: topSong?.songName ?? '—',
              hint: topSong == null ? '暂无数据' : topSong.artistNames,
            ),
            DesktopStatCard(
              icon: Icons.library_music_outlined,
              label: '收录歌曲',
              value: '${state.totalSongCount}',
              hint: '至少播放过一次',
            ),
            DesktopStatCard(
              icon: Icons.calendar_today_outlined,
              label: '活跃天数',
              value: '${state.activeDayCount}',
              hint: '有播放记录的天数',
            ),
          ],
        ),
        if (report.isLoading)
          const Padding(
            padding: EdgeInsets.only(top: DesktopSpacing.md),
            child: LinearProgressIndicator(minHeight: 2),
          ),
        const SizedBox(height: DesktopSpacing.xxxl),
        const DesktopSectionHeader(title: '常听歌手', subtitle: '按累计收听时长排序'),
        if (artists.isEmpty)
          const _EmptyHint(message: '还没有足够的歌手数据')
        else
          _ArtistBars(artists: artists.take(8).toList()),
        const SizedBox(height: DesktopSpacing.xxxl),
        DesktopSectionHeader(
          title: '最近 14 天',
          subtitle: days.isEmpty ? '还没有每日汇总' : '每日播放次数',
        ),
        _DailyBars(days: days),
        const SizedBox(height: DesktopSpacing.xxxl),
        DesktopSectionHeader(
          title: '常听歌曲',
          subtitle: '展示前 ${topSongs.length} 首（共 ${state.allSongs.length} 首）',
        ),
        _TopSongsList(songs: topSongs),
      ],
    );
  }

  Future<void> _confirmClear(
    BuildContext context,
    ListeningStatsNotifier notifier,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('清空听歌统计'),
        content: const Text('将删除全部播放明细与每日汇总，且无法撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await notifier.clear();
    }
  }
}

/// Responsive metric grid: 4 columns on a wide window, 2 on a narrow one.
class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.cards});

  final List<Widget> cards;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = DesktopSpacing.md;
        final width = constraints.maxWidth;
        final columns = width >= 1180
            ? 4
            : width >= 760
            ? 3
            : 2;
        final cardWidth = (width - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final card in cards) SizedBox(width: cardWidth, child: card),
          ],
        );
      },
    );
  }
}

class _ArtistBars extends StatelessWidget {
  const _ArtistBars({required this.artists});

  final List<ListeningStatsDimension> artists;

  @override
  Widget build(BuildContext context) {
    final maxPlays = artists.fold<int>(
      1,
      (value, artist) => artist.playCount > value ? artist.playCount : value,
    );
    return Column(
      children: [
        for (final artist in artists)
          DesktopStatBar(
            label: artist.label,
            fraction: artist.playCount / maxPlays,
            trailing: '${artist.playCount} 次',
          ),
      ],
    );
  }
}

class _DailyBars extends StatelessWidget {
  const _DailyBars({required this.days});

  final List<ListeningStatsDay> days;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (days.isEmpty) {
      return const _EmptyHint(message: '还没有每日汇总');
    }
    final recent = days.length > 14 ? days.sublist(days.length - 14) : days;
    final maxPlays = recent.fold<int>(
      1,
      (value, day) => day.playCount > value ? day.playCount : value,
    );
    return Column(
      children: [
        SizedBox(
          height: 116,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final day in recent)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: DesktopSpacing.xxs + 1,
                    ),
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Container(
                        width: double.infinity,
                        height: 112 * day.playCount / maxPlays,
                        decoration: BoxDecoration(
                          color: scheme.primary.withValues(
                            alpha: day.playCount == 0 ? 0.14 : 0.72,
                          ),
                          borderRadius: const BorderRadius.vertical(
                            top: DesktopRadii.xs,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: DesktopSpacing.xs),
        Row(
          children: [
            for (final day in recent)
              Expanded(
                child: Text(
                  _shortDay(day.day),
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  softWrap: false,
                  textAlign: TextAlign.center,
                  style: DesktopText.caption.copyWith(
                    fontSize: 10,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  String _shortDay(String day) {
    if (day.length == 10) return day.substring(5);
    return day;
  }
}

/// Ranked list for 常听歌曲.
///
/// A plain list rather than the shared song table: these rows are statistics
/// entries rather than playable [Song]s, and the two numeric columns are play
/// count and listened time (the table's columns are album and track length).
class _TopSongsList extends StatelessWidget {
  const _TopSongsList({required this.songs});

  final List<ListeningStatsSongEntry> songs;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: DesktopSpacing.xs),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow.withValues(alpha: 0.55),
        borderRadius: DesktopRadii.lgAll,
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.38),
        ),
      ),
      child: Column(
        children: [
          for (var index = 0; index < songs.length; index++)
            _TopSongRow(rank: index + 1, entry: songs[index]),
        ],
      ),
    );
  }
}

class _TopSongRow extends StatelessWidget {
  const _TopSongRow({required this.rank, required this.entry});

  final int rank;
  final ListeningStatsSongEntry entry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: DesktopSpacing.md,
        vertical: DesktopSpacing.xs + 2,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 26,
            child: Text(
              '$rank',
              style: DesktopText.caption.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: DesktopSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.songName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DesktopText.bodyStrong.copyWith(
                    color: scheme.onSurface,
                  ),
                ),
                Text(
                  entry.artistNames,
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
            width: 92,
            child: Align(
              alignment: Alignment.centerLeft,
              child: DesktopPlatformBadge(platform: entry.platform),
            ),
          ),
          SizedBox(
            width: 64,
            child: Text(
              '${entry.playCount} 次',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: DesktopText.caption.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          SizedBox(
            width: 88,
            child: Text(
              formatDesktopTotalDuration(entry.listenDuration),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: DesktopText.caption.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: DesktopSpacing.md),
      child: Text(
        message,
        style: DesktopText.body.copyWith(color: scheme.onSurfaceVariant),
      ),
    );
  }
}
