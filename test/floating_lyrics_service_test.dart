import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/features/floating_lyrics/data/floating_lyrics_models.dart';
import 'package:mconnect/features/floating_lyrics/data/floating_lyrics_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.mconnect.mconnect/floating_lyrics');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return switch (call.method) {
            'canDrawOverlays' => true,
            'openOverlaySettings' => true,
            'show' => true,
            'update' => true,
            'hide' => true,
            _ => null,
          };
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('canDrawOverlays invokes the native permission check', () async {
    final allowed = await FloatingLyricsService.instance.canDrawOverlays();

    expect(allowed, isTrue);
    expect(calls.single.method, 'canDrawOverlays');
  });

  test('show sends transparent default style to native overlay', () async {
    const settings = FloatingLyricsSettings(enabled: true);
    const payload = FloatingLyricsPayload(
      text: 'Everything that kills me makes me feel alive',
      translation: '凡是击垮我的一切，都让我感到自己仍然鲜活',
      progress: 0.45,
    );

    await FloatingLyricsService.instance.show(payload, settings);

    expect(calls.single.method, 'show');
    final args = calls.single.arguments as Map<Object?, Object?>;
    expect(args['text'], payload.text);
    expect(args['translation'], payload.translation);
    expect(args['backgroundColor'], Colors.transparent.toARGB32());
    expect(args['textColor'], settings.textColor.toARGB32());
    expect(args['highlightColor'], settings.highlightColor.toARGB32());
  });

  test('update and hide call native overlay methods', () async {
    await FloatingLyricsService.instance.update(
      const FloatingLyricsPayload(text: 'Next line'),
      const FloatingLyricsSettings(enabled: true),
    );
    await FloatingLyricsService.instance.hide();

    expect(calls.map((call) => call.method), ['update', 'hide']);
  });

  test(
    'hide returns false when the native overlay channel is unavailable',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);

      final hidden = await FloatingLyricsService.instance.hide();

      expect(hidden, isFalse);
      expect(calls, isEmpty);
    },
  );

  test(
    'Windows asks the native floating lyrics channel for availability',
    () async {
      PlatformUtils.setDebugOverride(AppPlatform.windows);
      addTearDown(() => PlatformUtils.setDebugOverride(null));

      final allowed = await FloatingLyricsService.instance.canDrawOverlays();

      expect(allowed, isTrue);
      expect(calls.single.method, 'canDrawOverlays');
    },
  );

  test('native window resize events are exposed as a typed stream', () async {
    final events = <({int width, int height})>[];
    final sub = FloatingLyricsService.instance.windowResizedStream.listen(
      events.add,
    );
    addTearDown(sub.cancel);

    await _sendNativeFloatingLyricsCall('windowResized', {
      'width': 456,
      'height': 118,
    });
    await pumpEventQueue();

    expect(events, [(width: 456, height: 118)]);
  });
}

Future<void> _sendNativeFloatingLyricsCall(String method, [Object? arguments]) {
  const codec = StandardMethodCodec();
  return TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
        'com.mconnect.mconnect/floating_lyrics',
        codec.encodeMethodCall(MethodCall(method, arguments)),
        (_) {},
      );
}
