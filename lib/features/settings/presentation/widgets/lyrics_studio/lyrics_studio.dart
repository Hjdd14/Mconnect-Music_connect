import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mconnect/core/lyrics/lyrics_animation_catalog.dart';
import 'package:mconnect/core/lyrics/lyrics_overlay_config.dart';
import 'package:mconnect/core/lyrics/lyrics_overlay_sink.dart';
import 'package:mconnect/features/floating_lyrics/presentation/providers/floating_lyrics_provider.dart';
import 'package:mconnect/features/floating_lyrics/presentation/providers/taskbar_lyrics_provider.dart';
import 'package:mconnect/features/settings/presentation/widgets/lyrics_studio/animation_picker.dart';
import 'package:mconnect/features/settings/presentation/widgets/lyrics_studio/desktop_lyrics_preview.dart';
import 'package:mconnect/features/settings/presentation/widgets/lyrics_studio/lyrics_studio_controller.dart';
import 'package:mconnect/features/settings/presentation/widgets/lyrics_studio/surface_sections.dart';

/// The embeddable "lyrics studio": pick a surface, watch the in-app preview,
/// then tune geometry, typography and animation for that surface.
///
/// It is deliberately self-contained (own provider, own preview) so
/// settings_page.dart only has to drop the widget in; nothing here touches the
/// router, the player page or the Android layout.
///
/// The style controls live in surface_sections.dart; this file is the shell
/// (surface switch, preview, replay) plus the animation pickers.
///
/// Why the copy is hard-coded Chinese: lib/l10n/** belongs to the W3-D pass,
/// the same reason scrobble_settings_section.dart ships hard-coded strings
/// (see its class comment). Every string here is a candidate ARB key.
class LyricsStudio extends ConsumerWidget {
  const LyricsStudio({
    super.key,
    this.autoPlayPreview = true,
    this.nativePreview,
  });

  /// Tests disable the demo ticker; the production page leaves it running.
  final bool autoPlayPreview;

  /// Optional native preview seam. When null the widget asks the sync
  /// controller; tests inject a no-op so no platform channel is touched.
  final Future<void> Function(
    LyricsSurface surface,
    LyricsLineTransition animation,
  )?
  nativePreview;

  static const List<LyricsPreviewLine> sampleLines = <LyricsPreviewLine>[
    LyricsPreviewLine(
      text: '夜色渐浓，城市在窗外后退',
      translation: 'The night deepens, the city slips behind',
    ),
    LyricsPreviewLine(
      text: '这一刻的旋律刚好',
      translation: 'The melody lands right on time',
    ),
    LyricsPreviewLine(
      text: '把心事交给节拍',
      translation: 'Hand the heart to the beat',
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final floating = ref.watch(floatingLyricsProvider);
    final taskbar = ref.watch(taskbarLyricsProvider);
    final studio = ref.watch(lyricsStudioProvider);
    final surface = studio.surface;
    final isFloating = surface == LyricsSurface.floating;
    final config = isFloating
        ? floating.toOverlayConfig()
        : taskbar.toOverlayConfig();
    final enabled = isFloating ? floating.enabled : taskbar.enabled;
    final reduceMotion = isFloating
        ? floating.reduceMotion
        : taskbar.reduceMotion;
    final theme = Theme.of(context);

    return Card(
      key: const Key('lyrics-studio'),
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          ListTile(
            leading: const Icon(Icons.auto_awesome_outlined),
            title: const Text('歌词工作室'),
            subtitle: const Text('先在这里调好尺寸、位置与动画，再打开桌面窗口'),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<LyricsSurface>(
              segments: const <ButtonSegment<LyricsSurface>>[
                ButtonSegment<LyricsSurface>(
                  value: LyricsSurface.floating,
                  label: Text('悬浮歌词'),
                  icon: Icon(Icons.picture_in_picture_alt_outlined),
                ),
                ButtonSegment<LyricsSurface>(
                  value: LyricsSurface.taskbar,
                  label: Text('任务栏歌词'),
                  icon: Icon(Icons.crop_16_9_outlined),
                ),
              ],
              selected: <LyricsSurface>{surface},
              onSelectionChanged: (selection) => ref
                  .read(lyricsStudioProvider.notifier)
                  .selectSurface(selection.first),
            ),
          ),
          SwitchListTile(
            key: const Key('lyrics-studio-enabled'),
            dense: true,
            secondary: const Icon(Icons.visibility_outlined),
            title: Text(isFloating ? '显示悬浮歌词' : '显示任务栏歌词'),
            value: enabled,
            onChanged: (value) => isFloating
                ? ref.read(floatingLyricsProvider.notifier).setEnabled(value)
                : ref.read(taskbarLyricsProvider.notifier).setEnabled(value),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: DesktopLyricsPreview(
              key: const Key('lyrics-studio-preview'),
              config: config,
              lines: sampleLines,
              previewToken: studio.previewToken,
              autoPlay: autoPlayPreview,
              height: isFloating ? 150 : 82,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: <Widget>[
                FilledButton.tonalIcon(
                  key: const Key('lyrics-studio-replay'),
                  onPressed: () {
                    ref.read(lyricsStudioProvider.notifier).replay();
                    final preview = nativePreview;
                    if (preview != null) {
                      unawaited(preview(surface, config.lineAnimation));
                    } else {
                      unawaited(
                        _previewNative(ref, surface, config.lineAnimation),
                      );
                    }
                  },
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('重播预览'),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    enabled ? '窗口已开启，改动会实时下发' : '窗口未开启，仅本地预览',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (isFloating)
            const FloatingLyricsSections()
          else
            const TaskbarLyricsSections(),
          SwitchListTile(
            key: const Key('lyrics-studio-reduce-motion'),
            dense: true,
            secondary: const Icon(Icons.animation_outlined),
            title: const Text('减少动态效果'),
            subtitle: const Text('开启后所有行动画与窗口动画都变成硬切，只保留文字本身的变化'),
            value: reduceMotion,
            onChanged: (value) => isFloating
                ? ref
                      .read(floatingLyricsProvider.notifier)
                      .setReduceMotion(value)
                : ref
                      .read(taskbarLyricsProvider.notifier)
                      .setReduceMotion(value),
          ),
          if (reduceMotion) _ReduceMotionNotice(surface: surface),
          AnimationPicker<LyricsLineTransition>(
            title: '行动画',
            idPrefix: 'lyrics-line-animation',
            subtitle: '★ 为任务栏推荐；窄条上纵向与翻转变换容易糊',
            options: LyricsAnimationCatalog.lineChoicesFor(surface),
            selected: config.lineAnimation,
            onSelected: (value) => _setLineAnimation(ref, surface, value),
          ),
          AnimationPicker<LyricsWindowTransition>(
            title: '窗口动画',
            idPrefix: 'lyrics-window-animation',
            options: LyricsAnimationCatalog.windowChoicesFor(surface),
            selected: config.windowAnimation,
            onSelected: (value) => _setWindowAnimation(ref, surface, value),
          ),
          _durationPicker(context, ref, surface, config),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Row(
              children: <Widget>[
                const Icon(Icons.speed_outlined, size: 20),
                const SizedBox(width: 12),
                const Text('缓动'),
                const SizedBox(width: 12),
                DropdownButton<LyricsEasing>(
                  key: const Key('lyrics-studio-easing'),
                  value: config.easing,
                  onChanged: (value) {
                    if (value == null) return;
                    _setEasing(ref, surface, value);
                  },
                  items: <DropdownMenuItem<LyricsEasing>>[
                    for (final easing in LyricsAnimationCatalog.easingOptions)
                      DropdownMenuItem<LyricsEasing>(
                        value: easing.value,
                        child: Text(easing.label),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _durationPicker(
    BuildContext context,
    WidgetRef ref,
    LyricsSurface surface,
    LyricsOverlayConfig config,
  ) {
    final durations = <int>{
      ...LyricsAnimationCatalog.supportedDurationsMs,
      // The taskbar default (200 ms) is not one of the floating presets.
      if (surface == LyricsSurface.taskbar) 200,
    }.toList()..sort();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('动画时长', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: <Widget>[
              for (final duration in durations)
                ChoiceChip(
                  key: ValueKey<String>('lyrics-studio-duration-$duration'),
                  label: Text(duration == 0 ? '关闭' : '$duration 毫秒'),
                  selected: config.animationDurationMs == duration,
                  onSelected: (_) => surface == LyricsSurface.floating
                      ? ref
                            .read(floatingLyricsProvider.notifier)
                            .setAnimationDurationMs(duration)
                      : ref
                            .read(taskbarLyricsProvider.notifier)
                            .setAnimationDurationMs(duration),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _previewNative(
    WidgetRef ref,
    LyricsSurface surface,
    LyricsLineTransition animation,
  ) async {
    final controller = ref.read(floatingLyricsSyncProvider);
    try {
      await controller.preview(
        LyricsPreviewRequest(
          animation: LyricsAnimationCatalog.resolve(animation),
          sampleLines: sampleLines,
          durationMs: 2400,
        ),
      );
    } catch (_) {
      // A missing native window is not an error: the in-app preview already
      // showed the animation.
    }
  }

  static Future<void> _setLineAnimation(
    WidgetRef ref,
    LyricsSurface surface,
    LyricsLineTransition value,
  ) {
    return surface == LyricsSurface.floating
        ? ref.read(floatingLyricsProvider.notifier).setLineAnimation(value)
        : ref.read(taskbarLyricsProvider.notifier).setLineAnimation(value);
  }

  static Future<void> _setWindowAnimation(
    WidgetRef ref,
    LyricsSurface surface,
    LyricsWindowTransition value,
  ) {
    return surface == LyricsSurface.floating
        ? ref.read(floatingLyricsProvider.notifier).setWindowAnimation(value)
        : ref.read(taskbarLyricsProvider.notifier).setWindowAnimation(value);
  }

  static Future<void> _setEasing(
    WidgetRef ref,
    LyricsSurface surface,
    LyricsEasing value,
  ) {
    return surface == LyricsSurface.floating
        ? ref.read(floatingLyricsProvider.notifier).setEasing(value)
        : ref.read(taskbarLyricsProvider.notifier).setEasing(value);
  }
}

/// Explains the one state in which the animation pickers below do nothing.
///
/// Without it the pickers look broken: the native side hard-cuts every
/// transition while reduceMotion is on, so a newly picked animation appears to
/// have no effect at all.
class _ReduceMotionNotice extends ConsumerWidget {
  const _ReduceMotionNotice({required this.surface});

  final LyricsSurface surface;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Container(
      key: const Key('lyrics-studio-reduce-motion-notice'),
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            Icons.info_outline,
            size: 20,
            color: theme.colorScheme.onErrorContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '当前已开启「减少动态效果」，动画选择不会生效',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
          ),
          TextButton(
            key: const Key('lyrics-studio-reduce-motion-off'),
            onPressed: () => unawaited(
              surface == LyricsSurface.floating
                  ? ref
                        .read(floatingLyricsProvider.notifier)
                        .setReduceMotion(false)
                  : ref
                        .read(taskbarLyricsProvider.notifier)
                        .setReduceMotion(false),
            ),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }
}
