import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/core/platform/platform_utils.dart';
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
      nextText: 'Next line of the song',
      highlightProgress: 0.5,
      highlightRate: 0.002,
      isPlaying: true,
      hasSong: true,
    );

    await FloatingLyricsService.instance.show(payload, settings);

    expect(calls.single.method, 'show');
    final args = calls.single.arguments as Map<Object?, Object?>;
    expect(args['text'], payload.text);
    expect(args['translation'], payload.translation);
    expect(args['nextText'], payload.nextText);
    expect(args['highlightProgress'], 0.5);
    expect(args['highlightRate'], 0.002);
    expect(args['backgroundColor'], Colors.transparent.toARGB32());
    expect(args['textColor'], settings.textColor.toARGB32());
    expect(args['highlightColor'], settings.highlightColor.toARGB32());
    expect(args['positionY'], settings.positionY);
    expect(args['fontSize'], settings.fontSize);
    expect(args['isPlaying'], isTrue);
    expect(args['hasSong'], isTrue);
  });

  test('floating lyrics defaults to a white base color', () {
    const settings = FloatingLyricsSettings();

    expect(settings.textColor, const Color(0xFFFFFFFF));
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

  test('Windows native color parser accepts opaque ARGB values', () {
    final source = File(
      'windows/runner/floating_lyrics_channel.cpp',
    ).readAsStringSync();

    expect(source, contains('std::uint32_t'));
    expect(source, contains('static_cast<std::uint32_t>'));
    expect(source, isNot(contains('if (argb < 0)')));
  });

  test(
    'Android native floating lyrics uses stable system TextView rendering',
    () {
      final source = File(
        'android/app/src/main/kotlin/com/mconnect/mconnect/FloatingLyricsController.kt',
      ).readAsStringSync();

      expect(source, isNot(contains('FastMarqueeTextView')));
      expect(source, isNot(contains('override fun onDraw')));
      expect(source, isNot(contains('canvas.drawText')));
      expect(source, contains('lyricText = TextView(activity).apply'));
      expect(source, contains('translationText = TextView(activity).apply'));
      expect(source, contains('minHeight = dp('));
      expect(source, contains('setTextIfChanged'));
      expect(source, isNot(contains('this.text = text')));
      expect(source, isNot(contains('this.text = translation')));
    },
  );

  test('Android native overlay only drags vertically and stays full width', () {
    final source = File(
      'android/app/src/main/kotlin/com/mconnect/mconnect/FloatingLyricsController.kt',
    ).readAsStringSync();

    // Full width comes from MATCH_PARENT so a rotation re-measures the window
    // without any display-metric math.
    expect(source, contains('WindowManager.LayoutParams.MATCH_PARENT'));
    expect(source, isNot(contains('screenWidthPx')));
    expect(source, contains('FLAG_NOT_TOUCH_MODAL'));
    // Horizontal drag is gone: only the vertical offset is ever written.
    expect(source, isNot(contains('params.x = startX')));
    expect(source, isNot(contains('resizeHandle')));
    // The overlay drives the new native events the Dart side listens to.
    expect(source, contains('styleChanged'));
    expect(source, contains('controlRequested'));
    expect(source, contains('positionChanged'));
    expect(source, contains('isLocked'));
  });

  test('Android overlay colors the played part inside the lyric text itself', () {
    final source = File(
      'android/app/src/main/kotlin/com/mconnect/mconnect/FloatingLyricsController.kt',
    ).readAsStringSync();

    // The highlight is a color span on the same TextView that draws the line,
    // so it can never detach from the glyphs and there is no second view whose
    // visibility/clip/scroll state could go stale.
    expect(source, contains('ForegroundColorSpan'));
    expect(source, contains('applyProgressSpans'));
    expect(source, contains('blendColor'));
    expect(source, contains('TextView.BufferType.SPANNABLE'));
    expect(source, contains('highlightProgress'));
    expect(source, contains('highlightRate'));
    // Frames fill the gaps between the ~200ms Dart anchors.
    expect(source, contains('runFrame'));
    expect(source, contains('FRAME_INTERVAL_MS'));
  });

  test('Android overlay does not stack a second highlighted lyric view', () {
    final source = File(
      'android/app/src/main/kotlin/com/mconnect/mconnect/FloatingLyricsController.kt',
    ).readAsStringSync();

    // Regression guards for the machinery that made the current line render
    // blank until a layout pass: a clipped overlay copy, a paint shader, and
    // the controller owning the line's scroll offset.
    expect(source, isNot(contains('progressText')));
    expect(source, isNot(contains('clipBounds')));
    expect(source, isNot(contains('paint.shader = ')));
    expect(source, isNot(contains('configureScrollingLine')));
    expect(source, isNot(contains('scrollTo(')));
    expect(source, contains('configureMarquee'));
  });

  test('Android overlay always re-applies the font size to fresh views', () {
    final source = File(
      'android/app/src/main/kotlin/com/mconnect/mconnect/FloatingLyricsController.kt',
    ).readAsStringSync();

    // The overlay rebuilds its TextViews every time it is shown again, and the
    // default TextView size is 14sp. Gating applyTextSize() on "the incoming
    // size differs from the cached field" meant an unchanged persisted size was
    // never written to the fresh views, so the lyrics fell back to 14sp until
    // the user tapped a size button.
    expect(source, contains('applyTextSize()'));
    expect(source, isNot(contains('if (sizeChanged || shadowChanged)')));
    expect(source, contains('resetAppliedState()'));
    expect(source, contains('appliedFontSize = -1f'));
  });

  test('Android overlay is click-through while locked', () {
    final source = File(
      'android/app/src/main/kotlin/com/mconnect/mconnect/FloatingLyricsController.kt',
    ).readAsStringSync();

    expect(source, contains('FLAG_NOT_TOUCHABLE'));
    expect(source, contains('LOCKED_LOCK_ALPHA'));
    expect(source, contains('BUTTON_ALPHA'));
  });

  test('Android overlay reports unsigned 32 bit ARGB colors', () {
    final source = File(
      'android/app/src/main/kotlin/com/mconnect/mconnect/FloatingLyricsController.kt',
    ).readAsStringSync();

    expect(source, contains('and 0xFFFFFFFFL'));
  });

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

  test('native close events are exposed as a stream', () async {
    var closedCount = 0;
    final sub = FloatingLyricsService.instance.closedByUserStream.listen(
      (_) => closedCount++,
    );
    addTearDown(sub.cancel);

    await _sendNativeFloatingLyricsCall('closedByUser');
    await pumpEventQueue();

    expect(closedCount, 1);
  });

  test('native style changes are exposed as a typed stream', () async {
    final events = <({Color highlightColor, double fontSize})>[];
    final sub = FloatingLyricsService.instance.styleChangedStream.listen(
      events.add,
    );
    addTearDown(sub.cancel);

    await _sendNativeFloatingLyricsCall('styleChanged', {
      'highlightColor': 0xFF4AA8FF,
      'fontSize': 27.0,
    });
    await pumpEventQueue();

    expect(events, [
      (highlightColor: const Color(0xFF4AA8FF), fontSize: 27.0),
    ]);
  });

  test('native style changes tolerate signed 32 bit colors', () async {
    final events = <({Color highlightColor, double fontSize})>[];
    final sub = FloatingLyricsService.instance.styleChangedStream.listen(
      events.add,
    );
    addTearDown(sub.cancel);

    // 0xFF4AA8FF truncated into a signed 32 bit integer by a native caller.
    await _sendNativeFloatingLyricsCall('styleChanged', {
      'highlightColor': -11884289,
      'fontSize': 24.0,
    });
    await pumpEventQueue();

    expect(events, [
      (highlightColor: const Color(0xFF4AA8FF), fontSize: 24.0),
    ]);
  });

  test('native transport taps are exposed as a typed stream', () async {
    final events = <FloatingLyricsControl>[];
    final sub = FloatingLyricsService.instance.controlRequestedStream.listen(
      events.add,
    );
    addTearDown(sub.cancel);

    await _sendNativeFloatingLyricsCall('controlRequested', {
      'action': 'playPause',
    });
    await _sendNativeFloatingLyricsCall('controlRequested', {
      'action': 'previous',
    });
    await _sendNativeFloatingLyricsCall('controlRequested', {'action': 'next'});
    await _sendNativeFloatingLyricsCall('controlRequested', {
      'action': 'unsupported',
    });
    await pumpEventQueue();

    expect(events, [
      FloatingLyricsControl.playPause,
      FloatingLyricsControl.previous,
      FloatingLyricsControl.next,
    ]);
  });

  test('native drag positions are exposed as a stream', () async {
    final events = <double>[];
    final sub = FloatingLyricsService.instance.positionChangedStream.listen(
      events.add,
    );
    addTearDown(sub.cancel);

    await _sendNativeFloatingLyricsCall('positionChanged', 512.0);
    await pumpEventQueue();

    expect(events, [512.0]);
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
