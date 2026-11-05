import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/utils/file_opener.dart';

/// The channel the native side registers on Windows and Android.
const _channel = MethodChannel('com.mconnect.mconnect/file_opener');

void _setHandler(Future<Object?> Function(MethodCall call)? handler) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, handler);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    _setHandler((call) async {
      calls.add(call);
      return true;
    });
  });

  tearDown(() {
    _setHandler(null);
  });

  test('openFolder invokes the native openFolder method', () async {
    await FileOpener.openFolder('/storage/emulated/0/Mconnect/netease/mp3');

    expect(calls, hasLength(1));
    expect(calls.single.method, 'openFolder');
    expect(calls.single.arguments, '/storage/emulated/0/Mconnect/netease/mp3');
  });

  test('openFile invokes the native openFile method', () async {
    await FileOpener.openFile(r'D:\Music\song.mp3');

    expect(calls.single.method, 'openFile');
    expect(calls.single.arguments, r'D:\Music\song.mp3');
  });

  group('failures reach the caller as one typed exception', () {
    test('no native implementation at all', () async {
      _setHandler(null);

      await expectLater(
        FileOpener.openFolder('/tmp/music'),
        throwsA(
          isA<FileOpenerException>()
              .having((e) => e.unsupported, 'unsupported', isTrue)
              .having((e) => e.message, 'message', contains('原生')),
        ),
      );
    });

    test('the native side reports a failure', () async {
      _setHandler((call) async {
        throw PlatformException(
          code: 'OPEN_FAILED',
          message: 'No app can open this file',
        );
      });

      await expectLater(
        FileOpener.openFile('/tmp/song.mp3'),
        throwsA(
          isA<FileOpenerException>()
              .having(
                (e) => e.message,
                'message',
                contains('No app can open this file'),
              )
              .having((e) => e.unsupported, 'unsupported', isFalse),
        ),
      );
    });

    test('the native side declines without an error code', () async {
      _setHandler((call) async => false);

      await expectLater(
        FileOpener.openFolder('/tmp/music'),
        throwsA(isA<FileOpenerException>()),
      );
    });

    test('a void reply still counts as handled (Android returns true, but not every platform must)', () async {
      _setHandler((call) async => null);

      await expectLater(FileOpener.openFolder('/tmp/music'), completes);
    });

    test('an empty path fails before the channel is touched', () async {
      await expectLater(
        FileOpener.openFolder('   '),
        throwsA(isA<FileOpenerException>()),
      );
      await expectLater(
        FileOpener.openFile(''),
        throwsA(isA<FileOpenerException>()),
      );

      expect(calls, isEmpty);
    });
  });
}
