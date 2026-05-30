import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../models/audio_quality.dart';
import '../providers/player_provider.dart';
import '../providers/quality_provider.dart';

/// Bottom sheet for selecting audio quality.
void showQualitySheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => const QualityBottomSheet(),
  );
}

class QualityBottomSheet extends ConsumerWidget {
  const QualityBottomSheet({super.key});

  String _bitrateLabel(AudioQuality q) {
    if (q.isLossless) return '无损';
    final kbps = q.bitrate ~/ 1000;
    return '${kbps}kbps';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentQuality = ref.watch(
      playerProvider.select((s) => s.currentQuality),
    );
    final song = ref.watch(playerProvider.select((s) => s.currentSong));
    final qualitiesAsync = ref.watch(availableQualitiesProvider);

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Title
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    '音质选择',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                if (song != null)
                  Text(
                    song.name,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Quality list
          qualitiesAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            error: (_, __) => Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                '加载失败',
                style: TextStyle(color: Theme.of(context).colorScheme.outline),
              ),
            ),
            data: (qualities) {
              if (qualities.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    '暂无可用音质',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                );
              }

              final highestLevel = qualities
                  .map((q) => q.level)
                  .reduce((a, b) => a.index >= b.index ? a : b);

              return ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: qualities.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final q = qualities[index];
                  final isSelected = q.level == currentQuality;

                  return ListTile(
                    leading: Icon(
                      isSelected
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      color: isSelected
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.outline,
                      size: 20,
                    ),
                    title: Text(
                      song == null
                          ? q.level.displayName
                          : q.level.displayNameFor(song.platform),
                      style: TextStyle(
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: isSelected
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                    ),
                    subtitle: Text(
                      '${_bitrateLabel(q)} · ${q.format.toUpperCase()}',
                      style: TextStyle(
                        fontSize: 12,
                        color: isSelected
                            ? Theme.of(
                                context,
                              ).colorScheme.primary.withValues(alpha: 0.7)
                            : Theme.of(context).colorScheme.outline,
                      ),
                    ),
                    trailing: q.isLossless
                        ? Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Theme.of(
                                context,
                              ).colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'Hi-Fi',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          )
                        : null,
                    onTap: () {
                      final playerNotifier = ref.read(playerProvider.notifier);
                      Navigator.pop(context);
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        playerNotifier.switchQuality(
                          q.level,
                          preferHighest: q.level == highestLevel,
                        );
                      });
                    },
                  );
                },
              );
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
