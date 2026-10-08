import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../lyrics/widgets/lyrics_options_section.dart';
import '../providers/lyrics_offset_provider.dart';
import '../providers/lyrics_provider.dart';
import '../providers/player_provider.dart';

/// Playback extras: speed, A-B loop, skip-silence and lyrics calibration.
///
/// Deliberately a bottom sheet instead of more controls in the player column:
/// `player_screen.dart` reserves a hard-coded `_nonLyricsColumnHeight` that five
/// viewport tests (600/700/736/780/840 dp) pin down, so adding rows there means
/// recomputing it. A sheet cannot break that contract.
class PlaybackOptionsSheet extends ConsumerWidget {
  const PlaybackOptionsSheet({super.key});

  static const List<double> speedOptions = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => const PlaybackOptionsSheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.watch(playerProvider);
    final notifier = ref.read(playerProvider.notifier);
    final lyricsOffset = ref.watch(lyricsOffsetProvider);
    final offsetNotifier = ref.read(lyricsOffsetProvider.notifier);
    final supportsSpeed = notifier.supportsPlaybackSpeed;
    final supportsSkipSilence = notifier.supportsSkipSilence;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '播放设置',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Expanded(child: Text('倍速')),
                if (!supportsSpeed)
                  Text(
                    '当前后端不支持',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.outline,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              children: [
                for (final speed in speedOptions)
                  ChoiceChip(
                    label: Text(speed == 1.0 ? '原速' : '${speed}x'),
                    selected: (player.playbackSpeed - speed).abs() < 0.001,
                    onSelected: supportsSpeed
                        ? (_) => notifier.setPlaybackSpeed(speed)
                        : null,
                  ),
              ],
            ),
            const Divider(height: 32),
            const Text('A-B 循环'),
            const SizedBox(height: 4),
            Text(
              'A ${_formatDuration(player.abLoopStart)} · '
              'B ${_formatDuration(player.abLoopEnd)}',
              style: TextStyle(
                color: Theme.of(context).colorScheme.outline,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton(
                  onPressed: () => notifier.setAbLoopStart(),
                  child: const Text('设 A'),
                ),
                OutlinedButton(
                  onPressed: () => notifier.setAbLoopEnd(),
                  child: const Text('设 B'),
                ),
                TextButton(
                  onPressed: player.abLoopStart == null &&
                          player.abLoopEnd == null
                      ? null
                      : notifier.clearAbLoop,
                  child: const Text('清除'),
                ),
              ],
            ),
            const Divider(height: 32),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('跳过静音'),
              subtitle: Text(
                supportsSkipSilence ? '自动略过歌曲中的无声片段' : '当前后端不支持',
                style: const TextStyle(fontSize: 12),
              ),
              value: player.skipSilence,
              onChanged: supportsSkipSilence
                  ? (value) => notifier.setSkipSilence(value)
                  : null,
            ),
            const Divider(height: 24),
            const Text('歌词偏移'),
            const SizedBox(height: 4),
            Row(
              children: [
                IconButton(
                  tooltip: '提前 0.5 秒',
                  onPressed: () => offsetNotifier.adjust(lyricsOffsetStep),
                  icon: const Icon(Icons.remove),
                ),
                Expanded(
                  child: Text(
                    _formatOffset(lyricsOffset),
                    textAlign: TextAlign.center,
                  ),
                ),
                IconButton(
                  tooltip: '延后 0.5 秒',
                  onPressed: () => offsetNotifier.adjust(-lyricsOffsetStep),
                  icon: const Icon(Icons.add),
                ),
                TextButton(
                  onPressed: lyricsOffset == Duration.zero
                      ? null
                      : offsetNotifier.reset,
                  child: const Text('归零'),
                ),
              ],
            ),
            Text(
              '歌词比人声慢时点「+」，快时点「−」，范围 ±5 秒。',
              style: TextStyle(
                color: Theme.of(context).colorScheme.outline,
                fontSize: 12,
              ),
            ),
            const Divider(height: 32),
            // 三态 / 字号 / 行距 / 缓存清理（W2-A）。独立 widget：这些控件不碰
            // player 状态，放在独立文件里也让它们可单独测。TTL 天数与清理回调都
            // 从播放 feature 注入，`lib/lyrics` 因此不反向依赖本 feature。
            LyricsOptionsSection(
              purge: purgeExpiredLyricsCache,
              cacheTtlDays: lyricsCacheTtl.inDays,
            ),
          ],
        ),
      ),
    );
  }

  static String _formatDuration(Duration? value) {
    if (value == null) return '未设置';
    final minutes = value.inMinutes;
    final seconds = value.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  static String _formatOffset(Duration offset) {
    if (offset == Duration.zero) return '无偏移';
    final sign = offset.isNegative ? '-' : '+';
    final absolute = offset.abs();
    final seconds = absolute.inMilliseconds / 1000;
    return '$sign${seconds.toStringAsFixed(1)} 秒';
  }
}
