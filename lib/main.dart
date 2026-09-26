import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'app.dart';
import 'core/diagnostics/diagnostics_service.dart';
import 'features/player/data/background_audio_initializer.dart';
import 'platform/base/platform_registry.dart';
import 'platform/netease/netease_platform.dart';
import 'platform/qq/qq_platform.dart';
import 'platform/kugou/kugou_platform.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 预热的只是片元着色器程序对象（磁盘 I/O），但它是可失败的操作
  // （平台不支持 / shader 资源缺失），失败了也不能挡住启动 ——
  // 玻璃控件在 1.7.2 里自己会退回 BackdropFilter / 不透明填充。
  try {
    await LiquidGlassWidgets.initialize();
  } catch (error, stack) {
    debugPrint('LiquidGlassWidgets.initialize 失败（已忽略）: $error\n$stack');
  }

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
