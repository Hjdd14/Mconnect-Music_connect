import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/widgets/app_scrollbar.dart';
import '../../../../models/song.dart';
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

    return Column(
      children: [
        // The old page only showed `error` when the rule list was empty, so a
        // failed save/delete on a populated list was completely silent.
        if (state.error != null)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              state.error!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
            ),
          ),
        if (state.isSaving)
          const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: AppScrollbar(
            builder: (controller) => ListView.builder(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
              itemCount: state.rules.length,
              itemBuilder: (context, index) =>
                  _ruleCard(context, ref, state, index),
            ),
          ),
        ),
      ],
    );
  }

  Widget _ruleCard(
    BuildContext context,
    WidgetRef ref,
    SmartPlaylistsState state,
    int index,
  ) {
    final rule = state.rules[index];
    final songs = ref.watch(smartPlaylistPreviewProvider(rule));
    final saved = state.snapshotFor(rule.id);
    return Card(
            margin: const EdgeInsets.symmetric(vertical: 6),
            child: ListTile(
              leading: const Icon(Icons.auto_awesome),
              title: Text(rule.name),
              subtitle: Text(
                '${songs.length} 首 · ${_ruleSummary(rule)}'
                '${saved == null ? '' : '\n已保存 ${saved.songs.length} 首'
                    '（${_formatSavedAt(saved.generatedAt)}）'}',
              ),
              isThreeLine: saved != null,
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
                    case 'save':
                      unawaited(_saveSnapshot(context, ref, rule.id, songs));
                      break;
                    case 'playSaved':
                      if (saved != null && saved.songs.isNotEmpty) {
                        unawaited(
                          ref
                              .read(playerProvider.notifier)
                              .playPlaylist(saved.songs),
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
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'play',
                    child: ListTile(
                      leading: Icon(Icons.play_arrow),
                      title: Text('播放'),
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'save',
                    child: ListTile(
                      leading: Icon(Icons.save_outlined),
                      title: Text('保存生成结果'),
                    ),
                  ),
                  if (saved != null)
                    const PopupMenuItem(
                      value: 'playSaved',
                      child: ListTile(
                        leading: Icon(Icons.bookmark_outline),
                        title: Text('播放已保存结果'),
                      ),
                    ),
                  const PopupMenuItem(
                    value: 'edit',
                    child: ListTile(
                      leading: Icon(Icons.edit_outlined),
                      title: Text('编辑规则'),
                    ),
                  ),
                  const PopupMenuItem(
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
  }

  Future<void> _saveSnapshot(
    BuildContext context,
    WidgetRef ref,
    String ruleId,
    List<Song> songs,
  ) async {
    if (songs.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('没有可保存的歌曲')));
      return;
    }
    final saved = await ref
        .read(smartPlaylistsProvider.notifier)
        .saveSnapshot(ruleId, songs);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          saved == null
              ? '保存失败'
              : '已保存 ${saved.songs.length} 首，可在菜单中再次播放',
        ),
      ),
    );
  }

  String _formatSavedAt(DateTime value) {
    final local = value.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$month-$day $hour:$minute';
  }

  String _ruleSummary(SmartPlaylistRule rule) {
    final items = <String>[];
    if (rule.platforms.isNotEmpty) {
      items.add(rule.platforms.map((p) => p.displayName).join('/'));
    }
    if (rule.keyword.isNotEmpty) items.add('关键词 ${rule.keyword}');
    if (rule.artistIds.isNotEmpty) items.add('歌手 ${rule.artistIds.length}');
    if (rule.albumIds.isNotEmpty) items.add('专辑 ${rule.albumIds.length}');
    if (rule.minPlayCount > 0) items.add('播放>=${rule.minPlayCount}');
    if (rule.maxPlayCount > 0) items.add('播放<=${rule.maxPlayCount}');
    if (rule.recentlyPlayedDays > 0) {
      items.add('${rule.recentlyPlayedDays}天内');
    }
    if (rule.notPlayedSinceDays > 0) {
      items.add('${rule.notPlayedSinceDays}天未听');
    }
    if (rule.minDurationMs > 0 || rule.maxDurationMs > 0) {
      items.add('时长 ${_durationBound(rule)}');
    }
    if (rule.likedOnly) items.add('红心');
    if (rule.excludeLiked) items.add('未红心');
    if (rule.cachedOnly) items.add('已缓存');
    if (rule.downloadedOnly) items.add('已下载');
    if (rule.localOnly) items.add('仅本地');
    if (items.length > 1) items.add('按${rule.match.displayName}');
    items.add('排序：${rule.sortBy.displayName}');
    return items.isEmpty ? '全部本地记录' : items.join(' · ');
  }

  String _durationBound(SmartPlaylistRule rule) {
    final min = rule.minDurationMs > 0
        ? '${(rule.minDurationMs / 60000).toStringAsFixed(1)}分'
        : '0';
    final max = rule.maxDurationMs > 0
        ? '${(rule.maxDurationMs / 60000).toStringAsFixed(1)}分'
        : '不限';
    return '$min-$max';
  }
}
