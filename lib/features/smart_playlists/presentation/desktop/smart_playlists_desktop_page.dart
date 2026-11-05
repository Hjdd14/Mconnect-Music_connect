import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/desktop/desktop_empty_state.dart';
import '../../../../core/desktop/desktop_page_scaffold.dart';
import '../../../../core/desktop/desktop_tokens.dart';
import '../../../player/presentation/providers/player_provider.dart';
import '../../domain/smart_playlist_rule.dart';
import '../providers/smart_playlist_preview_provider.dart';
import '../providers/smart_playlists_provider.dart';

/// 智能歌单桌面页。
///
/// A card grid instead of the phone page's vertical list: each rule shows its
/// generated track count ([smartPlaylistPreviewProvider] — the same generator
/// the editor previews with), its rule summary, and the entry points that
/// already exist (editor, play, delete).
class SmartPlaylistsDesktopPage extends ConsumerWidget {
  const SmartPlaylistsDesktopPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(smartPlaylistsProvider);
    final notifier = ref.read(smartPlaylistsProvider.notifier);

    return DesktopPageScaffold(
      title: '智能歌单',
      subtitle: state.rules.isEmpty
          ? '用规则自动生成歌单'
          : '共 ${state.rules.length} 条规则 · 实时生成',
      actions: [
        IconButton(
          tooltip: '刷新规则',
          onPressed: () => unawaited(notifier.load()),
          icon: const Icon(Icons.refresh, size: 20),
        ),
        FilledButton.icon(
          onPressed: () => context.push('/smart-playlists/editor'),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('新建规则'),
        ),
      ],
      child: _buildBody(context, state, notifier),
    );
  }

  Widget _buildBody(
    BuildContext context,
    SmartPlaylistsState state,
    SmartPlaylistsNotifier notifier,
  ) {
    final scheme = Theme.of(context).colorScheme;
    if (state.isLoading && state.rules.isEmpty) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (state.error != null && state.rules.isEmpty) {
      return DesktopEmptyState(
        icon: Icons.error_outline,
        title: '智能歌单加载失败',
        message: state.error,
        action: FilledButton(
          onPressed: () => unawaited(notifier.load()),
          child: const Text('重试'),
        ),
      );
    }
    if (state.rules.isEmpty) {
      return DesktopEmptyState(
        icon: Icons.auto_awesome_outlined,
        title: '还没有智能歌单',
        message: '用规则自动生成歌单，例如「最近没听的收藏」或「播放最多的本地歌曲」',
        action: FilledButton.icon(
          onPressed: () => context.push('/smart-playlists/editor'),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('新建规则'),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: DesktopSpacing.sm),
            child: Row(
              children: [
                Icon(Icons.error_outline, size: 16, color: scheme.error),
                const SizedBox(width: DesktopSpacing.sm),
                Expanded(
                  child: Text(
                    state.error!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: DesktopText.caption.copyWith(color: scheme.error),
                  ),
                ),
              ],
            ),
          ),
        if (state.isSaving)
          const Padding(
            padding: EdgeInsets.only(bottom: DesktopSpacing.sm),
            child: LinearProgressIndicator(minHeight: 2),
          ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(bottom: DesktopSpacing.xxxl),
            children: [_RuleGrid(rules: state.rules)],
          ),
        ),
      ],
    );
  }
}

class _RuleGrid extends StatelessWidget {
  const _RuleGrid({required this.rules});

  final List<SmartPlaylistRule> rules;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = DesktopSpacing.lg;
        final width = constraints.maxWidth;
        final columns = width >= 1180
            ? 3
            : width >= 760
            ? 2
            : 1;
        final cardWidth = (width - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final rule in rules)
              SizedBox(
                width: cardWidth,
                child: _RuleCard(key: ValueKey(rule.id), rule: rule),
              ),
          ],
        );
      },
    );
  }
}

class _RuleCard extends ConsumerWidget {
  const _RuleCard({super.key, required this.rule});

  final SmartPlaylistRule rule;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final songs = ref.watch(smartPlaylistPreviewProvider(rule));
    final saved = ref.watch(
      smartPlaylistsProvider.select((state) => state.snapshotFor(rule.id)),
    );

    return Container(
      padding: const EdgeInsets.all(DesktopSpacing.lg),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow.withValues(alpha: 0.72),
        borderRadius: DesktopRadii.lgAll,
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.42),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.12),
                  borderRadius: DesktopRadii.smAll,
                ),
                child: Icon(
                  Icons.auto_awesome,
                  size: 18,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(width: DesktopSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      rule.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DesktopText.title.copyWith(
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${songs.length} 首 · 排序：${rule.sortBy.displayName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DesktopText.caption.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: '规则操作',
                icon: Icon(
                  Icons.more_horiz,
                  size: 18,
                  color: scheme.onSurfaceVariant,
                ),
                onSelected: (value) {
                  if (value == 'edit') {
                    context.push('/smart-playlists/editor?id=${rule.id}');
                  } else if (value == 'delete') {
                    unawaited(_confirmDelete(context, ref));
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem<String>(value: 'edit', child: Text('编辑规则')),
                  PopupMenuItem<String>(value: 'delete', child: Text('删除')),
                ],
              ),
            ],
          ),
          const SizedBox(height: DesktopSpacing.md),
          Text(
            ruleSummary(rule),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: DesktopText.caption.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
          if (saved != null) ...[
            const SizedBox(height: DesktopSpacing.sm),
            Text(
              '已保存 ${saved.songs.length} 首 · ${_formatSavedAt(saved.generatedAt)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: DesktopText.caption.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: DesktopSpacing.md),
          Row(
            children: [
              FilledButton.tonalIcon(
                onPressed: songs.isEmpty
                    ? null
                    : () => unawaited(
                        ref.read(playerProvider.notifier).playPlaylist(songs),
                      ),
                icon: const Icon(Icons.play_arrow, size: 18),
                label: const Text('播放'),
              ),
              const SizedBox(width: DesktopSpacing.sm),
              TextButton.icon(
                onPressed: () =>
                    context.push('/smart-playlists/editor?id=${rule.id}'),
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('编辑'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除智能歌单'),
        content: Text('将删除规则「${rule.name}」，已保存的生成结果也会一并删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(smartPlaylistsProvider.notifier).deleteRule(rule.id);
    }
  }

  String _formatSavedAt(DateTime value) {
    final local = value.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$month-$day $hour:$minute';
  }
}

/// One line description of what a rule selects.
///
/// Mirrors the phone page's summary so a rule reads the same in both shells; it
/// is presentation text, not rule logic, so it lives with the presentation.
String ruleSummary(SmartPlaylistRule rule) {
  final items = <String>[];
  if (rule.platforms.isNotEmpty) {
    items.add(rule.platforms.map((platform) => platform.displayName).join('/'));
  }
  if (rule.keyword.isNotEmpty) items.add('关键词 ${rule.keyword}');
  if (rule.artistIds.isNotEmpty) items.add('歌手 ${rule.artistIds.length}');
  if (rule.albumIds.isNotEmpty) items.add('专辑 ${rule.albumIds.length}');
  if (rule.minPlayCount > 0) items.add('播放>=${rule.minPlayCount}');
  if (rule.maxPlayCount > 0) items.add('播放<=${rule.maxPlayCount}');
  if (rule.recentlyPlayedDays > 0) {
    items.add('${rule.recentlyPlayedDays} 天内');
  }
  if (rule.notPlayedSinceDays > 0) {
    items.add('${rule.notPlayedSinceDays} 天未听');
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
      ? '${(rule.minDurationMs / 60000).toStringAsFixed(1)} 分'
      : '0';
  final max = rule.maxDurationMs > 0
      ? '${(rule.maxDurationMs / 60000).toStringAsFixed(1)} 分'
      : '不限';
  return '$min-$max';
}
