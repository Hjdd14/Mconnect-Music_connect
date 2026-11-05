import 'dart:async';

import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/desktop/desktop_ambient_background.dart';
import '../../../../core/desktop/desktop_empty_state.dart';
import '../../../../core/desktop/desktop_page_scaffold.dart';
import '../../../../core/desktop/desktop_song_table.dart';
import '../../../../core/desktop/desktop_tokens.dart';
import '../../../../core/utils/snackbar_helper.dart';
import '../../../../core/widgets/app_scrollbar.dart';
import '../../../../models/song.dart';
import '../../../download/presentation/widgets/download_button.dart';
import '../../../library/presentation/providers/likes_provider.dart';
import '../providers/player_provider.dart';
import '../widgets/lyrics_display.dart';
import '../widgets/playback_options_sheet.dart';
import '../widgets/quality_bottom_sheet.dart';

/// Immersive desktop now-playing page (`/player`).
///
/// Layout: a fixed "now playing" column (artwork, metadata, seek, transport) and
/// a flexible right side carrying the existing [LyricsDisplay] plus a queue
/// preview. The phone screen's artwork/lyrics toggle is deliberately not
/// reproduced — a desktop window has room for both at once.
class PlayerDesktopPage extends ConsumerStatefulWidget {
  const PlayerDesktopPage({super.key});

  @override
  ConsumerState<PlayerDesktopPage> createState() => _PlayerDesktopPageState();
}

class _PlayerDesktopPageState extends ConsumerState<PlayerDesktopPage> {
  bool _seeking = false;
  double _seekValue = 0;

  void _close() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/');
    }
  }

  void _announcePlaybackError(String? error) {
    if (error == null || error.isEmpty) {
      playbackErrorDeduper.shouldAnnounce(null);
      return;
    }
    if (!playbackErrorDeduper.shouldAnnounce(error)) return;
    showErrorSnackBar(context, error);
  }

  @override
  Widget build(BuildContext context) {
    final song = ref.watch(playerProvider.select((s) => s.currentSong));

    // Shared with the phone player and the desktop player bar, so one failure
    // is announced once rather than once per live player surface.
    ref.listen<String?>(
      playerProvider.select((s) => s.error),
      (previous, next) => _announcePlaybackError(next),
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: DesktopAmbientBackground(
        child: DesktopPageScaffold(
          title: '正在播放',
          subtitle: song == null
              ? '还没有播放歌曲'
              : '${song.name} · ${song.artistNames}',
          leading: IconButton(
            tooltip: '返回',
            onPressed: _close,
            icon: const Icon(Icons.arrow_back, size: 20),
          ),
          actions: [
            if (song != null)
              IconButton(
                tooltip: '播放设置（倍速、跳过静音、歌词校准）',
                onPressed: () => PlaybackOptionsSheet.show(context),
                icon: const Icon(Icons.tune, size: 19),
              ),
            IconButton(
              tooltip: '播放队列',
              onPressed: () => context.push('/queue'),
              icon: const Icon(Icons.queue_music, size: 20),
            ),
            if (song != null) _MoreMenu(song: song),
          ],
          child: song == null
              ? _buildEmpty(context)
              : _buildContent(context, song),
        ),
      ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    return DesktopEmptyState(
      icon: Icons.music_note,
      title: '还没有播放歌曲',
      message: '从发现、搜索或音乐库选择一首歌开始播放',
      action: FilledButton(
        onPressed: () => context.go('/'),
        child: const Text('去发现音乐'),
      ),
    );
  }

  Widget _buildContent(BuildContext context, Song song) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        if (wide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 400,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(
                    right: DesktopSpacing.sm,
                    bottom: DesktopSpacing.lg,
                  ),
                  child: _NowPlayingColumn(
                    song: song,
                    seeking: _seeking,
                    seekValue: _seekValue,
                    onSeekStart: _onSeekStart,
                    onSeekChanged: _onSeekChanged,
                    onSeekEnd: _onSeekEnd,
                  ),
                ),
              ),
              const SizedBox(width: DesktopSpacing.xl),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: DesktopSectionCard(
                        title: '歌词',
                        subtitle: '点击歌词行可以跳转到对应时间',
                        fill: true,
                        child: const Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(top: DesktopSpacing.xs),
                            child: LyricsDisplay(),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: DesktopSpacing.lg),
                    const SizedBox(height: 208, child: _QueuePreview()),
                  ],
                ),
              ),
            ],
          );
        }

        return AppScrollbar(
          builder: (controller) => SingleChildScrollView(
            controller: controller,
            padding: const EdgeInsets.only(
              bottom: DesktopSpacing.xxxl,
              right: DesktopSpacing.xs,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: _NowPlayingColumn(
                      song: song,
                      seeking: _seeking,
                      seekValue: _seekValue,
                      onSeekStart: _onSeekStart,
                      onSeekChanged: _onSeekChanged,
                      onSeekEnd: _onSeekEnd,
                    ),
                  ),
                ),
                const SizedBox(height: DesktopSpacing.xl),
                SizedBox(
                  height: 320,
                  child: DesktopSectionCard(
                    title: '歌词',
                    fill: true,
                    child: const Expanded(child: LyricsDisplay()),
                  ),
                ),
                const SizedBox(height: DesktopSpacing.lg),
                const SizedBox(height: 208, child: _QueuePreview()),
              ],
            ),
          ),
        );
      },
    );
  }

  void _onSeekStart(double value) {
    final duration = ref.read(playerProvider).duration;
    if (duration.inMilliseconds <= 0) return;
    setState(() {
      _seeking = true;
      _seekValue = value * duration.inMilliseconds;
    });
  }

  void _onSeekChanged(double value) {
    final duration = ref.read(playerProvider).duration;
    if (duration.inMilliseconds <= 0) return;
    setState(() => _seekValue = value * duration.inMilliseconds);
  }

  void _onSeekEnd(double value) {
    final duration = ref.read(playerProvider).duration;
    setState(() {
      _seeking = false;
      _seekValue = value * duration.inMilliseconds;
    });
    if (duration.inMilliseconds <= 0) return;
    unawaited(
      ref
          .read(playerProvider.notifier)
          .seek(
            Duration(milliseconds: (value * duration.inMilliseconds).round()),
          ),
    );
  }
}

class _NowPlayingColumn extends ConsumerWidget {
  final Song song;
  final bool seeking;
  final double seekValue;
  final ValueChanged<double> onSeekStart;
  final ValueChanged<double> onSeekChanged;
  final ValueChanged<double> onSeekEnd;

  const _NowPlayingColumn({
    required this.song,
    required this.seeking,
    required this.seekValue,
    required this.onSeekStart,
    required this.onSeekChanged,
    required this.onSeekEnd,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final isPlaying = ref.watch(playerProvider.select((s) => s.isPlaying));
    final isTransitioning = ref.watch(
      playerProvider.select((s) => s.isTransitioning),
    );
    final isShuffle = ref.watch(playerProvider.select((s) => s.isShuffle));
    final repeatMode = ref.watch(playerProvider.select((s) => s.repeatMode));
    final quality = ref.watch(playerProvider.select((s) => s.currentQuality));
    final position = ref.watch(playerProvider.select((s) => s.position));
    final duration = ref.watch(playerProvider.select((s) => s.duration));
    final sourcePlatform = ref.watch(
      playerProvider.select((s) => s.sourcePlatform),
    );
    final liked = ref.watch(
      likesProvider.select(
        (s) => s.songs.any(
          (item) => item.id == song.id && item.platform == song.platform,
        ),
      ),
    );
    final notifier = ref.read(playerProvider.notifier);

    final totalMs = duration.inMilliseconds > 0
        ? duration.inMilliseconds.toDouble()
        : 1.0;
    final shownPosition = seeking
        ? Duration(milliseconds: seekValue.round())
        : position;
    final progress = (shownPosition.inMilliseconds / totalMs).clamp(0.0, 1.0);
    final hasDuration = duration.inMilliseconds > 0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final size = constraints.maxWidth.clamp(180.0, 320.0);
              return AnimatedSwitcher(
                duration: DesktopDurations.panel,
                child: Container(
                  key: ValueKey<String>('${song.platform.name}-${song.id}'),
                  decoration: BoxDecoration(
                    borderRadius: DesktopRadii.xlAll,
                    boxShadow: DesktopShadows.floating,
                  ),
                  child: DesktopCoverArt(
                    url: song.coverUrl,
                    size: size,
                    radius: 18,
                    icon: Icons.album,
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: DesktopSpacing.xl),
        Text(
          song.name,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: DesktopText.headline.copyWith(color: scheme.onSurface),
        ),
        const SizedBox(height: DesktopSpacing.xs),
        Text(
          song.artistNames,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: DesktopText.body.copyWith(color: scheme.onSurfaceVariant),
        ),
        if (song.album?.name != null && song.album!.name.trim().isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            song.album!.name,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: DesktopText.caption.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
        const SizedBox(height: DesktopSpacing.md),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: DesktopSpacing.sm,
          runSpacing: DesktopSpacing.xs,
          children: [
            InkWell(
              borderRadius: DesktopRadii.smAll,
              onTap: () => showQualitySheet(context),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: DesktopSpacing.sm,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.1),
                  borderRadius: DesktopRadii.smAll,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.equalizer, size: 13, color: scheme.primary),
                    const SizedBox(width: 4),
                    Text(
                      quality.displayNameFor(song.platform),
                      style: DesktopText.caption.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Icon(
                      Icons.keyboard_arrow_down,
                      size: 14,
                      color: scheme.primary,
                    ),
                  ],
                ),
              ),
            ),
            if (sourcePlatform != null && sourcePlatform != song.platform)
              DesktopStatusPill(
                label: '已换源 · 来自 ${sourcePlatform.displayName}',
                color: scheme.tertiary,
                icon: Icons.swap_horiz,
              ),
            IconButton(
              tooltip: liked ? '取消喜欢' : '喜欢',
              onPressed: () =>
                  unawaited(ref.read(likesProvider.notifier).toggleLike(song)),
              icon: Icon(
                liked ? Icons.favorite : Icons.favorite_border,
                size: 19,
                color: liked ? scheme.error : scheme.onSurfaceVariant,
              ),
            ),
            DownloadButton(song: song, size: 20),
          ],
        ),
        const SizedBox(height: DesktopSpacing.md),
        Slider(
          value: progress,
          onChangeStart: hasDuration ? onSeekStart : null,
          onChanged: hasDuration ? onSeekChanged : null,
          onChangeEnd: hasDuration ? onSeekEnd : null,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: DesktopSpacing.sm),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                formatDesktopClock(shownPosition),
                style: DesktopText.caption.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              Text(
                hasDuration ? formatDesktopDuration(duration) : '--:--',
                style: DesktopText.caption.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: DesktopSpacing.sm),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            IconButton(
              tooltip: '随机播放',
              onPressed: notifier.toggleShuffle,
              icon: Icon(
                Icons.shuffle,
                size: 20,
                color: isShuffle ? scheme.primary : scheme.onSurfaceVariant,
              ),
            ),
            IconButton(
              tooltip: '上一首',
              onPressed: notifier.skipToPrevious,
              icon: const Icon(Icons.skip_previous, size: 30),
            ),
            _PlayButton(
              isPlaying: isPlaying,
              isTransitioning: isTransitioning,
              onPressed: notifier.togglePlay,
            ),
            IconButton(
              tooltip: '下一首',
              onPressed: notifier.skipToNext,
              icon: const Icon(Icons.skip_next, size: 30),
            ),
            IconButton(
              tooltip: '循环模式',
              onPressed: notifier.cycleRepeatMode,
              icon: Icon(
                repeatMode == RepeatMode.one ? Icons.repeat_one : Icons.repeat,
                size: 20,
                color: repeatMode == RepeatMode.off
                    ? scheme.onSurfaceVariant
                    : scheme.primary,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _PlayButton extends StatelessWidget {
  final bool isPlaying;
  final bool isTransitioning;
  final VoidCallback onPressed;

  const _PlayButton({
    required this.isPlaying,
    required this.isTransitioning,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: isPlaying ? '暂停' : '播放',
      child: SizedBox(
        width: 56,
        height: 56,
        child: Material(
          color: scheme.primary,
          shape: const CircleBorder(),
          elevation: 2,
          child: InkWell(
            customBorder: const CircleBorder(),
            mouseCursor: SystemMouseCursors.click,
            onTap: onPressed,
            child: Center(
              child: isTransitioning
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: scheme.onPrimary,
                      ),
                    )
                  : Icon(
                      isPlaying ? Icons.pause : Icons.play_arrow,
                      size: 30,
                      color: scheme.onPrimary,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The next few tracks of the queue, with a link to the full queue page.
class _QueuePreview extends ConsumerWidget {
  const _QueuePreview();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final queue = ref.watch(playerProvider.select((s) => s.playlist));
    final currentIndex = ref.watch(
      playerProvider.select((s) => s.currentIndex),
    );
    final notifier = ref.read(playerProvider.notifier);

    final start = currentIndex < 0 ? 0 : currentIndex + 1;
    final upcoming = <int>[
      for (var i = start; i < queue.length && i < start + 20; i++) i,
    ];

    Widget body;
    if (queue.isEmpty) {
      body = Center(
        child: Text(
          '队列是空的',
          style: DesktopText.caption.copyWith(color: scheme.onSurfaceVariant),
        ),
      );
    } else if (upcoming.isEmpty) {
      body = Center(
        child: Text(
          '已经到队列最后一首',
          style: DesktopText.caption.copyWith(color: scheme.onSurfaceVariant),
        ),
      );
    } else {
      body = ListView.builder(
        padding: EdgeInsets.zero,
        itemCount: upcoming.length,
        itemBuilder: (context, index) {
          final queueIndex = upcoming[index];
          final song = queue[queueIndex];
          return InkWell(
            borderRadius: DesktopRadii.smAll,
            hoverColor: scheme.onSurface.withValues(alpha: 0.05),
            onTap: () => unawaited(notifier.playAtIndex(queueIndex)),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: DesktopSpacing.xs,
                vertical: 5,
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 22,
                    child: Text(
                      '${queueIndex + 1}',
                      style: DesktopText.caption.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      song.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DesktopText.caption.copyWith(
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                  const SizedBox(width: DesktopSpacing.sm),
                  Flexible(
                    flex: 2,
                    child: Text(
                      song.artistNames,
                      maxLines: 1,
                      textAlign: TextAlign.right,
                      overflow: TextOverflow.ellipsis,
                      style: DesktopText.caption.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: DesktopSpacing.sm),
                  Text(
                    formatDesktopDuration(song.duration),
                    style: DesktopText.caption.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    }

    return DesktopSectionCard(
      title: '接下来播放',
      subtitle: queue.isEmpty ? null : '共 ${queue.length} 首',
      trailing: TextButton(
        onPressed: () => context.push('/queue'),
        child: const Text('查看全部'),
      ),
      fill: true,
      child: Expanded(child: body),
    );
  }
}

class _MoreMenu extends ConsumerWidget {
  final Song song;

  const _MoreMenu({required this.song});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      tooltip: '更多',
      icon: const Icon(Icons.more_horiz, size: 20),
      onSelected: (value) {
        switch (value) {
          case 'options':
            unawaited(PlaybackOptionsSheet.show(context));
            break;
          case 'queue':
            context.push('/queue');
            break;
          case 'add_to_queue':
            ref.read(playerProvider.notifier).addToQueue(song);
            showSuccessSnackBar(context, '已加入播放队列');
            break;
          case 'copy':
            unawaited(
              Clipboard.setData(
                ClipboardData(text: '${song.artistNames} - ${song.name}'),
              ),
            );
            showSuccessSnackBar(context, '已复制歌曲信息');
            break;
        }
      },
      itemBuilder: (context) => const [
        PopupMenuItem(value: 'options', child: Text('播放设置')),
        PopupMenuItem(value: 'queue', child: Text('打开播放队列')),
        PopupMenuItem(value: 'add_to_queue', child: Text('加入播放队列')),
        PopupMenuItem(value: 'copy', child: Text('复制歌曲信息')),
      ],
    );
  }
}
