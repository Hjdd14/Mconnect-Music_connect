import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/core/platform/platform_utils.dart';
import 'package:mconnect/features/player/data/playback_keep_alive_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.mconnect.mconnect/playback_keep_alive');

  tearDown(() {
    PlatformUtils.setDebugOverride(null);
    MethodChannelPlaybackKeepAliveController.instance.resetForTest();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('Android playback keep alive follows playing state changes', () async {
    PlatformUtils.setDebugOverride(AppPlatform.android);
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return null;
        });

    final controller = MethodChannelPlaybackKeepAliveController.instance
      ..resetForTest();

    await controller.setPlaying(true);
    await controller.setPlaying(true);
    await controller.setPlaying(false);

    expect(calls, hasLength(2));
    expect(calls[0].method, 'setPlaying');
    expect(calls[0].arguments, isTrue);
    expect(calls[1].method, 'setPlaying');
    expect(calls[1].arguments, isFalse);
  });

  test('Android playback keep alive can force reassert playing', () async {
    PlatformUtils.setDebugOverride(AppPlatform.android);
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return null;
        });

    final controller = MethodChannelPlaybackKeepAliveController.instance
      ..resetForTest();

    await controller.setPlaying(true);
    await controller.setPlaying(true, force: true);

    expect(calls, hasLength(2));
    expect(calls.map((call) => call.arguments), [true, true]);
  });

  test(
    'Android dispose always asks native side to release wake lock',
    () async {
      PlatformUtils.setDebugOverride(AppPlatform.android);
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return null;
          });

      final controller = MethodChannelPlaybackKeepAliveController.instance
        ..resetForTest();

      await controller.dispose();

      expect(calls, hasLength(1));
      expect(calls.single.method, 'setPlaying');
      expect(calls.single.arguments, isFalse);
    },
  );

  test(
    'non-Android playback keep alive does not call native channel',
    () async {
      PlatformUtils.setDebugOverride(AppPlatform.windows);
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return null;
          });

      final controller = MethodChannelPlaybackKeepAliveController.instance
        ..resetForTest();

      await controller.setPlaying(true);
      await controller.setPlaying(false);

      expect(calls, isEmpty);
    },
  );

  test('Android background playback bridge files remain wired', () {
    final main = File('lib/main.dart').readAsStringSync();
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final activity = File(
      'android/app/src/main/kotlin/com/mconnect/mconnect/MainActivity.kt',
    ).readAsStringSync();

    expect(main, contains('BackgroundAudioInitializer.initialize'));
    expect(manifest, contains('com.ryanheise.audioservice.AudioService'));
    expect(manifest, contains('MediaButtonReceiver'));
    expect(activity, contains('class MainActivity : AudioServiceActivity()'));
    expect(activity, contains('playback_keep_alive'));
  });

  test('Android keep alive holds and releases a Wi-Fi lock with wake lock', () {
    final source = File(
      'android/app/src/main/kotlin/com/mconnect/mconnect/PlaybackKeepAliveController.kt',
    ).readAsStringSync();

    expect(source, contains('WifiManager'));
    expect(source, contains('WIFI_MODE_FULL_HIGH_PERF'));
    expect(source, contains('wifiLock.acquire()'));
    expect(source, contains('wifiLock.release()'));
  });
}
