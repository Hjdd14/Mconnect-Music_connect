import 'song.dart';

/// A platform chart (榜单) as listed by the platform's "all toplists" endpoint.
///
/// Introduced for the 榜单中心 page so QQ's 热歌榜 (topId 26, 300 tracks) and the
/// other ~29 QQ charts are reachable, instead of the single flat list the app
/// used to hardcode (`topId=4`, which is actually 流行指数榜, not 热歌榜).
class Toplist {
  /// Platform-native chart id, e.g. QQ `topId` (`'26'`), 网易云 playlist id,
  /// 酷狗 `rankid`.
  final String id;

  final String name;

  /// Cover image. QQ exposes `frontPicUrl`/`headPicUrl`, 网易云 `coverImgUrl`,
  /// 酷狗 `imgurl`.
  final String? coverUrl;

  /// Human-readable update cadence, e.g. `每日更新` / `每周更新`
  /// (QQ `updateTips`, 酷狗 `update_frequency`).
  final String? updateFrequency;

  /// Total number of tracks in the chart, when reported.
  final int? songCount;

  /// Chart period, e.g. QQ `2026-10-06` (daily) or `2026_40` (weekly).
  final String? period;

  /// Grouping used by the 榜单中心 page, e.g. QQ `巅峰榜` / `地区榜` /
  /// `特色榜` / `全球榜`.
  final String? groupName;

  /// Chart description / 榜单定义.
  final String? intro;

  const Toplist({
    required this.id,
    required this.name,
    this.coverUrl,
    this.updateFrequency,
    this.songCount,
    this.period,
    this.groupName,
    this.intro,
  });
}

/// A song plus its position inside a chart.
///
/// Charts are rendered from this rather than from `List<Song>` ordering because
/// QQ's 热歌榜 endpoint reports both the current and the previous position, and
/// the UI shows the movement.
class RankedSong {
  final Song song;

  /// 1-based position in the chart.
  final int rank;

  /// Position change since the previous period: positive means the song moved
  /// **up**. QQ reports this as `old_count - cur_count` (verified against the
  /// live 热歌榜 payload). `null` when the platform does not report it.
  final int? rankChange;

  /// Whether the song is new to the chart this period, when reported.
  final bool? isNew;

  /// Raw platform-specific ranking hint (QQ `rankValue` / `Franking_value`).
  final String? rankValue;

  const RankedSong({
    required this.song,
    required this.rank,
    this.rankChange,
    this.isNew,
    this.rankValue,
  });
}
