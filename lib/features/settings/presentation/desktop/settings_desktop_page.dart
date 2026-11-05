import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/desktop/desktop_behavior_settings.dart';
import '../../../../core/desktop/desktop_page_scaffold.dart';
import '../../../../core/desktop/desktop_runtime_status.dart';
import '../../../../core/desktop/desktop_tokens.dart';
import '../../../../l10n/l10n.dart';
import '../pages/settings_page.dart';
import '../widgets/lyrics_studio/lyrics_studio.dart';
import 'downloads_section.dart';
import 'widgets/desktop_settings_card.dart';

/// One settings section, addressable by URL.
///
/// The `id` is what `?section=` carries. It is derived from the location on
/// every build (see [SettingsDesktopPage]) instead of being kept in local
/// state, which is what makes the sidebar's 「账号与平台」 chip land on the
/// accounts section: it has always linked to `/settings?section=accounts`, but
/// the page used to ignore the parameter and open on 歌词窗口.
enum _SettingsSection {
  accounts('accounts', '账号与平台', Icons.person_outline),
  appearance('appearance', '外观', Icons.palette_outlined),
  playback('playback', '播放', Icons.play_circle_outline),
  lyrics('lyrics', '歌词窗口', Icons.lyrics_outlined),
  audio('audio', '音频增强', Icons.equalizer),
  downloads('downloads', '下载与缓存', Icons.download_outlined),
  desktop('desktop', null, Icons.desktop_windows_outlined),
  diagnostics('diagnostics', '诊断与关于', Icons.build_outlined);

  const _SettingsSection(this.id, this.label, this.icon);

  final String id;

  /// Null only for [desktop], whose label comes from l10n (its copy was added
  /// after the i18n freeze, so it must not grow the hard-coded-Chinese count).
  final String? label;
  final IconData icon;

  String labelFor(BuildContext context) =>
      label ?? context.l10n.desktopBehavior;

  static _SettingsSection fromId(String? id) {
    for (final section in values) {
      if (section.id == id) return section;
    }
    // Unknown or absent: the first section, which is what the sidebar order
    // promises. Never the lyrics studio any more -- that default is exactly
    // the extra click the account chip used to cost.
    return _SettingsSection.accounts;
  }
}

class SettingsDesktopPage extends StatelessWidget {
  const SettingsDesktopPage({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final section = _SettingsSection.fromId(
      GoRouterState.of(context).uri.queryParameters['section'],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const DesktopPageHeader(
          title: '设置',
          subtitle: '账号、外观、播放与歌词窗口',
        ),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 220,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(
                    DesktopSpacing.xl,
                    DesktopSpacing.sm,
                    DesktopSpacing.md,
                    DesktopSpacing.xl,
                  ),
                  children: [
                    for (final item in _SettingsSection.values)
                      _SectionTile(
                        item: item,
                        label: item.labelFor(context),
                        selected: item == section,
                        onTap: () => context.go(
                          '/settings?section=${item.id}',
                        ),
                      ),
                  ],
                ),
              ),
              VerticalDivider(
                width: 1,
                color: scheme.outlineVariant.withValues(alpha: 0.4),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(
                    DesktopSpacing.xxl,
                    DesktopSpacing.sm,
                    DesktopSpacing.xxl,
                    DesktopSpacing.xxxl,
                  ),
                  children: [
                    Text(
                      section.labelFor(context),
                      style: DesktopText.headline.copyWith(
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: DesktopSpacing.xs),
                    Text(
                      _subtitleFor(context, section),
                      style: DesktopText.body.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: DesktopSpacing.lg),
                    _content(context, section),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _subtitleFor(BuildContext context, _SettingsSection section) {
    switch (section) {
      case _SettingsSection.accounts:
        return '登录网易云、QQ 音乐、酷狗，同步收藏与歌单';
      case _SettingsSection.appearance:
        return '主题、强调色与桌面背景';
      case _SettingsSection.playback:
        return '淡入淡出与睡眠定时';
      case _SettingsSection.lyrics:
        return '悬浮歌词与任务栏歌词的样式、位置与动画';
      case _SettingsSection.audio:
        return '均衡器、自动换源与音频增强';
      case _SettingsSection.downloads:
        return '下载目录、离线缓存与清理';
      case _SettingsSection.desktop:
        return context.l10n.desktopBehaviorSubtitle;
      case _SettingsSection.diagnostics:
        return '日志、版本与平台诊断';
    }
  }

  /// Every section renders its rows **right here**.
  ///
  /// The page used to show a 「打开 XX 设置」 card per section and push a second
  /// screen for the actual controls, so a user who picked 账号与平台 in the
  /// sidebar still had to find and press another button. The mobile pages keep
  /// their Scaffold for phone navigation; `embedded: true` gives this page the
  /// identical rows without the wrapper.
  Widget _content(BuildContext context, _SettingsSection section) {
    switch (section) {
      case _SettingsSection.accounts:
        return const DesktopSettingsCard(
          title: '平台账号',
          subtitle: '三平台独立登录；登录后自动同步收藏与歌单',
          child: SettingsAccountsPage(embedded: true),
        );
      case _SettingsSection.appearance:
        return const DesktopSettingsCard(
          title: '主题与背景',
          subtitle: '主题模式、强调色、界面风格与桌面背景',
          child: SettingsAppearancePage(
            embedded: true,
            showUiStyle: false,
          ),
        );
      case _SettingsSection.playback:
        return const DesktopSettingsCard(
          title: '播放选项',
          subtitle: '淡入淡出与睡眠定时（倍速、A-B 循环在播放页的「播放设置」里）',
          child: SettingsAudioPage(
            embedded: true,
            section: SettingsAudioSection.playback,
          ),
        );
      case _SettingsSection.lyrics:
        return const LyricsStudio(autoPlayPreview: true);
      case _SettingsSection.audio:
        return const DesktopSettingsCard(
          title: '音频增强',
          subtitle: '均衡器、预设与自动换源',
          child: SettingsAudioPage(
            embedded: true,
            section: SettingsAudioSection.audioEffects,
          ),
        );
      case _SettingsSection.downloads:
        return const DesktopDownloadsSection();
      case _SettingsSection.desktop:
        return const _DesktopBehaviorContent();
      case _SettingsSection.diagnostics:
        return const DesktopSettingsCard(
          title: '诊断与关于',
          subtitle: '日志位置、平台诊断与版本',
          child: SettingsDiagnosticsPage(embedded: true),
        );
    }
  }
}

class _SectionTile extends StatelessWidget {
  final _SettingsSection item;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SectionTile({
    required this.item,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: selected
            ? scheme.primary.withValues(alpha: 0.12)
            : Colors.transparent,
        borderRadius: DesktopRadii.mdAll,
        child: InkWell(
          key: ValueKey('settings-section-${item.id}'),
          onTap: onTap,
          borderRadius: DesktopRadii.mdAll,
          hoverColor: scheme.onSurface.withValues(alpha: 0.05),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: DesktopSpacing.md,
              vertical: DesktopSpacing.sm,
            ),
            child: Row(
              children: [
                Icon(
                  item.icon,
                  size: 18,
                  color: selected ? scheme.primary : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: DesktopSpacing.sm),
                Expanded(
                  child: Text(
                    label,
                    style: DesktopText.body.copyWith(
                      color: selected ? scheme.primary : scheme.onSurface,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DesktopBehaviorContent extends ConsumerWidget {
  const _DesktopBehaviorContent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _RuntimeStatusCard(),
        const SizedBox(height: DesktopSpacing.md),
        const DesktopBehaviorSettingsSection(),
      ],
    );
  }
}

/// What the runner actually answered, next to the switches that asked for it.
///
/// A switch that is on while the tray icon is missing, or while the hotkey was
/// rejected, is indistinguishable from a working one unless the page says so.
class _RuntimeStatusCard extends ConsumerWidget {
  const _RuntimeStatusCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(desktopRuntimeStatusProvider);
    final scheme = Theme.of(context).colorScheme;

    Widget row({
      required IconData icon,
      required String title,
      required String subtitle,
      required bool? ok,
    }) {
      return ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(
          icon,
          color: ok == null
              ? scheme.onSurfaceVariant
              : (ok ? scheme.primary : scheme.error),
        ),
        title: Text(title),
        subtitle: Text(subtitle),
      );
    }

    final tray = status.trayReady;
    final trayError = status.trayError;
    final hotkeys = status.hotkeysRegistered;
    final smtc = status.smtcAvailable;
    // 关闭结局：隐藏到托盘 / 无托盘也隐藏到后台（可双击唤回）/ 旧版最小化 / 退出。
    final hiddenToBackground = status.lastCloseHiddenToTray && tray == false;
    final closeText = hiddenToBackground
        ? '已隐藏到后台（托盘不可用）：再次双击 Mconnect 可唤回窗口'
        : status.trayKeptWindowOpen
        ? '托盘不可用：已保持窗口打开，未关闭'
        : status.minimizedInsteadOfTray
        ? '托盘不可用，已最小化到任务栏'
        : status.lastCloseHiddenToTray
        ? '已隐藏到托盘'
        : (status.lastCloseFellBackToExit ? '已直接退出' : '尚未关闭过');
    // 文案必须和真实行为一致：托盘不可用时窗口**照样隐藏**（用户的诉求是别留在
    // 任务栏），但必须说清怎么把它叫回来，否则就变成"程序不见了"。
    final trayText = switch (tray) {
      null => '尚未收到运行器答复',
      true => '已就绪',
      false when trayError != null =>
        '不可用（错误码 $trayError）：关窗会隐藏到后台，双击 Mconnect 可唤回',
      false => '不可用：关窗会隐藏到后台，双击 Mconnect 可唤回',
    };
    // 低完整性进程（沙箱/受限启动）与资源管理器不同级别，UIPI 会直接拦住
    // Shell_NotifyIcon，系统返回 ACCESS_DENIED。这是唯一能解释"所有进程都加不上
    // 托盘图标"的原因，必须写出来，否则又会被当成程序 bug。
    final integrity = status.integrityLevel;
    final elevatedHint = integrity != null && integrity <= 0x1000
        ? '当前进程完整性 0x${integrity.toRadixString(16)}（低），系统会拒绝托盘图标；'
              '请直接双击 mconnect.exe 启动'
        : null;

    return DesktopSettingsCard(
      title: '运行状态',
      subtitle: '开关是否真的生效，以这里为准；Win11 的新图标可能收在任务栏「^」溢出区',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          row(
            icon: Icons.notifications_active_outlined,
            title: '托盘图标',
            subtitle: elevatedHint == null
                ? trayText
                : '$trayText；$elevatedHint',
            ok: tray,
          ),
          row(
            icon: Icons.keyboard_outlined,
            title: '全局热键',
            subtitle: hotkeys == null
                ? '尚未注册'
                : (hotkeys ? '已注册' : '注册失败：快捷键可能被其他程序占用'),
            ok: hotkeys,
          ),
          row(
            icon: Icons.album_outlined,
            title: '系统媒体面板',
            subtitle: smtc == null
                ? '尚未收到运行器答复'
                : (smtc ? '可用' : '不可用（不影响播放）'),
            ok: smtc,
          ),
          row(
            icon: Icons.close_fullscreen_outlined,
            title: '最近一次关闭',
            subtitle: closeText,
            // 「保持窗口打开」和「最小化」都是"关闭没有按设置生效"的告警，
            // 既不是成功也不是退出。
            ok: status.trayKeptWindowOpen || status.minimizedInsteadOfTray
                ? false
                : (status.lastCloseHiddenToTray ||
                          status.lastCloseFellBackToExit
                      ? status.lastCloseHiddenToTray
                      : null),
          ),
        ],
      ),
    );
  }
}

/// The 「桌面行为」 section: tray, window memory, global hotkeys and sleep.
///
/// Public (not `_`, unlike the appearance section) so
/// `test/settings_desktop_page_test.dart` can pump it on its own. The full
/// settings shell builds the lyrics studio first, whose preview ticker would
/// otherwise run through every assertion in this file.
///
/// It only ever touches the [desktopBehaviorSettingsProvider] and — for the one
/// destructive action — the injected [desktopIntegrationServiceProvider]. The
/// channel calls that keep the runner in sync live in `lib/app.dart`, so there is
/// exactly one place that translates settings into native calls.
class DesktopBehaviorSettingsSection extends ConsumerWidget {
  const DesktopBehaviorSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final settings = ref.watch(desktopBehaviorSettingsProvider);
    final notifier = ref.read(desktopBehaviorSettingsProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DesktopSettingsCard(
          title: l.desktopWindowSection,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SwitchListTile(
                key: const Key('desktop-close-to-tray'),
                contentPadding: EdgeInsets.zero,
                title: Text(l.desktopCloseToTray),
                subtitle: Text(l.desktopCloseToTraySubtitle),
                value: settings.closeToTray,
                onChanged: (value) => unawaited(notifier.setCloseToTray(value)),
              ),
              SwitchListTile(
                key: const Key('desktop-first-run-hint'),
                contentPadding: EdgeInsets.zero,
                title: Text(l.desktopFirstRunHint),
                subtitle: Text(l.desktopFirstRunHintSubtitle),
                value: settings.firstRunHint,
                onChanged: (value) =>
                    unawaited(notifier.setFirstRunHint(value)),
              ),
              SwitchListTile(
                key: const Key('desktop-remember-window'),
                contentPadding: EdgeInsets.zero,
                title: Text(l.desktopRememberWindow),
                subtitle: Text(l.desktopRememberWindowSubtitle),
                value: settings.rememberWindowState,
                onChanged: (value) =>
                    unawaited(notifier.setRememberWindowState(value)),
              ),
              const SizedBox(height: DesktopSpacing.sm),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  key: const Key('desktop-reset-window'),
                  onPressed: () => _resetWindowState(context, ref),
                  icon: const Icon(Icons.settings_backup_restore, size: 18),
                  label: Text(l.desktopResetWindow),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: DesktopSpacing.md),
        DesktopSettingsCard(
          title: l.desktopHotkeysSection,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SwitchListTile(
                key: const Key('desktop-hotkeys-enabled'),
                contentPadding: EdgeInsets.zero,
                title: Text(l.desktopHotkeysEnabled),
                subtitle: Text(l.desktopHotkeysEnabledSubtitle),
                value: settings.hotkeysEnabled,
                onChanged: (value) =>
                    unawaited(notifier.setHotkeysEnabled(value)),
              ),
              _HotkeyField(
                fieldKey: const Key('desktop-hotkey-toggle-lyrics'),
                label: l.desktopHotkeyToggleLyrics,
                value: settings.toggleLyricsHotkey,
                enabled: settings.hotkeysEnabled,
                onSubmitted: (value) =>
                    unawaited(notifier.setToggleLyricsHotkey(value)),
              ),
              _HotkeyField(
                fieldKey: const Key('desktop-hotkey-play-pause'),
                label: l.desktopHotkeyPlayPause,
                value: settings.playPauseHotkey,
                enabled: settings.hotkeysEnabled,
                onSubmitted: (value) =>
                    unawaited(notifier.setPlayPauseHotkey(value)),
              ),
              SwitchListTile(
                key: const Key('desktop-prevent-sleep'),
                contentPadding: EdgeInsets.zero,
                title: Text(l.desktopPreventSleep),
                subtitle: Text(l.desktopPreventSleepSubtitle),
                value: settings.preventSleepWhilePlaying,
                onChanged: (value) =>
                    unawaited(notifier.setPreventSleepWhilePlaying(value)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Asks the runner to forget the remembered window rectangle.
///
/// The messenger is captured **before** the await: the widget can be gone by the
/// time the channel answers, and `ScaffoldMessenger.of` after an await is the
/// classic `use_build_context_synchronously` trap.
Future<void> _resetWindowState(BuildContext context, WidgetRef ref) async {
  final l = context.l10n;
  final messenger = ScaffoldMessenger.maybeOf(context);
  final reset = await ref
      .read(desktopIntegrationServiceProvider)
      .resetWindowState();
  if (!context.mounted) return;
  messenger?.showSnackBar(
    SnackBar(
      content: Text(
        reset ? l.desktopResetWindowDone : l.desktopResetWindowFailed,
      ),
    ),
  );
}

/// One global-hotkey field.
///
/// Commits on submit **and** on focus loss: a chord typed and then clicked away
/// from must not be silently dropped, and a per-keystroke save would write Hive
/// on every character.
class _HotkeyField extends StatefulWidget {
  const _HotkeyField({
    required this.fieldKey,
    required this.label,
    required this.value,
    required this.enabled,
    required this.onSubmitted,
  });

  /// Key of the inner [TextField], so a test can target the field itself.
  final Key fieldKey;
  final String label;
  final String value;
  final bool enabled;
  final ValueChanged<String> onSubmitted;

  @override
  State<_HotkeyField> createState() => _HotkeyFieldState();
}

class _HotkeyFieldState extends State<_HotkeyField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );
  final FocusNode _focusNode = FocusNode();
  late String _lastSubmitted = widget.value;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_handleFocusChange);
  }

  void _handleFocusChange() {
    if (!_focusNode.hasFocus) _commit();
  }

  @override
  void didUpdateWidget(covariant _HotkeyField oldWidget) {
    super.didUpdateWidget(oldWidget);
    _lastSubmitted = widget.value;
    // Never overwrite what the user is in the middle of typing: a parent
    // rebuild (another switch toggled) must not reset the caret.
    if (!_focusNode.hasFocus && _controller.text != widget.value) {
      _controller.text = widget.value;
    }
  }

  void _commit() {
    final text = _controller.text.trim();
    if (text == _lastSubmitted) return;
    _lastSubmitted = text;
    widget.onSubmitted(text);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: DesktopSpacing.sm),
      child: TextField(
        key: widget.fieldKey,
        controller: _controller,
        focusNode: _focusNode,
        enabled: widget.enabled,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(
          labelText: widget.label,
          hintText: context.l10n.desktopHotkeyHint,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
        onSubmitted: (_) {
          _commit();
          _focusNode.unfocus();
        },
      ),
    );
  }
}