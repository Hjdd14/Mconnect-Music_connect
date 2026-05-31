import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/core/platform/platform_utils.dart';
import 'package:mconnect/utils/file_opener.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.mconnect.mconnect/file_opener');
  final calls = <MethodCall>[];
  final launches = <String>[];

  setUp(() {
    calls.clear();
    launches.clear();
    PlatformUtils.setDebugOverride(AppPlatform.android);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return true;
        });
    FileOpener.setWindowsLauncherForTest((executable, arguments) async {
      launches.add('$executable ${arguments.join('|')}');
      return ProcessResult(0, 0, '', '');
    });
  });

  tearDown(() {
    PlatformUtils.setDebugOverride(null);
    FileOpener.resetWindowsLauncherForTest();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('Android openFolder invokes the native openFolder method', () async {
    await FileOpener.openFolder('/storage/emulated/0/Mconnect/netease/mp3');

    expect(calls, hasLength(1));
    expect(calls.single.method, 'openFolder');
    expect(calls.single.arguments, '/storage/emulated/0/Mconnect/netease/mp3');
    expect(launches, isEmpty);
  });

  test('Windows openFolder launches Explorer', () async {
    PlatformUtils.setDebugOverride(AppPlatform.windows);

    await FileOpener.openFolder(r'D:\MconnectTestDownloads\netease\mp3');

    expect(calls, isEmpty);
    expect(
      launches.single,
      r'explorer.exe D:\MconnectTestDownloads\netease\mp3',
    );
  });

  test('Windows openFile uses shell start', () async {
    PlatformUtils.setDebugOverride(AppPlatform.windows);

    await FileOpener.openFile(r'D:\MconnectTestDownloads\netease\mp3\Song.mp3');

    expect(calls, isEmpty);
    expect(
      launches.single,
      r'cmd /c|start||D:\MconnectTestDownloads\netease\mp3\Song.mp3',
    );
  });
}
