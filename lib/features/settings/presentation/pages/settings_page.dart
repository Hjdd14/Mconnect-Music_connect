import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mconnect/core/diagnostics/diagnostics_service.dart';
import 'package:mconnect/core/platform/platform_utils.dart';
import 'package:mconnect/core/theme/app_theme.dart';
import 'package:mconnect/core/theme/theme_provider.dart';
import 'package:mconnect/features/auth/presentation/providers/auth_provider.dart';
import 'package:mconnect/features/audio_effects/presentation/providers/audio_effects_provider.dart';
import 'package:mconnect/features/audio_effects/presentation/providers/sleep_timer_provider.dart';
import 'package:mconnect/features/floating_lyrics/data/floating_lyrics_service.dart';
import 'package:mconnect/features/floating_lyrics/presentation/providers/floating_lyrics_provider.dart';
import 'package:mconnect/models/platform_type.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  static const _themePresets = [
    Color(0xFFE91E63),
    Color(0xFF31C27C),
    Color(0xFF2F80ED),
    Color(0xFF7B61FF),
    Color(0xFFFF8A00),
    Color(0xFF111827),
  ];

  static const lyricTextPresets = [
    Color(0xFFFFF4F8),
    Colors.white,
    Color(0xFFB8F7FF),
    Color(0xFFFFF2A8),
    Color(0xFF111827),
    Color(0xFF0F172A),
    Color(0xFF1F2937),
    Color(0xFF312E81),
  ];

  static const lyricHighlightPresets = [
    Color(0xFFFFD44A),
    Color(0xFF31C27C),
    Color(0xFF64B5F6),
    Color(0xFFFF7AAE),
    Color(0xFF1E3A8A),
    Color(0xFF14532D),
    Color(0xFF581C87),
    Color(0xFF7F1D1D),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeSettings = ref.watch(themeSettingsProvider);
    final themeNotifier = ref.read(themeSettingsProvider.notifier);
    final floatingLyrics = ref.watch(floatingLyricsProvider);
    final floatingLyricsNotifier = ref.read(floatingLyricsProvider.notifier);
    final audioEffects = ref.watch(audioEffectsSettingsProvider);
    final audioEffectsNotifier = ref.read(
      audioEffectsSettingsProvider.notifier,
    );
    final sleepTimer = ref.watch(sleepTimerProvider);
    final sleepTimerNotifier = ref.read(sleepTimerProvider.notifier);
    final authState = ref.watch(authProvider);
    final isWindows = PlatformUtils.isWindows;

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
            selected: themeSettings.mode == ThemeMode.system,
            onTap: () => themeNotifier.setMode(ThemeMode.system),
          ),
          _ThemeTile(
            title: '浅色模式',
            icon: Icons.light_mode,
            selected: themeSettings.mode == ThemeMode.light,
            onTap: () => themeNotifier.setMode(ThemeMode.light),
          ),
          _ThemeTile(
            title: '深色模式',
            icon: Icons.dark_mode,
            selected: themeSettings.mode == ThemeMode.dark,
            onTap: () => themeNotifier.setMode(ThemeMode.dark),
          ),
          _ColorPresetTile(
            title: '主题色',
            subtitle: '影响按钮、进度条、导航栏和高亮状态',
            icon: Icons.palette_outlined,
            selectedColor: themeSettings.seedColor,
            presets: _themePresets,
            fallbackColor: AppTheme.defaultSeedColor,
            onSelected: themeNotifier.setSeedColor,
          ),
          const Divider(),
          const _SectionHeader('悬浮歌词'),
          SwitchListTile(
            secondary: const Icon(Icons.picture_in_picture_alt_outlined),
            title: const Text('桌面悬浮歌词'),
            subtitle: Text(
              isWindows ? 'Windows 悬浮歌词将在原生置顶窗口完成后启用' : '显示在其他应用上方，需要系统悬浮窗权限',
            ),
            value: !isWindows && floatingLyrics.enabled,
            onChanged: isWindows
                ? null
                : (value) async {
                    if (value) {
                      final allowed = await FloatingLyricsService.instance
                          .canDrawOverlays();
                      if (!allowed) {
                        await FloatingLyricsService.instance
                            .openOverlaySettings();
                      }
                    } else {
                      await FloatingLyricsService.instance.hide();
                    }
                    await floatingLyricsNotifier.setEnabled(value);
                  },
          ),
          _ColorPresetTile(
            title: '歌词颜色',
            subtitle: '透明背景下的主歌词颜色',
            icon: Icons.format_color_text,
            selectedColor: floatingLyrics.textColor,
            presets: lyricTextPresets,
            fallbackColor: const Color(0xFFFFF4F8),
            onSelected: floatingLyricsNotifier.setTextColor,
          ),
          _ColorPresetTile(
            title: '高亮颜色',
            subtitle: '逐字歌词和当前播放片段的颜色',
            icon: Icons.border_color_outlined,
            selectedColor: floatingLyrics.highlightColor,
            presets: lyricHighlightPresets,
            fallbackColor: const Color(0xFFFFD44A),
            onSelected: floatingLyricsNotifier.setHighlightColor,
          ),
          _SliderTile(
            title: '字号',
            subtitle: '${floatingLyrics.fontSize.round()} px',
            icon: Icons.text_fields,
            value: floatingLyrics.fontSize,
            min: 14,
            max: 48,
            divisions: 34,
            onChanged: floatingLyricsNotifier.setFontSize,
          ),
          _SliderTile(
            title: '描边强度',
            subtitle: floatingLyrics.strokeWidth.toStringAsFixed(1),
            icon: Icons.format_shapes_outlined,
            value: floatingLyrics.strokeWidth,
            min: 0,
            max: 2,
            divisions: 20,
            onChanged: floatingLyricsNotifier.setStrokeWidth,
          ),
          _SliderTile(
            title: '阴影强度',
            subtitle: '${(floatingLyrics.shadowOpacity * 100).round()}%',
            icon: Icons.blur_on,
            value: floatingLyrics.shadowOpacity,
            min: 0,
            max: 1,
            divisions: 20,
            onChanged: floatingLyricsNotifier.setShadowOpacity,
          ),
          const Divider(),
          const _SectionHeader('音频增强'),
          SwitchListTile(
            secondary: const Icon(Icons.graphic_eq),
            title: const Text('淡入淡出'),
            subtitle: const Text('播放、暂停时平滑调整音量，默认关闭'),
            value: audioEffects.fadeEnabled,
            onChanged: audioEffectsNotifier.setFadeEnabled,
          ),
          _SliderTile(
            title: '淡入淡出时长',
            subtitle: '${audioEffects.fadeDuration.inMilliseconds} ms',
            icon: Icons.timelapse,
            value: audioEffects.fadeDuration.inMilliseconds.toDouble(),
            min: 200,
            max: 3000,
            divisions: 14,
            onChanged: (value) => audioEffectsNotifier.setFadeDuration(
              Duration(milliseconds: value.round()),
            ),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.equalizer),
            title: const Text('均衡器'),
            subtitle: Text(
              isWindows
                  ? 'Windows 端暂不启用 Android 原生均衡器'
                  : '调整播放音频的频段增益，设备不支持时会自动忽略',
            ),
            value: !isWindows && audioEffects.equalizerEnabled,
            onChanged: isWindows
                ? null
                : audioEffectsNotifier.setEqualizerEnabled,
          ),
          if (!isWindows) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.tune),
                title: const Text('均衡器预设'),
                subtitle: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final preset in EqualizerPreset.values)
                      ChoiceChip(
                        label: Text(preset.displayName),
                        selected: audioEffects.equalizerPreset == preset,
                        onSelected: (_) =>
                            audioEffectsNotifier.setEqualizerPreset(preset),
                      ),
                  ],
                ),
              ),
            ),
            _SliderTile(
              title: '低频',
              subtitle:
                  '${audioEffects.effectiveEqualizerBandGains[0].round()} dB',
              icon: Icons.graphic_eq,
              value: audioEffects.effectiveEqualizerBandGains[0],
              min: -12,
              max: 12,
              divisions: 24,
              onChanged: (value) =>
                  audioEffectsNotifier.setEqualizerBandGain(0, value),
            ),
            _SliderTile(
              title: '中低频',
              subtitle:
                  '${audioEffects.effectiveEqualizerBandGains[1].round()} dB',
              icon: Icons.graphic_eq,
              value: audioEffects.effectiveEqualizerBandGains[1],
              min: -12,
              max: 12,
              divisions: 24,
              onChanged: (value) =>
                  audioEffectsNotifier.setEqualizerBandGain(1, value),
            ),
            _SliderTile(
              title: '中频',
              subtitle:
                  '${audioEffects.effectiveEqualizerBandGains[2].round()} dB',
              icon: Icons.graphic_eq,
              value: audioEffects.effectiveEqualizerBandGains[2],
              min: -12,
              max: 12,
              divisions: 24,
              onChanged: (value) =>
                  audioEffectsNotifier.setEqualizerBandGain(2, value),
            ),
            _SliderTile(
              title: '中高频',
              subtitle:
                  '${audioEffects.effectiveEqualizerBandGains[3].round()} dB',
              icon: Icons.graphic_eq,
              value: audioEffects.effectiveEqualizerBandGains[3],
              min: -12,
              max: 12,
              divisions: 24,
              onChanged: (value) =>
                  audioEffectsNotifier.setEqualizerBandGain(3, value),
            ),
            _SliderTile(
              title: '高频',
              subtitle:
                  '${audioEffects.effectiveEqualizerBandGains[4].round()} dB',
              icon: Icons.graphic_eq,
              value: audioEffects.effectiveEqualizerBandGains[4],
              min: -12,
              max: 12,
              divisions: 24,
              onChanged: (value) =>
                  audioEffectsNotifier.setEqualizerBandGain(4, value),
            ),
          ],
          SwitchListTile(
            secondary: const Icon(Icons.bedtime_outlined),
            title: const Text('睡眠定时'),
            subtitle: Text(
              sleepTimer.enabled
                  ? '剩余 ${_formatTimerRemaining(sleepTimer.remaining)}'
                  : '${audioEffects.sleepTimerDuration.inMinutes} 分钟后暂停播放',
            ),
            value: sleepTimer.enabled,
            onChanged: sleepTimerNotifier.setEnabled,
          ),
          _SliderTile(
            title: '定时时长',
            subtitle: '${audioEffects.sleepTimerDuration.inMinutes} 分钟',
            icon: Icons.timer_outlined,
            value: audioEffects.sleepTimerDuration.inMinutes.toDouble(),
            min: 5,
            max: 120,
            divisions: 23,
            onChanged: (value) => audioEffectsNotifier.setSleepTimerDuration(
              Duration(minutes: value.round()),
            ),
          ),
          const Divider(),
          const _SectionHeader('诊断'),
          _DiagnosticsTile(diagnostics: DiagnosticsService.instance),
          const Divider(),
          const _SectionHeader('关于'),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('版本'),
            subtitle: Text('1.1.0'),
          ),
        ],
      ),
    );
  }

  String _formatTimerRemaining(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (duration.inHours > 0) {
      return '${duration.inHours}:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }
}

class _ColorPresetTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color selectedColor;
  final Color fallbackColor;
  final List<Color> presets;
  final ValueChanged<Color> onSelected;

  const _ColorPresetTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selectedColor,
    required this.fallbackColor,
    required this.presets,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            leading: Icon(icon),
            title: Text(title),
            subtitle: Text(subtitle),
            trailing: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selectedColor,
                border: Border.all(color: cs.outlineVariant),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(72, 0, 16, 4),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final color in presets)
                  _ColorSwatchButton(
                    color: color,
                    selected: color.toARGB32() == selectedColor.toARGB32(),
                    onTap: () => onSelected(color),
                  ),
                ActionChip(
                  avatar: const Icon(Icons.restart_alt, size: 18),
                  label: const Text('默认'),
                  onPressed: () => onSelected(fallbackColor),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ColorSwatchButton extends StatelessWidget {
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _ColorSwatchButton({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkResponse(
      onTap: onTap,
      radius: 24,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? cs.primary : cs.outlineVariant,
            width: selected ? 3 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: selected ? const Icon(Icons.check, color: Colors.white) : null,
      ),
    );
  }
}

class _SliderTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;

  const _SliderTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Slider(
        value: value.clamp(min, max),
        min: min,
        max: max,
        divisions: divisions,
        label: subtitle,
        onChanged: onChanged,
      ),
      trailing: SizedBox(
        width: 52,
        child: Text(subtitle, textAlign: TextAlign.end),
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
                    content: Text('确定要退出 ${platform.displayName} 账号吗？'),
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
