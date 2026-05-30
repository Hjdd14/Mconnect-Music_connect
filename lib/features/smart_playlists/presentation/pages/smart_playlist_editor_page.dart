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
  Set<PlatformType> _platforms = {};
  var _minPlayCount = 0;
  var _recentlyPlayedDays = 0;
  var _likedOnly = false;
  var _cachedOnly = false;
  var _maxSongs = 100;
  String? _loadedRuleId;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: '智能歌单');
    _keywordController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _keywordController.dispose();
    super.dispose();
  }

  void _syncFromRule(SmartPlaylistRule? rule) {
    if (rule == null || _loadedRuleId == rule.id) return;
    _loadedRuleId = rule.id;
    _nameController.text = rule.name;
    _keywordController.text = rule.keyword;
    _platforms = Set<PlatformType>.from(rule.platforms);
    _minPlayCount = rule.minPlayCount;
    _recentlyPlayedDays = rule.recentlyPlayedDays;
    _likedOnly = rule.likedOnly;
    _cachedOnly = rule.cachedOnly;
    _maxSongs = rule.maxSongs;
  }

  Future<void> _save(SmartPlaylistRule? existing) async {
    final notifier = ref.read(smartPlaylistsProvider.notifier);
    if (existing == null) {
      await notifier.createRule(
        name: _nameController.text,
        platforms: _platforms,
        keyword: _keywordController.text,
        minPlayCount: _minPlayCount,
        recentlyPlayedDays: _recentlyPlayedDays,
        likedOnly: _likedOnly,
        cachedOnly: _cachedOnly,
        maxSongs: _maxSongs,
      );
    } else {
      await notifier.updateRule(
        existing.copyWith(
          name: _nameController.text,
          platforms: _platforms,
          keyword: _keywordController.text,
          minPlayCount: _minPlayCount,
          recentlyPlayedDays: _recentlyPlayedDays,
          likedOnly: _likedOnly,
          cachedOnly: _cachedOnly,
          maxSongs: _maxSongs,
        ),
      );
    }
    if (mounted) context.pop();
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
              secondary: const Icon(Icons.offline_pin_outlined),
              title: const Text('只包含已缓存'),
              value: _cachedOnly,
              onChanged: (value) => setState(() => _cachedOnly = value),
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
              title: '最近播放范围',
              icon: Icons.schedule,
              value: _recentlyPlayedDays,
              min: 0,
              max: 180,
              suffix: _recentlyPlayedDays == 0 ? '不限' : '天',
              onChanged: (value) => setState(() => _recentlyPlayedDays = value),
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
