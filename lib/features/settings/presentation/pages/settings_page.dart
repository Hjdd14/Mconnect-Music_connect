import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mconnect/core/diagnostics/diagnostics_service.dart';
import 'package:mconnect/core/theme/theme_provider.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/features/auth/presentation/providers/auth_provider.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentMode = ref.watch(themeModeProvider);
    final notifier = ref.read(themeModeProvider.notifier);
    final authState = ref.watch(authProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: [
          const _SectionHeader('账号管理'),
          _PlatformLoginTile(
            platform: PlatformType.netease,
            user: authState.userFor(PlatformType.netease),
            onLogin: () => context.push('/login/netease'),
            onLogout: () =>
                ref.read(authProvider.notifier).logout(PlatformType.netease),
          ),
          _PlatformLoginTile(
            platform: PlatformType.qq,
            user: authState.userFor(PlatformType.qq),
            onLogin: () => context.push('/login/qq'),
            onLogout: () =>
                ref.read(authProvider.notifier).logout(PlatformType.qq),
          ),
          _PlatformLoginTile(
            platform: PlatformType.kugou,
            user: authState.userFor(PlatformType.kugou),
            onLogin: () => context.push('/login/kugou'),
            onLogout: () =>
                ref.read(authProvider.notifier).logout(PlatformType.kugou),
          ),
          const Divider(),
          const _SectionHeader('外观'),
          _ThemeTile(
            title: '跟随系统',
            icon: Icons.brightness_auto,
            selected: currentMode == ThemeMode.system,
            onTap: () => notifier.setMode(ThemeMode.system),
          ),
          _ThemeTile(
            title: '浅色模式',
            icon: Icons.light_mode,
            selected: currentMode == ThemeMode.light,
            onTap: () => notifier.setMode(ThemeMode.light),
          ),
          _ThemeTile(
            title: '深色模式',
            icon: Icons.dark_mode,
            selected: currentMode == ThemeMode.dark,
            onTap: () => notifier.setMode(ThemeMode.dark),
          ),
          const Divider(),
          const _SectionHeader('诊断'),
          _DiagnosticsTile(diagnostics: DiagnosticsService.instance),
          const Divider(),
          const _SectionHeader('关于'),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('版本'),
            subtitle: Text('1.0.0'),
          ),
        ],
      ),
    );
  }
}

class _DiagnosticsTile extends StatelessWidget {
  final DiagnosticsService diagnostics;

  const _DiagnosticsTile({required this.diagnostics});

  @override
  Widget build(BuildContext context) {
    final path = diagnostics.logFile.path;
    return ListTile(
      leading: const Icon(Icons.bug_report_outlined),
      title: const Text('诊断日志'),
      subtitle: Text(path, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: PopupMenuButton<String>(
        onSelected: (value) async {
          switch (value) {
            case 'copy':
              await Clipboard.setData(ClipboardData(text: path));
              if (!context.mounted) return;
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('日志路径已复制')));
              break;
            case 'clear':
              await diagnostics.clear();
              if (!context.mounted) return;
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('诊断日志已清空')));
              break;
          }
        },
        itemBuilder: (context) => const [
          PopupMenuItem(
            value: 'copy',
            child: ListTile(
              leading: Icon(Icons.copy),
              title: Text('复制路径'),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
          PopupMenuItem(
            value: 'clear',
            child: ListTile(
              leading: Icon(Icons.delete_outline),
              title: Text('清空日志'),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

class _ThemeTile extends StatelessWidget {
  final String title;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _ThemeTile({
    required this.title,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      trailing: selected
          ? Icon(Icons.check, color: Theme.of(context).colorScheme.primary)
          : null,
      onTap: onTap,
    );
  }
}

class _PlatformLoginTile extends StatelessWidget {
  final PlatformType platform;
  final dynamic user;
  final VoidCallback onLogin;
  final VoidCallback onLogout;

  const _PlatformLoginTile({
    required this.platform,
    this.user,
    required this.onLogin,
    required this.onLogout,
  });

  Color _platformColor() {
    switch (platform) {
      case PlatformType.local:
        return Colors.grey;
      case PlatformType.netease:
        return const Color(0xFFE60026);
      case PlatformType.qq:
        return const Color(0xFF31C27C);
      case PlatformType.kugou:
        return const Color(0xFF2CA2F9);
    }
  }

  IconData _platformIcon() {
    switch (platform) {
      case PlatformType.local:
        return Icons.folder_open;
      case PlatformType.netease:
        return Icons.cloud_outlined;
      case PlatformType.qq:
        return Icons.music_note;
      case PlatformType.kugou:
        return Icons.headphones;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLoggedIn = user != null;
    final cs = Theme.of(context).colorScheme;

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: _platformColor().withValues(alpha: 0.12),
        child: Icon(_platformIcon(), color: _platformColor(), size: 20),
      ),
      title: Text(platform.displayName),
      subtitle: isLoggedIn
          ? Text(
              user!.nickname.isNotEmpty ? user!.nickname : '已登录',
              style: TextStyle(color: cs.outline, fontSize: 13),
            )
          : Text('点击登录', style: TextStyle(color: cs.outline, fontSize: 13)),
      trailing: isLoggedIn
          ? IconButton(
              icon: Icon(Icons.logout, size: 20, color: cs.error),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('退出登录'),
                    content: Text('确定要退出${platform.displayName}账号吗？'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('取消'),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.pop(ctx);
                          onLogout();
                        },
                        child: Text('退出', style: TextStyle(color: cs.error)),
                      ),
                    ],
                  ),
                );
              },
            )
          : Icon(Icons.chevron_right, color: cs.outline),
      onTap: isLoggedIn ? null : onLogin,
    );
  }
}
