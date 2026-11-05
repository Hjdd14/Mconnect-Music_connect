import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../theme/theme_provider.dart';
import 'desktop_panel_provider.dart';
import 'desktop_shell_policy.dart';
import 'desktop_tokens.dart';

class DesktopSidebar extends ConsumerWidget {
  final bool collapsed;
  final String? currentPath;

  const DesktopSidebar({super.key, required this.collapsed, this.currentPath});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = currentPath ?? GoRouterState.of(context).uri.path;
    final width = collapsed
        ? DesktopShellPolicy.sidebarCollapsedWidth
        : DesktopShellPolicy.sidebarWidth;

    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          DesktopSpacing.sm,
          DesktopSpacing.sm,
          DesktopSpacing.xs,
          DesktopSpacing.sm,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxHeight < 680;
            final navGap = compact ? DesktopSpacing.sm : DesktopSpacing.lg;
            final top = <Widget>[
              _Brand(collapsed: collapsed),
              SizedBox(height: navGap),
              _NavItem(
                icon: Icons.explore_outlined,
                activeIcon: Icons.explore,
                label: '发现',
                path: '/',
                selected: path == '/',
                collapsed: collapsed,
              ),
              _NavItem(
                icon: Icons.search,
                activeIcon: Icons.search,
                label: '搜索',
                path: '/search',
                selected: path == '/search',
                collapsed: collapsed,
              ),
              _NavItem(
                icon: Icons.library_music_outlined,
                activeIcon: Icons.library_music,
                label: '音乐库',
                path: '/library',
                selected: path == '/library',
                collapsed: collapsed,
              ),
              _NavItem(
                icon: Icons.download_outlined,
                activeIcon: Icons.download,
                label: '下载',
                path: '/downloads',
                selected: path == '/downloads',
                collapsed: collapsed,
              ),
              SizedBox(height: navGap),
              _SectionLabel('资料库', collapsed: collapsed),
              _NavItem(
                icon: Icons.folder_open_outlined,
                activeIcon: Icons.folder_open,
                label: '本地音乐',
                path: '/local-music',
                selected: path == '/local-music',
                collapsed: collapsed,
              ),
              _NavItem(
                icon: Icons.insights_outlined,
                activeIcon: Icons.insights,
                label: '听歌统计',
                path: '/listening-stats',
                selected: path == '/listening-stats',
                collapsed: collapsed,
              ),
              _NavItem(
                icon: Icons.auto_awesome_outlined,
                activeIcon: Icons.auto_awesome,
                label: '智能歌单',
                path: '/smart-playlists',
                selected: path == '/smart-playlists',
                collapsed: collapsed,
              ),
              _NavItem(
                icon: Icons.history,
                activeIcon: Icons.history,
                label: '最近播放',
                path: '/history',
                selected: path == '/history',
                collapsed: collapsed,
              ),
            ];
            final bottom = <Widget>[
              _NavItem(
                icon: Icons.queue_music,
                activeIcon: Icons.queue_music,
                label: '播放队列',
                path: '/queue',
                selected: path == '/queue',
                collapsed: collapsed,
                onTap: () => ref.read(desktopPanelTabProvider.notifier).state =
                    DesktopPanelTab.queue,
              ),
              _NavItem(
                icon: Icons.settings_outlined,
                activeIcon: Icons.settings,
                label: '设置',
                path: '/settings',
                selected: path.startsWith('/settings'),
                collapsed: collapsed,
              ),
              SizedBox(height: compact ? DesktopSpacing.xs : DesktopSpacing.sm),
              _ThemeToggle(collapsed: collapsed),
              SizedBox(height: compact ? DesktopSpacing.xs : DesktopSpacing.sm),
              _AccountChip(collapsed: collapsed),
            ];

            // Below a 600-logical-height window the fixed column cannot fit
            // ten navigation entries plus the account block. Compact density
            // (32 px rows, no section heading, 4 px gaps) fits every entry in
            // the 508 px body of a 600 px window; a scroll view remains as a
            // safety net for even shorter windows.
            if (!compact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [...top, const Spacer(), ...bottom],
              );
            }
            final content = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ...top,
                SizedBox(height: DesktopSpacing.sm),
                ...bottom,
              ],
            );
            return _SidebarDensity(
              compact: true,
              child: constraints.maxHeight < 480
                  ? _SidebarScroll(child: content)
                  : content,
            );
          },
        ),
      ),
    );
  }
}

/// Short-window fallback: the fixed sidebar column cannot fit every entry at
/// 600 logical px, so the whole sidebar scrolls. A persistent thin thumb makes
/// the overflow discoverable; the global desktop shell disables ordinary
/// scrollbars, so this one is explicit.
class _SidebarScroll extends StatefulWidget {
  final Widget child;

  const _SidebarScroll({required this.child});

  @override
  State<_SidebarScroll> createState() => _SidebarScrollState();
}

class _SidebarDensity extends InheritedWidget {
  final bool compact;

  const _SidebarDensity({required this.compact, required super.child});

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_SidebarDensity>()?.compact ??
      false;

  @override
  bool updateShouldNotify(_SidebarDensity oldWidget) =>
      oldWidget.compact != compact;
}

class _SidebarScrollState extends State<_SidebarScroll> {
  final ScrollController _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      controller: _controller,
      thumbVisibility: true,
      thickness: 3,
      radius: const Radius.circular(3),
      child: SingleChildScrollView(
        controller: _controller,
        child: widget.child,
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  final bool collapsed;
  const _Brand({required this.collapsed});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: collapsed ? 0 : DesktopSpacing.sm,
        vertical: DesktopSpacing.xs,
      ),
      child: Row(
        mainAxisAlignment: collapsed
            ? MainAxisAlignment.center
            : MainAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [scheme.primary, scheme.tertiary],
              ),
              borderRadius: DesktopRadii.smAll,
            ),
            child: Icon(Icons.graphic_eq, size: 18, color: scheme.onPrimary),
          ),
          if (!collapsed) ...[
            const SizedBox(width: DesktopSpacing.sm),
            Text(
              'Mconnect',
              style: DesktopText.title.copyWith(
                color: scheme.onSurface,
                letterSpacing: -0.3,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  final bool collapsed;
  const _SectionLabel(this.label, {required this.collapsed});

  @override
  Widget build(BuildContext context) {
    final compact = _SidebarDensity.of(context);
    if (collapsed || compact) {
      return SizedBox(height: compact ? DesktopSpacing.xs : DesktopSpacing.sm);
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        DesktopSpacing.md,
        DesktopSpacing.sm,
        DesktopSpacing.md,
        DesktopSpacing.xs,
      ),
      child: Text(
        label,
        style: DesktopText.caption.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          letterSpacing: 0.4,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final String path;
  final bool selected;
  final bool collapsed;
  final VoidCallback? onTap;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.path,
    required this.selected,
    required this.collapsed,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final compact = _SidebarDensity.of(context);
    final scheme = Theme.of(context).colorScheme;
    final foreground = selected ? scheme.primary : scheme.onSurfaceVariant;
    final contents = Container(
      height: compact ? 32 : 38,
      padding: EdgeInsets.symmetric(
        horizontal: collapsed ? 0 : DesktopSpacing.md,
      ),
      decoration: BoxDecoration(
        color: selected ? scheme.primary.withValues(alpha: 0.12) : null,
        borderRadius: DesktopRadii.mdAll,
      ),
      child: Row(
        mainAxisAlignment: collapsed
            ? MainAxisAlignment.center
            : MainAxisAlignment.start,
        children: [
          Icon(
            selected ? activeIcon : icon,
            size: compact ? 18 : 19,
            color: foreground,
          ),
          if (!collapsed) ...[
            const SizedBox(width: DesktopSpacing.md),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: DesktopText.bodyStrong.copyWith(
                  color: selected ? scheme.primary : scheme.onSurface,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
          ],
        ],
      ),
    );

    final button = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap ?? () => context.go(path),
        borderRadius: DesktopRadii.mdAll,
        hoverColor: scheme.onSurface.withValues(alpha: 0.06),
        child: contents,
      ),
    );

    if (!collapsed) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: compact ? 0 : 1),
        child: button,
      );
    }
    return Padding(
      padding: EdgeInsets.symmetric(vertical: compact ? 0 : 1),
      child: Tooltip(message: label, child: button),
    );
  }
}

class _ThemeToggle extends ConsumerWidget {
  final bool collapsed;
  const _ThemeToggle({required this.collapsed});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final compact = _SidebarDensity.of(context);
    final mode = ref.watch(themeSettingsProvider.select((s) => s.mode));
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final icon = isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined;
    final label = isDark ? '切换到浅色' : '切换到深色';

    final button = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => ref
            .read(themeSettingsProvider.notifier)
            .setMode(isDark ? ThemeMode.light : ThemeMode.dark),
        borderRadius: DesktopRadii.mdAll,
        hoverColor: Theme.of(context).colorScheme.onSurface
            .withValues(alpha: 0.06),
        child: Container(
          height: compact ? 32 : 38,
          padding: EdgeInsets.symmetric(
            horizontal: collapsed ? 0 : DesktopSpacing.md,
          ),
          child: Row(
            mainAxisAlignment: collapsed
                ? MainAxisAlignment.center
                : MainAxisAlignment.start,
            children: [
              Icon(
                icon,
                size: compact ? 18 : 19,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              if (!collapsed) ...[
                const SizedBox(width: DesktopSpacing.md),
                Text(
                  mode == ThemeMode.system ? '跟随系统' : label,
                  style: DesktopText.body.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );

    return collapsed ? Tooltip(message: label, child: button) : button;
  }
}

class _AccountChip extends StatelessWidget {
  final bool collapsed;
  const _AccountChip({required this.collapsed});

  @override
  Widget build(BuildContext context) {
    final compact = _SidebarDensity.of(context);
    final scheme = Theme.of(context).colorScheme;
    final button = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => context.go('/settings?section=accounts'),
        borderRadius: DesktopRadii.mdAll,
        hoverColor: scheme.onSurface.withValues(alpha: 0.06),
        child: Container(
          height: compact ? 36 : 44,
          padding: EdgeInsets.symmetric(
            horizontal: collapsed ? 0 : DesktopSpacing.sm,
          ),
          child: Row(
            mainAxisAlignment: collapsed
                ? MainAxisAlignment.center
                : MainAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: compact ? 12 : 14,
                backgroundColor: scheme.primary.withValues(alpha: 0.16),
                child: Icon(
                  Icons.person_outline,
                  size: compact ? 14 : 16,
                  color: scheme.primary,
                ),
              ),
              if (!collapsed) ...[
                const SizedBox(width: DesktopSpacing.sm),
                Expanded(
                  child: Text(
                    '账号与平台',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DesktopText.caption.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  size: 16,
                  color: scheme.onSurfaceVariant,
                ),
              ],
            ],
          ),
        ),
      ),
    );

    return collapsed ? Tooltip(message: '账号与平台', child: button) : button;
  }
}
