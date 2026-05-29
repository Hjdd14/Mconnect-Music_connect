import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/widgets/app_scrollbar.dart';
import '../../../../models/song.dart';
import '../../../../models/platform_type.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../download/presentation/widgets/download_button.dart';
import '../../../player/presentation/providers/player_provider.dart';
import '../providers/recommendations_provider.dart';

class RecommendationsPage extends ConsumerStatefulWidget {
  const RecommendationsPage({super.key});

  @override
  ConsumerState<RecommendationsPage> createState() =>
      _RecommendationsPageState();
}

class _RecommendationsPageState extends ConsumerState<RecommendationsPage>
    with SingleTickerProviderStateMixin {
  TabController? _tabController;
  int _lastTabCount = 0;

  @override
  void initState() {
    super.initState();
    ref.listenManual(authProvider.select((s) => s.loggedUsers), (
      previous,
      next,
    ) {
      if (!mounted || previous == next) return;
      ref.read(recommendationsProvider.notifier).loadRecommendations();
    });
    final state = ref.read(recommendationsProvider);
    if (state.songsByPlatform.isEmpty && !state.isLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(recommendationsProvider.notifier).loadRecommendations();
      });
    }
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  void _syncTabController(int length) {
    if (length <= 0) {
      _tabController?.dispose();
      _tabController = null;
      _lastTabCount = 0;
      return;
    }
    if (_lastTabCount != length) {
      final previousIndex = _tabController?.index ?? 0;
      _tabController?.dispose();
      _tabController = TabController(length: length, vsync: this);
      // Preserve index if still valid
      if (previousIndex < length) {
        _tabController!.index = previousIndex;
      }
      _lastTabCount = length;
    }
  }

  Color _platformColor(PlatformType platform) {
    switch (platform) {
      case PlatformType.local:
        return Theme.of(context).colorScheme.primary;
      case PlatformType.netease:
        return const Color(0xFFE60026);
      case PlatformType.qq:
        return const Color(0xFF31C27C);
      case PlatformType.kugou:
        return const Color(0xFF2CA2F9);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(recommendationsProvider);
    final platforms = state.songsByPlatform.keys.toList();
    _syncTabController(platforms.length);

    return Scaffold(
      appBar: AppBar(
        title: const Text('每日推荐'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref
                .read(recommendationsProvider.notifier)
                .loadRecommendations(),
          ),
        ],
        bottom: _tabController != null
            ? TabBar(
                controller: _tabController!,
                tabs: platforms.map((p) => Tab(text: p.displayName)).toList(),
              )
            : null,
      ),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : platforms.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.wb_sunny_outlined,
                    size: 64,
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    state.error ?? '请先登录平台账号',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.outline,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: () => ref
                        .read(recommendationsProvider.notifier)
                        .loadRecommendations(),
                    child: const Text('重试'),
                  ),
                ],
              ),
            )
          : TabBarView(
              controller: _tabController!,
              children: platforms.map((platform) {
                final songs = state.songsForPlatform(platform);
                return _PlatformRecommendations(
                  platform: platform,
                  songs: songs,
                  error: state.errorsByPlatform[platform],
                  platformColor: _platformColor(platform),
                );
              }).toList(),
            ),
    );
  }
}

class _PlatformRecommendations extends StatelessWidget {
  final PlatformType platform;
  final List<Song> songs;
  final String? error;
  final Color platformColor;

  const _PlatformRecommendations({
    required this.platform,
    required this.songs,
    required this.error,
    required this.platformColor,
  });

  @override
  Widget build(BuildContext context) {
    if (songs.isNotEmpty) {
      return _SongList(songs: songs, platformColor: platformColor);
    }

    final cs = Theme.of(context).colorScheme;
    final hasError = error != null && error!.isNotEmpty;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hasError ? Icons.error_outline : Icons.music_note_outlined,
              size: 56,
              color: hasError ? cs.error : cs.outlineVariant,
            ),
            const SizedBox(height: 14),
            Text(
              hasError
                  ? '${platform.displayName}每日推荐加载失败'
                  : '${platform.displayName}暂无每日推荐',
              style: TextStyle(
                color: hasError ? cs.error : cs.outline,
                fontSize: 16,
              ),
              textAlign: TextAlign.center,
            ),
            if (hasError) ...[
              const SizedBox(height: 8),
              Text(
                error!,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: cs.outline, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SongList extends ConsumerWidget {
  final List<Song> songs;
  final Color platformColor;

  const _SongList({required this.songs, required this.platformColor});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppScrollbar(
      builder: (controller) => ListView.builder(
        controller: controller,
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: songs.length,
        itemBuilder: (context, index) {
          final song = songs[index];
          return ListTile(
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: platformColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  '${index + 1}',
                  style: TextStyle(
                    color: platformColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            title: Text(
              song.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 15),
            ),
            subtitle: Text(
              song.artistNames,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Theme.of(context).colorScheme.outline,
                fontSize: 13,
              ),
            ),
            trailing: DownloadButton(song: song, size: 22),
            onTap: () {
              ref
                  .read(playerProvider.notifier)
                  .playPlaylist(songs, startIndex: index);
            },
          );
        },
      ),
    );
  }
}
