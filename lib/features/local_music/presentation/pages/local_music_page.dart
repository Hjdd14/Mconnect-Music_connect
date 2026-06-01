import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/app_scrollbar.dart';
import '../../../player/presentation/providers/player_provider.dart';
import '../providers/local_music_provider.dart';

class LocalMusicPage extends ConsumerWidget {
  const LocalMusicPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(localMusicProvider);
    final notifier = ref.read(localMusicProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('本地音乐'),
        actions: [
          IconButton(
            icon: const Icon(Icons.folder_open),
            onPressed: state.isScanning ? null : notifier.pickAndScanDirectory,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    state.selectedDirectory ?? '尚未选择文件夹',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.outline,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: state.isScanning
                      ? null
                      : notifier.pickAndScanDirectory,
                  icon: const Icon(Icons.folder),
                  label: const Text('选择文件夹'),
                ),
              ],
            ),
          ),
          if (state.isScanning) const LinearProgressIndicator(minHeight: 2),
          if (state.error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                state.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          Expanded(
            child: state.songs.isEmpty
                ? _EmptyLocalMusic(isScanning: state.isScanning)
                : AppScrollbar(
                    builder: (controller) => ListView.builder(
                      controller: controller,
                      padding: const EdgeInsets.only(bottom: 8),
                      itemCount: state.songs.length,
                      itemBuilder: (context, index) {
                        final song = state.songs[index];
                        final hasLyrics = state.lyricsBySongId.containsKey(
                          song.id,
                        );
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Theme.of(
                              context,
                            ).colorScheme.primaryContainer,
                            child: const Icon(Icons.music_note),
                          ),
                          title: Text(
                            song.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            hasLyrics ? '已匹配歌词' : song.id,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: const Icon(Icons.play_arrow),
                          onTap: () {
                            ref
                                .read(playerProvider.notifier)
                                .playPlaylist(state.songs, startIndex: index);
                          },
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _EmptyLocalMusic extends StatelessWidget {
  final bool isScanning;

  const _EmptyLocalMusic({required this.isScanning});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.library_music_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
            const SizedBox(height: 16),
            Text(
              isScanning ? '正在扫描本地音乐' : '选择一个文件夹开始扫描本地音乐',
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
          ],
        ),
      ),
    );
  }
}
