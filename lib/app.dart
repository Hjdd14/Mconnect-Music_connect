import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'core/router/app_router.dart';
import 'core/share/deep_link_service.dart';
import 'core/share/deep_link_wiring.dart';
import 'core/utils/snackbar_helper.dart';
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
import 'l10n/app_localizations.dart';
import 'l10n/l10n.dart';
import 'l10n/platform_labels.dart';
import 'models/platform_type.dart';

/// Marks the Material ancestor injected under [UiStyle.miuix].
///
/// Only ever present under [UiStyle.miuix]; `test/floating_glass_nav_bar_test.dart`
/// asserts its absence under [UiStyle.material] (invariant I-8 — the Material
/// path must not gain a wrapper).
///
/// `LiquidGlassWidgets.wrap` is a plain function, not a widget, so it takes no
/// `key`; the `GlassAdaptiveScope` it installs is located by *type* in tests.
const Key glassMaterialAncestorKey = Key('app-glass-material-ancestor');

/// Shows the app-wide toasts that have no `BuildContext` of their own.
///
/// The "session expired" notice is raised by a feature provider (which can
/// happen while any route is on screen, including a modal), so it cannot go
/// through a page's `ScaffoldMessenger.of(context)`.
final GlobalKey<ScaffoldMessengerState> appScaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

/// Locales the UI is actually translated for.
///
/// Only `zh` is *declared* this round: v1.4.0 migrated three pages
/// (settings / bottom navigation / player) and the English bundle exists and is
/// generated, but publishing `en` here would switch those three pages to
/// English on an English device while the other ~90 files stay Chinese — a
/// half-translated interface. `test/l10n_locale_switch_test.dart` proves the
/// English bundle works by rendering with `Locale('en')` explicitly.
///
/// Condition for adding `Locale('en')`: the remaining Chinese literals in
/// `lib/` are migrated (see the counts in `docs/`). The change is this one line
/// — `supportedLocales: AppLocalizations.supportedLocales`.
const List<Locale> appSupportedLocales = <Locale>[Locale('zh')];

/// Shows the app-wide "session expired" notice with its 「去登录」 action.
///
/// Extracted from the widget tree so a test can assert the copy, the action and
/// the navigation target without booting the whole app (pumping [MconnectApp]
/// drags in Hive, media_kit and the auth session restore).
void showSessionExpiredNotice({
  required ScaffoldMessengerState messenger,
  required PlatformType platform,
  required VoidCallback onGoToLogin,
}) {
  final l = messenger.context.l10n;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text('${platform.label(l)}：${l.sessionExpired}'),
        behavior: SnackBarBehavior.floating,
        // Longer than a normal toast: the user has to read it and decide.
        duration: const Duration(seconds: 6),
        action: SnackBarAction(
          label: l.sessionGoToLogin,
          onPressed: onGoToLogin,
        ),
      ),
    );
}

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
  /// Inbound `mconnect://` links (WS-I). Null until [initState] has run, and
  /// disposed with the app so a link arriving after teardown is not handled.
  DeepLinkService? _deepLinks;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ref.read(authProvider.notifier).init();
    // WS-I wiring: cold-start + running-app deep links. `attachDeepLinkHandling`
    // defers its own `start()` to a post-frame callback, so calling it from
    // `initState` cannot navigate before the router exists.
    //
    // The message callback goes through the app-wide messenger: this `context` is
    // *above* `MaterialApp`, where `ScaffoldMessenger.maybeOf` finds nothing.
    _deepLinks = attachDeepLinkHandling(
      ref,
      navigate: appRouter.go,
      onMessage: (message) {
        final messenger = appScaffoldMessengerKey.currentState;
        if (messenger == null) return;
        showInfoSnackBar(messenger.context, message);
      },
    );
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
    _deepLinks?.dispose();
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

    // task-5: a provider that hit HTTP 401 reports it through `authProvider`;
    // this is where the user actually finds out. The notice is app-wide (not
    // page-local) because the expiry can surface while any route is on screen.
    ref.listen<AuthState>(authProvider, (previous, next) {
      final platform = next.expiredPlatform;
      if (platform == null) return;
      if (previous?.expiryNoticeId == next.expiryNoticeId) return;
      final messenger = appScaffoldMessengerKey.currentState;
      if (messenger == null) return;
      showSessionExpiredNotice(
        messenger: messenger,
        platform: platform,
        onGoToLogin: () => appRouter.push('/login/${platform.name}'),
      );
      ref.read(authProvider.notifier).clearExpiryNotice();
    });

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
      scaffoldMessengerKey: appScaffoldMessengerKey,
      // Material/Cupertino's own built-in copy (dialog buttons, "Back", text
      // selection handles, …) follows these delegates. Without them Flutter
      // falls back to `DefaultMaterialLocalizations`, i.e. English chrome
      // inside a Chinese app.
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: appSupportedLocales,
      onGenerateTitle: (context) => context.l10n.appTitle,
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: themeSettings.mode,
      builder: (context, child) =>
          MconnectApp.buildGlassShell(context, child, uiStyle),
      routerConfig: appRouter,
    );
  }
}
