import 'package:flutter/material.dart';

import '../../models/platform_type.dart';
import '../../models/song.dart';
import '../theme/platform_accent.dart';
import '../widgets/app_scrollbar.dart';
import 'desktop_empty_state.dart';
import 'desktop_network_image.dart';
import 'desktop_section_header.dart';
import 'desktop_tokens.dart';

/// Column keys shared by every desktop song table.
///
/// The pages own the sorting (it is local data), so the header only needs to
/// know which column the page is currently sorting by.
abstract final class DesktopSongColumn {
  DesktopSongColumn._();

  static const String title = 'title';
  static const String artist = 'artist';
  static const String album = 'album';
  static const String platform = 'platform';
  static const String duration = 'duration';
}

/// Fixed geometry for the song table, kept in one place so the header and every
/// row cannot drift apart by a few pixels (which is exactly what happens when
/// the two are laid out with duplicated magic numbers).
abstract final class DesktopSongTableMetrics {
  DesktopSongTableMetrics._();

  static const double indexWidth = 30;
  static const double coverSize = 36;
  static const double platformWidth = 74;
  static const double durationWidth = 56;
  static const double actionsWidth = 84;
  static const double rowHeight = 54;
  static const double horizontalPadding = DesktopSpacing.sm;

  /// Below this width the album column is dropped instead of squeezed to
  /// nothing: it is the least important column and the title needs the space.
  static const double albumBreakpoint = 720;
}

/// `03:45`; an unknown length renders as `--:--` rather than `00:00`, which
/// would claim the track is empty.
String formatDesktopDuration(Duration value) {
  if (value <= Duration.zero) return '--:--';
  final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
  final hours = value.inHours;
  return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
}

/// `00:00` — always a clock, never a dash. Used for the playback position,
/// where zero is a real value rather than an unknown length.
String formatDesktopClock(Duration value) {
  final clamped = value.isNegative ? Duration.zero : value;
  final minutes = clamped.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = clamped.inSeconds.remainder(60).toString().padLeft(2, '0');
  final hours = clamped.inHours;
  return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
}

/// `2 小时 13 分` / `45 分` — the queue summary wording, shared by both desktop
/// pages that show a total.
String formatDesktopTotalDuration(Duration total) {
  if (total <= Duration.zero) return '0 分';
  final hours = total.inHours;
  final minutes = total.inMinutes.remainder(60);
  if (hours > 0) return '$hours 小时 $minutes 分';
  return '$minutes 分';
}

/// `1.4 MB` / `812 KB` / `930 B`.
String formatDesktopBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

/// Sorts [songs] by one of the [DesktopSongColumn] keys.
///
/// Pure and copied-on-write, so a page can sort without touching the provider's
/// list order (the aggregated search state owns the platform-priority order).
List<Song> sortDesktopSongs(
  List<Song> songs, {
  String? key,
  bool ascending = true,
}) {
  final sorted = List<Song>.from(songs);
  int compare(Song a, Song b) {
    final result = switch (key) {
      DesktopSongColumn.artist => a.artistNames.toLowerCase().compareTo(
        b.artistNames.toLowerCase(),
      ),
      DesktopSongColumn.album => (a.album?.name ?? '').toLowerCase().compareTo(
        (b.album?.name ?? '').toLowerCase(),
      ),
      DesktopSongColumn.platform => a.platform.index.compareTo(
        b.platform.index,
      ),
      DesktopSongColumn.duration => a.duration.compareTo(b.duration),
      _ => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    };
    if (result != 0) return ascending ? result : -result;
    // Stable tie-break so equal names do not reshuffle on every rebuild.
    return a.id.compareTo(b.id);
  }

  sorted.sort(compare);
  return sorted;
}

/// Whether [row] is the track the player is currently on.
bool isSameDesktopSong(Song row, Song? current) =>
    current != null && row.id == current.id && row.platform == current.platform;

/// Cover thumbnail used by every row, card and hero on the desktop pages.
class DesktopCoverArt extends StatelessWidget {
  final String? url;
  final double size;
  final double radius;
  final IconData icon;

  const DesktopCoverArt({
    super.key,
    this.url,
    this.size = DesktopSongTableMetrics.coverSize,
    this.radius = 8,
    this.icon = Icons.music_note,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasImage = url != null && url!.trim().isNotEmpty;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: size,
        height: size,
        child: hasImage
            ? DesktopNetworkImage(
                url: url!,
                cacheWidth: (size * 2).round(),
                placeholder: _placeholder(scheme),
                error: _placeholder(scheme),
              )
            : _placeholder(scheme),
      ),
    );
  }

  Widget _placeholder(ColorScheme scheme) {
    return ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: Icon(icon, size: size * 0.45, color: scheme.onSurfaceVariant),
    );
  }
}

/// Small platform tag. The mobile list uses a two-character abbreviation to fit
/// a phone row; a desktop row has the room (and the width is fixed in
/// [DesktopSongTableMetrics]) to show the real service name.
class DesktopPlatformBadge extends StatelessWidget {
  final PlatformType platform;
  final bool compact;

  const DesktopPlatformBadge({
    super.key,
    required this.platform,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final accent = PlatformAccent.neutralColorOf(platform);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.13),
        borderRadius: DesktopRadii.smAll,
      ),
      child: Text(
        compact ? platform.displayName.substring(0, 2) : platform.displayName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: DesktopText.caption.copyWith(
          fontSize: 10.5,
          height: 1.3,
          fontWeight: FontWeight.w600,
          color: accent,
        ),
      ),
    );
  }
}

/// Coloured status pill (`下载中` / `已完成` / `失败` …).
class DesktopStatusPill extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;

  const DesktopStatusPill({
    super.key,
    required this.label,
    required this.color,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: DesktopRadii.smAll,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 3),
          ],
          Text(
            label,
            style: DesktopText.caption.copyWith(
              fontSize: 11,
              height: 1.3,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Header row of a desktop song list. Clicking a sortable cell reports the
/// column key; the page decides what order that means.
class DesktopSongTableHeader extends StatelessWidget {
  final bool showAlbum;
  final String? sortKey;
  final bool sortAscending;
  final void Function(String key)? onSort;

  /// Label for the right-most (actions) column. `null` renders no label but
  /// still reserves the space, so rows keep their column alignment.
  final String? actionsLabel;

  const DesktopSongTableHeader({
    super.key,
    this.showAlbum = true,
    this.sortKey,
    this.sortAscending = true,
    this.onSort,
    this.actionsLabel,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        DesktopSongTableMetrics.horizontalPadding,
        DesktopSpacing.xs,
        DesktopSongTableMetrics.horizontalPadding,
        DesktopSpacing.xs,
      ),
      child: Row(
        children: [
          const SizedBox(width: DesktopSongTableMetrics.indexWidth),
          const SizedBox(width: DesktopSpacing.sm),
          const SizedBox(width: DesktopSongTableMetrics.coverSize),
          const SizedBox(width: DesktopSpacing.md),
          Expanded(
            flex: 4,
            child: _HeaderCell(
              label: '标题',
              columnKey: DesktopSongColumn.title,
              sortKey: sortKey,
              sortAscending: sortAscending,
              onSort: onSort,
            ),
          ),
          if (showAlbum) ...[
            const SizedBox(width: DesktopSpacing.md),
            Expanded(
              flex: 3,
              child: _HeaderCell(
                label: '专辑',
                columnKey: DesktopSongColumn.album,
                sortKey: sortKey,
                sortAscending: sortAscending,
                onSort: onSort,
              ),
            ),
          ],
          const SizedBox(width: DesktopSpacing.sm),
          SizedBox(
            width: DesktopSongTableMetrics.platformWidth,
            child: _HeaderCell(
              label: '平台',
              columnKey: DesktopSongColumn.platform,
              sortKey: sortKey,
              sortAscending: sortAscending,
              onSort: onSort,
            ),
          ),
          SizedBox(
            width: DesktopSongTableMetrics.durationWidth,
            child: _HeaderCell(
              label: '时长',
              columnKey: DesktopSongColumn.duration,
              sortKey: sortKey,
              sortAscending: sortAscending,
              onSort: onSort,
              alignEnd: true,
            ),
          ),
          SizedBox(
            width: DesktopSongTableMetrics.actionsWidth,
            child: Align(
              alignment: Alignment.centerRight,
              child: actionsLabel == null
                  ? const SizedBox.shrink()
                  : Text(
                      actionsLabel!,
                      style: DesktopText.caption.copyWith(
                        color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  final String label;
  final String? columnKey;
  final String? sortKey;
  final bool sortAscending;
  final void Function(String key)? onSort;
  final bool alignEnd;

  const _HeaderCell({
    required this.label,
    this.columnKey,
    this.sortKey,
    this.sortAscending = true,
    this.onSort,
    this.alignEnd = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final active = columnKey != null && columnKey == sortKey;
    final sortable = columnKey != null && onSort != null;
    final child = Row(
      mainAxisAlignment: alignEnd
          ? MainAxisAlignment.end
          : MainAxisAlignment.start,
      children: [
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: DesktopText.caption.copyWith(
              color: active ? scheme.primary : scheme.onSurfaceVariant,
              fontWeight: active ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
        if (sortable && active) ...[
          const SizedBox(width: 2),
          Icon(
            sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
            size: 12,
            color: scheme.primary,
          ),
        ],
      ],
    );

    if (!sortable) return child;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onSort!(columnKey!),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: child,
        ),
      ),
    );
  }
}

/// One dense song row: index / cover / title+artist / album / platform /
/// duration / caller-owned trailing actions.
///
/// Public because the queue page needs the exact same row *inside* a
/// [ReorderableListView], where the table wrapper's own scroll view cannot be
/// used.
class DesktopSongRow extends StatefulWidget {
  final Song song;
  final int index;
  final bool isCurrent;
  final bool showAlbum;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;

  /// Right-aligned actions. The area is fixed-width so the duration column
  /// stays aligned even when a row shows fewer actions than its neighbour.
  final List<Widget> trailing;

  final String? albumLabel;

  const DesktopSongRow({
    super.key,
    required this.song,
    required this.index,
    this.isCurrent = false,
    this.showAlbum = true,
    this.onTap,
    this.onDoubleTap,
    this.trailing = const <Widget>[],
    this.albumLabel,
  });

  @override
  State<DesktopSongRow> createState() => _DesktopSongRowState();
}

class _DesktopSongRowState extends State<DesktopSongRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final song = widget.song;
    final album = widget.albumLabel ?? song.album?.name ?? '—';
    return MouseRegion(
      onEnter: (_) {
        if (!_hovered) setState(() => _hovered = true);
      },
      onExit: (_) {
        if (_hovered) setState(() => _hovered = false);
      },
      child: Material(
        color: widget.isCurrent
            ? scheme.primary.withValues(alpha: 0.1)
            : Colors.transparent,
        borderRadius: DesktopRadii.smAll,
        child: InkWell(
          onTap: widget.onTap,
          onDoubleTap: widget.onDoubleTap,
          borderRadius: DesktopRadii.smAll,
          mouseCursor: widget.onTap == null
              ? MouseCursor.defer
              : SystemMouseCursors.click,
          hoverColor: scheme.onSurface.withValues(alpha: 0.05),
          child: SizedBox(
            height: DesktopSongTableMetrics.rowHeight,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: DesktopSongTableMetrics.horizontalPadding,
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: DesktopSongTableMetrics.indexWidth,
                    child: Center(child: _indexBadge(scheme)),
                  ),
                  const SizedBox(width: DesktopSpacing.sm),
                  DesktopCoverArt(url: song.coverUrl),
                  const SizedBox(width: DesktopSpacing.md),
                  Expanded(
                    flex: 4,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          song.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: DesktopText.bodyStrong.copyWith(
                            color: widget.isCurrent
                                ? scheme.primary
                                : scheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 1),
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
                  if (widget.showAlbum) ...[
                    const SizedBox(width: DesktopSpacing.md),
                    Expanded(
                      flex: 3,
                      child: Text(
                        album,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DesktopText.caption.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(width: DesktopSpacing.sm),
                  SizedBox(
                    width: DesktopSongTableMetrics.platformWidth,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: DesktopPlatformBadge(platform: song.platform),
                    ),
                  ),
                  SizedBox(
                    width: DesktopSongTableMetrics.durationWidth,
                    child: Text(
                      formatDesktopDuration(song.duration),
                      textAlign: TextAlign.right,
                      style: DesktopText.caption.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: DesktopSongTableMetrics.actionsWidth,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: widget.trailing,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _indexBadge(ColorScheme scheme) {
    if (widget.isCurrent) {
      return Icon(Icons.graphic_eq, size: 16, color: scheme.primary);
    }
    if (_hovered && widget.onTap != null) {
      return Icon(Icons.play_arrow, size: 18, color: scheme.onSurface);
    }
    return Text(
      '${widget.index + 1}',
      style: DesktopText.caption.copyWith(color: scheme.onSurfaceVariant),
    );
  }
}

/// Scrollable, dense song list with a sortable header.
///
/// [onPlay] receives the index *inside the list passed in*, so callers hand in
/// the sorted list and can play straight from it.
class DesktopSongTable extends StatelessWidget {
  final List<Song> songs;
  final Song? currentSong;
  final void Function(int index)? onPlay;
  final List<Widget> Function(Song song, int index)? trailingBuilder;
  final String? sortKey;
  final bool sortAscending;
  final void Function(String key)? onSort;
  final Widget? emptyState;
  final Widget? footer;
  final String? actionsLabel;

  /// Optional per-row album text (the library uses it to show the listened
  /// time in the "最近播放" column instead of the album).
  final String? Function(Song song)? albumLabelBuilder;

  const DesktopSongTable({
    super.key,
    required this.songs,
    this.currentSong,
    this.onPlay,
    this.trailingBuilder,
    this.sortKey,
    this.sortAscending = true,
    this.onSort,
    this.emptyState,
    this.footer,
    this.actionsLabel,
    this.albumLabelBuilder,
  });

  @override
  Widget build(BuildContext context) {
    if (songs.isEmpty) {
      return emptyState ??
          const DesktopEmptyState(
            icon: Icons.music_note,
            title: '这里还没有歌曲',
            message: '播放或喜欢一些歌曲后会出现在这里',
          );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final showAlbum =
            constraints.maxWidth >= DesktopSongTableMetrics.albumBreakpoint;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DesktopSongTableHeader(
              showAlbum: showAlbum,
              sortKey: sortKey,
              sortAscending: sortAscending,
              onSort: onSort,
              actionsLabel: actionsLabel,
            ),
            const Divider(height: 1),
            Expanded(
              child: AppScrollbar(
                builder: (controller) => ListView.builder(
                  controller: controller,
                  padding: const EdgeInsets.symmetric(
                    vertical: DesktopSpacing.xs,
                  ),
                  itemCount: songs.length + (footer == null ? 0 : 1),
                  itemBuilder: (context, index) {
                    if (index >= songs.length) return footer!;
                    final song = songs[index];
                    return DesktopSongRow(
                      key: ValueKey(
                        'song-${song.platform.name}-${song.id}-$index',
                      ),
                      song: song,
                      index: index,
                      isCurrent: isSameDesktopSong(song, currentSong),
                      showAlbum: showAlbum,
                      albumLabel: albumLabelBuilder?.call(song),
                      onTap: onPlay == null ? null : () => onPlay!(index),
                      onDoubleTap: onPlay == null ? null : () => onPlay!(index),
                      trailing:
                          trailingBuilder?.call(song, index) ??
                          const <Widget>[],
                    );
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Card used to group a section of a desktop page (active downloads, lyrics …).
class DesktopSectionCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;
  final EdgeInsetsGeometry padding;

  /// When true the card fills its incoming height and its child may use
  /// [Expanded] (the now-playing page uses this for the lyrics panel).
  final bool fill;

  const DesktopSectionCard({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    required this.child,
    this.fill = false,
    this.padding = const EdgeInsets.fromLTRB(
      DesktopSpacing.lg,
      DesktopSpacing.md,
      DesktopSpacing.lg,
      DesktopSpacing.md,
    ),
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow.withValues(alpha: 0.5),
        borderRadius: DesktopRadii.lgAll,
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min,
        children: [
          DesktopSectionHeader(
            title: title,
            subtitle: subtitle,
            trailing: trailing,
          ),
          child,
        ],
      ),
    );
  }
}

/// A tab of [DesktopTabStrip].
class DesktopTabItem<T> {
  final T value;
  final String label;

  /// Rendered in parentheses after the label when non-null.
  final int? count;
  final IconData? icon;

  const DesktopTabItem({
    required this.value,
    required this.label,
    this.count,
    this.icon,
  });
}

/// Pill tab strip used instead of a Material [TabBar], which brings a phone-era
/// indicator and 48 dp touch targets that look wrong on a desktop toolbar.
class DesktopTabStrip<T> extends StatelessWidget {
  final List<DesktopTabItem<T>> tabs;
  final T selected;
  final ValueChanged<T> onSelected;

  const DesktopTabStrip({
    super.key,
    required this.tabs,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: DesktopSpacing.xs,
      runSpacing: DesktopSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final tab in tabs)
          Material(
            color: tab.value == selected
                ? scheme.primary.withValues(alpha: 0.14)
                : Colors.transparent,
            borderRadius: DesktopRadii.smAll,
            child: InkWell(
              borderRadius: DesktopRadii.smAll,
              hoverColor: scheme.onSurface.withValues(alpha: 0.05),
              onTap: () => onSelected(tab.value),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: DesktopSpacing.md,
                  vertical: 6,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (tab.icon != null) ...[
                      Icon(
                        tab.icon,
                        size: 15,
                        color: tab.value == selected
                            ? scheme.primary
                            : scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 5),
                    ],
                    Text(
                      tab.count == null
                          ? tab.label
                          : '${tab.label} ${tab.count}',
                      style: DesktopText.caption.copyWith(
                        fontSize: 13,
                        color: tab.value == selected
                            ? scheme.primary
                            : scheme.onSurfaceVariant,
                        fontWeight: tab.value == selected
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Compact "label + value" chip for a page's stat row.
class DesktopInfoChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const DesktopInfoChip({super.key, required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DesktopSpacing.sm,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh.withValues(alpha: 0.5),
        borderRadius: DesktopRadii.smAll,
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: scheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(
            label,
            style: DesktopText.caption.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// Centred spinner for a page region that is loading for the first time.
class DesktopInlineLoading extends StatelessWidget {
  final String? label;

  const DesktopInlineLoading({super.key, this.label});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          if (label != null) ...[
            const SizedBox(height: DesktopSpacing.md),
            Text(
              label!,
              style: DesktopText.caption.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Centred failure with a retry action, for pages that own a "reload" callback.
class DesktopInlineError extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const DesktopInlineError({super.key, required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(DesktopSpacing.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 28, color: scheme.error),
              const SizedBox(height: DesktopSpacing.md),
              Text(
                message,
                textAlign: TextAlign.center,
                style: DesktopText.body.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              if (onRetry != null) ...[
                const SizedBox(height: DesktopSpacing.md),
                OutlinedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('重试'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
