import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../lyrics_display_settings.dart';
import '../models/lyrics_line.dart';

/// 分享卡片的固定尺寸（逻辑像素）。固定尺寸让"截图 → PNG"可预期，也让不同
/// 机型上分享出去的图长一个样。
const Size lyricsShareCardSize = Size(720, 960);

/// 卡片上一次显示多少行歌词（超出部分按当前行居中裁）。
const int lyricsShareCardLineCount = 12;

/// 分享用的歌词卡片：歌名 / 歌手 / 来源 + 当前附近的几句词。
///
/// 纯展示 widget，无状态、无 provider：截图流程把它临时挂进 Overlay 就能拍。
/// 三态复用 [displayLineFor]，所以"仅译文"模式下分享出去的也是译文。
class LyricsShareCard extends StatelessWidget {
  const LyricsShareCard({
    super.key,
    required this.title,
    required this.artists,
    this.source = LyricsSource.unknown,
    this.lines = const [],
    this.activeIndex = -1,
    this.mode = LyricsDisplayMode.bilingual,
  });

  final String title;
  final String artists;
  final LyricsSource source;
  final List<LyricsLine> lines;

  /// 当前唱到第几行（-1 = 从头显示）。
  final int activeIndex;

  final LyricsDisplayMode mode;

  /// 卡片上实际画出来的那几行（当前行居中，上下各留若干）。
  List<LyricsLine> get visibleLines => window.lines;

  /// The drawn slice plus the active line's index **inside that slice**.
  ///
  /// Computed once per build: comparing against the whole list would need the
  /// slice's start offset, and the preview window is the only place that knows it.
  ({List<LyricsLine> lines, int activeIndex}) get window {
    if (lines.isEmpty) return (lines: const <LyricsLine>[], activeIndex: -1);
    final count = lyricsShareCardLineCount;
    final clampedActive = activeIndex.clamp(0, lines.length - 1);
    if (lines.length <= count) {
      return (
        lines: lines,
        activeIndex: activeIndex < 0 ? -1 : clampedActive,
      );
    }
    var start = activeIndex < 0 ? 0 : clampedActive - count ~/ 2;
    if (start + count > lines.length) start = lines.length - count;
    if (start < 0) start = 0;
    return (
      lines: lines.sublist(start, start + count),
      activeIndex: activeIndex < 0 ? -1 : clampedActive - start,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final window = this.window;
    final visible = window.lines;

    return SizedBox(
      width: lyricsShareCardSize.width,
      height: lyricsShareCardSize.height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [colors.surface, colors.surfaceContainerHighest],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(48, 44, 48, 36),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title.trim().isEmpty ? '未知歌曲' : title.trim(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.bold,
                        color: colors.onSurface,
                      ),
                    ),
                  ),
                  if (source.isKnown)
                    Padding(
                      padding: const EdgeInsets.only(left: 12),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: colors.primary.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          child: Text(
                            source.displayName,
                            style: TextStyle(
                              fontSize: 18,
                              color: colors.primary,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                artists.trim().isEmpty ? '未知歌手' : artists.trim(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 22, color: colors.outline),
              ),
              const SizedBox(height: 28),
              Expanded(
                child: visible.isEmpty
                    ? Center(
                        child: Text(
                          '暂无歌词',
                          style: TextStyle(fontSize: 24, color: colors.outline),
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.start,
                        children: [
                          for (var i = 0; i < visible.length; i++)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 14),
                              child: _CardLine(
                                line: visible[i],
                                mode: mode,
                                isActive: i == window.activeIndex,
                                colors: colors,
                              ),
                            ),
                        ],
                      ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Text(
                    AppConstants.appName,
                    style: TextStyle(
                      fontSize: 18,
                      color: colors.outline,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CardLine extends StatelessWidget {
  const _CardLine({
    required this.line,
    required this.mode,
    required this.isActive,
    required this.colors,
  });

  final LyricsLine line;
  final LyricsDisplayMode mode;
  final bool isActive;
  final ColorScheme colors;

  @override
  Widget build(BuildContext context) {
    final displayed = displayLineFor(line, mode);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          displayed.text,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: isActive ? 30 : 26,
            height: 1.3,
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
            color: isActive ? colors.primary : colors.onSurface,
          ),
        ),
        if (displayed.hasTranslation)
          Text(
            displayed.translation!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 22,
              height: 1.3,
              color: colors.outline,
            ),
          ),
      ],
    );
  }
}
