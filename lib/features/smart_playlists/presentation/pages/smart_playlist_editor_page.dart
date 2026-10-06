import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/widgets/app_scrollbar.dart';
import '../../../../models/platform_type.dart';
import '../../domain/smart_playlist_rule.dart';
import '../providers/smart_playlists_provider.dart';

class SmartPlaylistEditorPage extends ConsumerStatefulWidget {
  final String? ruleId;

  const SmartPlaylistEditorPage({super.key, this.ruleId});

  @override
  ConsumerState<SmartPlaylistEditorPage> createState() =>
      _SmartPlaylistEditorPageState();
}

class _SmartPlaylistEditorPageState
    extends ConsumerState<SmartPlaylistEditorPage> {
  late final TextEditingController _nameController;
  late final TextEditingController _keywordController;
  late final TextEditingController _artistIdsController;
  late final TextEditingController _albumIdsController;
  Set<PlatformType> _platforms = {};
  var _minPlayCount = 0;
  var _maxPlayCount = 0;
  var _recentlyPlayedDays = 0;
  var _notPlayedSinceDays = 0;
  var _likedOnly = false;
  var _excludeLiked = false;
  var _cachedOnly = false;
  var _downloadedOnly = false;
  var _localOnly = false;
  var _maxSongs = 100;
  var _minDurationMs = 0;
  var _maxDurationMs = 0;
  var _match = SmartPlaylistMatch.all;
  var _sortBy = SmartPlaylistSortOrder.mostListened;
  String? _loadedRuleId;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: '智能歌单');
    _keywordController = TextEditingController();
    _artistIdsController = TextEditingController();
    _albumIdsController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _keywordController.dispose();
    _artistIdsController.dispose();
    _albumIdsController.dispose();
    super.dispose();
  }

  void _syncFromRule(SmartPlaylistRule? rule) {
    if (rule == null || _loadedRuleId == rule.id) return;
    _loadedRuleId = rule.id;
    _nameController.text = rule.name;
    _keywordController.text = rule.keyword;
    _artistIdsController.text = rule.artistIds.join(', ');
    _albumIdsController.text = rule.albumIds.join(', ');
    _platforms = Set<PlatformType>.from(rule.platforms);
    _minPlayCount = rule.minPlayCount;
    _maxPlayCount = rule.maxPlayCount;
    _recentlyPlayedDays = rule.recentlyPlayedDays;
    _notPlayedSinceDays = rule.notPlayedSinceDays;
    _likedOnly = rule.likedOnly;
    _excludeLiked = rule.excludeLiked;
    _cachedOnly = rule.cachedOnly;
    _downloadedOnly = rule.downloadedOnly;
    _localOnly = rule.localOnly;
    _maxSongs = rule.maxSongs;
    _minDurationMs = rule.minDurationMs;
    _maxDurationMs = rule.maxDurationMs;
    _match = rule.match;
    _sortBy = rule.sortBy;
  }

  Set<String> _parseIds(TextEditingController controller) {
    return {
      for (final part in controller.text.split(','))
        if (part.trim().isNotEmpty) part.trim(),
    };
  }

  Future<void> _save(SmartPlaylistRule? existing) async {
    final notifier = ref.read(smartPlaylistsProvider.notifier);
    final artistIds = _parseIds(_artistIdsController);
    final albumIds = _parseIds(_albumIdsController);
    if (existing == null) {
      await notifier.createRule(
        name: _nameController.text,
        platforms: _platforms,
        keyword: _keywordController.text,
        minPlayCount: _minPlayCount,
        maxPlayCount: _maxPlayCount,
        recentlyPlayedDays: _recentlyPlayedDays,
        notPlayedSinceDays: _notPlayedSinceDays,
        likedOnly: _likedOnly,
        excludeLiked: _excludeLiked,
        cachedOnly: _cachedOnly,
        downloadedOnly: _downloadedOnly,
        localOnly: _localOnly,
        maxSongs: _maxSongs,
        artistIds: artistIds,
        albumIds: albumIds,
        minDurationMs: _minDurationMs,
        maxDurationMs: _maxDurationMs,
        match: _match,
        sortBy: _sortBy,
      );
    } else {
      await notifier.updateRule(
        existing.copyWith(
          name: _nameController.text,
          platforms: _platforms,
          keyword: _keywordController.text,
          minPlayCount: _minPlayCount,
          maxPlayCount: _maxPlayCount,
          recentlyPlayedDays: _recentlyPlayedDays,
          notPlayedSinceDays: _notPlayedSinceDays,
          likedOnly: _likedOnly,
          excludeLiked: _excludeLiked,
          cachedOnly: _cachedOnly,
          downloadedOnly: _downloadedOnly,
          localOnly: _localOnly,
          maxSongs: _maxSongs,
          artistIds: artistIds,
          albumIds: albumIds,
          minDurationMs: _minDurationMs,
          maxDurationMs: _maxDurationMs,
          match: _match,
          sortBy: _sortBy,
        ),
      );
    }
    if (!mounted) return;
    // The old editor popped unconditionally, so a failed save looked successful.
    final error = ref.read(smartPlaylistsProvider).error;
    if (error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(smartPlaylistsProvider);
    final existing = _findRule(state.rules, widget.ruleId);
    _syncFromRule(existing);

    return Scaffold(
      appBar: AppBar(
        title: Text(existing == null ? '新建智能歌单' : '编辑智能歌单'),
        actions: [
          TextButton(
            onPressed: state.isSaving ? null : () => _save(existing),
            child: const Text('保存'),
          ),
        ],
      ),
      body: AppScrollbar(
        builder: (controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: '歌单名称',
                prefixIcon: Icon(Icons.auto_awesome),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _keywordController,
              decoration: const InputDecoration(
                labelText: '关键词',
                helperText: '匹配歌曲名、歌手或专辑，可留空',
                prefixIcon: Icon(Icons.search),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _artistIdsController,
              decoration: const InputDecoration(
                labelText: '限定歌手 ID（可选）',
                helperText: '多个 ID 用英文逗号分隔，留空表示不限',
                prefixIcon: Icon(Icons.person_outline),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _albumIdsController,
              decoration: const InputDecoration(
                labelText: '限定专辑 ID（可选）',
                helperText: '多个 ID 用英文逗号分隔，留空表示不限',
                prefixIcon: Icon(Icons.album_outlined),
              ),
            ),
            const SizedBox(height: 20),
            Text('平台', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final platform in PlatformType.musicServices)
                  FilterChip(
                    label: Text(platform.displayName),
                    selected: _platforms.contains(platform),
                    onSelected: (selected) {
                      setState(() {
                        if (selected) {
                          _platforms.add(platform);
                        } else {
                          _platforms.remove(platform);
                        }
                      });
                    },
                  ),
              ],
            ),
            const SizedBox(height: 20),
            Text('条件组合', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SegmentedButton<SmartPlaylistMatch>(
              segments: [
                for (final mode in SmartPlaylistMatch.values)
                  ButtonSegment(
                    value: mode,
                    label: Text(mode.displayName),
                  ),
              ],
              selected: {_match},
              onSelectionChanged: (selection) =>
                  setState(() => _match = selection.first),
            ),
            const SizedBox(height: 12),
            // `DropdownButton` (controlled by `value`) rather than
            // `DropdownButtonFormField`: the latter keeps the value it was first
            // built with, so loading a rule in edit mode would show the wrong
            // sort order.
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.sort),
              title: const Text('排序方式'),
              trailing: DropdownButton<SmartPlaylistSortOrder>(
                value: _sortBy,
                underline: const SizedBox.shrink(),
                items: [
                  for (final order in SmartPlaylistSortOrder.values)
                    DropdownMenuItem(
                      value: order,
                      child: Text(order.displayName),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _sortBy = value);
                },
              ),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.favorite_outline),
              title: const Text('只包含我喜欢'),
              value: _likedOnly,
              onChanged: (value) => setState(() => _likedOnly = value),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.favorite_border),
              title: const Text('排除我喜欢的'),
              value: _excludeLiked,
              onChanged: (value) => setState(() => _excludeLiked = value),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.offline_pin_outlined),
              title: const Text('只包含已缓存'),
              value: _cachedOnly,
              onChanged: (value) => setState(() => _cachedOnly = value),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.download_done_outlined),
              title: const Text('只包含已下载'),
              value: _downloadedOnly,
              onChanged: (value) => setState(() => _downloadedOnly = value),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.folder_outlined),
              title: const Text('只包含本地文件'),
              value: _localOnly,
              onChanged: (value) => setState(() => _localOnly = value),
            ),
            _IntSliderTile(
              title: '最低播放次数',
              icon: Icons.repeat,
              value: _minPlayCount,
              min: 0,
              max: 20,
              suffix: '次',
              onChanged: (value) => setState(() => _minPlayCount = value),
            ),
            _IntSliderTile(
              title: '最高播放次数',
              icon: Icons.filter_9_plus,
              value: _maxPlayCount,
              min: 0,
              max: 50,
              suffix: '次',
              onChanged: (value) => setState(() => _maxPlayCount = value),
            ),
            _IntSliderTile(
              title: '最近播放范围',
              icon: Icons.schedule,
              value: _recentlyPlayedDays,
              min: 0,
              max: 180,
              suffix: _recentlyPlayedDays == 0 ? '不限' : '天',
              onChanged: (value) => setState(() => _recentlyPlayedDays = value),
            ),
            _IntSliderTile(
              title: '多久没听',
              icon: Icons.history_toggle_off,
              value: _notPlayedSinceDays,
              min: 0,
              max: 365,
              suffix: _notPlayedSinceDays == 0 ? '不限' : '天未听',
              onChanged: (value) =>
                  setState(() => _notPlayedSinceDays = value),
            ),
            _DurationRangeTile(
              minMs: _minDurationMs,
              maxMs: _maxDurationMs,
              onChanged: (min, max) => setState(() {
                _minDurationMs = min;
                _maxDurationMs = max;
              }),
            ),
            _IntSliderTile(
              title: '最多歌曲数',
              icon: Icons.format_list_numbered,
              value: _maxSongs,
              min: 10,
              max: 300,
              suffix: '首',
              onChanged: (value) => setState(() => _maxSongs = value),
            ),
          ],
        ),
      ),
    );
  }

  SmartPlaylistRule? _findRule(List<SmartPlaylistRule> rules, String? id) {
    if (id == null || id.isEmpty) return null;
    for (final rule in rules) {
      if (rule.id == id) return rule;
    }
    return null;
  }
}

class _DurationRangeTile extends StatelessWidget {
  final int minMs;
  final int maxMs;
  final void Function(int min, int max) onChanged;

  const _DurationRangeTile({
    required this.minMs,
    required this.maxMs,
    required this.onChanged,
  });

  static const int _step = 15000;
  static const int _maxSeconds = 600;

  @override
  Widget build(BuildContext context) {
    final start = (minMs / 1000).clamp(0, _maxSeconds).toDouble();
    final end = (maxMs / 1000).clamp(0, _maxSeconds).toDouble();
    final label = (minMs == 0 && maxMs == 0)
        ? '不限'
        : '${(start / 60).toStringAsFixed(1)} - '
              '${end == 0 ? '不限' : (end / 60).toStringAsFixed(1)} 分';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.timer_outlined),
      title: const Text('时长范围'),
      subtitle: RangeSlider(
        values: RangeValues(start, end <= start ? start : end),
        min: 0,
        max: _maxSeconds.toDouble(),
        divisions: _maxSeconds ~/ (_step ~/ 1000),
        labels: RangeLabels(
          '${(start / 60).toStringAsFixed(1)}分',
          '${(end / 60).toStringAsFixed(1)}分',
        ),
        onChanged: (values) => onChanged(
          values.start.round() * 1000,
          values.end.round() * 1000,
        ),
      ),
      trailing: SizedBox(
        width: 84,
        child: Text(label, textAlign: TextAlign.end),
      ),
    );
  }
}

class _IntSliderTile extends StatelessWidget {
  final String title;
  final IconData icon;
  final int value;
  final int min;
  final int max;
  final String suffix;
  final ValueChanged<int> onChanged;

  const _IntSliderTile({
    required this.title,
    required this.icon,
    required this.value,
    required this.min,
    required this.max,
    required this.suffix,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final label = suffix == '不限' ? suffix : '$value $suffix';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(title),
      subtitle: Slider(
        value: value.clamp(min, max).toDouble(),
        min: min.toDouble(),
        max: max.toDouble(),
        divisions: max - min,
        label: label,
        onChanged: (next) => onChanged(next.round()),
      ),
      trailing: SizedBox(
        width: 56,
        child: Text(label, textAlign: TextAlign.end),
      ),
    );
  }
}
