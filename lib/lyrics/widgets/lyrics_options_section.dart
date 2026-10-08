import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../lyrics_display_settings.dart';

/// Removes the lyrics-cache rows that are past their TTL and returns how many
/// went. Injected instead of imported so this widget stays inside `lib/lyrics`
/// without depending on the player feature (the sheet passes
/// `lyricsCachePurgeProvider`).
typedef LyricsCachePurge = Future<int> Function();

/// W2-A 批次 3：播放页歌词控件（三态 / 字号 / 行距 / 缓存清理入口）。
///
/// 独立成 widget 而不是塞进 `playback_options_sheet.dart` 内部：
/// * 该 sheet 自己的注释写明它"不是播放列"是为了不动 `player_screen.dart` 的
///   `_nonLyricsColumnHeight` 契约，把控件留在一个独立 widget 里让这条契约更容易守；
/// * 这些用例因此不必拉起整个播放器（`playerProvider` + 音频控制器）。
class LyricsOptionsSection extends ConsumerWidget {
  const LyricsOptionsSection({
    super.key,
    required this.purge,
    required this.cacheTtlDays,
  });

  final LyricsCachePurge purge;

  /// Cache lifetime in days, shown in the hint next to the purge entry.
  ///
  /// Injected for the same reason as [purge]: the value lives in the player
  /// feature, and `lib/lyrics` must not depend on it.
  final int cacheTtlDays;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(lyricsDisplayModeProvider);
    final typography = ref.watch(lyricsTypographyProvider);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            const Expanded(child: Text('歌词')),
            _ResetTypographyButton(typography: typography),
          ],
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          children: [
            for (final value in LyricsDisplayMode.values)
              ChoiceChip(
                label: Text(value.displayName),
                selected: mode == value,
                onSelected: (_) =>
                    ref.read(lyricsDisplayModeProvider.notifier).setMode(value),
              ),
          ],
        ),
        const SizedBox(height: 12),
        _StepperRow(
          label: '字号',
          value: '${typography.fontSize.round()}',
          decreaseKey: const Key('lyrics-font-smaller'),
          increaseKey: const Key('lyrics-font-larger'),
          enabledDecrease: typography.fontSize > LyricsTypography.minFontSize,
          enabledIncrease: typography.fontSize < LyricsTypography.maxFontSize,
          onDecrease: () => ref
              .read(lyricsTypographyProvider.notifier)
              .adjustFontSize(-LyricsTypography.fontStep),
          onIncrease: () => ref
              .read(lyricsTypographyProvider.notifier)
              .adjustFontSize(LyricsTypography.fontStep),
        ),
        _StepperRow(
          label: '行距',
          value: typography.lineHeight.toStringAsFixed(1),
          decreaseKey: const Key('lyrics-line-height-smaller'),
          increaseKey: const Key('lyrics-line-height-larger'),
          enabledDecrease:
              typography.lineHeight > LyricsTypography.minLineHeight + 1e-9,
          enabledIncrease:
              typography.lineHeight < LyricsTypography.maxLineHeight - 1e-9,
          onDecrease: () => ref
              .read(lyricsTypographyProvider.notifier)
              .adjustLineHeight(-LyricsTypography.lineHeightStep),
          onIncrease: () => ref
              .read(lyricsTypographyProvider.notifier)
              .adjustLineHeight(LyricsTypography.lineHeightStep),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: Text(
                // 天数由调用方喂进来：`lyricsCacheTtl` 住在播放 feature 里，
                // 从这里 import 它会让 `lib/lyrics` 反向依赖播放页。
                '歌词缓存超过 $cacheTtlDays 天后会自动重新获取',
                style: TextStyle(fontSize: 12, color: theme.colorScheme.outline),
              ),
            ),
            TextButton(
              key: const Key('lyrics-cache-purge'),
              onPressed: () => _runPurge(context),
              child: const Text('清理歌词缓存'),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _runPurge(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    String message;
    try {
      final removed = await purge();
      message = removed == 0 ? '没有需要清理的歌词缓存' : '已清理 $removed 首歌词缓存';
    } catch (e) {
      message = '歌词缓存清理失败';
    }
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _ResetTypographyButton extends ConsumerWidget {
  const _ResetTypographyButton({required this.typography});

  final LyricsTypography typography;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const defaults = LyricsTypography();
    if (typography == defaults) return const SizedBox.shrink();
    return TextButton(
      key: const Key('lyrics-typography-reset'),
      onPressed: () => ref.read(lyricsTypographyProvider.notifier).reset(),
      child: const Text('恢复默认'),
    );
  }
}

class _StepperRow extends StatelessWidget {
  const _StepperRow({
    required this.label,
    required this.value,
    required this.decreaseKey,
    required this.increaseKey,
    required this.enabledDecrease,
    required this.enabledIncrease,
    required this.onDecrease,
    required this.onIncrease,
  });

  final String label;
  final String value;
  final Key decreaseKey;
  final Key increaseKey;
  final bool enabledDecrease;
  final bool enabledIncrease;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(label)),
        IconButton(
          key: decreaseKey,
          onPressed: enabledDecrease ? onDecrease : null,
          icon: const Icon(Icons.remove),
          tooltip: '$label减小',
        ),
        SizedBox(
          width: 40,
          child: Text(value, textAlign: TextAlign.center),
        ),
        IconButton(
          key: increaseKey,
          onPressed: enabledIncrease ? onIncrease : null,
          icon: const Icon(Icons.add),
          tooltip: '$label增大',
        ),
      ],
    );
  }
}
