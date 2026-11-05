import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/core/lyrics/lyrics_animation_catalog.dart';
import 'package:mconnect/core/lyrics/lyrics_overlay_config.dart';
import 'package:mconnect/core/lyrics/lyrics_overlay_frame.dart';
import 'package:mconnect/features/floating_lyrics/data/floating_lyrics_models.dart';

/// Guards the persisted settings contract: old records keep loading, new
/// fields have the protocol defaults, and every ranged field clamps exactly
/// like its setter (docs/desktop-lyrics-protocol.md, section 2).
void main() {
  Map<String, Object?> legacySettingsJson() {
    return <String, Object?>{
      'enabled': true,
      'textColor': 0xFFFFFFFF,
      'highlightColor': 0xFFFFD44A,
      'backgroundColor': 0x00000000,
      'fontSize': 23.0,
      'strokeWidth': 0.7,
      'shadowOpacity': 0.78,
      'width': 320.0,
      'height': 92.0,
      'isLocked': false,
      'positionY': 160.0,
    };
  }

  group('FloatingLyricsSettings', () {
    test('defaults match the desktop protocol', () {
      const settings = FloatingLyricsSettings();

      expect(settings.positionX, isNull);
      expect(settings.positionYRatio, isNull);
      expect(settings.monitorDeviceName, '');
      expect(settings.lineAnimation, LyricsLineTransition.fade);
      expect(settings.animationDurationMs, 220);
      expect(settings.easing, LyricsEasing.easeOut);
      expect(settings.windowAnimation, LyricsWindowTransition.fade);
      expect(settings.backgroundMode, LyricsBackgroundMode.none);
      expect(settings.backgroundColor2, const Color(0x00000000));
      expect(settings.backgroundOpacity, 0.55);
      expect(settings.cornerRadius, 16);
      expect(settings.fontFamily, '');
      expect(settings.fontWeight, 600);
      expect(settings.textAlign, LyricsTextAlignment.center);
      expect(settings.lineMode, LyricsLineMode.currentAndTranslation);
      expect(settings.showTranslation, LyricsTranslationVisibility.auto);
      expect(settings.letterSpacing, 0);
      expect(settings.lineHeight, 1.2);
      expect(settings.padding, 12);
      expect(settings.showControls, isTrue);
      expect(settings.clickThrough, isFalse);
      expect(settings.alwaysOnTop, isTrue);
      expect(settings.hideInFullscreen, isTrue);
      // Off by default on purpose: the native side treats an enabled
      // reduceMotion as a hard cut, so defaulting it to true made every
      // animation picked in the studio look like it did nothing.
      expect(settings.reduceMotion, isFalse);
      expect(settings.strokeColor, const Color(0xFF000000));
      expect(settings.shadowBlur, 8);
      expect(settings.wordHighlight, isTrue);
      expect(settings.coverImagePath, isNull);
    });

    test('a pre-desktop record still loads and keeps its values', () {
      final settings = FloatingLyricsSettings.fromJson(legacySettingsJson());

      expect(settings.enabled, isTrue);
      expect(settings.fontSize, 23);
      expect(settings.positionY, 160);
      expect(settings.isLocked, isFalse);
      // Desktop fields fall back to the protocol defaults.
      expect(settings.lineAnimation, LyricsLineTransition.fade);
      expect(settings.animationDurationMs, 220);
      expect(settings.windowAnimation, LyricsWindowTransition.fade);
      expect(settings.backgroundMode, LyricsBackgroundMode.none);
      expect(settings.positionX, isNull);
      expect(settings.positionYRatio, isNull);
    });

    test('fromJson clamps every ranged field like the setters', () {
      final settings = FloatingLyricsSettings.fromJson(<String, Object?>{
        'fontSize': 999,
        'strokeWidth': -1,
        'shadowOpacity': 2,
        'width': 10,
        'height': 999,
        'positionY': -50,
        'positionX': 5,
        'positionYRatio': -2,
        'animationDurationMs': 999,
        'backgroundOpacity': -1,
        'cornerRadius': 99,
        'fontWeight': 50,
        'letterSpacing': 99,
        'lineHeight': 9,
        'padding': -5,
        'shadowBlur': 99,
      });

      expect(settings.fontSize, 48);
      expect(settings.strokeWidth, 0);
      expect(settings.shadowOpacity, 1);
      expect(settings.width, 180);
      expect(settings.height, 220);
      expect(settings.positionY, 0);
      expect(settings.positionX, 1);
      expect(settings.positionYRatio, 0);
      expect(settings.animationDurationMs, 420);
      expect(settings.backgroundOpacity, 0);
      expect(settings.cornerRadius, 48);
      expect(settings.fontWeight, 100);
      expect(settings.letterSpacing, 16);
      expect(settings.lineHeight, 3);
      expect(settings.padding, 0);
      expect(settings.shadowBlur, 32);

      // Same numbers as the public clamps the setters use.
      expect(settings.fontSize, FloatingLyricsSettings.clampFontSize(999));
      expect(settings.width, FloatingLyricsSettings.clampWidth(10));
      expect(
        settings.animationDurationMs,
        FloatingLyricsSettings.clampAnimationDurationMs(999),
      );
      expect(
        settings.cornerRadius,
        FloatingLyricsSettings.clampCornerRadius(99),
      );
    });

    test('unknown enum ids fall back to the protocol defaults', () {
      final settings = FloatingLyricsSettings.fromJson(<String, Object?>{
        'lineAnimation': 'wobble',
        'windowAnimation': 'wobble',
        'easing': 'wobble',
        'backgroundMode': 'wobble',
        'textAlign': 'wobble',
        'lineMode': 'wobble',
        'showTranslation': 'wobble',
      });

      expect(settings.lineAnimation, LyricsLineTransition.fade);
      expect(settings.windowAnimation, LyricsWindowTransition.fade);
      expect(settings.easing, LyricsEasing.easeOut);
      expect(settings.backgroundMode, LyricsBackgroundMode.none);
      expect(settings.textAlign, LyricsTextAlignment.center);
      expect(settings.lineMode, LyricsLineMode.currentAndTranslation);
      expect(settings.showTranslation, LyricsTranslationVisibility.auto);
    });

    test('JSON round-trips without losing a field', () {
      const original = FloatingLyricsSettings(
        enabled: true,
        textColor: Color(0xFF112233),
        fontSize: 30,
        width: 420,
        height: 120,
        positionX: 0.25,
        positionYRatio: 0.75,
        monitorDeviceName: 'DISPLAY2',
        lineAnimation: LyricsLineTransition.wipeLeft,
        animationDurationMs: 300,
        easing: LyricsEasing.overshoot,
        windowAnimation: LyricsWindowTransition.slideFromBottom,
        backgroundMode: LyricsBackgroundMode.gradient,
        backgroundColor2: Color(0x66000000),
        backgroundOpacity: 0.4,
        cornerRadius: 24,
        fontFamily: 'Microsoft YaHei UI',
        fontWeight: 700,
        textAlign: LyricsTextAlignment.left,
        lineMode: LyricsLineMode.threeLines,
        showTranslation: LyricsTranslationVisibility.always,
        letterSpacing: 1.5,
        lineHeight: 1.4,
        padding: 18,
        showControls: false,
        clickThrough: true,
        alwaysOnTop: false,
        hideInFullscreen: false,
        reduceMotion: false,
        strokeColor: Color(0xFF445566),
        shadowBlur: 12,
        wordHighlight: false,
        coverImagePath: 'C:/cache/cover.png',
      );

      final roundTripped = FloatingLyricsSettings.fromJson(original.toJson());

      expect(roundTripped.toJson(), original.toJson());
    });

    test('toOverlayConfig carries the floating surface and legacy offset', () {
      const settings = FloatingLyricsSettings(
        enabled: true,
        positionY: 240,
        positionX: 0.5,
        textColor: Color(0xFF00FFAA),
        lineAnimation: LyricsLineTransition.glowSoft,
        animationDurationMs: 420,
      );

      final config = settings.toOverlayConfig();

      expect(config.surface, LyricsSurface.floating);
      expect(config.enabled, isTrue);
      expect(config.positionY, 240);
      expect(config.positionX, 0.5);
      expect(config.textColor, const Color(0xFF00FFAA).toARGB32());
      expect(config.lineAnimation, LyricsLineTransition.glowSoft);
      expect(config.animationDurationMs, 420);
    });
  });

  group('TaskbarLyricsSettings', () {
    test('defaults match the desktop protocol', () {
      const settings = TaskbarLyricsSettings();

      expect(settings.enabled, isFalse);
      expect(settings.monitorDeviceName, 'primary');
      expect(settings.anchor, LyricsTaskbarAnchor.auto);
      expect(settings.offsetX, 0);
      expect(settings.width, 560);
      expect(settings.height, 0);
      expect(settings.fontSize, 16);
      expect(settings.fontWeight, 600);
      expect(settings.textColor, const Color(0xFFFFFFFF));
      expect(settings.highlightColor, const Color(0xFFFFD44A));
      expect(settings.backgroundMode, LyricsBackgroundMode.transparent);
      expect(settings.backgroundColor, const Color(0xFF000000));
      expect(settings.backgroundOpacity, 0.35);
      expect(settings.lineMode, LyricsLineMode.auto);
      expect(settings.translationLayout, LyricsTranslationLayout.stacked);
      expect(settings.lineAnimation, LyricsLineTransition.slideLeft);
      expect(settings.animationDurationMs, 200);
      expect(settings.easing, LyricsEasing.easeOut);
      expect(settings.windowAnimation, LyricsWindowTransition.fade);
      expect(settings.clickThrough, isTrue);
      expect(settings.followAutoHide, isTrue);
      expect(settings.hideInFullscreen, isTrue);
      expect(settings.marquee, isTrue);
      expect(settings.edgePadding, 8);
      expect(settings.cornerRadius, 8);
      expect(settings.debugGeometry, isFalse);
    });

    test('fromJson clamps and falls back', () {
      final settings = TaskbarLyricsSettings.fromJson(<String, Object?>{
        'offsetX': 99999,
        'width': 10,
        'height': 999,
        'fontSize': 1,
        'fontWeight': 1000,
        'backgroundOpacity': 2,
        'edgePadding': 99,
        'cornerRadius': 99,
        'animationDurationMs': 9999,
        'anchor': 'nope',
        'lineMode': 'nope',
        'translationLayout': 'nope',
        'backgroundMode': 'nope',
        'lineAnimation': 'nope',
        'windowAnimation': 'nope',
        'easing': 'nope',
      });

      expect(settings.offsetX, 4000);
      expect(settings.width, 160);
      expect(settings.height, 400);
      expect(settings.fontSize, 8);
      expect(settings.fontWeight, 900);
      expect(settings.backgroundOpacity, 1);
      expect(settings.edgePadding, 32);
      expect(settings.cornerRadius, 48);
      expect(settings.animationDurationMs, 1000);
      expect(settings.anchor, LyricsTaskbarAnchor.auto);
      expect(settings.lineMode, LyricsLineMode.auto);
      expect(settings.translationLayout, LyricsTranslationLayout.stacked);
      expect(settings.backgroundMode, LyricsBackgroundMode.transparent);
      expect(settings.lineAnimation, LyricsLineTransition.slideLeft);
      expect(settings.windowAnimation, LyricsWindowTransition.fade);
      expect(settings.easing, LyricsEasing.easeOut);
    });

    test('keeps the documented 200 ms default out of the floating presets', () {
      // 200 is not one of the floating preset durations; the taskbar must not
      // snap it away.
      final settings = TaskbarLyricsSettings.fromJson(<String, Object?>{
        'animationDurationMs': 200,
      });
      expect(settings.animationDurationMs, 200);
      expect(FloatingLyricsSettings.clampAnimationDurationMs(200), isNot(200));
    });

    test('JSON round-trips without losing a field', () {
      const original = TaskbarLyricsSettings(
        enabled: true,
        monitorDeviceName: 'DISPLAY2',
        anchor: LyricsTaskbarAnchor.right,
        offsetX: 24,
        width: 720,
        height: 32,
        fontSize: 18,
        fontFamily: 'Microsoft YaHei UI',
        fontWeight: 700,
        textColor: Color(0xFFFFFFFF),
        highlightColor: Color(0xFF00FFAA),
        backgroundMode: LyricsBackgroundMode.solid,
        backgroundColor: Color(0xCC000000),
        backgroundOpacity: 0.6,
        lineMode: LyricsLineMode.currentAndNext,
        translationLayout: LyricsTranslationLayout.inline,
        lineAnimation: LyricsLineTransition.pushLeft,
        animationDurationMs: 180,
        easing: LyricsEasing.easeInOut,
        windowAnimation: LyricsWindowTransition.slideFromRight,
        clickThrough: false,
        followAutoHide: false,
        hideInFullscreen: false,
        marquee: false,
        edgePadding: 12,
        cornerRadius: 14,
        debugGeometry: true,
      );

      final roundTripped = TaskbarLyricsSettings.fromJson(original.toJson());

      expect(roundTripped.toJson(), original.toJson());
    });

    test('toOverlayConfig emits only taskbar style keys', () {
      const settings = TaskbarLyricsSettings(enabled: true, width: 600);

      final config = settings.toOverlayConfig();
      final json = config.toJson();

      expect(config.surface, LyricsSurface.taskbar);
      expect(json['enabled'], isTrue);
      expect(json['width'], 600);
      expect(json['anchor'], 'auto');
      expect(json['translationLayout'], 'stacked');
      expect(json.containsKey('debugGeometry'), isTrue);
      expect(json.containsKey('positionX'), isFalse);
      expect(json.containsKey('wordHighlight'), isFalse);
      expect(json.containsKey('alwaysOnTop'), isFalse);
    });
  });

  group('FloatingLyricsPayload', () {
    test('toJson keeps the frozen Android key set', () {
      const settings = FloatingLyricsSettings(enabled: true);
      const payload = FloatingLyricsPayload(
        text: 'line',
        translation: '译文',
        nextText: 'next',
        lineIndex: 3,
        songTitle: 'title',
        artistName: 'artist',
        coverUrl: 'https://example.test/c.jpg',
      );

      final json = payload.toJson(settings);

      expect(json.keys.toSet(), <String>{
        'enabled',
        'textColor',
        'highlightColor',
        'backgroundColor',
        'fontSize',
        'strokeWidth',
        'shadowOpacity',
        'width',
        'height',
        'isLocked',
        'positionY',
        'text',
        'translation',
        'progress',
        'nextText',
        'highlightProgress',
        'highlightRate',
        'isPlaying',
        'hasSong',
      });
      // Desktop-only fields never reach the Kotlin parser.
      expect(json.containsKey('lineIndex'), isFalse);
      expect(json.containsKey('songTitle'), isFalse);
      expect(json.containsKey('coverUrl'), isFalse);
      expect(json.containsKey('wordSegments'), isFalse);
    });
  });

  group('LyricsOverlayFrame', () {
    test('toJson clamps ranges and normalizes word segments', () {
      const frame = LyricsOverlayFrame(
        text: 'hello',
        progress: 2,
        highlightProgress: -1,
        highlightRate: -4,
        wordSegments: <double>[0.2, 0.1, 1.4, 0.6],
        revision: 9,
        lineIndex: 4,
      );

      final json = frame.toJson();

      expect(json['progress'], 1.0);
      expect(json['highlightProgress'], 0.0);
      expect(json['highlightRate'], 0.0);
      // 0.1 is dropped (not ascending), 1.4 clamps to 1.0.
      expect(json['wordSegments'], <double>[0.2, 1.0]);
      expect(json['revision'], 9);
      expect(json['lineIndex'], 4);
    });

    test('word segments are capped at 32 entries', () {
      final frame = LyricsOverlayFrame(
        text: 'many',
        wordSegments: <double>[for (var i = 0; i < 40; i++) i / 40],
      );

      final segments = frame.toJson()['wordSegments'] as List<double>;

      expect(segments, hasLength(LyricsOverlayFrame.maxWordSegments));
      expect(segments.first, 0);
      expect(segments.last, closeTo(31 / 40, 1e-9));
    });

    test('empty segments become null so the native side sweeps evenly', () {
      const frame = LyricsOverlayFrame(text: 'x', wordSegments: <double>[]);
      expect(frame.toJson()['wordSegments'], isNull);
      expect(LyricsOverlayFrame.empty.toJson()['text'], '');
    });

    test('the taskbar frame drops the next-line translation', () {
      const frame = LyricsOverlayFrame(
        text: 'current',
        translation: '当前',
        nextText: 'next',
        nextTranslation: '下一句',
      );

      expect(frame.toJson()['nextTranslation'], '下一句');
      expect(
        frame.toJsonFor(LyricsSurface.taskbar).containsKey('nextTranslation'),
        isFalse,
      );
    });
  });
}
