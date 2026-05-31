import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'app.dart';
import 'core/diagnostics/diagnostics_service.dart';
import 'features/player/data/background_audio_initializer.dart';
import 'platform/base/platform_registry.dart';
import 'platform/netease/netease_platform.dart';
import 'platform/qq/qq_platform.dart';
import 'platform/kugou/kugou_platform.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await Hive.openBox('settings');
  final diagnostics = DiagnosticsService.instance;
  await diagnostics.initialize();
  diagnostics.startUiHeartbeat();
  await BackgroundAudioInitializer.initialize(diagnostics: diagnostics);

  // Global error handling
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('FlutterError: ${details.exceptionAsString()}');
    diagnostics.recordError(
      'FlutterError',
      details.exception,
      details.stack ?? StackTrace.current,
    );
  };

  ErrorWidget.builder = (details) {
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
  };

  // Register platforms
  PlatformRegistry.register(NeteasePlatform());
  PlatformRegistry.register(QqPlatform());
  PlatformRegistry.register(KugouPlatform());

  runZonedGuarded(() => runApp(const ProviderScope(child: MconnectApp())), (
    error,
    stack,
  ) {
    debugPrint('Uncaught error: $error\n$stack');
    diagnostics.recordError('runZonedGuarded', error, stack);
  });
}
