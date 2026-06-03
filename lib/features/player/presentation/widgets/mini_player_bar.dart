import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../../core/diagnostics/diagnostics_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../providers/player_provider.dart';

class MiniPlayerBar extends ConsumerWidget {
  const MiniPlayerBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final song = ref.watch(playerProvider.select((s) => s.currentSong));
    final isPlaying = ref.watch(playerProvider.select((s) => s.isPlaying));

    if (song == null) return const SizedBox.shrink();

    final position = ref.watch(playerProvider.select((s) => s.position));
    final duration = ref.watch(playerProvider.select((s) => s.duration));

    return GestureDetector(
      onTap: () {
        final from = GoRouterState.of(context).uri.toString();
        DiagnosticsService.instance.record(
          'navigation',
          'open_player_from_mini',
          data: {
            'from': from,
            'song_id': song.id,
            'platform': song.platform.name,
          },
        );
        context.push(
          Uri(path: '/player', queryParameters: {'from': from}).toString(),
        );
      },
      child: Container(
        height: 64,
        decoration: BoxDecoration(
          color: Theme.of(
            context,
          ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.92),
          boxShadow: [
            BoxShadow(
              color: Theme.of(context).shadowColor.withValues(alpha: 0.08),
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Column(
          children: [
            LinearProgressIndicator(
              value: duration.inMilliseconds > 0
                  ? position.inMilliseconds / duration.inMilliseconds
                  : 0,
              minHeight: 2,
              backgroundColor: Colors.transparent,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: song.coverUrl != null
                          ? CachedNetworkImage(
                              imageUrl: song.coverUrl!,
                              width: 44,
                              height: 44,
                              memCacheWidth: 88,
                              fit: BoxFit.cover,
                              placeholder: (_, __) => Container(
                                width: 44,
                                height: 44,
                                color: AppColors.placeholder(context),
                                child: const Icon(Icons.music_note, size: 20),
                              ),
                              errorWidget: (_, __, ___) => Container(
                                width: 44,
                                height: 44,
                                color: AppColors.placeholder(context),
                                child: const Icon(Icons.music_note, size: 20),
                              ),
                            )
                          : Container(
                              width: 44,
                              height: 44,
                              color: AppColors.placeholder(context),
                              child: const Icon(Icons.music_note, size: 20),
                            ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            song.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Text(
                            song.artistNames,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).colorScheme.outline,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.skip_previous, size: 28),
                      onPressed: ref
                          .read(playerProvider.notifier)
                          .skipToPrevious,
                    ),
                    IconButton(
                      icon: Icon(
                        isPlaying
                            ? Icons.pause_circle_filled
                            : Icons.play_circle_filled,
                        size: 36,
                      ),
                      onPressed: ref.read(playerProvider.notifier).togglePlay,
                    ),
                    IconButton(
                      icon: const Icon(Icons.skip_next, size: 28),
                      onPressed: ref.read(playerProvider.notifier).skipToNext,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
