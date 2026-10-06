import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:collection/collection.dart';
import 'dart:async';
import '../../../../models/audio_quality.dart';
import '../../../../models/song.dart';
import '../../../../models/user.dart';
import '../../../../platform/base/platform_registry.dart';
import '../../domain/entities/download_task.dart';
import '../providers/download_provider.dart';

/// A button that initiates song download with quality selection.
class DownloadButton extends ConsumerWidget {
  final Song song;
  final double size;

  const DownloadButton({super.key, required this.song, this.size = 24});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloadState = ref.watch(downloadProvider);
    final notifier = ref.read(downloadProvider.notifier);

    // Check if any version of this song is downloading
    final activeTask = downloadState.tasks
        .where(
          (t) =>
              t.song.id == song.id &&
              t.song.platform == song.platform &&
              (t.status == DownloadStatus.downloading ||
                  t.status == DownloadStatus.waiting),
        )
        .firstOrNull;

    final completedTask = downloadState.tasks
        .where(
          (t) =>
              t.song.id == song.id &&
              t.song.platform == song.platform &&
              t.status == DownloadStatus.completed,
        )
        .firstOrNull;

    if (activeTask != null) {
      // Currently downloading — show progress
      return SizedBox(
        width: size + 8,
        height: size + 8,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CircularProgressIndicator(
              value: activeTask.progress,
              strokeWidth: 2,
            ),
            IconButton(
              icon: Icon(Icons.pause, size: size * 0.7),
              padding: EdgeInsets.zero,
              constraints: BoxConstraints.tightFor(width: size, height: size),
              onPressed: () => notifier.pauseDownload(activeTask.id),
            ),
          ],
        ),
      );
    }

    if (completedTask != null) {
      // Already downloaded
      return Icon(
        Icons.download_done,
        size: size,
        color: Theme.of(context).colorScheme.tertiary,
      );
    }

    // Not downloaded — show download button. Long-press adds the song to the
    // offline-cache queue: `cacheSongs` had no caller anywhere in `lib/`, so the
    // queue could not be filled from the UI at all.
    //
    // Deliberately an `InkWell` rather than an `IconButton` wrapped in a
    // `GestureDetector`: the IconButton's tap recogniser wins the gesture arena
    // and the parent long-press never fires. One InkWell owns both gestures.
    return Tooltip(
      message: '下载（长按加入离线缓存）',
      child: InkWell(
        onTap: () => _showQualityPicker(context, ref),
        onLongPress: () => unawaited(_addToOfflineCache(context, ref)),
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: size + 8,
          height: size + 8,
          child: Icon(Icons.file_download_outlined, size: size),
        ),
      ),
    );
  }

  /// Adds [song] to the offline-cache queue at standard quality.
  Future<void> _addToOfflineCache(BuildContext context, WidgetRef ref) async {
    final notifier = ref.read(downloadProvider.notifier);
    final report = await notifier.cacheSongs([song], quality: AudioLevel.low);
    if (!context.mounted) return;

    final String message;
    if (report.blockedOfflineMode > 0) {
      message = '离线模式已开启，已加入缓存队列但不会自动开始';
    } else if (report.blockedNoConnection > 0) {
      message = '已加入离线缓存队列，将在连接 Wi-Fi 后开始';
    } else if (report.blockedQueuePaused > 0) {
      message = '已加入离线缓存队列，队列当前已暂停';
    } else if (report.enqueued > 0) {
      message = '已加入离线缓存：${song.name}';
    } else {
      message = '该歌曲已在缓存列表中';
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  void _showQualityPicker(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      // The nearest navigator is the shell's nested one, which is now full-screen so
      // routed pages can paint to the bottom edge. A sheet pushed there would be
      // laid out under the floating chrome (the mini player, and the nav capsule on
      // the home tabs). The root navigator puts it above the whole shell, which is
      // what a modal sheet should cover.
      useRootNavigator: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return SafeArea(
          child: FutureBuilder<List<AudioQuality>>(
            future: _loadQualities(),
            builder: (context, snapshot) {
              final qualities = snapshot.data ?? const <AudioQuality>[];
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(top: 12, bottom: 8),
                    decoration: BoxDecoration(
                      color: cs.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Text(
                      '选择下载音质 - ${song.name}',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Divider(height: 1),
                  if (snapshot.connectionState == ConnectionState.waiting)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: qualities.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final quality = qualities[index];
                          return ListTile(
                            leading: Icon(
                              quality.isLossless
                                  ? Icons.album
                                  : quality.level == AudioLevel.low
                                  ? Icons.music_note
                                  : Icons.high_quality,
                              size: 20,
                            ),
                            title: Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    quality.level.displayNameFor(song.platform),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (quality.isVipOnly ||
                                    quality.isSvipOnly) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 1,
                                    ),
                                    decoration: BoxDecoration(
                                      color: cs.primaryContainer,
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                    child: Text(
                                      quality.isSvipOnly ? '需 SVIP' : '需 VIP',
                                      style: TextStyle(
                                        fontSize: 9,
                                        color: cs.primary,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            subtitle: Text(_qualitySubtitle(quality)),
                            onTap: () =>
                                _startDownload(ctx, ref, quality.level),
                          );
                        },
                      ),
                    ),
                  const SizedBox(height: 8),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Future<List<AudioQuality>> _loadQualities() async {
    try {
      final platform = PlatformRegistry.get(song.platform);
      final qualities = await platform
          .getAvailableQualities(song.id)
          .timeout(const Duration(seconds: 8));
      if (qualities.isNotEmpty) return qualities;
    } catch (_) {
      // Fallback below keeps download usable when a provider quality probe fails.
    }
    return const [
      AudioQuality(level: AudioLevel.low, bitrate: 128000, format: 'mp3'),
      AudioQuality(level: AudioLevel.medium, bitrate: 320000, format: 'mp3'),
      AudioQuality(level: AudioLevel.lossless, bitrate: 999000, format: 'flac'),
    ];
  }

  String _qualitySubtitle(AudioQuality quality) {
    if (quality.isLossless && quality.bitrate <= 0) {
      return '${quality.format.toUpperCase()} · 无损音质';
    }
    if (quality.bitrate <= 0) return quality.format.toUpperCase();
    final kbps = quality.bitrate ~/ 1000;
    return '$kbps kbps · ${quality.format.toUpperCase()}';
  }

  Future<void> _startDownload(
    BuildContext context,
    WidgetRef ref,
    AudioLevel quality,
  ) async {
    Navigator.pop(context);
    final notifier = ref.read(downloadProvider.notifier);

    // Check VIP
    final allowed = await notifier.checkVipForDownload(song, quality);
    if (!allowed && context.mounted) {
      final required = notifier.requiredVipLevel(quality);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '需要${required == VipLevel.svip ? "超级会员" : "VIP"}才能下载${quality.displayNameFor(song.platform)}音质',
          ),
          action: SnackBarAction(
            label: '用标准音质',
            onPressed: () => notifier.startDownload(song, AudioLevel.low),
          ),
        ),
      );
      return;
    }

    // Awaited: `startDownload` returns once the task is in the queue, so the
    // snackbar below is only shown for a download that was really enqueued.
    await notifier.startDownload(song, quality);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '已开始下载: ${song.name} (${quality.displayNameFor(song.platform)})',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }}
