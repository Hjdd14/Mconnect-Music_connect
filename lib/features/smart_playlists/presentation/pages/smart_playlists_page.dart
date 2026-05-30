import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/widgets/app_scrollbar.dart';
import '../../../player/presentation/providers/player_provider.dart';
import '../../domain/smart_playlist_rule.dart';
import '../providers/smart_playlist_preview_provider.dart';
import '../providers/smart_playlists_provider.dart';

class SmartPlaylistsPage extends ConsumerWidget {
  const SmartPlaylistsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(smartPlaylistsProvider);
    final notifier = ref.read(smartPlaylistsProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('智能歌单'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
            onPressed: notifier.load,
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '新建规则',
            onPressed: () => context.push('/smart-playlists/editor'),
          ),
        ],
      ),
      body: _SmartPlaylistsBody(state: state),
    );
  }
}

class _SmartPlaylistsBody extends ConsumerWidget {
  final SmartPlaylistsState state;

  const _SmartPlaylistsBody({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (state.isLoading && state.rules.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.error != null && state.rules.isEmpty) {
      return Center(
        child: Text(
          state.error!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      );
    }
    if (state.rules.isEmpty) {
      return Center(
        child: Text(
          '暂无智能歌单',
          style: TextStyle(color: Theme.of(context).colorScheme.outline),
        ),
      );
    }

    return AppScrollbar(
      builder: (controller) => ListView.builder(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
        itemCount: state.rules.length,
        itemBuilder: (context, index) {
          final rule = state.rules[index];
          final songs = ref.watch(smartPlaylistPreviewProvider(rule));
          return Card(
            margin: const EdgeInsets.symmetric(vertical: 6),
            child: ListTile(
              leading: const Icon(Icons.auto_awesome),
              title: Text(rule.name),
              subtitle: Text('${songs.length} 首 · ${_ruleSummary(rule)}'),
              trailing: PopupMenuButton<String>(
                tooltip: '规则操作',
                onSelected: (value) {
                  switch (value) {
                    case 'edit':
                      context.push('/smart-playlists/editor?id=${rule.id}');
                      break;
                    case 'play':
                      if (songs.isNotEmpty) {
                        unawaited(
                          ref.read(playerProvider.notifier).playPlaylist(songs),
                        );
                      }
                      break;
                    case 'delete':
                      unawaited(
                        ref
                            .read(smartPlaylistsProvider.notifier)
                            .deleteRule(rule.id),
                      );
                      break;
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: 'play',
                    child: ListTile(
                      leading: Icon(Icons.play_arrow),
                      title: Text('播放'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'edit',
                    child: ListTile(
                      leading: Icon(Icons.edit_outlined),
                      title: Text('编辑规则'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: ListTile(
                      leading: Icon(Icons.delete_outline),
                      title: Text('删除'),
                    ),
                  ),
                ],
              ),
              onTap: () =>
                  context.push('/smart-playlists/editor?id=${rule.id}'),
            ),
          );
        },
      ),
    );
  }

  String _ruleSummary(SmartPlaylistRule rule) {
    final items = <String>[];
    if (rule.platforms.isNotEmpty) {
      items.add(rule.platforms.map((p) => p.displayName).join('/'));
    }
    if (rule.keyword.isNotEmpty) items.add('关键词 ${rule.keyword}');
    if (rule.minPlayCount > 0) items.add('播放>=${rule.minPlayCount}');
    if (rule.recentlyPlayedDays > 0) {
      items.add('${rule.recentlyPlayedDays}天内');
    }
    if (rule.likedOnly) items.add('红心');
    if (rule.cachedOnly) items.add('已缓存');
    return items.isEmpty ? '全部本地记录' : items.join(' · ');
  }
}
