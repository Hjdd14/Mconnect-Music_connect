import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:mconnect/core/theme/app_colors.dart';
// Only for `_RenderIntrinsicOpaqueBox`, the pass-through box that lets the
// dialog's preview answer the intrinsic query `AlertDialog` makes.
import 'package:flutter/rendering.dart' show RenderProxyBox;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mconnect/core/constants/app_constants.dart';
import 'package:mconnect/core/diagnostics/diagnostics_export.dart';
import 'package:mconnect/core/diagnostics/diagnostics_service.dart';
import 'package:mconnect/core/theme/app_background.dart';
import 'package:mconnect/core/theme/app_background_provider.dart';
import 'package:mconnect/core/theme/app_theme.dart';
import 'package:mconnect/core/theme/platform_accent.dart';
import 'package:mconnect/core/theme/theme_provider.dart';
import 'package:mconnect/core/theme/ui_style_provider.dart';
import 'package:mconnect/core/utils/snackbar_helper.dart';
import 'package:mconnect/features/auth/presentation/providers/auth_provider.dart';
import 'package:mconnect/features/audio_effects/presentation/providers/audio_effects_provider.dart';
import 'package:mconnect/features/audio_effects/presentation/providers/sleep_timer_provider.dart';
import 'package:mconnect/features/floating_lyrics/data/floating_lyrics_service.dart';
import 'package:mconnect/features/floating_lyrics/presentation/providers/floating_lyrics_provider.dart';
import 'package:mconnect/l10n/l10n.dart';
import 'package:mconnect/l10n/platform_labels.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

String createBackgroundDestinationPath({
  required String backgroundsDirPath,
  required String originalName,
  DateTime? now,
}) {
  final rawExtension = p.extension(originalName).toLowerCase();
  final extension = rawExtension.isEmpty ? '.png' : rawExtension;
  final timestamp = (now ?? DateTime.now()).microsecondsSinceEpoch.toString();
  return p.join(backgroundsDirPath, 'custom_background_$timestamp$extension');
}

Size backgroundCropViewportSize(Size screenSize) {
  if (screenSize.width <= 0 || screenSize.height <= 0) {
    return const Size(9, 16);
  }
  return screenSize;
}

bool canUseDecodedBackgroundImage({
  required double imageWidth,
  required double imageHeight,
}) {
  return imageWidth > 0 && imageHeight > 0;
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, this.diagnosticsExport, this.diagnosticsShare});

  /// Test seam for the 「导出诊断日志」 row.
  ///
  /// Production leaves it null and the row calls `exportDiagnosticsLog()`, which
  /// needs a real temporary directory plus a share target. Injecting the exporter
  /// lets a widget test assert "one tap → exactly one export" without either.
  @visibleForTesting
  final Future<DiagnosticsExportResult> Function()? diagnosticsExport;

  /// Test seam for the share step. The real one is share_plus, whose
  /// platform channel never answers in a widget test — that would leave the row
  /// spinning forever instead of reaching its success/failure state.
  @visibleForTesting
  final Future<void> Function(String path)? diagnosticsShare;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.settingsTitle)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          _SettingsEntryTile(
            icon: Icons.account_circle_outlined,
            title: context.l10n.settingsAccounts,
            subtitle: context.l10n.settingsAccountsSubtitle,
            onTap: () => context.push('/settings/accounts'),
          ),
          _SettingsEntryTile(
            icon: Icons.palette_outlined,
            title: context.l10n.settingsAppearance,
            subtitle: context.l10n.settingsAppearanceSubtitle,
            onTap: () => context.push('/settings/appearance'),
          ),
          _SettingsEntryTile(
            icon: Icons.picture_in_picture_alt_outlined,
            title: context.l10n.settingsFloatingLyrics,
            subtitle: context.l10n.settingsFloatingLyricsSubtitle,
            onTap: () => context.push('/settings/floating-lyrics'),
          ),
          _SettingsEntryTile(
            icon: Icons.graphic_eq,
            title: context.l10n.settingsAudio,
            subtitle: context.l10n.settingsAudioSubtitle,
            onTap: () => context.push('/settings/audio'),
          ),
          // task-12: the data layer (WS-F) and diagnostics (task-11) shipped
          // their features, but without an entry point they were unreachable.
          _SettingsEntryTile(
            icon: Icons.backup_outlined,
            title: context.l10n.settingsBackup,
            subtitle: context.l10n.settingsBackupSubtitle,
            onTap: () => context.push('/backup'),
          ),
          _DiagnosticsExportTile(
            export: diagnosticsExport,
            share: diagnosticsShare,
          ),
          _SettingsEntryTile(
            icon: Icons.info_outline,
            title: context.l10n.settingsDiagnostics,
            subtitle: context.l10n.settingsDiagnosticsSubtitle,
            onTap: () => context.push('/settings/diagnostics'),
          ),
        ],
      ),
    );
  }
}

// `_SettingsEntryTile` is a plain `ListTile`, which already exposes button
// semantics; the label doubles as the screen-reader text so an icon-only change
// can never ship without its meaning.
class _SettingsEntryTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SettingsEntryTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

/// 「导出诊断日志」入口（task-11 的导出逻辑 + share_plus）。
///
/// Stateful only so the row can show progress and refuse a second tap while an
/// export is running: `exportDiagnosticsLog` reads the on-disk log, and a
/// double tap used to be able to produce two bundles.
class _DiagnosticsExportTile extends StatefulWidget {
  const _DiagnosticsExportTile({this.export, this.share});

  /// Injected exporter (tests); null means the production entry point.
  final Future<DiagnosticsExportResult> Function()? export;

  /// Injected share step (tests); null means share_plus.
  final Future<void> Function(String path)? share;

  @override
  State<_DiagnosticsExportTile> createState() => _DiagnosticsExportTileState();
}

class _DiagnosticsExportTileState extends State<_DiagnosticsExportTile> {
  bool _busy = false;

  Future<void> _export() async {
    if (_busy) return;
    setState(() => _busy = true);
    final l = context.l10n;
    try {
      final result = await (widget.export ?? exportDiagnosticsLog)();
      if (!mounted) return;
      try {
        final share = widget.share;
        if (share != null) {
          await share(result.filePath);
        } else {
          await SharePlus.instance.share(
            ShareParams(files: [XFile(result.filePath)]),
          );
        }
        if (!mounted) return;
        showSuccessSnackBar(context, l.diagnosticsExported);
      } catch (_) {
        // A platform without a file share target (Windows desktop) still has to
        // leave the user a way to reach the export, so fall back to the path.
        await Clipboard.setData(ClipboardData(text: result.filePath));
        if (!mounted) return;
        showInfoSnackBar(context, l.diagnosticsExportPathCopied);
      }
    } on DiagnosticsExportException catch (error) {
      if (!mounted) return;
      showErrorSnackBar(context, l.diagnosticsExportFailed(error.message));
    } catch (error) {
      if (!mounted) return;
      showErrorSnackBar(context, l.diagnosticsExportFailed('$error'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return ListTile(
      key: const Key('diagnostics-export-tile'),
      leading: const Icon(Icons.file_upload_outlined),
      title: Text(l.settingsExportDiagnostics),
      subtitle: Text(l.settingsExportDiagnosticsSubtitle),
      trailing: _busy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.chevron_right),
      onTap: _busy ? null : _export,
    );
  }
}

class SettingsAccountsPage extends ConsumerWidget {
  const SettingsAccountsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);

    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.settingsAccounts)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
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
        ],
      ),
    );
  }
}

class SettingsAppearancePage extends ConsumerWidget {
  const SettingsAppearancePage({super.key});

  static const _themePresets = [
    Color(0xFFE91E63),
    Color(0xFF31C27C),
    Color(0xFF2F80ED),
    Color(0xFF7B61FF),
    Color(0xFFFF8A00),
    Color(0xFF111827),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeSettings = ref.watch(themeSettingsProvider);
    final themeNotifier = ref.read(themeSettingsProvider.notifier);
    final appBackground = ref.watch(appBackgroundSettingsProvider);
    final appBackgroundNotifier = ref.read(
      appBackgroundSettingsProvider.notifier,
    );
    final uiStyleSettings = ref.watch(uiStyleProvider);

    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.settingsAppearance)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          _ThemeTile(
            title: context.l10n.themeFollowSystem,
            icon: Icons.brightness_auto,
            selected: themeSettings.mode == ThemeMode.system,
            onTap: () => themeNotifier.setMode(ThemeMode.system),
          ),
          _ThemeTile(
            title: context.l10n.themeLight,
            icon: Icons.light_mode,
            selected: themeSettings.mode == ThemeMode.light,
            onTap: () => themeNotifier.setMode(ThemeMode.light),
          ),
          _ThemeTile(
            title: context.l10n.themeDark,
            icon: Icons.dark_mode,
            selected: themeSettings.mode == ThemeMode.dark,
            onTap: () => themeNotifier.setMode(ThemeMode.dark),
          ),
          _ColorPresetTile(
            title: context.l10n.themeColor,
            subtitle: context.l10n.themeColorSubtitle,
            icon: Icons.palette_outlined,
            selectedColor: themeSettings.seedColor,
            presets: _themePresets,
            fallbackColor: AppTheme.defaultSeedColor,
            onSelected: themeNotifier.setSeedColor,
          ),
          _AppBackgroundTile(
            settings: appBackground,
            onPick: () => _pickBackground(context, appBackgroundNotifier),
            onEdit: () =>
                _editBackground(context, appBackground, appBackgroundNotifier),
            onClear: () async {
              await appBackgroundNotifier.clear();
              if (!context.mounted) return;
              showSuccessSnackBar(context, context.l10n.backgroundRemoved);
            },
          ),
          const Divider(),
          _SectionHeader(context.l10n.uiStyle),
          _UiStyleTile(
            selected: uiStyleSettings.style,
            onSelected: (style) =>
                ref.read(uiStyleProvider.notifier).setStyle(style),
          ),
        ],
      ),
    );
  }

  Future<void> _pickBackground(
    BuildContext context,
    AppBackgroundSettingsNotifier notifier,
  ) async {
    // Resolve the copy before the first `await`: using `context` after an async
    // gap is both a lint and a real hazard (the widget may be gone).
    final l = context.l10n;
    try {
      final cropViewportSize = backgroundCropViewportSize(
        MediaQuery.sizeOf(context),
      );
      final picked = await FilePicker.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        withData: true,
      );
      if (picked == null || picked.files.isEmpty) return;

      final file = picked.files.single;
      final sourcePath = file.path;
      final bytes =
          file.bytes ??
          (sourcePath == null
              ? throw StateError(l.backgroundImageUnreadable)
              : await File(sourcePath).readAsBytes());
      final previousPath = notifier.current.imagePath;
      final imageSize = await _decodeImageSize(bytes);
      if (!canUseDecodedBackgroundImage(
        imageWidth: imageSize.width.toDouble(),
        imageHeight: imageSize.height.toDouble(),
      )) {
        throw StateError(l.backgroundImageSizeUnreadable);
      }
      final documentsDir = await getApplicationDocumentsDirectory();
      final backgroundsDir = Directory(
        p.join(documentsDir.path, 'backgrounds'),
      );
      if (!await backgroundsDir.exists()) {
        await backgroundsDir.create(recursive: true);
      }

      final destination = File(
        createBackgroundDestinationPath(
          backgroundsDirPath: backgroundsDir.path,
          originalName: file.name,
        ),
      );
      await destination.writeAsBytes(bytes, flush: true);
      PaintingBinding.instance.imageCache.evict(FileImage(destination));

      final settings = AppBackgroundSettings(
        imagePath: destination.path,
        imageWidth: imageSize.width.toDouble(),
        imageHeight: imageSize.height.toDouble(),
        cropViewportWidth: cropViewportSize.width,
        cropViewportHeight: cropViewportSize.height,
      );

      if (!context.mounted) return;
      final edited = await showDialog<AppBackgroundSettings>(
        context: context,
        builder: (context) => BackgroundEditorDialog(settings: settings),
      );
      if (edited == null) return;

      if (previousPath != null && previousPath.isNotEmpty) {
        PaintingBinding.instance.imageCache.evict(
          FileImage(File(previousPath)),
        );
      }
      PaintingBinding.instance.imageCache.evict(FileImage(destination));
      await notifier.save(edited);
      if (!context.mounted) return;
      showSuccessSnackBar(context, l.backgroundApplied);
    } catch (error) {
      if (!context.mounted) return;
      showErrorSnackBar(context, l.backgroundProcessFailed('$error'));
    }
  }

  Future<void> _editBackground(
    BuildContext context,
    AppBackgroundSettings settings,
    AppBackgroundSettingsNotifier notifier,
  ) async {
    final imagePath = settings.imagePath;
    if (imagePath == null ||
        imagePath.isEmpty ||
        !File(imagePath).existsSync()) {
      showErrorSnackBar(context, context.l10n.backgroundFileMissing);
      return;
    }

    final edited = await showDialog<AppBackgroundSettings>(
      context: context,
      builder: (context) => BackgroundEditorDialog(settings: settings),
    );
    if (edited == null) return;

    PaintingBinding.instance.imageCache.evict(FileImage(File(imagePath)));
    await notifier.save(edited);
    if (!context.mounted) return;
    showSuccessSnackBar(context, context.l10n.backgroundUpdated);
  }

  Future<({int width, int height})> _decodeImageSize(Uint8List bytes) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    final size = (width: descriptor.width, height: descriptor.height);
    descriptor.dispose();
    buffer.dispose();
    return size;
  }
}

class SettingsFloatingLyricsPage extends ConsumerWidget {
  const SettingsFloatingLyricsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final floatingLyrics = ref.watch(floatingLyricsProvider);
    final floatingLyricsNotifier = ref.read(floatingLyricsProvider.notifier);
    final isWindows = Platform.isWindows;

    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.settingsFloatingLyrics)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.picture_in_picture_alt_outlined),
            title: Text(context.l10n.floatingLyricsEnable),
            subtitle: Text(
              isWindows ? context.l10n.floatingLyricsEnableSubtitle : context.l10n.floatingLyricsPermissionSubtitle,
            ),
            value: floatingLyrics.enabled,
            onChanged: (value) async {
              if (value) {
                final allowed = await FloatingLyricsService.instance
                    .canDrawOverlays();
                if (!allowed) {
                  await FloatingLyricsService.instance.openOverlaySettings();
                }
              } else {
                await FloatingLyricsService.instance.hide();
              }
              await floatingLyricsNotifier.setEnabled(value);
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.lock_outline),
            title: Text(context.l10n.floatingLyricsLock),
            subtitle: Text(context.l10n.floatingLyricsLockSubtitle),
            key: const Key('floating-lyrics-lock-tile'),
            value: floatingLyrics.isLocked,
            onChanged: floatingLyrics.enabled
                ? floatingLyricsNotifier.setLocked
                : null,
          ),
          _ColorPresetTile(
            title: context.l10n.floatingLyricsTextColor,
            subtitle: context.l10n.floatingLyricsTextColorSubtitle,
            key: const Key('floating-lyrics-text-color-tile'),
            icon: Icons.format_color_text,
            selectedColor: floatingLyrics.textColor,
            presets: const [],
            fallbackColor: const Color(0xFFFFFFFF),
            onSelected: floatingLyricsNotifier.setTextColor,
          ),
          _ColorPresetTile(
            title: context.l10n.floatingLyricsHighlightColor,
            subtitle: context.l10n.floatingLyricsHighlightColorSubtitle,
            key: const Key('floating-lyrics-highlight-color-tile'),
            icon: Icons.border_color_outlined,
            selectedColor: floatingLyrics.highlightColor,
            presets: const [],
            fallbackColor: const Color(0xFFFFD44A),
            onSelected: floatingLyricsNotifier.setHighlightColor,
          ),
          _SliderTile(
            title: context.l10n.floatingLyricsFontSize,
            subtitle: '${floatingLyrics.fontSize.round()} px',
            icon: Icons.text_fields,
            value: floatingLyrics.fontSize,
            min: 14,
            max: 48,
            divisions: 34,
            onChanged: floatingLyricsNotifier.setFontSize,
          ),
          _SliderTile(
            title: context.l10n.floatingLyricsStrokeWidth,
            subtitle: floatingLyrics.strokeWidth.toStringAsFixed(1),
            icon: Icons.format_shapes_outlined,
            value: floatingLyrics.strokeWidth,
            min: 0,
            max: 2,
            divisions: 20,
            onChanged: floatingLyricsNotifier.setStrokeWidth,
          ),
          _SliderTile(
            title: context.l10n.floatingLyricsShadowOpacity,
            subtitle: '${(floatingLyrics.shadowOpacity * 100).round()}%',
            icon: Icons.blur_on,
            value: floatingLyrics.shadowOpacity,
            min: 0,
            max: 1,
            divisions: 20,
            onChanged: floatingLyricsNotifier.setShadowOpacity,
          ),
        ],
      ),
    );
  }
}

class SettingsAudioPage extends ConsumerWidget {
  const SettingsAudioPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final audioEffects = ref.watch(audioEffectsSettingsProvider);
    final audioEffectsNotifier = ref.read(
      audioEffectsSettingsProvider.notifier,
    );
    final sleepTimer = ref.watch(sleepTimerProvider);
    final sleepTimerNotifier = ref.read(sleepTimerProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.settingsAudio)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.graphic_eq),
            title: Text(context.l10n.audioFade),
            subtitle: Text(context.l10n.audioFadeSubtitle),
            value: audioEffects.fadeEnabled,
            onChanged: audioEffectsNotifier.setFadeEnabled,
          ),
          _SliderTile(
            title: context.l10n.audioFadeDuration,
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
            title: Text(context.l10n.audioEqualizer),
            subtitle: Text(context.l10n.audioEqualizerSubtitle),
            value: audioEffects.equalizerEnabled,
            onChanged: audioEffectsNotifier.setEqualizerEnabled,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.tune),
              title: Text(context.l10n.audioEqualizerPreset),
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
            title: context.l10n.audioBandLow,
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
            title: context.l10n.audioBandLowMid,
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
            title: context.l10n.audioBandMid,
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
            title: context.l10n.audioBandHighMid,
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
            title: context.l10n.audioBandHigh,
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
          SwitchListTile(
            secondary: const Icon(Icons.bedtime_outlined),
            title: Text(context.l10n.audioSleepTimer),
            subtitle: Text(
              sleepTimer.enabled
                  ? context.l10n.audioSleepTimerRemaining(_formatTimerRemaining(sleepTimer.remaining))
                  : context.l10n.audioSleepTimerCountdown(audioEffects.sleepTimerDuration.inMinutes),
            ),
            value: sleepTimer.enabled,
            onChanged: sleepTimerNotifier.setEnabled,
          ),
          _SliderTile(
            title: context.l10n.audioSleepTimerDuration,
            subtitle: context.l10n.audioMinutes(audioEffects.sleepTimerDuration.inMinutes),
            icon: Icons.timer_outlined,
            value: audioEffects.sleepTimerDuration.inMinutes.toDouble(),
            min: 5,
            max: 120,
            divisions: 23,
            onChanged: (value) => audioEffectsNotifier.setSleepTimerDuration(
              Duration(minutes: value.round()),
            ),
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

class SettingsDiagnosticsPage extends StatelessWidget {
  const SettingsDiagnosticsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.settingsDiagnostics)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          const Divider(),
          _SectionHeader(context.l10n.diagnosticsSection),
          _DiagnosticsTile(diagnostics: DiagnosticsService.instance),
          const Divider(),
          _SectionHeader(context.l10n.aboutSection),
          ListTile(
            leading: Icon(Icons.info_outline),
            title: Text(context.l10n.version),
            subtitle: Text(AppConstants.appVersion),
          ),
        ],
      ),
    );
  }
}

class _AppBackgroundTile extends StatelessWidget {
  final AppBackgroundSettings settings;
  final VoidCallback onPick;
  final VoidCallback onEdit;
  final VoidCallback onClear;

  const _AppBackgroundTile({
    required this.settings,
    required this.onPick,
    required this.onEdit,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = settings.enabled;
    return ListTile(
      key: const Key('app-background-tile'),
      leading: const Icon(Icons.wallpaper_outlined),
      title: Text(context.l10n.customBackground),
      subtitle: Text(enabled ? context.l10n.customBackgroundEnabledHint : context.l10n.customBackgroundChooseHint),
      trailing: enabled
          ? IconButton(
              tooltip: context.l10n.removeBackground,
              icon: const Icon(Icons.close),
              onPressed: onClear,
            )
          : const Icon(Icons.chevron_right),
      onTap: enabled ? onEdit : onPick,
    );
  }
}

class BackgroundEditorDialog extends StatefulWidget {
  final AppBackgroundSettings settings;
  final Widget Function(File file)? imageBuilder;

  const BackgroundEditorDialog({
    super.key,
    required this.settings,
    this.imageBuilder,
  });

  @override
  State<BackgroundEditorDialog> createState() => _BackgroundEditorDialogState();
}

class _BackgroundEditorDialogState extends State<BackgroundEditorDialog> {
  late final TransformationController _controller;
  Size? _lastPreviewSize;
  bool _initializedForPreview = false;

  @override
  void initState() {
    super.initState();
    _controller = TransformationController(Matrix4.identity());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Seeds the controller from the stored settings, in preview pixels.
  ///
  /// The stored offsets are relative to the viewport the picture was cropped in,
  /// which is not the preview's viewport, so they are rescaled here — the same
  /// relationship `appBackgroundImageGeometry` applies when it paints them at
  /// full size. Runs once: re-seeding on every layout would throw away a drag
  /// whenever the window is resized.
  void _seedController(Size previewSize) {
    if (_initializedForPreview) return;
    _initializedForPreview = true;
    final referenceWidth = widget.settings.cropViewportWidth > 0
        ? widget.settings.cropViewportWidth
        : previewSize.width;
    final referenceHeight = widget.settings.cropViewportHeight > 0
        ? widget.settings.cropViewportHeight
        : previewSize.height;
    _controller.value = appBackgroundMatrixFromTransform(
      scale: widget.settings.scale,
      offset: Offset(
        referenceWidth > 0
            ? widget.settings.offsetX * previewSize.width / referenceWidth
            : widget.settings.offsetX,
        referenceHeight > 0
            ? widget.settings.offsetY * previewSize.height / referenceHeight
            : widget.settings.offsetY,
      ),
    );
  }

  /// Paints the preview with the same widget the app-level shell uses.
  ///
  /// Passing the matrix through [appBackgroundTransformFromMatrix] is the whole
  /// point: the preview must scale about the viewport centre, exactly as
  /// `AppBackgroundImageCanvas` does everywhere else. Letting `InteractiveViewer`
  /// render its own matrix anchored the scale at the child's top-left instead,
  /// which put the real background down-right of what the preview showed.
  Widget _previewCanvas({
    required AppBackgroundSettings settings,
    required Size previewSize,
    required String imagePath,
    required Matrix4 matrix,
  }) {
    final placement = appBackgroundTransformFromMatrix(matrix);
    return AppBackgroundImageCanvas(
      settings: settings.copyWith(
        scale: placement.scale,
        offsetX: placement.offset.dx,
        offsetY: placement.offset.dy,
      ),
      viewportSize: previewSize,
      file: File(imagePath),
      imageBuilder: widget.imageBuilder,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final imagePath = widget.settings.imagePath!;
    final screenSize = MediaQuery.sizeOf(context);
    final cropViewportSize = backgroundCropViewportSize(screenSize);
    final cropAspectRatio = cropViewportSize.width / cropViewportSize.height;
    final isLandscape = cropAspectRatio >= 1;
    final maxPreviewWidth = isLandscape ? 560.0 : 420.0;
    final maxPreviewHeight = isLandscape ? 360.0 : 560.0;

    return AlertDialog(
      key: const Key('app-background-editor-dialog'),
      title: Text(context.l10n.adjustBackground),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxPreviewWidth,
          maxHeight: maxPreviewHeight + 64,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: maxPreviewWidth,
                maxHeight: maxPreviewHeight,
              ),
              child: AspectRatio(
                aspectRatio: cropAspectRatio,
                child: DecoratedBox(
                  key: const Key('app-background-editor-preview'),
                  decoration: BoxDecoration(
                    color: AppColors.imageBase,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: cs.outlineVariant),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: _IntrinsicOpaqueBox(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final previewSize = Size(
                            constraints.maxWidth,
                            constraints.maxHeight,
                          );
                          final previewSettings = widget.settings.copyWith(
                            scale: 1,
                            offsetX: 0,
                            offsetY: 0,
                            cropViewportWidth: previewSize.width,
                            cropViewportHeight: previewSize.height,
                          );
                          final geometry = appBackgroundImageGeometry(
                            settings: previewSettings,
                            viewportSize: previewSize,
                          );
                          final horizontalBoundary = math.max(
                            previewSize.width,
                            geometry.canvasSize.width,
                          );
                          final verticalBoundary = math.max(
                            previewSize.height,
                            geometry.canvasSize.height,
                          );
                          _lastPreviewSize = previewSize;
                          _seedController(previewSize);

                          return Stack(
                            fit: StackFit.expand,
                            children: [
                              IgnorePointer(
                                child: ValueListenableBuilder<Matrix4>(
                                  valueListenable: _controller,
                                  builder: (context, matrix, _) =>
                                      _previewCanvas(
                                        settings: previewSettings,
                                        previewSize: previewSize,
                                        imagePath: imagePath,
                                        matrix: matrix,
                                      ),
                                ),
                              ),
                              // A pure gesture surface: it paints nothing, and it
                              // must stay the top-most layer — the canvas below
                              // is hit-test opaque, so with the order reversed it
                              // swallows the pointer and dragging stops working.
                              InteractiveViewer(
                                boundaryMargin: EdgeInsets.symmetric(
                                  horizontal: horizontalBoundary,
                                  vertical: verticalBoundary,
                                ),
                                minScale: 1,
                                maxScale: 4,
                                transformationController: _controller,
                                child: SizedBox(
                                  width: previewSize.width,
                                  height: previewSize.height,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              context.l10n.backgroundEditorHint,
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => _controller.value = Matrix4.identity(),
          child: Text(context.l10n.actionReset),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.actionCancel),
        ),
        FilledButton(
          onPressed: () {
            // Read through the same function the preview renders through, so what
            // is saved is what the user just looked at.
            final placement = appBackgroundTransformFromMatrix(
              _controller.value,
            );
            final previewSize = _lastPreviewSize ?? cropViewportSize;
            Navigator.pop(
              context,
              widget.settings.copyWith(
                scale: placement.scale,
                offsetX: placement.offset.dx,
                offsetY: placement.offset.dy,
                cropViewportWidth: previewSize.width,
                cropViewportHeight: previewSize.height,
              ),
            );
          },
          child: Text(context.l10n.actionSave),
        ),
      ],
    );
  }
}

/// Lays its child out normally, but answers intrinsic-size queries with zero
/// instead of measuring it.
///
/// **Why this is here.** `AlertDialog` wraps its content in an `IntrinsicWidth`
/// to decide how wide the dialog should be, and the preview below is a
/// `LayoutBuilder` — which cannot answer an intrinsic query, because that would
/// mean running its builder speculatively. In a **debug** build that query
/// throws, and because the throw aborts the whole intrinsic pass the dialog's
/// body is never laid out at all: the editor opens with an empty preview area and
/// a rendering exception in the log. In a **release** build `LayoutBuilder`
/// answers `0.0` for every intrinsic query, so returning zero here is exactly
/// what release already does — this only makes debug match it.
///
/// Layout, painting and hit testing are untouched: it is a pass-through box. It
/// must stay above the `LayoutBuilder` (or anything else that cannot answer
/// intrinsics) for the dialog to lay out in debug.
class _IntrinsicOpaqueBox extends SingleChildRenderObjectWidget {
  const _IntrinsicOpaqueBox({super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderIntrinsicOpaqueBox();
}

class _RenderIntrinsicOpaqueBox extends RenderProxyBox {
  @override
  double computeMinIntrinsicWidth(double height) => 0;

  @override
  double computeMaxIntrinsicWidth(double height) => 0;

  @override
  double computeMinIntrinsicHeight(double width) => 0;

  @override
  double computeMaxIntrinsicHeight(double width) => 0;
}

class _ColorPresetTile extends StatelessWidget {
  static const _fullPickerQuickColors = [
    Color(0xFFFFFFFF),
    Color(0xFFFFF4F8),
    Color(0xFFFFD44A),
    Color(0xFF31C27C),
    Color(0xFF2F80ED),
    Color(0xFF111827),
  ];

  final String title;
  final String subtitle;
  final IconData icon;
  final Color selectedColor;
  final Color fallbackColor;
  final List<Color> presets;
  final ValueChanged<Color> onSelected;

  const _ColorPresetTile({
    super.key,
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
    final usesFullPicker = presets.isEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            leading: Icon(icon),
            title: Text(title),
            subtitle: Text(subtitle),
            onTap: usesFullPicker ? () => _showFullColorPicker(context) : null,
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
                for (final color
                    in usesFullPicker ? _fullPickerQuickColors : presets)
                  _ColorSwatchButton(
                    color: color,
                    selected: color.toARGB32() == selectedColor.toARGB32(),
                    onTap: () => onSelected(color),
                  ),
                if (usesFullPicker)
                  ActionChip(
                    avatar: const Icon(Icons.color_lens_outlined, size: 18),
                    label: Text(context.l10n.customColor),
                    onPressed: () => _showFullColorPicker(context),
                  ),
                ActionChip(
                  avatar: const Icon(Icons.restart_alt, size: 18),
                  label: Text(context.l10n.defaultLabel),
                  onPressed: () => onSelected(fallbackColor),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showFullColorPicker(BuildContext context) async {
    final picked = await showDialog<Color>(
      context: context,
      builder: (context) => _FullColorPickerDialog(
        initialColor: selectedColor,
        fallbackColor: fallbackColor,
      ),
    );
    if (picked != null) {
      onSelected(picked);
    }
  }
}

class _FullColorPickerDialog extends StatefulWidget {
  final Color initialColor;
  final Color fallbackColor;

  const _FullColorPickerDialog({
    required this.initialColor,
    required this.fallbackColor,
  });

  @override
  State<_FullColorPickerDialog> createState() => _FullColorPickerDialogState();
}

class _FullColorPickerDialogState extends State<_FullColorPickerDialog> {
  late HSVColor _color = HSVColor.fromColor(widget.initialColor);

  @override
  Widget build(BuildContext context) {
    final picked = _color.toColor();
    return AlertDialog(
      key: const Key('floating-color-picker-dialog'),
      title: const Text('Custom color'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              height: 52,
              decoration: BoxDecoration(
                color: picked,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
            ),
            const SizedBox(height: 16),
            _PickerSlider(
              key: const Key('floating-color-picker-hue'),
              label: 'Hue',
              value: _color.hue,
              min: 0,
              max: 360,
              onChanged: (value) {
                setState(() {
                  _color = _color.withHue(value);
                });
              },
            ),
            _PickerSlider(
              key: const Key('floating-color-picker-saturation'),
              label: 'Saturation',
              value: _color.saturation,
              min: 0,
              max: 1,
              onChanged: (value) {
                setState(() {
                  _color = _color.withSaturation(value);
                });
              },
            ),
            _PickerSlider(
              key: const Key('floating-color-picker-value'),
              label: 'Brightness',
              value: _color.value,
              min: 0,
              max: 1,
              onChanged: (value) {
                setState(() {
                  _color = _color.withValue(value);
                });
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            setState(() {
              _color = HSVColor.fromColor(widget.fallbackColor);
            });
          },
          child: const Text('Default'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, picked),
          child: const Text('OK'),
        ),
      ],
    );
  }
}

class _PickerSlider extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  const _PickerSlider({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // `minWidth` instead of a hard 88 dp: the row used to clip the label as
        // soon as the user scaled text up (`textScaleFactor: 2` made 「描边强度」
        // wider than its box). The minimum keeps the scale-1.0 layout identical
        // while letting the label grow.
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 88),
          child: Text(label),
        ),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
      ],
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
    // A bare colour disc announces nothing to a screen reader; `selected` also
    // stops the check mark from being the only "this one is chosen" signal.
    return Semantics(
      button: true,
      selected: selected,
      label: context.l10n.customColor,
      child: InkResponse(
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
                color: AppColors.swatchShadow,
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: selected
              ? const Icon(Icons.check, color: AppColors.swatchCheck)
              : null,
        ),
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
      trailing: ConstrainedBox(
        // Same reasoning as `_PickerSlider`: a hard 52 dp wrapped the value
        // ("180 天", "500 ms") once the text was scaled up.
        constraints: const BoxConstraints(minWidth: 52),
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
      title: Text(context.l10n.diagnosticsLog),
      subtitle: Text(path, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: PopupMenuButton<String>(
        // An icon-only overflow menu: without this the reader announces only
        // "button" (and the popup's own items, which are text).
        tooltip: context.l10n.moreActions,
        onSelected: (value) async {
          switch (value) {
            case 'copy':
              await Clipboard.setData(ClipboardData(text: path));
              if (!context.mounted) return;
              showSuccessSnackBar(context, context.l10n.diagnosticsLogPathCopied);
              break;
            case 'clear':
              await diagnostics.clear();
              if (!context.mounted) return;
              showSuccessSnackBar(context, context.l10n.diagnosticsLogCleared);
              break;
          }
        },
        itemBuilder: (context) => [
          PopupMenuItem(
            value: 'copy',
            child: ListTile(
              leading: Icon(Icons.copy),
              title: Text(context.l10n.copyPath),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
          PopupMenuItem(
            value: 'clear',
            child: ListTile(
              leading: Icon(Icons.delete_outline),
              title: Text(context.l10n.clearLog),
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

/// Material / Miuix switch for the app chrome.
///
/// Mirrors [_ThemeTile]'s interaction exactly; it is appended after the
/// existing appearance controls and leaves their structure, keys and copy
/// untouched.
class _UiStyleTile extends StatelessWidget {
  final UiStyle selected;
  final ValueChanged<UiStyle> onSelected;

  const _UiStyleTile({required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const Key('ui-style-tile'),
      children: [
        _ThemeTile(
          title: context.l10n.uiStyleMaterial,
          icon: Icons.widgets_outlined,
          selected: selected == UiStyle.material,
          onTap: () => onSelected(UiStyle.material),
        ),
        _ThemeTile(
          title: context.l10n.uiStyleMiuix,
          icon: Icons.auto_awesome_mosaic_outlined,
          selected: selected == UiStyle.miuix,
          onTap: () => onSelected(UiStyle.miuix),
        ),
      ],
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

  Color _platformColor() => PlatformAccent.neutralColorOf(platform);

  IconData _platformIcon() => PlatformAccent.iconOf(platform);

  @override
  Widget build(BuildContext context) {
    final isLoggedIn = user != null;
    final cs = Theme.of(context).colorScheme;

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: _platformColor().withValues(alpha: 0.12),
        child: Icon(_platformIcon(), color: _platformColor(), size: 20),
      ),
      // platform.label is the localizable path; displayName is the enum's
      // own Chinese label and stays for the not-yet-migrated pages.
      title: Text(platform.label(context.l10n)),
      subtitle: isLoggedIn
          ? Text(
              user!.nickname.isNotEmpty ? user!.nickname : context.l10n.accountLoggedIn,
              style: TextStyle(color: cs.outline, fontSize: 13),
            )
          : Text(context.l10n.accountTapToLogin, style: TextStyle(color: cs.outline, fontSize: 13)),
      trailing: isLoggedIn
          ? IconButton(
              icon: Icon(Icons.logout, size: 20, color: cs.error),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: Text(context.l10n.accountLogout),
                    content: Text(context.l10n.accountLogoutConfirm(platform.label(context.l10n))),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: Text(context.l10n.actionCancel),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.pop(ctx);
                          onLogout();
                        },
                        child: Text(
                          context.l10n.actionLogout,
                          style: TextStyle(color: cs.error),
                        ),
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
