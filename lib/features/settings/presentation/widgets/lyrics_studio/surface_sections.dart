import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mconnect/core/lyrics/lyrics_animation_catalog.dart';
import 'package:mconnect/core/lyrics/lyrics_overlay_config.dart';
import 'package:mconnect/core/lyrics/lyrics_overlay_sink.dart';
import 'package:mconnect/features/floating_lyrics/data/sinks/desktop_lyrics_sinks.dart';
import 'package:mconnect/features/floating_lyrics/presentation/providers/floating_lyrics_provider.dart';
import 'package:mconnect/features/floating_lyrics/presentation/providers/taskbar_lyrics_provider.dart';

/// The geometry, typography and behaviour half of the lyrics studio.
///
/// Kept out of lyrics_studio.dart so that file stays the animation/picker shell.
/// Everything here writes through the persisted notifiers, never to a local
/// copy: the two native windows read the same Hive records
/// (docs/desktop-lyrics-protocol.md sections 2.2 and 2.3).
///
/// Why the copy is hard-coded Chinese: lib/l10n/** belongs to the W3-D pass.

/// One labelled row with a slider, matching the studio's existing look.
///
/// [divisions] defaults to one step per whole unit, capped at 48 so a 0..4000
/// range does not turn into 4000 tick marks.
class StudioSlider extends StatelessWidget {
  const StudioSlider({
    super.key,
    required this.sliderKey,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.divisions,
    this.suffix = '',
  });

  final Key sliderKey;
  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final int? divisions;
  final String suffix;

  @override
  Widget build(BuildContext context) {
    final clamped = value.clamp(min, max).toDouble();
    final steps = divisions ?? (max - min).round().clamp(1, 48);
    final text = clamped.toStringAsFixed(
      clamped == clamped.roundToDouble() ? 0 : 1,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: Row(
        children: <Widget>[
          SizedBox(width: 96, child: Text(label)),
          Expanded(
            child: Slider(
              key: sliderKey,
              value: clamped,
              min: min,
              max: max,
              divisions: steps,
              onChanged: onChanged,
            ),
          ),
          SizedBox(
            width: 64,
            child: Text(
              suffix.isEmpty ? text : '$text$suffix',
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}

/// Section title inside the studio card.
class StudioGroupHeader extends StatelessWidget {
  const StudioGroupHeader({super.key, required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: theme.textTheme.titleSmall),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                subtitle!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A "follow the primary screen" aware monitor picker.
///
/// The monitor list comes from the floating overlay channel (the taskbar
/// channel has no getMonitors), so an empty list — Android, an older Windows
/// build, a failed probe — still renders: the current value and the two
/// well-known pseudo-names stay selectable.
class _MonitorDropdown extends StatelessWidget {
  const _MonitorDropdown({
    required this.value,
    required this.monitors,
    required this.onChanged,
  });

  final String value;
  final List<LyricsMonitorInfo> monitors;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final deviceNames = <String>[
      for (final monitor in monitors)
        if (monitor.deviceName.isNotEmpty) monitor.deviceName,
    ];
    final values = <String>[
      '',
      'primary',
      ...deviceNames,
      if (value.isNotEmpty &&
          value != 'primary' &&
          !deviceNames.contains(value))
        value,
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Row(
        children: <Widget>[
          const Icon(Icons.monitor_outlined, size: 20),
          const SizedBox(width: 12),
          const Text('显示器'),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButton<String>(
              key: const Key('lyrics-studio-monitor'),
              isExpanded: true,
              value: value,
              onChanged: (selected) {
                if (selected != null) onChanged(selected);
              },
              items: <DropdownMenuItem<String>>[
                for (final candidate in values)
                  DropdownMenuItem<String>(
                    value: candidate,
                    child: Text(_monitorLabel(candidate, monitors)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _monitorLabel(String value, List<LyricsMonitorInfo> monitors) {
    if (value.isEmpty) return '跟随主屏幕';
    if (value == 'primary') return '主屏幕';
    for (final monitor in monitors) {
      if (monitor.deviceName == value) {
        return monitor.isPrimary ? '主屏幕（$value）' : value;
      }
    }
    return value;
  }
}

/// Everything the floating window's style exposes, minus the animations.
class FloatingLyricsSections extends ConsumerWidget {
  const FloatingLyricsSections({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(floatingLyricsProvider);
    final notifier = ref.read(floatingLyricsProvider.notifier);
    final monitors = ref.watch(
      taskbarLyricsStatusProvider.select((status) => status.monitors),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const StudioGroupHeader(title: '窗口尺寸', subtitle: '原生窗口按这一组值建窗，改完立刻下发'),
        StudioSlider(
          sliderKey: const Key('lyrics-studio-width'),
          label: '宽度',
          value: settings.width,
          min: 180,
          max: 720,
          divisions: 54,
          suffix: ' px',
          onChanged: notifier.setWidth,
        ),
        StudioSlider(
          sliderKey: const Key('lyrics-studio-height'),
          label: '高度',
          value: settings.height,
          min: 56,
          max: 220,
          divisions: 82,
          suffix: ' px',
          onChanged: notifier.setHeight,
        ),
        StudioSlider(
          sliderKey: const Key('lyrics-studio-corner-radius'),
          label: '圆角',
          value: settings.cornerRadius,
          min: 0,
          max: 48,
          onChanged: notifier.setCornerRadius,
        ),
        StudioSlider(
          sliderKey: const Key('lyrics-studio-opacity'),
          label: '背景不透明度',
          value: settings.backgroundOpacity,
          min: 0,
          max: 1,
          divisions: 20,
          onChanged: notifier.setBackgroundOpacity,
        ),
        const StudioGroupHeader(
          title: '位置',
          subtitle: '按屏幕比例定位；「居中 / 重置」清掉手动拖出来的位置',
        ),
        StudioSlider(
          sliderKey: const Key('lyrics-studio-position-x'),
          label: '水平',
          value: settings.positionX ?? 0.5,
          min: 0,
          max: 1,
          divisions: 100,
          onChanged: notifier.setPositionX,
        ),
        StudioSlider(
          sliderKey: const Key('lyrics-studio-position-y-ratio'),
          label: '垂直',
          value: settings.positionYRatio ?? 0.5,
          min: 0,
          max: 1,
          divisions: 100,
          onChanged: notifier.setPositionYRatio,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: <Widget>[
              OutlinedButton.icon(
                key: const Key('lyrics-studio-position-center'),
                onPressed: () => unawaited(notifier.setPositionX(0.5)),
                icon: const Icon(Icons.align_horizontal_center_outlined),
                label: const Text('水平居中'),
              ),
              OutlinedButton.icon(
                key: const Key('lyrics-studio-position-reset'),
                onPressed: () => unawaited(_resetPosition(ref)),
                icon: const Icon(Icons.restart_alt_outlined),
                label: const Text('重置位置'),
              ),
            ],
          ),
        ),
        _MonitorDropdown(
          value: settings.monitorDeviceName,
          monitors: monitors,
          onChanged: (value) => unawaited(notifier.setMonitorDeviceName(value)),
        ),
        const StudioGroupHeader(title: '文字'),
        StudioSlider(
          sliderKey: const Key('lyrics-studio-font-size'),
          label: '字号',
          value: settings.fontSize,
          min: 14,
          max: 48,
          onChanged: notifier.setFontSize,
        ),
        StudioSlider(
          sliderKey: const Key('lyrics-studio-font-weight'),
          label: '字重',
          value: settings.fontWeight.toDouble(),
          min: 100,
          max: 900,
          divisions: 8,
          onChanged: (value) =>
              unawaited(notifier.setFontWeight(value.round())),
        ),
        StudioSlider(
          sliderKey: const Key('lyrics-studio-line-height'),
          label: '行高',
          value: settings.lineHeight,
          min: 0.8,
          max: 3,
          divisions: 22,
          onChanged: notifier.setLineHeight,
        ),
        StudioSlider(
          sliderKey: const Key('lyrics-studio-letter-spacing'),
          label: '字距',
          value: settings.letterSpacing,
          min: -4,
          max: 16,
          divisions: 20,
          onChanged: notifier.setLetterSpacing,
        ),
        StudioSlider(
          sliderKey: const Key('lyrics-studio-padding'),
          label: '内边距',
          value: settings.padding,
          min: 0,
          max: 64,
          onChanged: notifier.setPadding,
        ),
        StudioSlider(
          sliderKey: const Key('lyrics-studio-stroke-width'),
          label: '描边宽度',
          value: settings.strokeWidth,
          min: 0,
          max: 2,
          divisions: 20,
          onChanged: notifier.setStrokeWidth,
        ),
        StudioSlider(
          sliderKey: const Key('lyrics-studio-shadow-opacity'),
          label: '阴影不透明度',
          value: settings.shadowOpacity,
          min: 0,
          max: 1,
          divisions: 20,
          onChanged: notifier.setShadowOpacity,
        ),
        _EnumDropdown<LyricsLineMode>(
          dropdownKey: const Key('lyrics-studio-line-mode'),
          icon: Icons.view_stream_outlined,
          label: '行显示',
          value: settings.lineMode,
          // "auto" belongs to the strip: the floating window has no
          // thickness to adapt to.
          values: LyricsLineMode.values
              .where((mode) => mode != LyricsLineMode.auto)
              .toList(growable: false),
          labelOf: (value) => value.label,
          onChanged: (value) => unawaited(notifier.setLineMode(value)),
        ),
        const StudioGroupHeader(title: '行为'),
        SwitchListTile(
          key: const Key('lyrics-studio-click-through'),
          dense: true,
          secondary: const Icon(Icons.mouse_outlined),
          title: const Text('点击穿透'),
          subtitle: const Text('鼠标不再停在窗口上，拖动与按钮都交给下面的播放器'),
          value: settings.clickThrough,
          onChanged: (value) => unawaited(notifier.setClickThrough(value)),
        ),
        SwitchListTile(
          key: const Key('lyrics-studio-always-on-top'),
          dense: true,
          secondary: const Icon(Icons.push_pin_outlined),
          title: const Text('始终置顶'),
          value: settings.alwaysOnTop,
          onChanged: (value) => unawaited(notifier.setAlwaysOnTop(value)),
        ),
        SwitchListTile(
          key: const Key('lyrics-studio-show-controls'),
          dense: true,
          secondary: const Icon(Icons.play_circle_outline),
          title: const Text('显示控制条'),
          subtitle: const Text('窗口内的播放 / 上一首 / 下一首按钮'),
          value: settings.showControls,
          onChanged: (value) => unawaited(notifier.setShowControls(value)),
        ),
        _EnumDropdown<LyricsTranslationVisibility>(
          dropdownKey: const Key('lyrics-studio-show-translation'),
          icon: Icons.translate_outlined,
          label: '显示翻译',
          value: settings.showTranslation,
          values: LyricsTranslationVisibility.values,
          labelOf: (value) => value.label,
          onChanged: (value) => unawaited(notifier.setShowTranslation(value)),
        ),
      ],
    );
  }

  /// Resets the native window first (it owns the live rectangle), then clears
  /// the persisted ratios so the next show() starts from the default spot.
  Future<void> _resetPosition(WidgetRef ref) async {
    for (final sink in ref.read(desktopLyricsSinksProvider)) {
      if (sink.surface == LyricsSurface.floating) {
        await sink.resetPosition();
      }
    }
    await ref.read(floatingLyricsProvider.notifier).clearPosition();
  }
}

/// Everything the taskbar strip's style exposes, plus its live status.
class TaskbarLyricsSections extends ConsumerWidget {
  const TaskbarLyricsSections({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(taskbarLyricsProvider);
    final notifier = ref.read(taskbarLyricsProvider.notifier);
    final monitors = ref.watch(
      taskbarLyricsStatusProvider.select((status) => status.monitors),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const TaskbarStatusBar(),
        const StudioGroupHeader(
          title: '位置与尺寸',
          subtitle: '锚点决定贴哪一侧，偏移是相对自由区域的水平微调',
        ),
        _MonitorDropdown(
          value: settings.monitorDeviceName,
          monitors: monitors,
          onChanged: (value) => unawaited(notifier.setMonitorDeviceName(value)),
        ),
        _EnumDropdown<LyricsTaskbarAnchor>(
          dropdownKey: const Key('lyrics-studio-anchor'),
          icon: Icons.vertical_align_center_outlined,
          label: '锚点',
          value: settings.anchor,
          values: LyricsTaskbarAnchor.values,
          labelOf: (value) => value.label,
          onChanged: (value) => unawaited(notifier.setAnchor(value)),
        ),
        StudioSlider(
          sliderKey: const Key('lyrics-studio-offset-x'),
          label: '水平偏移',
          value: settings.offsetX,
          min: -4000,
          max: 4000,
          divisions: 80,
          suffix: ' px',
          onChanged: notifier.setOffsetX,
        ),
        StudioSlider(
          sliderKey: const Key('lyrics-studio-width'),
          label: '宽度',
          value: settings.width,
          min: 160,
          max: 3000,
          divisions: 142,
          suffix: ' px',
          onChanged: notifier.setWidth,
        ),
        StudioSlider(
          sliderKey: const Key('lyrics-studio-height'),
          label: '高度',
          value: settings.height,
          min: 0,
          max: 400,
          divisions: 40,
          suffix: ' px',
          onChanged: notifier.setHeight,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(128, 0, 16, 0),
          child: Text(
            '高度 0 = 跟随任务栏厚度',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        StudioSlider(
          sliderKey: const Key('lyrics-studio-edge-padding'),
          label: '边距',
          value: settings.edgePadding,
          min: 0,
          max: 32,
          onChanged: notifier.setEdgePadding,
        ),
        StudioSlider(
          sliderKey: const Key('lyrics-studio-corner-radius'),
          label: '圆角',
          value: settings.cornerRadius,
          min: 0,
          max: 48,
          onChanged: notifier.setCornerRadius,
        ),
        const StudioGroupHeader(title: '背景与文字'),
        _EnumDropdown<LyricsBackgroundMode>(
          dropdownKey: const Key('lyrics-studio-background-mode'),
          icon: Icons.gradient_outlined,
          label: '背景模式',
          value: settings.backgroundMode,
          values: LyricsBackgroundMode.values,
          labelOf: (value) => value.label,
          onChanged: (value) => unawaited(notifier.setBackgroundMode(value)),
        ),
        _ColorSwatches(
          swatchKey: const Key('lyrics-studio-background-color'),
          label: '背景颜色',
          value: settings.backgroundColor,
          onChanged: (color) => unawaited(notifier.setBackgroundColor(color)),
        ),
        StudioSlider(
          sliderKey: const Key('lyrics-studio-opacity'),
          label: '背景不透明度',
          value: settings.backgroundOpacity,
          min: 0,
          max: 1,
          divisions: 20,
          onChanged: notifier.setBackgroundOpacity,
        ),
        StudioSlider(
          sliderKey: const Key('lyrics-studio-font-size'),
          label: '字号',
          value: settings.fontSize,
          min: 8,
          max: 48,
          onChanged: notifier.setFontSize,
        ),
        StudioSlider(
          sliderKey: const Key('lyrics-studio-font-weight'),
          label: '字重',
          value: settings.fontWeight.toDouble(),
          min: 100,
          max: 900,
          divisions: 8,
          onChanged: (value) =>
              unawaited(notifier.setFontWeight(value.round())),
        ),
        _EnumDropdown<LyricsLineMode>(
          dropdownKey: const Key('lyrics-studio-line-mode'),
          icon: Icons.view_stream_outlined,
          label: '行显示',
          value: settings.lineMode,
          values: LyricsLineMode.values,
          labelOf: (value) => value.label,
          onChanged: (value) => unawaited(notifier.setLineMode(value)),
        ),
        _EnumDropdown<LyricsTranslationLayout>(
          dropdownKey: const Key('lyrics-studio-translation-layout'),
          icon: Icons.format_line_spacing_outlined,
          label: '译文布局',
          value: settings.translationLayout,
          values: LyricsTranslationLayout.values,
          labelOf: (value) => value.label,
          onChanged: (value) => unawaited(notifier.setTranslationLayout(value)),
        ),
        const StudioGroupHeader(title: '行为'),
        SwitchListTile(
          key: const Key('lyrics-studio-marquee'),
          dense: true,
          secondary: const Icon(Icons.text_fields_outlined),
          title: const Text('跑马灯'),
          subtitle: const Text('一行放不下时横向滚动，而不是截断'),
          value: settings.marquee,
          onChanged: (value) => unawaited(notifier.setMarquee(value)),
        ),
        SwitchListTile(
          key: const Key('lyrics-studio-follow-auto-hide'),
          dense: true,
          secondary: const Icon(Icons.visibility_off_outlined),
          title: const Text('跟随自动隐藏'),
          subtitle: const Text('任务栏自动隐藏时，歌词条一起收起'),
          value: settings.followAutoHide,
          onChanged: (value) => unawaited(notifier.setFollowAutoHide(value)),
        ),
        SwitchListTile(
          key: const Key('lyrics-studio-hide-in-fullscreen'),
          dense: true,
          secondary: const Icon(Icons.fullscreen_outlined),
          title: const Text('全屏时隐藏'),
          value: settings.hideInFullscreen,
          onChanged: (value) => unawaited(notifier.setHideInFullscreen(value)),
        ),
        SwitchListTile(
          key: const Key('lyrics-studio-click-through'),
          dense: true,
          secondary: const Icon(Icons.mouse_outlined),
          title: const Text('点击穿透'),
          value: settings.clickThrough,
          onChanged: (value) => unawaited(notifier.setClickThrough(value)),
        ),
        SwitchListTile(
          key: const Key('lyrics-studio-debug-geometry'),
          dense: true,
          secondary: const Icon(Icons.straighten_outlined),
          title: const Text('调试几何'),
          subtitle: const Text('在条上画出任务栏 / 自由区域的边框，排查停靠问题'),
          value: settings.debugGeometry,
          onChanged: (value) => unawaited(notifier.setDebugGeometry(value)),
        ),
      ],
    );
  }
}

/// The strip's live state, with the one action that can fix a wrong reading.
class TaskbarStatusBar extends ConsumerWidget {
  const TaskbarStatusBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(taskbarLyricsStatusProvider);
    final theme = Theme.of(context);
    final rect = status.placement;
    // The rectangle is the answer to "did my slider do anything": it changes on
    // every placement, including the ones that happen while the strip itself is
    // hard to spot against a busy taskbar.
    final geometry = rect == null
        ? ''
        : ' · 宽 ${rect.width.round()}×${rect.height.round()}'
              ' · 位置 ${rect.left.round()},${rect.top.round()}';
    final label = !status.found
        ? '未找到任务栏，已隐藏'
        : '已停靠：${_edgeLabel(status.edge)}$geometry';
    final hint = status.lastError ??
        (status.spaceInsufficient ? '任务栏应用区已被系统占满，歌词条铺满整条任务栏' : null);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: <Widget>[
            Icon(
              status.found ? Icons.check_circle_outline : Icons.error_outline,
              size: 20,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    label,
                    key: const Key('lyrics-studio-taskbar-status'),
                    style: theme.textTheme.bodySmall,
                  ),
                  if (hint != null)
                    Text(
                      hint,
                      key: const Key('lyrics-studio-taskbar-status-hint'),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            TextButton(
              key: const Key('lyrics-studio-taskbar-refresh'),
              onPressed: () => unawaited(
                ref.read(taskbarLyricsStatusProvider.notifier).refresh(),
              ),
              child: const Text('重新探测'),
            ),
          ],
        ),
      ),
    );
  }

  static String _edgeLabel(String edge) {
    return switch (edge) {
      'bottom' => '底部',
      'top' => '顶部',
      'left' => '左侧',
      'right' => '右侧',
      _ => edge,
    };
  }
}

/// Icon + label + [DropdownButton] row, used for every enum the styles expose.
class _EnumDropdown<T> extends StatelessWidget {
  const _EnumDropdown({
    required this.dropdownKey,
    required this.icon,
    required this.label,
    required this.value,
    required this.values,
    required this.labelOf,
    required this.onChanged,
  });

  final Key dropdownKey;
  final IconData icon;
  final String label;
  final T value;
  final List<T> values;
  final String Function(T value) labelOf;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 20),
          const SizedBox(width: 12),
          Text(label),
          const SizedBox(width: 12),
          DropdownButton<T>(
            key: dropdownKey,
            value: value,
            onChanged: (selected) {
              if (selected != null) onChanged(selected);
            },
            items: <DropdownMenuItem<T>>[
              for (final option in values)
                DropdownMenuItem<T>(
                  value: option,
                  child: Text(labelOf(option)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A short swatch row: the strip only needs a background tint, not a picker
/// dialog with a full hue wheel.
class _ColorSwatches extends StatelessWidget {
  const _ColorSwatches({
    required this.swatchKey,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final Key swatchKey;
  final String label;
  final Color value;
  final ValueChanged<Color> onChanged;

  static const List<Color> _presets = <Color>[
    Color(0xFF000000),
    Color(0xFFFFFFFF),
    Color(0xFF1E1E1E),
    Color(0xFF1B2430),
    Color(0xFF2A1F3D),
    Color(0xFF102A1E),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: <Widget>[
          const Icon(Icons.palette_outlined, size: 20),
          const SizedBox(width: 12),
          SizedBox(width: 72, child: Text(label)),
          Expanded(
            child: Wrap(
              key: swatchKey,
              spacing: 8,
              runSpacing: 4,
              children: <Widget>[
                for (final preset in _presets)
                  InkWell(
                    onTap: () => onChanged(preset),
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: preset,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: preset.toARGB32() == value.toARGB32()
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.outlineVariant,
                          width: preset.toARGB32() == value.toARGB32() ? 3 : 1,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
