import 'dart:async';

import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/download/presentation/widgets/download_button.dart';
import '../../features/library/presentation/providers/likes_provider.dart';
import '../../features/player/presentation/providers/player_provider.dart';
import '../../features/player/presentation/widgets/playback_options_sheet.dart';
import '../../features/player/presentation/widgets/quality_bottom_sheet.dart';
import '../../models/audio_quality.dart';
import '../../models/song.dart';
import '../utils/snackbar_helper.dart';
import 'desktop_network_image.dart';
import 'desktop_panel_provider.dart';
import 'desktop_shell_policy.dart';
import 'desktop_tokens.dart';

class DesktopPlayerBar extends ConsumerStatefulWidget {
  final bool compact;

  const DesktopPlayerBar({super.key, this.compact = false});

  @override
  ConsumerState<DesktopPlayerBar> createState() => _DesktopPlayerBarState();
}

class _DesktopPlayerBarState extends ConsumerState<DesktopPlayerBar> {
  bool _seeking = false;
  double _seekValue = 0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final song = ref.watch(playerProvider.select((s) => s.currentSong));
    final isPlaying = ref.watch(playerProvider.select((s) => s.isPlaying));
    final isTransitioning = ref.watch(
      playerProvider.select((s) => s.isTransitioning),
    );
    final position = ref.watch(playerProvider.select((s) => s.position));
    final duration = ref.watch(playerProvider.select((s) => s.duration));
    final quality = ref.watch(playerProvider.select((s) => s.currentQuality));
    final isShuffle = ref.watch(playerProvider.select((s) => s.isShuffle));
    final repeatMode = ref.watch(playerProvider.select((s) => s.repeatMode));
    final liked = ref.watch(
      likesProvider.select(
        (s) => song == null
            ? false
            : s.songs.any(
                (item) => item.id == song.id && item.platform == song.platform,
              ),
      ),
    );
    final notifier = ref.read(playerProvider.notifier);
    final isNarrow =
        MediaQuery.sizeOf(context).width < DesktopShellPolicy.mediumBreakpoint;

    final shownPosition = _seeking
        ? Duration(milliseconds: _seekValue.round())
        : position;
    final totalMs = duration.inMilliseconds > 0
        ? duration.inMilliseconds.toDouble()
        : 1.0;
    final progress = (shownPosition.inMilliseconds / totalMs).clamp(0.0, 1.0);

    return Container(
      height: widget.compact
          ? DesktopShellPolicy.playerBarCompactHeight
          : DesktopShellPolicy.playerBarHeight,
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.92),
        border: Border(
          top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.45)),
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: DesktopSpacing.md),
          _Cover(
            song: song,
            onTap: song == null ? null : () => _openPlayer(context),
          ),
          const SizedBox(width: DesktopSpacing.md),
          SizedBox(
            width: isNarrow ? 150 : 200,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  song?.name ?? '未在播放',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DesktopText.bodyStrong.copyWith(
                    color: song == null
                        ? scheme.onSurfaceVariant
                        : scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  song?.artistNames ?? '选择一首歌开始',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DesktopText.caption.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: DesktopSpacing.sm),
          if (song != null)
            IconButton(
              tooltip: liked ? '取消喜欢' : '喜欢',
              onPressed: () =>
                  unawaited(ref.read(likesProvider.notifier).toggleLike(song)),
              icon: Icon(
                liked ? Icons.favorite : Icons.favorite_border,
                size: 18,
                color: liked ? scheme.error : scheme.onSurfaceVariant,
              ),
            ),
          const SizedBox(width: DesktopSpacing.sm),
          IconButton(
            tooltip: '随机',
            onPressed: notifier.toggleShuffle,
            icon: Icon(
              Icons.shuffle,
              size: 18,
              color: isShuffle ? scheme.primary : scheme.onSurfaceVariant,
            ),
          ),
          IconButton(
            tooltip: '上一首',
            onPressed: notifier.skipToPrevious,
            icon: const Icon(Icons.skip_previous, size: 22),
          ),
          _PlayButton(
            isPlaying: isPlaying,
            isTransitioning: isTransitioning,
            enabled: song != null,
            onPressed: notifier.togglePlay,
          ),
          IconButton(
            tooltip: '下一首',
            onPressed: notifier.skipToNext,
            icon: const Icon(Icons.skip_next, size: 22),
          ),
          IconButton(
            tooltip: '循环',
            onPressed: notifier.cycleRepeatMode,
            icon: Icon(
              repeatMode == RepeatMode.one ? Icons.repeat_one : Icons.repeat,
              size: 18,
              color: repeatMode == RepeatMode.off
                  ? scheme.onSurfaceVariant
                  : scheme.primary,
            ),
          ),
          const SizedBox(width: DesktopSpacing.sm),
          Expanded(
            child: Row(
              children: [
                Text(
                  _format(shownPosition),
                  style: DesktopText.caption.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: DesktopSpacing.sm),
                Expanded(
                  child: Slider(
                    value: progress,
                    onChangeStart: duration.inMilliseconds <= 0
                        ? null
                        : (value) => setState(() {
                            _seeking = true;
                            _seekValue = value * totalMs;
                          }),
                    onChanged: duration.inMilliseconds <= 0
                        ? null
                        : (value) =>
                              setState(() => _seekValue = value * totalMs),
                    onChangeEnd: duration.inMilliseconds <= 0
                        ? null
                        : (value) {
                            final target = Duration(
                              milliseconds: value.round(),
                            );
                            setState(() {
                              _seeking = false;
                              _seekValue = target.inMilliseconds.toDouble();
                            });
                            unawaited(notifier.seek(target));
                          },
                  ),
                ),
                const SizedBox(width: DesktopSpacing.sm),
                Text(
                  _format(duration),
                  style: DesktopText.caption.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (!isNarrow) ...[
            const SizedBox(width: DesktopSpacing.sm),
            _QualityChip(quality: quality, song: song),
          ],
          IconButton(
            tooltip: '歌词',
            onPressed: () {
              if (isNarrow) {
                context.push('/player');
              } else {
                ref.read(desktopPanelTabProvider.notifier).state =
                    DesktopPanelTab.lyrics;
              }
            },
            icon: const Icon(Icons.lyrics_outlined, size: 19),
          ),
          IconButton(
            tooltip: '播放队列',
            onPressed: () {
              if (isNarrow) {
                context.push('/queue');
              } else {
                ref.read(desktopPanelTabProvider.notifier).state =
                    DesktopPanelTab.queue;
              }
            },
            icon: const Icon(Icons.queue_music, size: 20),
          ),
          if (song != null) DownloadButton(song: song),
          _MoreMenu(song: song),
          const SizedBox(width: DesktopSpacing.sm),
        ],
      ),
    );
  }

  void _openPlayer(BuildContext context) {
    context.push('/player');
  }

  String _format(Duration value) {
    final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

class _Cover extends StatelessWidget {
  final Song? song;
  final VoidCallback? onTap;

  const _Cover({required this.song, this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: DesktopRadii.smAll,
        child: SizedBox(
          width: 52,
          height: 52,
          child: song?.coverUrl != null
              ? DesktopNetworkImage(
                  url: song!.coverUrl!,
                  cacheWidth: 160,
                  placeholder: _placeholder(scheme),
                  error: _placeholder(scheme),
                )
              : _placeholder(scheme),
        ),
      ),
    );
  }

  Widget _placeholder(ColorScheme scheme) {
    return ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: Icon(Icons.music_note, size: 22, color: scheme.onSurfaceVariant),
    );
  }
}

class _PlayButton extends StatelessWidget {
  final bool isPlaying;
  final bool isTransitioning;
  final bool enabled;
  final VoidCallback onPressed;

  const _PlayButton({
    required this.isPlaying,
    required this.isTransitioning,
    required this.enabled,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: DesktopSpacing.xs),
      child: SizedBox(
        width: 36,
        height: 36,
        child: Material(
          color: enabled ? scheme.primary : scheme.surfaceContainerHighest,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: enabled ? onPressed : null,
            child: Center(
              child: isTransitioning
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: scheme.onPrimary,
                      ),
                    )
                  : Icon(
                      isPlaying ? Icons.pause : Icons.play_arrow,
                      size: 22,
                      color: enabled
                          ? scheme.onPrimary
                          : scheme.onSurfaceVariant,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _QualityChip extends StatelessWidget {
  final AudioLevel quality;
  final Song? song;

  const _QualityChip({required this.quality, required this.song});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = song == null
        ? quality.displayName
        : quality.displayNameFor(song!.platform);
    return Tooltip(
      message: '切换音质',
      child: InkWell(
        onTap: song == null ? null : () => showQualitySheet(context),
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
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.equalizer, size: 13, color: scheme.primary),
              const SizedBox(width: 4),
              Text(
                label,
                style: DesktopText.caption.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MoreMenu extends ConsumerWidget {
  final Song? song;

  const _MoreMenu({required this.song});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      tooltip: '更多',
      icon: const Icon(Icons.more_horiz, size: 20),
      onSelected: (value) {
        switch (value) {
          case 'player':
            context.push('/player');
            break;
          case 'options':
            PlaybackOptionsSheet.show(context);
            break;
          case 'queue':
            if (song != null) {
              ref.read(playerProvider.notifier).addToQueue(song!);
              showSuccessSnackBar(context, '已加入播放队列');
            }
            break;
          case 'copy':
            if (song != null) {
              Clipboard.setData(
                ClipboardData(text: '${song!.artistNames} - ${song!.name}'),
              );
              showSuccessSnackBar(context, '已复制歌曲信息');
            }
            break;
        }
      },
      itemBuilder: (context) => const [
        PopupMenuItem(value: 'player', child: Text('打开播放页')),
        PopupMenuItem(value: 'options', child: Text('播放设置')),
        PopupMenuItem(value: 'queue', child: Text('加入播放队列')),
        PopupMenuItem(value: 'copy', child: Text('复制歌曲信息')),
      ],
    );
  }
}
