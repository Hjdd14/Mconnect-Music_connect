import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import 'app.dart';
import 'core/constants/app_constants.dart';
import 'core/desktop/desktop_data_directory.dart';
import 'core/desktop/desktop_shell_policy.dart';
import 'core/diagnostics/crash_reporter.dart';
import 'core/diagnostics/diagnostics_service.dart';
import 'core/network/system_trust.dart';
import 'features/player/data/background_audio_initializer.dart';
import 'features/widget/widget_bridge.dart';
import 'features/widget/widget_bridge_observer.dart';
import 'platform/base/platform_registry.dart';
import 'platform/netease/netease_platform.dart';
import 'platform/qq/qq_platform.dart';
import 'platform/kugou/kugou_platform.dart';

void Function(Object, StackTrace)? _zoneErrorHandler;

bool _appStarted = false;

void main() {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      try {
        await _bootstrap();
      } catch (error, stack) {
        debugPrint('Startup failed: $error\n$stack');
        final handler = _zoneErrorHandler;
        if (handler != null) handler(error, stack);
        if (!_appStarted) {
          runApp(_StartupErrorApp(error: error));
        }
      }
    },
    (error, stack) {
      final handler = _zoneErrorHandler;
      if (handler != null) {
        handler(error, stack);
      } else {
        debugPrint('Uncaught error: $error\n$stack');
      }
    },
  );
}

/// Shown only when bootstrap fails before the real app is mounted.
///
/// Without this the Windows runner presents an empty white client area when,
/// for example, the profile data directory is denied before the first frame.
/// The copy is English on purpose: it must not increase the hardcoded-Chinese
/// i18n ratchet, and it is not part of normal navigation.
class _StartupErrorApp extends StatelessWidget {
  final Object error;

  const _StartupErrorApp({required this.error});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Mconnect failed to start',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'The app could not prepare its local data directory. '
                    'Check that the user profile is writable, then restart.',
                  ),
                  const SizedBox(height: 16),
                  SelectableText(
                    '$error',
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _bootstrap() async {
  // Flutter Windows' bundled BoringSSL root store can lag the OS. Add a current
  // CA bundle before any platform/Dio request; this is trust-store completion,
  // not certificate bypass.
  await installBundledCaBundle();

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
  // Hive first: on Windows, starting the diagnostics file writer before the
  // first Hive box made every subsequent directory/file future hang during
  // desktop bring-up. The box is a prerequisite for settings anyway.
  await _openSettingsBox();
  await Future.wait<void>([
    // The desktop shell never uses liquid glass, and the package's shader
    // pre-warm can block startup on Windows. Skip it there; on mobile keep the
    // existing best-effort pre-warm (with a timeout so it can never wedge the
    // first frame).
    if (!DesktopShellPolicy.isEnabled)
      _prewarmGlassWidgets().timeout(
        const Duration(seconds: 4),
        onTimeout: () {},
      )
    else
      Future<void>.value(),
    diagnostics.initialize().timeout(
      const Duration(seconds: 8),
      onTimeout: () {},
    ),
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
  _zoneErrorHandler = onZoneError;
  _appStarted = true;
  runApp(
    ProviderScope(
      // W3-A: hands the widget bridge a ProviderContainer so it can push
      // playback state and accept play/pause/next taps. See WidgetBridgeObserver.
      observers: [WidgetBridgeObserver()],
      child: const MconnectApp(),
    ),
  );
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
  if (DesktopShellPolicy.isEnabled) {
    final dir = await desktopDataDirectory(child: 'hive');
    Hive.init(dir.path);
  } else {
    await Hive.initFlutter();
  }
  await Hive.openBox('settings');
}
