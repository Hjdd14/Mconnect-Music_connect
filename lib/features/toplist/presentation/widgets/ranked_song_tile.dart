import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/share/song_actions.dart';
import '../../../../models/song.dart';
import '../../../../models/toplist.dart';
import '../../../download/presentation/widgets/download_button.dart';

/// One chart row: 本期名次 + 涨跌箭头 + 歌曲信息.
///
/// The movement badge is the reason [RankedSong] exists: QQ reports each song's
/// previous position, so the chart is not just an ordered list. Long-press opens
/// the shared song-actions menu (下一首播放 / 添加到歌单 / 下载 / 喜欢 / 复制链接 /
/// 分享) — the same menu the playlist pages use, which previously only existed
/// on one screen.
class RankedSongTile extends ConsumerWidget {
  const RankedSongTile({
    super.key,
    required this.ranked,
    required this.accent,
    required this.onTap,
    this.playlist,
    this.index,
  });

  final RankedSong ranked;
  final Color accent;
  final VoidCallback onTap;

  /// The full chart, for "play from here". Falls back to the single song.
  final List<Song>? playlist;
  final int? index;

  Song get song => ranked.song;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      onTap: onTap,
      onLongPress: () => showSongActionsMenu(context, ref, song: song),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      // 名次在左、封面紧随其后。榜单行以前只有那个数字方块，300 首全是
      // "只有名次没有封面"——数据层本来就有封面（网易云 al.picUrl / QQ
      // albummid / 酷狗 trans_param.union_cover），只是这一行没画。
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _RankBadge(rank: ranked.rank, accent: accent),
          const SizedBox(width: 10),
          _ChartCover(song: song, accent: accent),
        ],
      ),
      title: Text(
        song.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 15),
      ),
      subtitle: Text(
        song.album?.name != null && song.album!.name.isNotEmpty
            ? '${song.artistNames} · ${song.album!.name}'
            : song.artistNames,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: cs.outline, fontSize: 12),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          RankMovementBadge(
            rankChange: ranked.rankChange,
            isNew: ranked.isNew,
            rankValue: ranked.rankValue,
          ),
          const SizedBox(width: 4),
          DownloadButton(song: song, size: 22),
        ],
      ),
    );
  }
}

class _RankBadge extends StatelessWidget {
  const _RankBadge({required this.rank, required this.accent});

  final int rank;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final isTop = rank <= 3;
    return Container(
      // 34 (not 38): the cover needs the room, and 3-digit ranks still fit.
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: isTop
            ? accent.withValues(alpha: 0.16)
            : Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      alignment: Alignment.center,
      child: Text(
        '$rank',
        style: TextStyle(
          color: isTop
              ? accent
              : Theme.of(context).colorScheme.onSurfaceVariant,
          fontWeight: isTop ? FontWeight.bold : FontWeight.w500,
          fontSize: 13,
        ),
      ),
    );
  }
}

/// 榜单行的封面：46×46、圆角 6，固定尺寸的占位保证滚动时不跳动。
///
/// 三平台的封面来源不同（网易云 `al.picUrl`、QQ `albummid`、酷狗
/// `trans_param.union_cover`），所以这里只认 `Song.coverUrl`，缺图就落到占位。
class _ChartCover extends StatelessWidget {
  const _ChartCover({required this.song, required this.accent});

  final Song song;
  final Color accent;

  static const double _size = 46;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: _size,
      height: _size,
      color: accent.withValues(alpha: 0.12),
      alignment: Alignment.center,
      child: Icon(Icons.music_note, size: 18, color: accent),
    );
    final url = song.coverUrl;
    return ClipRRect(
      key: const ValueKey('ranked-song-cover'),
      borderRadius: BorderRadius.circular(6),
      child: url == null || url.isEmpty
          ? placeholder
          : CachedNetworkImage(
              imageUrl: url,
              width: _size,
              height: _size,
              // 46 logical pixels at 2x: enough for the row, quarter of the
              // memory a full-size cover would take on a 300-row chart.
              memCacheWidth: 96,
              fit: BoxFit.cover,
              placeholder: (_, _) => placeholder,
              errorWidget: (_, _, _) => placeholder,
            ),
    );
  }
}

/// 涨跌箭头: 正数上升（绿）、负数下降（红）、0 持平（横线）、新上榜（新）.
///
/// `null` movement means the platform did not report a previous position (QQ's
/// score-ordered charts, 网易云/酷狗); a raw `rankValue` such as `11%` is shown
/// instead of inventing an arrow.
class RankMovementBadge extends StatelessWidget {
  const RankMovementBadge({
    super.key,
    required this.rankChange,
    this.isNew,
    this.rankValue,
  });

  final int? rankChange;
  final bool? isNew;
  final String? rankValue;

  @override
  Widget build(BuildContext context) {
    if (isNew == true) {
      return _Badge(
        text: '新',
        color: const Color(0xFF2E9E5B),
        background: const Color(0x1A2E9E5B),
      );
    }

    final change = rankChange;
    if (change == null) {
      final value = rankValue;
      if (value == null || value.isEmpty || value == '0') {
        return const SizedBox(width: 4);
      }
      return Text(
        value,
        style: TextStyle(
          fontSize: 11,
          color: Theme.of(context).colorScheme.outline,
        ),
      );
    }
    if (change == 0) {
      return Text(
        '—',
        style: TextStyle(
          fontSize: 12,
          color: Theme.of(context).colorScheme.outline,
        ),
      );
    }

    final up = change > 0;
    final color = up ? const Color(0xFF2E9E5B) : const Color(0xFFD9534F);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          up ? Icons.arrow_drop_up : Icons.arrow_drop_down,
          color: color,
          size: 20,
        ),
        Text(
          '${change.abs()}',
          style: TextStyle(fontSize: 11, color: color),
        ),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.text,
    required this.color,
    required this.background,
  });

  final String text;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}
