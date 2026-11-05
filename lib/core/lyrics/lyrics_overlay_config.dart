import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'lyrics_animation_catalog.dart';

/// Background treatment of an overlay surface.
enum LyricsBackgroundMode {
  none('none', '无背景'),
  transparent('transparent', '透明'),
  solid('solid', '纯色'),
  gradient('gradient', '渐变'),
  cover('cover', '封面模糊');

  const LyricsBackgroundMode(this.id, this.label);

  final String id;
  final String label;

  static LyricsBackgroundMode fromId(
    Object? id, {
    LyricsBackgroundMode fallback = LyricsBackgroundMode.none,
  }) {
    if (id is! String) return fallback;
    for (final value in values) {
      if (value.id == id) return value;
    }
    return fallback;
  }
}

/// Horizontal alignment of the lyric text.
enum LyricsTextAlignment {
  left('left', '左对齐', TextAlign.left),
  center('center', '居中', TextAlign.center),
  right('right', '右对齐', TextAlign.right);

  const LyricsTextAlignment(this.id, this.label, this.textAlign);

  final String id;
  final String label;
  final TextAlign textAlign;

  static LyricsTextAlignment fromId(
    Object? id, {
    LyricsTextAlignment fallback = LyricsTextAlignment.center,
  }) {
    if (id is! String) return fallback;
    for (final value in values) {
      if (value.id == id) return value;
    }
    return fallback;
  }
}

/// How many lines a surface shows.
enum LyricsLineMode {
  currentOnly('currentOnly', '仅当前行'),
  currentAndTranslation('currentAndTranslation', '当前行 + 译文'),
  currentAndNext('currentAndNext', '当前行 + 下一行'),
  threeLines('threeLines', '三行'),
  auto('auto', '自动');

  const LyricsLineMode(this.id, this.label);

  final String id;
  final String label;

  static LyricsLineMode fromId(
    Object? id, {
    LyricsLineMode fallback = LyricsLineMode.currentAndTranslation,
  }) {
    if (id is! String) return fallback;
    for (final value in values) {
      if (value.id == id) return value;
    }
    return fallback;
  }

  /// The taskbar strip has its own default (auto), so it validates separately.
  static LyricsLineMode fromTaskbarId(Object? id) {
    return fromId(id, fallback: LyricsLineMode.auto);
  }
}

/// Whether the translation is shown at all.
enum LyricsTranslationVisibility {
  auto('auto', '自动'),
  always('always', '总是'),
  never('never', '从不');

  const LyricsTranslationVisibility(this.id, this.label);

  final String id;
  final String label;

  static LyricsTranslationVisibility fromId(
    Object? id, {
    LyricsTranslationVisibility fallback = LyricsTranslationVisibility.auto,
  }) {
    if (id is! String) return fallback;
    for (final value in values) {
      if (value.id == id) return value;
    }
    return fallback;
  }
}

/// Where the translation sits relative to its own line (taskbar).
enum LyricsTranslationLayout {
  stacked('stacked', '换行'),
  inline('inline', '同一行'),
  hidden('hidden', '隐藏');

  const LyricsTranslationLayout(this.id, this.label);

  final String id;
  final String label;

  static LyricsTranslationLayout fromId(
    Object? id, {
    LyricsTranslationLayout fallback = LyricsTranslationLayout.stacked,
  }) {
    if (id is! String) return fallback;
    for (final value in values) {
      if (value.id == id) return value;
    }
    return fallback;
  }
}

/// Horizontal anchor of the taskbar strip inside the taskbar free area.
enum LyricsTaskbarAnchor {
  auto('auto', '自动'),
  left('left', '靠左'),
  center('center', '居中'),
  right('right', '靠右');

  const LyricsTaskbarAnchor(this.id, this.label);

  final String id;
  final String label;

  static LyricsTaskbarAnchor fromId(
    Object? id, {
    LyricsTaskbarAnchor fallback = LyricsTaskbarAnchor.auto,
  }) {
    if (id is! String) return fallback;
    for (final value in values) {
      if (value.id == id) return value;
    }
    return fallback;
  }
}

/// One surface's complete style, in the shape the native side expects
/// (docs/desktop-lyrics-protocol.md sections 2.2 and 2.3).
///
/// Both surfaces share this class so the controller can hand one style to
/// every sink; [toJson] emits only the keys that belong to [surface], so a
/// floating window never receives taskbar-only fields and vice versa.
@immutable
class LyricsOverlayConfig {
  const LyricsOverlayConfig({
    required this.surface,
    this.enabled = false,
    this.monitorDeviceName = '',
    this.positionX,
    this.positionYRatio,
    this.positionY = 0,
    this.isLocked = false,
    this.lineAnimation = LyricsLineTransition.fade,
    this.animationDurationMs = 220,
    this.easing = LyricsEasing.easeOut,
    this.windowAnimation = LyricsWindowTransition.fade,
    this.backgroundMode = LyricsBackgroundMode.none,
    this.backgroundColor = 0x00000000,
    this.backgroundColor2 = 0x00000000,
    this.backgroundOpacity = 0.55,
    this.cornerRadius = 16,
    this.fontFamily = '',
    this.fontWeight = 600,
    this.textAlign = LyricsTextAlignment.center,
    this.lineMode = LyricsLineMode.currentAndTranslation,
    this.showTranslation = LyricsTranslationVisibility.auto,
    this.letterSpacing = 0,
    this.lineHeight = 1.2,
    this.padding = 12,
    this.showControls = true,
    this.clickThrough = false,
    this.alwaysOnTop = true,
    this.hideInFullscreen = true,
    this.reduceMotion = true,
    this.textColor = 0xFFFFFFFF,
    this.highlightColor = 0xFFFFD44A,
    this.strokeColor = 0xFF000000,
    this.strokeWidth = 0.7,
    this.shadowOpacity = 0.78,
    this.shadowBlur = 8,
    this.fontSize = 23,
    this.width = 320,
    this.height = 92,
    this.wordHighlight = true,
    this.coverImagePath,
    this.anchor = LyricsTaskbarAnchor.auto,
    this.offsetX = 0,
    this.translationLayout = LyricsTranslationLayout.stacked,
    this.marquee = true,
    this.followAutoHide = true,
    this.edgePadding = 8,
    this.debugGeometry = false,
  });

  /// Protocol defaults for the taskbar strip (section 2.3).
  static const LyricsOverlayConfig taskbarDefaults = LyricsOverlayConfig(
    surface: LyricsSurface.taskbar,
    monitorDeviceName: 'primary',
    width: 560,
    height: 0,
    fontSize: 16,
    backgroundMode: LyricsBackgroundMode.transparent,
    backgroundColor: 0xFF000000,
    backgroundOpacity: 0.35,
    lineMode: LyricsLineMode.auto,
    lineAnimation: LyricsLineTransition.slideLeft,
    animationDurationMs: 200,
    clickThrough: true,
    cornerRadius: 8,
    reduceMotion: false,
  );

  final LyricsSurface surface;

  /// Taskbar style carries the enabled flag (section 2.3); the floating style
  /// does too (section 2.2), even though the window is driven by update().
  final bool enabled;

  final String monitorDeviceName;

  /// Normalised horizontal position 0..1; null means centered.
  final double? positionX;

  /// Normalised vertical position 0..1; null means "use [positionY]".
  final double? positionYRatio;

  /// Legacy Android vertical offset in physical pixels.
  final double positionY;

  final bool isLocked;

  final LyricsLineTransition lineAnimation;
  final int animationDurationMs;
  final LyricsEasing easing;
  final LyricsWindowTransition windowAnimation;

  final LyricsBackgroundMode backgroundMode;
  final int backgroundColor;
  final int backgroundColor2;
  final double backgroundOpacity;
  final double cornerRadius;

  final String fontFamily;
  final int fontWeight;
  final LyricsTextAlignment textAlign;
  final LyricsLineMode lineMode;
  final LyricsTranslationVisibility showTranslation;
  final double letterSpacing;
  final double lineHeight;
  final double padding;

  final bool showControls;
  final bool clickThrough;
  final bool alwaysOnTop;
  final bool hideInFullscreen;
  final bool reduceMotion;

  final int textColor;
  final int highlightColor;
  final int strokeColor;
  final double strokeWidth;
  final double shadowOpacity;
  final double shadowBlur;
  final double fontSize;
  final double width;
  final double height;
  final bool wordHighlight;
  final String? coverImagePath;

  final LyricsTaskbarAnchor anchor;
  final double offsetX;
  final LyricsTranslationLayout translationLayout;
  final bool marquee;
  final bool followAutoHide;
  final double edgePadding;
  final bool debugGeometry;

  /// Style JSON for the native side, limited to this surface's protocol keys.
  Map<String, Object?> toJson() {
    if (surface == LyricsSurface.taskbar) {
      return <String, Object?>{
        'enabled': enabled,
        'monitorDeviceName': monitorDeviceName,
        'anchor': anchor.id,
        'offsetX': offsetX,
        'width': width,
        'height': height,
        'fontSize': fontSize,
        'fontFamily': fontFamily,
        'fontWeight': fontWeight,
        'textColor': textColor,
        'highlightColor': highlightColor,
        'backgroundMode': backgroundMode.id,
        'backgroundColor': backgroundColor,
        'backgroundOpacity': backgroundOpacity,
        'lineMode': lineMode.id,
        'translationLayout': translationLayout.id,
        'lineAnimation': lineAnimation.id,
        'animationDurationMs': animationDurationMs,
        'easing': easing.id,
        'windowAnimation': windowAnimation.id,
        'clickThrough': clickThrough,
        'followAutoHide': followAutoHide,
        'hideInFullscreen': hideInFullscreen,
        'marquee': marquee,
        'edgePadding': edgePadding,
        'cornerRadius': cornerRadius,
        'debugGeometry': debugGeometry,
        'reduceMotion': reduceMotion,
      };
    }
    return <String, Object?>{
      'enabled': enabled,
      'monitorDeviceName': monitorDeviceName,
      'positionX': positionX,
      'positionY': positionY,
      'positionYRatio': positionYRatio,
      'isLocked': isLocked,
      'lineAnimation': lineAnimation.id,
      'animationDurationMs': animationDurationMs,
      'easing': easing.id,
      'windowAnimation': windowAnimation.id,
      'backgroundMode': backgroundMode.id,
      'backgroundColor': backgroundColor,
      'backgroundColor2': backgroundColor2,
      'backgroundOpacity': backgroundOpacity,
      'cornerRadius': cornerRadius,
      'fontFamily': fontFamily,
      'fontWeight': fontWeight,
      'textAlign': textAlign.id,
      'lineMode': lineMode.id,
      'showTranslation': showTranslation.id,
      'letterSpacing': letterSpacing,
      'lineHeight': lineHeight,
      'padding': padding,
      'showControls': showControls,
      'clickThrough': clickThrough,
      'alwaysOnTop': alwaysOnTop,
      'hideInFullscreen': hideInFullscreen,
      'reduceMotion': reduceMotion,
      'textColor': textColor,
      'highlightColor': highlightColor,
      'strokeColor': strokeColor,
      'strokeWidth': strokeWidth,
      'shadowOpacity': shadowOpacity,
      'shadowBlur': shadowBlur,
      'fontSize': fontSize,
      'width': width,
      'height': height,
      'wordHighlight': wordHighlight,
      'coverImagePath': coverImagePath,
    };
  }

  /// True when the style asks for no animation at all, on either axis.
  ///
  /// reduceMotion gates every animation the app itself drives; the native side
  /// receives the flag and does the same.
  bool get animationsEnabled =>
      !reduceMotion &&
      animationDurationMs > 0 &&
      (lineAnimation != LyricsLineTransition.none ||
          windowAnimation != LyricsWindowTransition.none);
}
