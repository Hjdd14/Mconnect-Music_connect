import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_background.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/miuix_theme.dart';
import 'core/theme/theme_provider.dart';
import 'core/theme/ui_style_provider.dart';
import 'features/auth/presentation/providers/auth_provider.dart';
import 'features/audio_effects/presentation/providers/audio_effects_provider.dart';
import 'features/floating_lyrics/presentation/providers/floating_lyrics_provider.dart';
import 'features/player/presentation/providers/player_provider.dart';
import 'features/stats/presentation/providers/listening_stats_provider.dart';

/// Marks the Material ancestor injected under [UiStyle.miuix].
///
/// Only ever present under [UiStyle.miuix]; `test/floating_glass_nav_bar_test.dart`
/// asserts its absence under [UiStyle.material] (invariant I-8 — the Material
/// path must not gain a wrapper).
///
/// `LiquidGlassWidgets.wrap` is a plain function, not a widget, so it takes no
/// `key`; the `GlassAdaptiveScope` it installs is located by *type* in tests.
const Key glassMaterialAncestorKey = Key('app-glass-material-ancestor');

class MconnectApp extends ConsumerStatefulWidget {
  const MconnectApp({super.key});

  /// Wraps the routed content in the app background, plus — for
  /// [UiStyle.miuix] only — the liquid-glass infrastructure.
  ///
  /// [UiStyle.material] must stay byte-for-byte what it was before 阶段 C, so
  /// the glass scopes are added *conditionally* rather than unconditionally: an
  /// always-present wrapper would change the Material element tree and break
  /// invariant I-8.
  ///
  /// A static, rather than a private method on the state, so that the invariant
  /// can be asserted without booting the whole app — pumping [MconnectApp]
  /// drags in Hive, the media_kit native library and the auth session restore,
  /// none of which this function's decision depends on.
  @visibleForTesting
  static Widget buildGlassShell(
    BuildContext context,
    Widget? child,
    UiStyle uiStyle,
  ) {
    final content = AppBackgroundShell(
      child: child ?? const SizedBox.shrink(),
    );

    if (uiStyle != UiStyle.miuix) return content;

    // `wrap` needs a BuildContext that can already resolve the app theme — the
    // `MaterialApp.builder` context can, which is why it is done here and not
    // in `main.dart` where no Theme exists yet. `brightnessResolver` bridges
    // `ThemeMode` (light/dark/system) into the package's brightness cascade; a
    // mismatch between the OS and the app theme would otherwise drop the glass
    // shadows and rim strokes.
    return LiquidGlassWidgets.wrap(
      adaptiveQuality: true,
      brightnessResolver: Theme.maybeBrightnessOf,
      child: Material(
        // `liquid_glass_widgets` imports only `flutter/widgets.dart` (its
        // `cupertino_ui` split), so it installs no `Material` ancestor. Without
        // this every `Text` under the glass subtree would paint Flutter's
        // yellow double-underline debug decoration.
        key: glassMaterialAncestorKey,
        type: MaterialType.transparency,
        child: content,
      ),
    );
  }

  @override
  ConsumerState<MconnectApp> createState() => _MconnectAppState();
}

class _MconnectAppState extends ConsumerState<MconnectApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ref.read(authProvider.notifier).init();
    ref.listenManual(audioEffectsSettingsProvider, (previous, next) {
      ref
          .read(playerProvider.notifier)
          .setFadeOptions(
            enabled: next.fadeEnabled,
            duration: next.fadeDuration,
          );
      unawaited(ref.read(playerProvider.notifier).applyEqualizerSettings(next));
    }, fireImmediately: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      unawaited(ref.read(playerProvider.notifier).flushPlaybackMemory());
      unawaited(ref.read(playerProvider.notifier).reassertBackgroundPlayback());
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(floatingLyricsSyncProvider);
    ref.watch(listeningStatsTrackerProvider);
    final themeSettings = ref.watch(themeSettingsProvider);
    final uiStyle = ref.watch(uiStyleProvider).style;

    final ThemeData lightTheme = switch (uiStyle) {
      UiStyle.material => AppTheme.light(seedColor: themeSettings.seedColor),
      UiStyle.miuix => miuixTheme(
        brightness: Brightness.light,
        seedColor: themeSettings.seedColor,
      ),
    };
    final ThemeData darkTheme = switch (uiStyle) {
      UiStyle.material => AppTheme.dark(seedColor: themeSettings.seedColor),
      UiStyle.miuix => miuixTheme(
        brightness: Brightness.dark,
        seedColor: themeSettings.seedColor,
      ),
    };

    return MaterialApp.router(
      title: 'Mconnect',
      debugShowCheckedModeBanner: false,
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: themeSettings.mode,
      builder: (context, child) =>
          MconnectApp.buildGlassShell(context, child, uiStyle),
      routerConfig: appRouter,
    );
  }
}
