import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'core/desktop/desktop_behavior_settings.dart';
import 'core/desktop/desktop_integration_service.dart';
import 'core/diagnostics/diagnostics_service.dart';
import 'core/desktop/desktop_runtime_status.dart';
import 'core/desktop/desktop_shell_policy.dart';
import 'core/desktop/desktop_theme.dart';
import 'core/network/platform_http.dart';
import 'core/platform/platform_utils.dart';
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
import 'features/floating_lyrics/presentation/providers/taskbar_lyrics_provider.dart';
import 'features/player/data/playback_notification_service.dart'
    as playback_notification;
import 'features/player/presentation/providers/player_provider.dart';
import 'features/stats/presentation/providers/listening_stats_provider.dart';
import 'l10n/app_localizations.dart';
import 'l10n/l10n.dart';
import 'l10n/platform_labels.dart';
import 'models/platform_type.dart';
import 'platform/base/platform_registry.dart';

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

/// Whether a network-reported session expiry for [platform] should actually
/// clear the stored session.
///
/// Kept as a free function (rather than inlined into the state object) so the
/// negative case — "an anonymous request got a 403, so do **not** treat the
/// user as expired" — is directly testable without mounting the app.
///
/// Returns false when the platform is not registered (bare test mounts) or when
/// it currently has no session: there is nothing to expire, and clearing would
/// be a lie the user pays for with a spurious "please sign in again" toast.
bool shouldClearSessionOnExpiry(PlatformType platform) {
  try {
    return PlatformRegistry.get(platform).isLoggedIn;
  } catch (_) {
    return false;
  }
}

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
    // The desktop shell paints its own ambient background and rounded content
    // plate. Wrapping it in the phone background shell (and, under Miuix, the
    // liquid-glass scopes) would double the backdrop and re-enable the expensive
    // full-screen blur this port deliberately avoids.
    if (DesktopShellPolicy.isEnabled) {
      return Material(
        type: MaterialType.transparency,
        child: child ?? const SizedBox.shrink(),
      );
    }

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

  /// Installed process-wide so the network layer can report a dead session
  /// without every caller remembering to (see [SessionExpiryReporter]).
  SessionExpiredHandler? _sessionExpiryHandler;

  /// The Windows runner channel, or null everywhere else.
  ///
  /// Only Windows has a `desktop_integration` handler, so every call site below
  /// is a no-op on Android/iOS/desktop-other instead of a missing-plugin error
  /// per frame.
  DesktopIntegrationService? _desktop;

  /// Runner events (tray commands, close requests, deep links).
  StreamSubscription<DesktopIntegrationEvent>? _desktopEvents;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ref.read(authProvider.notifier).init();

    // Windows only: the runner owns SMTC, the tray icon, window state, the
    // single-instance hand-off and the `mconnect://` launch argument. Every call
    // below answers false/null when the native handler is missing (a dev build,
    // an older runner binary), which is why this whole block is best-effort and
    // cannot fail startup.
    final desktop = PlatformUtils.isWindows
        ? ref.read(desktopIntegrationServiceProvider)
        : null;
    _desktop = desktop;
    if (desktop != null) {
      _desktopEvents = desktop.events.listen(_handleDesktopEvent);
      unawaited(_initializeDesktopIntegration(desktop));
    }

    // WS-I wiring: cold-start + running-app deep links. `attachDeepLinkHandling`
    // defers its own `start()` to a post-frame callback, so calling it from
    // `initState` cannot navigate before the router exists.
    //
    // The message callback goes through the app-wide messenger: this `context` is
    // *above* `MaterialApp`, where `ScaffoldMessenger.maybeOf` finds nothing.
    //
    // On Windows the source is the runner (`takeInitialUri` + `uriReceived`)
    // rather than `app_links` — same `LinkSource` seam, same parsing and
    // navigation, only the origin of the URI differs.
    _deepLinks = attachDeepLinkHandling(
      ref,
      navigate: appRouter.go,
      source: desktop == null
          ? const AppLinksSource()
          : DesktopLinkSource(desktop: desktop),
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

    // 桌面行为设置 → 原生。一处接线：设置页只改 provider，通道调用集中在这里
    // （而且只在有桌面通道时发生）。
    ref.listenManual<DesktopBehaviorSettings>(
      desktopBehaviorSettingsProvider,
      (previous, next) => _applyDesktopBehavior(next),
    );
    // 防休眠是**状态**而不是开关：同一份设置，播放中要为 true，暂停后必须回落。
    ref.listenManual<bool>(
      playerProvider.select((state) => state.isPlaying),
      (previous, next) => _applyPreventSleep(next),
      fireImmediately: true,
    );
    // 任务栏歌词开关不在 PlaybackNotificationController.update 的入参里，所以由
    // 这里把设置推给 Windows 控制器（否则托盘菜单的勾选永远是"关"）。
    ref.listenManual<bool>(
      taskbarLyricsProvider.select((settings) => settings.enabled),
      (previous, next) => _pushTaskbarLyricsFlag(next),
      fireImmediately: true,
    );

    // v1.4.1: session expiry is reported by the network layer itself
    // (`PlatformErrorInterceptor`), not by individual providers. Before this,
    // exactly one production call site reacted to `LoginExpiredException`, so a
    // dead cookie anywhere else left the app showing the user as logged in
    // while every request failed.
    _sessionExpiryHandler = _reportSessionExpiry;
    SessionExpiryReporter.handler = _sessionExpiryHandler;
  }

  /// `initialize` once, then push the persisted settings into the runner.
  ///
  /// Nothing below runs when the runner answers false: a Windows build whose
  /// runner predates this channel keeps working, with one diagnostic instead of
  /// three failed calls per settings change.
  Future<void> _initializeDesktopIntegration(
    DesktopIntegrationService desktop,
  ) async {
    if (!await desktop.initialize()) return;
    _applyDesktopBehavior(ref.read(desktopBehaviorSettingsProvider));
    // Events are the fast path, not the only one. A tray icon the shell never
    // accepted emits nothing at all, so without this pull the status card keeps
    // saying "尚未收到运行器答复" while the user is looking at a tray with no
    // icon in it.
    await _refreshRuntimeStatus(desktop);
  }

  /// One pull of `getRuntimeStatus`, folded into the same state the events feed.
  ///
  /// Everything is read defensively: a runner older than this Dart build answers
  /// a map without the newer keys (or nothing at all), and "unknown" has to stay
  /// distinguishable from "failed".
  Future<void> _refreshRuntimeStatus(DesktopIntegrationService desktop) async {
    final runtime = await desktop.getRuntimeStatus();
    if (runtime == null || !mounted) return;
    final status = ref.read(desktopRuntimeStatusProvider.notifier);

    final trayAdded = runtime['trayAdded'];
    if (trayAdded is bool) {
      if (trayAdded) {
        status.setTrayReady(ready: true);
      } else {
        final error = runtime['trayError'];
        status.setTrayFailed(
          error: error is int ? error : (error is num ? error.round() : 1),
        );
      }
    }

    final smtcAvailable = runtime['smtcAvailable'];
    if (smtcAvailable is bool) {
      status.setSmtcAvailable(available: smtcAvailable);
    }

    // The registered list is the truth; `setHotkeys` answers true even when the
    // feature is off, which is the false positive this query exists to fix.
    final hotkeysEnabled = runtime['hotkeysEnabled'];
    if (hotkeysEnabled is bool) {
      status.setHotkeysEnabled(enabled: hotkeysEnabled);
    }

    final elevated = runtime['elevated'];
    if (elevated is bool) {
      status.setElevated(isElevated: elevated);
    }

    final integrity = runtime['integrity'];
    if (integrity is int && integrity > 0) {
      status.setIntegrityLevel(level: integrity);
    } else if (integrity is num && integrity > 0) {
      status.setIntegrityLevel(level: integrity.round());
    }

    // The runner remembers whether its last close had to leave the window open;
    // a fresh launch should not claim "关闭时窗口仍然打开" before the user has
    // actually tried to close it.
    final keptOpen = runtime['trayUnavailableClose'];
    if (keptOpen == true && trayAdded == false) {
      final error = runtime['trayError'];
      status.setTrayUnavailableKeptOpen(
        error: error is int ? error : (error is num ? error.round() : 1),
      );
    }
  }

  /// Pushes close/hotkey/sleep settings. Sleep depends on playback, so the
  /// current player state is passed in rather than assumed.
  void _applyDesktopBehavior(DesktopBehaviorSettings settings) {
    final desktop = _desktop;
    if (desktop == null) return;
    final status = ref.read(desktopRuntimeStatusProvider.notifier);
    unawaited(() async {
      final result = await settings.applyTo(
        desktop,
        isPlaying: ref.read(playerProvider).isPlaying,
      );
      if (!mounted) return;
      // The runner answers false when another application owns the chord; that
      // answer used to be thrown away, so a dead hotkey looked identical to a
      // working one.
      status.setHotkeysRegistered(
        registered: result.hotkeysRegistered,
      );
      // Pull once more after the push: `getRuntimeStatus.hotkeysEnabled` reads
      // the runner's actual registration list, which only now reflects what was
      // just applied (the setHotkeys answer alone is true even when disabled).
      await _refreshRuntimeStatus(desktop);
    }());
  }

  /// Re-arms (or releases) the OS sleep request after a play/pause transition.
  void _applyPreventSleep(bool isPlaying) {
    final desktop = _desktop;
    if (desktop == null) return;
    final settings = ref.read(desktopBehaviorSettingsProvider);
    unawaited(
      desktop.setPreventSleep(
        settings.shouldPreventSleep(isPlaying: isPlaying),
      ),
    );
  }

  /// Hands the taskbar-lyrics setting to the live Windows controller.
  ///
  /// The controller publishes `taskbarLyrics` on every tray update but has no
  /// parameter for it, so the value has to be pushed in from the setting that
  /// owns it.
  void _pushTaskbarLyricsFlag(bool enabled) {
    if (_desktop == null) return;
    // Reading the notifier guarantees the controller exists before the very
    // first (fireImmediately) push: the Windows controller registers itself on
    // attach, which happens in the player's constructor.
    ref.read(playerProvider.notifier);
    final controller =
        playback_notification.WindowsPlaybackNotificationController.active;
    controller?.taskbarLyricsEnabled = enabled;
  }

  /// Runner events that are not the player controller's business.
  ///
  /// `smtcControl` is deliberately absent: the Windows playback controller
  /// subscribes to the same stream and maps those actions onto the player. Doing
  /// it here too would fire every tray command twice.
  void _handleDesktopEvent(DesktopIntegrationEvent event) {
    switch (event.name) {
      case 'windowCloseRequested':
        unawaited(_persistBeforeClose());
      case 'trayReady':
        ref.read(desktopRuntimeStatusProvider.notifier).setTrayReady(
          ready: true,
        );
      case 'smtcUnavailable':
        ref.read(desktopRuntimeStatusProvider.notifier).setSmtcAvailable(
          available: false,
        );
      case 'trayUnavailableKeptOpen':
        final keptReason = event['reason'];
        final keptError = keptReason is int
            ? keptReason
            : (keptReason is num ? keptReason.round() : 1);
        ref
            .read(desktopRuntimeStatusProvider.notifier)
            .setTrayUnavailableKeptOpen(error: keptError);
        DiagnosticsService.instance.record(
          'desktop',
          'close_kept_window_open',
          data: {'trayError': keptError},
        );
        appScaffoldMessengerKey.currentState
          ?..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(
                '托盘图标不可用（错误 '
                '$keptError），已保持窗口打开；可在 设置→桌面行为→运行状态 查看原因',
              ),
            ),
          );
      case 'hiddenWithoutTray':
        final hideReason = event['reason'];
        final hideError = hideReason is int
            ? hideReason
            : (hideReason is num ? hideReason.round() : 1);
        ref
            .read(desktopRuntimeStatusProvider.notifier)
            .setHiddenWithoutTray(error: hideError);
        DiagnosticsService.instance.record(
          'desktop',
          'close_hidden_without_tray',
          data: {'trayError': hideError},
        );
      case 'trayIconPlaced':
        // Diagnostic only: the shell answered with the rectangle an accepted
        // icon occupies (or refused to answer when it lives in the overflow).
        DiagnosticsService.instance.record(
          'desktop',
          'tray_icon_placed',
          data: {
            'ok': event['ok'],
            'left': event['rectLeft'],
            'top': event['rectTop'],
          },
        );
      case 'hiddenToTray':
        ref.read(desktopRuntimeStatusProvider.notifier).recordClose(
          hiddenToTray: true,
        );
      case 'closeFellBackToExit':
        ref.read(desktopRuntimeStatusProvider.notifier).recordClose(
          hiddenToTray: false,
        );
      case 'trayFailed':
        final error = event['error'];
        ref
            .read(desktopRuntimeStatusProvider.notifier)
            .setTrayFailed(
              error: error is int ? error : (error is num ? error.round() : 1),
            );
      case 'minimizedInsteadOfTray':
        // 关闭到托盘 is on but there is no icon: the window is on the taskbar and
        // the process is alive. Neither of the other two close outcomes.
        ref.read(desktopRuntimeStatusProvider.notifier).setMinimizedInstead();
      case 'trayCommand':
        _handleTrayCommand(event['action']?.toString());
      case 'uriReceived':
        // Consumed by [DesktopLinkSource], which is the only consumer that can
        // turn a URI into navigation; nothing to do here.
        break;
      default:
        break;
    }
  }

  /// Tray menu items the player controller does not already handle.
  ///
  /// `play` / `pause` / `next` / `previous` / `toggleLike` / `toggleLyrics`
  /// all live in `WindowsPlaybackNotificationController._handleEvent`; repeating
  /// `toggleLyrics` here would toggle the floating lyrics off and straight back
  /// on, so only the taskbar switch is handled on this side.
  void _handleTrayCommand(String? action) {
    switch (action) {
      case 'toggleTaskbarLyrics':
        final notifier = ref.read(taskbarLyricsProvider.notifier);
        unawaited(
          notifier.setEnabled(!ref.read(taskbarLyricsProvider).enabled),
        );
      default:
        break;
    }
  }

  /// Last-chance persistence before the runner hides or closes the window.
  ///
  /// Dart does **not** decide whether the window hides or exits — that is the
  /// runner's job, and it was told which one to do through `setCloseBehavior`.
  /// Here the app only makes sure nothing in flight is lost.
  Future<void> _persistBeforeClose() async {
    unawaited(ref.read(playerProvider.notifier).flushPlaybackMemory());
    final desktop = _desktop;
    if (desktop == null) return;
    if (!ref.read(desktopBehaviorSettingsProvider).rememberWindowState) return;
    // No argument: the runner owns the window and knows its live rectangle.
    await desktop.saveWindowState();
  }

  /// Forwards a network-layer session expiry to [AuthProvider].
  ///
  /// The guard is what keeps this from being harmful: a 403 on an *anonymous*
  /// request must not clear anything, and because `handleSessionExpired` clears
  /// the session, the same check makes the burst of 401s that follows a real
  /// expiry report exactly once.
  void _reportSessionExpiry(PlatformType platform) {
    if (!mounted) return;
    if (!shouldClearSessionOnExpiry(platform)) return;
    unawaited(ref.read(authProvider.notifier).handleSessionExpired(platform));
  }

  @override
  void dispose() {
    final desktopEvents = _desktopEvents;
    _desktopEvents = null;
    if (desktopEvents != null) unawaited(desktopEvents.cancel());
    _deepLinks?.dispose();
    SessionExpiryReporter.handler = null;
    _sessionExpiryHandler = null;
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

    final ThemeData lightTheme = DesktopShellPolicy.isEnabled
        ? desktopTheme(
            brightness: Brightness.light,
            seedColor: themeSettings.seedColor,
          )
        : switch (uiStyle) {
            UiStyle.material => AppTheme.light(seedColor: themeSettings.seedColor),
            UiStyle.miuix => miuixTheme(
              brightness: Brightness.light,
              seedColor: themeSettings.seedColor,
            ),
          };
    final ThemeData darkTheme = DesktopShellPolicy.isEnabled
        ? desktopTheme(
            brightness: Brightness.dark,
            seedColor: themeSettings.seedColor,
          )
        : switch (uiStyle) {
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