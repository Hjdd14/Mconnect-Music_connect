import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/desktop/desktop_empty_state.dart';
import '../../../../core/desktop/desktop_media_card.dart';
import '../../../../core/desktop/desktop_page_scaffold.dart';
import '../../../../core/desktop/desktop_section_header.dart';
import '../../../../core/desktop/desktop_tokens.dart';
import '../../../../core/theme/platform_accent.dart';
import '../../../../models/platform_type.dart';
import '../../../../models/song.dart';
import '../../../../models/toplist.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../new_songs/presentation/providers/new_songs_provider.dart';
import '../../../player/presentation/providers/player_provider.dart';
import '../../../toplist/presentation/providers/toplists_provider.dart';
import '../providers/playlist_recommendations_provider.dart';

class DiscoveryDesktopPage extends ConsumerStatefulWidget {
  const DiscoveryDesktopPage({super.key});

  @override
  ConsumerState<DiscoveryDesktopPage> createState() =>
      _DiscoveryDesktopPageState();
}

class _DiscoveryDesktopPageState extends ConsumerState<DiscoveryDesktopPage> {
  /// True while the auth restore is still running and nothing has been loaded
  /// yet: the section shows a spinner instead of "还没有每日推荐".
  bool _waitingForSession = false;

  /// The logged-in platforms the current data was loaded for. A login, logout
  /// or a finished restore changes this set, and that is exactly when the page
  /// has to fetch again.
  Set<PlatformType>? _loadedForLogin;

  @override
  void initState() {
    super.initState();
    // The phone page has done this since v1.4 (`discovery_screen.dart`); the
    // desktop page did not, which is why the 发现 page sat on "未登录" until the
    // user pressed 刷新.
    //
    // `App.initState` starts `authProvider.init()` without awaiting it, and that
    // restore reads secure storage plus one `getUserInfo()` per platform. The
    // post-frame load below used to run first, see every platform as logged
    // out, and store that as the final answer.
    ref.listenManual(authProvider, (previous, next) => _autoLoad());
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoLoad());
  }

  void _autoLoad() {
    if (!mounted) return;
    final auth = ref.read(authProvider);
    if (auth.restoring) {
      if (!_waitingForSession) {
        setState(() => _waitingForSession = true);
      }
      return;
    }

    final logged = <PlatformType>{
      for (final entry in auth.loggedUsers.entries)
        if (entry.value != null) entry.key,
    };
    final unchanged = _loadedForLogin != null &&
        _loadedForLogin!.length == logged.length &&
        _loadedForLogin!.containsAll(logged);
    if (unchanged && !_waitingForSession) return;

    _loadedForLogin = logged;
    if (_waitingForSession) {
      setState(() => _waitingForSession = false);
    }
    _loadAll();
  }

  /// The three sections of this page.
  ///
  /// Recommendations are re-fetched on every login change; the other two do not
  /// depend on the session, so they only fill an empty section (their own
  /// `isLoading` guards keep the refresh button from double-firing).
  void _loadAll() {
    final recommendations = ref.read(playlistRecommendationsProvider);
    if (!recommendations.isLoading) {
      ref.read(playlistRecommendationsProvider.notifier).loadRecommendations();
    }
    final toplists = ref.read(toplistsProvider);
    if (toplists.toplistsByPlatform.isEmpty && !toplists.isLoading) {
      ref.read(toplistsProvider.notifier).load();
    }
    final newSongs = ref.read(newSongsProvider);
    if (newSongs.songsByPlatform.isEmpty && !newSongs.isLoading) {
      ref.read(newSongsProvider.notifier).load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final recState = ref.watch(playlistRecommendationsProvider);
    final toplistState = ref.watch(toplistsProvider);
    final newSongsState = ref.watch(newSongsProvider);
    final scheme = Theme.of(context).colorScheme;
    final songs = _flatten(recState.songsByPlatform);

    return DesktopPageScaffold(
      title: '发现',
      subtitle: '每日推荐、榜单与新歌，为桌面重新排版',
      actions: [
        IconButton(
          tooltip: '刷新',
          onPressed: () {
            // Manual refresh stays a full reload of all three sections; the
            // signature is cleared so a later login change still reloads.
            _loadedForLogin = null;
            _loadAll();
            ref.read(toplistsProvider.notifier).load();
            ref.read(newSongsProvider.notifier).load();
          },
          icon: const Icon(Icons.refresh, size: 20),
        ),
      ],
      child: ListView(
        padding: const EdgeInsets.only(bottom: DesktopSpacing.xxxl),
        children: [
          _HeroRow(
            recommended: songs.take(4).toList(),
            total: songs.length,
            onPlay: songs.isEmpty
                ? null
                : () => ref
                      .read(playerProvider.notifier)
                      .playPlaylist(songs, startIndex: 0),
          ),
          const SizedBox(height: DesktopSpacing.xxxl),
          if ((recState.isLoading || _waitingForSession) && songs.isEmpty)
            const SizedBox(
              key: ValueKey('discovery-recommendations-loading'),
              height: 240,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (songs.isEmpty)
            const SizedBox(
              height: 220,
              child: DesktopEmptyState(
                icon: Icons.wb_sunny_outlined,
                title: '还没有每日推荐',
                message: '登录平台账号后会按你的口味生成推荐',
              ),
            )
          else ...[
            DesktopSectionHeader(
              key: const ValueKey('discovery-see-all-recommendations'),
              title: '为你推荐',
              subtitle: '跨平台聚合，按平台优先顺序去重',
              actionLabel: '查看全部 ${songs.length} 首',
              onAction: () => context.push('/recommendations'),
            ),
            SizedBox(
              // 246 + twice the vertical padding the hover lift needs; without
              // it the viewport clips the cover's top strip on hover.
              height: 258,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(vertical: 6),
                itemCount: songs.take(12).length,
                separatorBuilder: (_, _) =>
                    const SizedBox(width: DesktopSpacing.md),
                itemBuilder: (context, index) {
                  final song = songs[index];
                  return DesktopMediaCard(
                    title: song.name,
                    subtitle: song.artistNames,
                    imageUrl: song.coverUrl,
                    width: 166,
                    badge: _PlatformBadge(platform: song.platform),
                    onTap: () => ref
                        .read(playerProvider.notifier)
                        .playPlaylist(songs, startIndex: index),
                    onPlay: () => ref
                        .read(playerProvider.notifier)
                        .playPlaylist(songs, startIndex: index),
                  );
                },
              ),
            ),
          ],
          const SizedBox(height: DesktopSpacing.xxxl),
          DesktopSectionHeader(
            title: '排行榜',
            subtitle: '三平台榜单入口',
            actionLabel: '全部榜单',
            onAction: () => context.push('/toplists'),
          ),
          _ToplistRow(state: toplistState),
          const SizedBox(height: DesktopSpacing.xxxl),
          DesktopSectionHeader(
            title: '新歌速递',
            subtitle: '最近发布',
            actionLabel: '查看全部',
            onAction: () => context.push('/new-songs'),
          ),
          _NewSongsRow(state: newSongsState),
          const SizedBox(height: DesktopSpacing.lg),
          Text(
            '提示：鼠标悬停歌曲卡片可快速播放，双击卡片也可播放。',
            style: DesktopText.caption.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  List<Song> _flatten(Map<PlatformType, List<Song>> byPlatform) {
    final result = <Song>[];
    final seen = <String>{};
    for (final platform in PlatformType.musicServices) {
      for (final song in byPlatform[platform] ?? const <Song>[]) {
        if (seen.add(song.dedupeKey)) result.add(song);
      }
    }
    return result;
  }
}

class _HeroRow extends StatelessWidget {
  final List<Song> recommended;
  final int total;
  final VoidCallback? onPlay;

  const _HeroRow({required this.recommended, required this.total, this.onPlay});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        final links = <Widget>[
          _QuickLink(
            icon: Icons.leaderboard_outlined,
            title: '榜单中心',
            subtitle: '三平台实时榜单',
            onTap: () => context.push('/toplists'),
          ),
          _QuickLink(
            icon: Icons.fiber_new_outlined,
            title: '新歌速递',
            subtitle: '最近发布的新歌',
            onTap: () => context.push('/new-songs'),
          ),
          _QuickLink(
            icon: Icons.favorite_border,
            title: '我喜欢的音乐',
            subtitle: '跨平台收藏聚合',
            onTap: () => context.push('/likes'),
          ),
        ];
        final hero = _HeroCard(
          recommended: recommended,
          total: total,
          onPlay: onPlay,
        );
        if (wide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: hero),
              const SizedBox(width: DesktopSpacing.lg),
              Expanded(
                child: SizedBox(
                  height: 228,
                  child: Column(
                    children: [
                      Expanded(child: links[0]),
                      const SizedBox(height: DesktopSpacing.sm),
                      Expanded(child: links[1]),
                      const SizedBox(height: DesktopSpacing.sm),
                      Expanded(child: links[2]),
                    ],
                  ),
                ),
              ),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            hero,
            const SizedBox(height: DesktopSpacing.md),
            SizedBox(
              height: 64,
              child: Row(
                children: [
                  Expanded(child: links[0]),
                  const SizedBox(width: DesktopSpacing.sm),
                  Expanded(child: links[1]),
                  const SizedBox(width: DesktopSpacing.sm),
                  Expanded(child: links[2]),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _HeroCard extends StatelessWidget {
  final List<Song> recommended;
  final int total;
  final VoidCallback? onPlay;

  const _HeroCard({
    required this.recommended,
    required this.total,
    this.onPlay,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 228,
      padding: const EdgeInsets.all(DesktopSpacing.xxl),
      decoration: BoxDecoration(
        borderRadius: DesktopRadii.xlAll,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primary.withValues(alpha: 0.9),
            scheme.tertiary.withValues(alpha: 0.72),
          ],
        ),
        boxShadow: DesktopShadows.floating,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '每日推荐',
                  style: DesktopText.display.copyWith(color: scheme.onPrimary),
                ),
                const SizedBox(height: DesktopSpacing.sm),
                Text(
                  total > 0 ? '根据你的口味挑选的 $total 首歌' : '登录平台账号后生成专属推荐',
                  style: DesktopText.body.copyWith(
                    color: scheme.onPrimary.withValues(alpha: 0.84),
                  ),
                ),
                const SizedBox(height: DesktopSpacing.xl),
                FilledButton.icon(
                  onPressed: onPlay,
                  style: FilledButton.styleFrom(
                    backgroundColor: scheme.onPrimary,
                    foregroundColor: scheme.primary,
                  ),
                  icon: const Icon(Icons.play_arrow, size: 18),
                  label: const Text('播放全部'),
                ),
              ],
            ),
          ),
          if (recommended.isNotEmpty)
            SizedBox(
              width: 240,
              height: 180,
              child: Stack(
                children: [
                  for (var i = 0; i < recommended.length; i++)
                    Positioned(
                      left: i * 48.0,
                      top: i * 10.0,
                      child: _HeroCover(song: recommended[i], index: i),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _QuickLink extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _QuickLink({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerLow.withValues(alpha: 0.7),
      borderRadius: DesktopRadii.lgAll,
      child: InkWell(
        onTap: onTap,
        borderRadius: DesktopRadii.lgAll,
        hoverColor: scheme.onSurface.withValues(alpha: 0.05),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: DesktopSpacing.md,
            vertical: DesktopSpacing.xs,
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.12),
                  borderRadius: DesktopRadii.mdAll,
                ),
                child: Icon(icon, size: 17, color: scheme.primary),
              ),
              const SizedBox(width: DesktopSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DesktopText.bodyStrong.copyWith(
                        color: scheme.onSurface,
                      ),
                    ),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DesktopText.caption.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                size: 16,
                color: scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroCover extends StatelessWidget {
  final Song song;
  final int index;

  const _HeroCover({required this.song, required this.index});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Transform.rotate(
      angle: (index - 1) * 0.04,
      child: Container(
        width: 128,
        height: 128,
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: DesktopRadii.mdAll,
          boxShadow: DesktopShadows.floating,
        ),
        clipBehavior: Clip.antiAlias,
        child: song.coverUrl != null
            ? Image.network(
                song.coverUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _coverPlaceholder(scheme),
              )
            : _coverPlaceholder(scheme),
      ),
    );
  }

  Widget _coverPlaceholder(ColorScheme scheme) {
    return ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: Icon(Icons.music_note, color: scheme.onSurfaceVariant),
    );
  }
}

class _ToplistRow extends StatelessWidget {
  final ToplistsState state;

  const _ToplistRow({required this.state});

  @override
  Widget build(BuildContext context) {
    if (state.isLoading && state.toplistsByPlatform.isEmpty) {
      return const SizedBox(
        height: 120,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    final platforms = state.toplistsByPlatform.keys.toList();
    if (platforms.isEmpty) {
      return const SizedBox(
        height: 120,
        child: DesktopEmptyState(
          icon: Icons.leaderboard_outlined,
          title: '暂无榜单数据',
        ),
      );
    }
    return SizedBox(
      height: 220,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final platform in platforms.take(3)) ...[
            Expanded(
              child: _ToplistCard(
                platform: platform,
                toplists: state.toplistsByPlatform[platform] ?? const [],
              ),
            ),
            if (platform != platforms.take(3).last)
              const SizedBox(width: DesktopSpacing.md),
          ],
        ],
      ),
    );
  }
}

class _ToplistCard extends StatelessWidget {
  final PlatformType platform;
  final List<Toplist> toplists;

  const _ToplistCard({required this.platform, required this.toplists});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = PlatformAccent.colorOf(context, platform);
    return Container(
      padding: const EdgeInsets.all(DesktopSpacing.lg),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow.withValues(alpha: 0.7),
        borderRadius: DesktopRadii.lgAll,
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(PlatformAccent.iconOf(platform), size: 16, color: accent),
              const SizedBox(width: DesktopSpacing.xs),
              Text(
                platform.displayName,
                style: DesktopText.bodyStrong.copyWith(color: accent),
              ),
            ],
          ),
          const SizedBox(height: DesktopSpacing.sm),
          Expanded(
            child: ListView.separated(
              itemCount: toplists.take(4).length,
              separatorBuilder: (_, _) => const SizedBox(height: 2),
              itemBuilder: (context, index) {
                final toplist = toplists[index];
                return InkWell(
                  onTap: () => context.push(
                    '/toplist/${platform.name}/${toplist.id}?name=${Uri.encodeComponent(toplist.name)}',
                  ),
                  borderRadius: DesktopRadii.smAll,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 4,
                      horizontal: 2,
                    ),
                    child: Row(
                      children: [
                        Text(
                          '${index + 1}',
                          style: DesktopText.caption.copyWith(color: accent),
                        ),
                        const SizedBox(width: DesktopSpacing.sm),
                        Expanded(
                          child: Text(
                            toplist.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: DesktopText.caption.copyWith(
                              color: scheme.onSurface,
                            ),
                          ),
                        ),
                        Icon(
                          Icons.chevron_right,
                          size: 14,
                          color: scheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _NewSongsRow extends StatelessWidget {
  final NewSongsState state;

  const _NewSongsRow({required this.state});

  @override
  Widget build(BuildContext context) {
    if (state.isLoading && state.songsByPlatform.isEmpty) {
      return const SizedBox(
        height: 220,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    final songs = <Song>[];
    for (final platform in PlatformType.musicServices) {
      songs.addAll((state.songsByPlatform[platform] ?? const <Song>[]).take(4));
    }
    if (songs.isEmpty) {
      return const SizedBox(
        height: 160,
        child: DesktopEmptyState(
          icon: Icons.fiber_new_outlined,
          title: '暂无新歌数据',
        ),
      );
    }
    return SizedBox(
      height: 232,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(vertical: 6),
        itemCount: songs.length,
        separatorBuilder: (_, _) => const SizedBox(width: DesktopSpacing.md),
        itemBuilder: (context, index) {
          final song = songs[index];
          return DesktopMediaCard(
            title: song.name,
            subtitle: song.artistNames,
            imageUrl: song.coverUrl,
            width: 156,
            badge: _PlatformBadge(platform: song.platform),
            onTap: () => context.push('/new-songs'),
          );
        },
      ),
    );
  }
}

class _PlatformBadge extends StatelessWidget {
  final PlatformType platform;

  const _PlatformBadge({required this.platform});

  @override
  Widget build(BuildContext context) {
    final accent = PlatformAccent.colorOf(context, platform);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: DesktopRadii.smAll,
      ),
      child: Text(
        platform.displayName,
        style: DesktopText.caption.copyWith(
          color: accent,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
