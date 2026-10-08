import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'app.dart';
import 'core/constants/app_constants.dart';
import 'core/diagnostics/crash_reporter.dart';
import 'core/diagnostics/diagnostics_service.dart';
import 'features/player/data/background_audio_initializer.dart';
import 'features/widget/widget_bridge.dart';
import 'features/widget/widget_bridge_observer.dart';
import 'platform/base/platform_registry.dart';
import 'platform/netease/netease_platform.dart';
import 'platform/qq/qq_platform.dart';
import 'platform/kugou/kugou_platform.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Apply the documented image cache budget. Until now nothing read this
  // constant, so the app ran on the framework default (100 MB) while the source
  // claimed 200 MB - a "tunable" that changed nothing.
  PaintingBinding.instance.imageCache.maximumSizeBytes =
      AppConstants.imageCacheSizeMb * 1024 * 1024;

  final diagnostics = DiagnosticsService.instance;

  // These three jobs are independent, so they run concurrently instead of
  // paying their latencies one after another before the first frame. The only
  // ordering that matters is Hive.initFlutter() before openBox('settings'),
  // which is why they are wrapped together.
  await Future.wait<void>([
    _prewarmGlassWidgets(),
    diagnostics.initialize(),
    _openSettingsBox(),
  ]);
  diagnostics.startUiHeartbeat();

  // Audio/session setup must finish before playback can be requested, but it
  // does not depend on the three jobs above (it is handed the already
  // initialised diagnostics instance).
  await BackgroundAudioInitializer.initialize(diagnostics: diagnostics);

  // Crash reporting: local by default (the existing diagnostics log, redacted),
  // and remote **only** when a DSN was supplied at build time
  // (`--dart-define=MCONNECT_SENTRY_DSN=…`) — see `CrashReporter`. With no DSN
  // there is no network behaviour at all, which is a structural guarantee rather
  // than a promise to remember.
  final crashReporter = CrashReporter(diagnostics: diagnostics);

  // The three process-wide entries. `installCrashHandling` takes over
  // `FlutterError.onError` and `ErrorWidget.builder` and **returns** the zone
  // callback `runZonedGuarded` needs, so the wiring stays testable.
  final onZoneError = installCrashHandling(
    crashReporter,
    // Unchanged red-screen text: this only adds "report it on the way out".
    buildErrorWidget: (details) {
      return Material(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              '发生了错误\n${details.exceptionAsString()}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ),
      );
    },
    // Same console output as the inline handler had: presentError + debugPrint.
    presentError: (details) {
      FlutterError.presentError(details);
      debugPrint('FlutterError: ${details.exceptionAsString()}');
    },
  );

  // Register platforms
  PlatformRegistry.register(NeteasePlatform());
  PlatformRegistry.register(QqPlatform());
  PlatformRegistry.register(KugouPlatform());

  // W3-A: home-screen widget bridge (see lib/features/widget/).
  //
  // `home_widget`'s pubspec declares `platforms:` for **android and ios only**, so
  // on Windows the plugin is simply not built or registered: nothing fails to
  // compile, but ANY `HomeWidget.*` call would throw MissingPluginException.
  // `WidgetBridge` therefore checks `isSupported` before touching the plugin and is
  // a hard no-op elsewhere (test/widget_bridge_test.dart pins that with a plugin-call
  // counter). Every failure here is swallowed and reported: the widget is a
  // nice-to-have and must never be able to break startup.
  await WidgetBridge.initialize(
    onError: (message, error, stack) =>
        diagnostics.recordError(message, error, stack),
  );

  runZonedGuarded(
    () => runApp(
      ProviderScope(
        // W3-A: hands the widget bridge a ProviderContainer so it can (a) push
        // playback state to the home screen and (b) drive play/pause/next from a
        // widget tap -- without editing app.dart or lib/core/share/** (other
        // owners' scopes). See WidgetBridgeObserver.
        observers: [WidgetBridgeObserver()],
        child: const MconnectApp(),
      ),
    ),
    (
      error,
      stack,
    ) {
    debugPrint('Uncaught error: $error\n$stack');
    onZoneError(error, stack);
  });
}

/// Pre-warms the liquid-glass fragment shader (a disk read).
///
/// Deliberately failure-tolerant: the platform may not support it and the
/// shader asset may be missing, in which case version 1.7.2 of the package
/// falls back to `BackdropFilter` or an opaque fill on its own. Startup must
/// never be blocked by a pre-warm, which is why the error is only logged.
Future<void> _prewarmGlassWidgets() async {
  try {
    await LiquidGlassWidgets.initialize();
  } catch (error, stack) {
    debugPrint('LiquidGlassWidgets.initialize 失败（已忽略）: $error\n$stack');
  }
}

/// Opens the Hive settings box. `initFlutter` must run first - those two are the
/// only ordered steps in the pre-runApp block.
Future<void> _openSettingsBox() async {
  await Hive.initFlutter();
  await Hive.openBox('settings');
}
