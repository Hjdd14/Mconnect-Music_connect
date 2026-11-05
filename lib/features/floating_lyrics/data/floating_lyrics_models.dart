import 'package:flutter/material.dart';

import '../../../core/lyrics/lyrics_animation_catalog.dart';
import '../../../core/lyrics/lyrics_overlay_config.dart';

/// Persisted style of the (Android + Windows) floating lyrics window.
///
/// The first eleven fields are the pre-desktop protocol and keep their exact
/// JSON keys; everything after [positionY] was added for the desktop rewrite
/// and is optional on read (docs/desktop-lyrics-protocol.md, section 2.2).
@immutable
class FloatingLyricsSettings {
  final bool enabled;
  final Color textColor;
  final Color highlightColor;
  final Color backgroundColor;
  final double fontSize;
  final double strokeWidth;
  final double shadowOpacity;
  final double width;
  final double height;
  final bool isLocked;

  /// Vertical overlay offset in physical pixels. The Android overlay owns the
  /// live value while it is on screen and only seeds it when the window is
  /// created, so this never fights an in-progress drag.
  final double positionY;

  /// Normalised horizontal position 0..1; null keeps the window centered.
  final double? positionX;

  /// Normalised vertical position 0..1 for the desktop window; null falls back
  /// to the legacy pixel [positionY].
  final double? positionYRatio;

  final String monitorDeviceName;

  final LyricsLineTransition lineAnimation;
  final int animationDurationMs;
  final LyricsEasing easing;
  final LyricsWindowTransition windowAnimation;
  final LyricsBackgroundMode backgroundMode;
  final Color backgroundColor2;
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
  final Color strokeColor;
  final double shadowBlur;
  final bool wordHighlight;
  final String? coverImagePath;

  const FloatingLyricsSettings({
    this.enabled = false,
    this.textColor = const Color(0xFFFFFFFF),
    this.highlightColor = const Color(0xFFFFD44A),
    this.backgroundColor = Colors.transparent,
    this.fontSize = 23,
    this.strokeWidth = 0.7,
    this.shadowOpacity = 0.78,
    this.width = 320,
    this.height = 92,
    this.isLocked = false,
    this.positionY = 160,
    this.positionX,
    this.positionYRatio,
    this.monitorDeviceName = '',
    this.lineAnimation = LyricsLineTransition.fade,
    this.animationDurationMs = 220,
    this.easing = LyricsEasing.easeOut,
    this.windowAnimation = LyricsWindowTransition.fade,
    this.backgroundMode = LyricsBackgroundMode.none,
    this.backgroundColor2 = const Color(0x00000000),
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
    // The native side reads this as "hard cut": defaulting it to true (as the
    // first desktop build did) made every animation picked in the studio look
    // like it did nothing.
    this.reduceMotion = false,
    this.strokeColor = const Color(0xFF000000),
    this.shadowBlur = 8,
    this.wordHighlight = true,
    this.coverImagePath,
  });

  // Every range below is shared by the setter and fromJson, so a Hive record
  // written by an older build (or by hand) can never bypass the UI limits.

  static double clampFontSize(double value) => value.clamp(14, 48).toDouble();

  static double clampStrokeWidth(double value) => value.clamp(0, 2).toDouble();

  static double clampShadowOpacity(double value) =>
      value.clamp(0, 1).toDouble();

  static double clampWidth(double value) => value.clamp(180, 720).toDouble();

  static double clampHeight(double value) => value.clamp(56, 220).toDouble();

  static double clampPositionY(double value) => value < 0 ? 0 : value;

  static double? clampPositionX(Object? value) => _readRatio(value);

  static double? clampPositionYRatio(Object? value) => _readRatio(value);

  static int clampAnimationDurationMs(int value) =>
      LyricsAnimationCatalog.snapDurationMs(value);

  static double clampBackgroundOpacity(double value) =>
      value.clamp(0, 1).toDouble();

  static double clampCornerRadius(double value) =>
      value.clamp(0, 48).toDouble();

  static int clampFontWeight(int value) => value.clamp(100, 900);

  static double clampLetterSpacing(double value) =>
      value.clamp(-4, 16).toDouble();

  static double clampLineHeight(double value) => value.clamp(0.8, 3).toDouble();

  static double clampPadding(double value) => value.clamp(0, 64).toDouble();

  static double clampShadowBlur(double value) => value.clamp(0, 32).toDouble();

  FloatingLyricsSettings copyWith({
    bool? enabled,
    Color? textColor,
    Color? highlightColor,
    Color? backgroundColor,
    double? fontSize,
    double? strokeWidth,
    double? shadowOpacity,
    double? width,
    double? height,
    bool? isLocked,
    double? positionY,
    double? positionX,
    bool clearPositionX = false,
    double? positionYRatio,
    bool clearPositionYRatio = false,
    String? monitorDeviceName,
    LyricsLineTransition? lineAnimation,
    int? animationDurationMs,
    LyricsEasing? easing,
    LyricsWindowTransition? windowAnimation,
    LyricsBackgroundMode? backgroundMode,
    Color? backgroundColor2,
    double? backgroundOpacity,
    double? cornerRadius,
    String? fontFamily,
    int? fontWeight,
    LyricsTextAlignment? textAlign,
    LyricsLineMode? lineMode,
    LyricsTranslationVisibility? showTranslation,
    double? letterSpacing,
    double? lineHeight,
    double? padding,
    bool? showControls,
    bool? clickThrough,
    bool? alwaysOnTop,
    bool? hideInFullscreen,
    bool? reduceMotion,
    Color? strokeColor,
    double? shadowBlur,
    bool? wordHighlight,
    String? coverImagePath,
  }) {
    return FloatingLyricsSettings(
      enabled: enabled ?? this.enabled,
      textColor: textColor ?? this.textColor,
      highlightColor: highlightColor ?? this.highlightColor,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      fontSize: fontSize ?? this.fontSize,
      strokeWidth: strokeWidth ?? this.strokeWidth,
      shadowOpacity: shadowOpacity ?? this.shadowOpacity,
      width: width ?? this.width,
      height: height ?? this.height,
      isLocked: isLocked ?? this.isLocked,
      positionY: positionY ?? this.positionY,
      positionX: clearPositionX ? null : (positionX ?? this.positionX),
      positionYRatio: clearPositionYRatio
          ? null
          : (positionYRatio ?? this.positionYRatio),
      monitorDeviceName: monitorDeviceName ?? this.monitorDeviceName,
      lineAnimation: lineAnimation ?? this.lineAnimation,
      animationDurationMs: animationDurationMs ?? this.animationDurationMs,
      easing: easing ?? this.easing,
      windowAnimation: windowAnimation ?? this.windowAnimation,
      backgroundMode: backgroundMode ?? this.backgroundMode,
      backgroundColor2: backgroundColor2 ?? this.backgroundColor2,
      backgroundOpacity: backgroundOpacity ?? this.backgroundOpacity,
      cornerRadius: cornerRadius ?? this.cornerRadius,
      fontFamily: fontFamily ?? this.fontFamily,
      fontWeight: fontWeight ?? this.fontWeight,
      textAlign: textAlign ?? this.textAlign,
      lineMode: lineMode ?? this.lineMode,
      showTranslation: showTranslation ?? this.showTranslation,
      letterSpacing: letterSpacing ?? this.letterSpacing,
      lineHeight: lineHeight ?? this.lineHeight,
      padding: padding ?? this.padding,
      showControls: showControls ?? this.showControls,
      clickThrough: clickThrough ?? this.clickThrough,
      alwaysOnTop: alwaysOnTop ?? this.alwaysOnTop,
      hideInFullscreen: hideInFullscreen ?? this.hideInFullscreen,
      reduceMotion: reduceMotion ?? this.reduceMotion,
      strokeColor: strokeColor ?? this.strokeColor,
      shadowBlur: shadowBlur ?? this.shadowBlur,
      wordHighlight: wordHighlight ?? this.wordHighlight,
      coverImagePath: coverImagePath ?? this.coverImagePath,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'enabled': enabled,
      'textColor': textColor.toARGB32(),
      'highlightColor': highlightColor.toARGB32(),
      'backgroundColor': backgroundColor.toARGB32(),
      'fontSize': fontSize,
      'strokeWidth': strokeWidth,
      'shadowOpacity': shadowOpacity,
      'width': width,
      'height': height,
      'isLocked': isLocked,
      'positionY': positionY,
      'positionX': positionX,
      'positionYRatio': positionYRatio,
      'monitorDeviceName': monitorDeviceName,
      'lineAnimation': lineAnimation.id,
      'animationDurationMs': animationDurationMs,
      'easing': easing.id,
      'windowAnimation': windowAnimation.id,
      'backgroundMode': backgroundMode.id,
      'backgroundColor2': backgroundColor2.toARGB32(),
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
      'strokeColor': strokeColor.toARGB32(),
      'shadowBlur': shadowBlur,
      'wordHighlight': wordHighlight,
      'coverImagePath': coverImagePath,
    };
  }

  factory FloatingLyricsSettings.fromJson(Map<dynamic, dynamic> json) {
    return FloatingLyricsSettings(
      enabled: json['enabled'] as bool? ?? false,
      textColor: Color(
        (json['textColor'] as num?)?.toInt() ??
            const Color(0xFFFFFFFF).toARGB32(),
      ),
      highlightColor: Color(
        (json['highlightColor'] as num?)?.toInt() ??
            const Color(0xFFFFD44A).toARGB32(),
      ),
      backgroundColor: Color(
        (json['backgroundColor'] as num?)?.toInt() ??
            Colors.transparent.toARGB32(),
      ),
      fontSize: clampFontSize((json['fontSize'] as num?)?.toDouble() ?? 23),
      strokeWidth: clampStrokeWidth(
        (json['strokeWidth'] as num?)?.toDouble() ?? 0.7,
      ),
      shadowOpacity: clampShadowOpacity(
        (json['shadowOpacity'] as num?)?.toDouble() ?? 0.78,
      ),
      width: clampWidth((json['width'] as num?)?.toDouble() ?? 320),
      height: clampHeight((json['height'] as num?)?.toDouble() ?? 92),
      isLocked: json['isLocked'] as bool? ?? false,
      positionY: clampPositionY((json['positionY'] as num?)?.toDouble() ?? 160),
      positionX: clampPositionX(json['positionX']),
      positionYRatio: clampPositionYRatio(json['positionYRatio']),
      monitorDeviceName: json['monitorDeviceName'] as String? ?? '',
      lineAnimation: LyricsLineTransition.fromId(json['lineAnimation']),
      animationDurationMs: clampAnimationDurationMs(
        (json['animationDurationMs'] as num?)?.toInt() ?? 220,
      ),
      easing: LyricsEasing.fromId(json['easing']),
      windowAnimation: LyricsWindowTransition.fromId(json['windowAnimation']),
      backgroundMode: LyricsBackgroundMode.fromId(json['backgroundMode']),
      backgroundColor2: Color(
        (json['backgroundColor2'] as num?)?.toInt() ?? 0x00000000,
      ),
      backgroundOpacity: clampBackgroundOpacity(
        (json['backgroundOpacity'] as num?)?.toDouble() ?? 0.55,
      ),
      cornerRadius: clampCornerRadius(
        (json['cornerRadius'] as num?)?.toDouble() ?? 16,
      ),
      fontFamily: json['fontFamily'] as String? ?? '',
      fontWeight: clampFontWeight((json['fontWeight'] as num?)?.toInt() ?? 600),
      textAlign: LyricsTextAlignment.fromId(json['textAlign']),
      lineMode: LyricsLineMode.fromId(json['lineMode']),
      showTranslation: LyricsTranslationVisibility.fromId(
        json['showTranslation'],
      ),
      letterSpacing: clampLetterSpacing(
        (json['letterSpacing'] as num?)?.toDouble() ?? 0,
      ),
      lineHeight: clampLineHeight(
        (json['lineHeight'] as num?)?.toDouble() ?? 1.2,
      ),
      padding: clampPadding((json['padding'] as num?)?.toDouble() ?? 12),
      showControls: json['showControls'] as bool? ?? true,
      clickThrough: json['clickThrough'] as bool? ?? false,
      alwaysOnTop: json['alwaysOnTop'] as bool? ?? true,
      hideInFullscreen: json['hideInFullscreen'] as bool? ?? true,
      reduceMotion: json['reduceMotion'] as bool? ?? false,
      strokeColor: Color((json['strokeColor'] as num?)?.toInt() ?? 0xFF000000),
      shadowBlur: clampShadowBlur(
        (json['shadowBlur'] as num?)?.toDouble() ?? 8,
      ),
      wordHighlight: json['wordHighlight'] as bool? ?? true,
      coverImagePath: json['coverImagePath'] as String?,
    );
  }

  /// The same style in the surface-neutral shape the sinks serialize.
  LyricsOverlayConfig toOverlayConfig() {
    return LyricsOverlayConfig(
      surface: LyricsSurface.floating,
      enabled: enabled,
      monitorDeviceName: monitorDeviceName,
      positionX: positionX,
      positionYRatio: positionYRatio,
      positionY: positionY,
      isLocked: isLocked,
      lineAnimation: lineAnimation,
      animationDurationMs: animationDurationMs,
      easing: easing,
      windowAnimation: windowAnimation,
      backgroundMode: backgroundMode,
      backgroundColor: backgroundColor.toARGB32(),
      backgroundColor2: backgroundColor2.toARGB32(),
      backgroundOpacity: backgroundOpacity,
      cornerRadius: cornerRadius,
      fontFamily: fontFamily,
      fontWeight: fontWeight,
      textAlign: textAlign,
      lineMode: lineMode,
      showTranslation: showTranslation,
      letterSpacing: letterSpacing,
      lineHeight: lineHeight,
      padding: padding,
      showControls: showControls,
      clickThrough: clickThrough,
      alwaysOnTop: alwaysOnTop,
      hideInFullscreen: hideInFullscreen,
      reduceMotion: reduceMotion,
      textColor: textColor.toARGB32(),
      highlightColor: highlightColor.toARGB32(),
      strokeColor: strokeColor.toARGB32(),
      strokeWidth: strokeWidth,
      shadowOpacity: shadowOpacity,
      shadowBlur: shadowBlur,
      fontSize: fontSize,
      width: width,
      height: height,
      wordHighlight: wordHighlight,
      coverImagePath: coverImagePath,
    );
  }
}

/// Persisted style of the Windows taskbar lyrics strip
/// (docs/desktop-lyrics-protocol.md, section 2.3).
@immutable
class TaskbarLyricsSettings {
  final bool enabled;
  final String monitorDeviceName;
  final LyricsTaskbarAnchor anchor;
  final double offsetX;
  final double width;

  /// Strip height; 0 lets the native side use the taskbar thickness.
  final double height;
  final double fontSize;
  final String fontFamily;
  final int fontWeight;
  final Color textColor;
  final Color highlightColor;
  final LyricsBackgroundMode backgroundMode;
  final Color backgroundColor;
  final double backgroundOpacity;
  final LyricsLineMode lineMode;
  final LyricsTranslationLayout translationLayout;
  final LyricsLineTransition lineAnimation;
  final int animationDurationMs;
  final LyricsEasing easing;
  final LyricsWindowTransition windowAnimation;
  final bool clickThrough;
  final bool followAutoHide;
  final bool hideInFullscreen;
  final bool marquee;
  final double edgePadding;
  final double cornerRadius;
  final bool debugGeometry;

  /// Hard-cuts every line/window animation on the strip. Shared with the
  /// floating window (see [FloatingLyricsSettings.reduceMotion]). Defaults to
  /// false: an animation the user picked must actually play.
  final bool reduceMotion;

  const TaskbarLyricsSettings({
    this.enabled = false,
    this.monitorDeviceName = 'primary',
    this.anchor = LyricsTaskbarAnchor.auto,
    this.offsetX = 0,
    this.width = 560,
    this.height = 0,
    this.fontSize = 16,
    this.fontFamily = '',
    this.fontWeight = 600,
    this.textColor = const Color(0xFFFFFFFF),
    this.highlightColor = const Color(0xFFFFD44A),
    this.backgroundMode = LyricsBackgroundMode.transparent,
    this.backgroundColor = const Color(0xFF000000),
    this.backgroundOpacity = 0.35,
    this.lineMode = LyricsLineMode.auto,
    this.translationLayout = LyricsTranslationLayout.stacked,
    this.lineAnimation = LyricsLineTransition.slideLeft,
    this.animationDurationMs = 200,
    this.easing = LyricsEasing.easeOut,
    this.windowAnimation = LyricsWindowTransition.fade,
    this.clickThrough = true,
    this.followAutoHide = true,
    this.hideInFullscreen = true,
    this.marquee = true,
    this.edgePadding = 8,
    this.cornerRadius = 8,
    this.debugGeometry = false,
    this.reduceMotion = false,
  });

  static double clampOffsetX(double value) =>
      value.clamp(-4000, 4000).toDouble();

  static double clampWidth(double value) => value.clamp(160, 3000).toDouble();

  static double clampHeight(double value) => value.clamp(0, 400).toDouble();

  static double clampFontSize(double value) => value.clamp(8, 48).toDouble();

  static int clampFontWeight(int value) => value.clamp(100, 900);

  static double clampBackgroundOpacity(double value) => value.clamp(0, 1);

  static double clampEdgePadding(double value) => value.clamp(0, 32).toDouble();

  static double clampCornerRadius(double value) =>
      value.clamp(0, 48).toDouble();

  /// Unlike the floating window the taskbar keeps any duration in this range:
  /// the protocol documents 200 ms as its default, which is not one of the
  /// floating presets.
  static int clampAnimationDurationMs(int value) => value.clamp(0, 1000);

  TaskbarLyricsSettings copyWith({
    bool? enabled,
    String? monitorDeviceName,
    LyricsTaskbarAnchor? anchor,
    double? offsetX,
    double? width,
    double? height,
    double? fontSize,
    String? fontFamily,
    int? fontWeight,
    Color? textColor,
    Color? highlightColor,
    LyricsBackgroundMode? backgroundMode,
    Color? backgroundColor,
    double? backgroundOpacity,
    LyricsLineMode? lineMode,
    LyricsTranslationLayout? translationLayout,
    LyricsLineTransition? lineAnimation,
    int? animationDurationMs,
    LyricsEasing? easing,
    LyricsWindowTransition? windowAnimation,
    bool? clickThrough,
    bool? followAutoHide,
    bool? hideInFullscreen,
    bool? marquee,
    double? edgePadding,
    double? cornerRadius,
    bool? debugGeometry,
    bool? reduceMotion,
  }) {
    return TaskbarLyricsSettings(
      enabled: enabled ?? this.enabled,
      monitorDeviceName: monitorDeviceName ?? this.monitorDeviceName,
      anchor: anchor ?? this.anchor,
      offsetX: offsetX ?? this.offsetX,
      width: width ?? this.width,
      height: height ?? this.height,
      fontSize: fontSize ?? this.fontSize,
      fontFamily: fontFamily ?? this.fontFamily,
      fontWeight: fontWeight ?? this.fontWeight,
      textColor: textColor ?? this.textColor,
      highlightColor: highlightColor ?? this.highlightColor,
      backgroundMode: backgroundMode ?? this.backgroundMode,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      backgroundOpacity: backgroundOpacity ?? this.backgroundOpacity,
      lineMode: lineMode ?? this.lineMode,
      translationLayout: translationLayout ?? this.translationLayout,
      lineAnimation: lineAnimation ?? this.lineAnimation,
      animationDurationMs: animationDurationMs ?? this.animationDurationMs,
      easing: easing ?? this.easing,
      windowAnimation: windowAnimation ?? this.windowAnimation,
      clickThrough: clickThrough ?? this.clickThrough,
      followAutoHide: followAutoHide ?? this.followAutoHide,
      hideInFullscreen: hideInFullscreen ?? this.hideInFullscreen,
      marquee: marquee ?? this.marquee,
      edgePadding: edgePadding ?? this.edgePadding,
      cornerRadius: cornerRadius ?? this.cornerRadius,
      debugGeometry: debugGeometry ?? this.debugGeometry,
      reduceMotion: reduceMotion ?? this.reduceMotion,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'enabled': enabled,
      'monitorDeviceName': monitorDeviceName,
      'anchor': anchor.id,
      'offsetX': offsetX,
      'width': width,
      'height': height,
      'fontSize': fontSize,
      'fontFamily': fontFamily,
      'fontWeight': fontWeight,
      'textColor': textColor.toARGB32(),
      'highlightColor': highlightColor.toARGB32(),
      'backgroundMode': backgroundMode.id,
      'backgroundColor': backgroundColor.toARGB32(),
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

  factory TaskbarLyricsSettings.fromJson(Map<dynamic, dynamic> json) {
    return TaskbarLyricsSettings(
      enabled: json['enabled'] as bool? ?? false,
      monitorDeviceName: json['monitorDeviceName'] as String? ?? 'primary',
      anchor: LyricsTaskbarAnchor.fromId(json['anchor']),
      offsetX: clampOffsetX((json['offsetX'] as num?)?.toDouble() ?? 0),
      width: clampWidth((json['width'] as num?)?.toDouble() ?? 560),
      height: clampHeight((json['height'] as num?)?.toDouble() ?? 0),
      fontSize: clampFontSize((json['fontSize'] as num?)?.toDouble() ?? 16),
      fontFamily: json['fontFamily'] as String? ?? '',
      fontWeight: clampFontWeight((json['fontWeight'] as num?)?.toInt() ?? 600),
      textColor: Color(
        (json['textColor'] as num?)?.toInt() ??
            const Color(0xFFFFFFFF).toARGB32(),
      ),
      highlightColor: Color(
        (json['highlightColor'] as num?)?.toInt() ??
            const Color(0xFFFFD44A).toARGB32(),
      ),
      backgroundMode: LyricsBackgroundMode.fromId(
        json['backgroundMode'],
        fallback: LyricsBackgroundMode.transparent,
      ),
      backgroundColor: Color(
        (json['backgroundColor'] as num?)?.toInt() ?? 0xFF000000,
      ),
      backgroundOpacity: clampBackgroundOpacity(
        (json['backgroundOpacity'] as num?)?.toDouble() ?? 0.35,
      ),
      lineMode: LyricsLineMode.fromTaskbarId(json['lineMode']),
      translationLayout: LyricsTranslationLayout.fromId(
        json['translationLayout'],
      ),
      lineAnimation: LyricsLineTransition.fromId(
        json['lineAnimation'],
        fallback: LyricsLineTransition.slideLeft,
      ),
      animationDurationMs: clampAnimationDurationMs(
        (json['animationDurationMs'] as num?)?.toInt() ?? 200,
      ),
      easing: LyricsEasing.fromId(json['easing']),
      windowAnimation: LyricsWindowTransition.fromId(json['windowAnimation']),
      clickThrough: json['clickThrough'] as bool? ?? true,
      followAutoHide: json['followAutoHide'] as bool? ?? true,
      hideInFullscreen: json['hideInFullscreen'] as bool? ?? true,
      marquee: json['marquee'] as bool? ?? true,
      edgePadding: clampEdgePadding(
        (json['edgePadding'] as num?)?.toDouble() ?? 8,
      ),
      cornerRadius: clampCornerRadius(
        (json['cornerRadius'] as num?)?.toDouble() ?? 8,
      ),
      debugGeometry: json['debugGeometry'] as bool? ?? false,
      reduceMotion: json['reduceMotion'] as bool? ?? false,
    );
  }

  LyricsOverlayConfig toOverlayConfig() {
    return LyricsOverlayConfig(
      surface: LyricsSurface.taskbar,
      enabled: enabled,
      monitorDeviceName: monitorDeviceName,
      anchor: anchor,
      offsetX: offsetX,
      width: width,
      height: height,
      fontSize: fontSize,
      fontFamily: fontFamily,
      fontWeight: fontWeight,
      textColor: textColor.toARGB32(),
      highlightColor: highlightColor.toARGB32(),
      backgroundMode: backgroundMode,
      backgroundColor: backgroundColor.toARGB32(),
      backgroundOpacity: backgroundOpacity,
      lineMode: lineMode,
      translationLayout: translationLayout,
      lineAnimation: lineAnimation,
      animationDurationMs: animationDurationMs,
      easing: easing,
      windowAnimation: windowAnimation,
      clickThrough: clickThrough,
      followAutoHide: followAutoHide,
      hideInFullscreen: hideInFullscreen,
      marquee: marquee,
      edgePadding: edgePadding,
      cornerRadius: cornerRadius,
      debugGeometry: debugGeometry,
      reduceMotion: reduceMotion,
    );
  }
}

@immutable
class FloatingLyricsPayload {
  final String text;
  final String? translation;
  final double progress;

  /// The upcoming lyric line, drawn under [text] so the overlay shows two
  /// lines at once. Empty when [text] is the last visible line.
  final String nextText;

  /// Continuous progress (0..1) of the already-sung part of [text]. The native
  /// overlay paints a left-to-right gradient at this position, so the sweep is
  /// smooth instead of jumping one character at a time.
  final double highlightProgress;

  /// Smoothed progress-per-millisecond, used by the native overlay to keep
  /// sweeping between two anchors. Zero while paused or during a vocal gap.
  final double highlightRate;

  /// Whether the player is currently playing, used by the overlay's
  /// play/pause button glyph.
  final bool isPlaying;

  /// Whether a song is loaded, used to hide the transport buttons when the
  /// overlay has nothing to control.
  final bool hasSong;

  /// Index of [text] in the lyrics document; carried so the desktop windows can
  /// tell a line change from a seek jump. Not sent on the Android channel.
  final int lineIndex;

  final String? nextTranslation;

  /// Cumulative word-timing boundaries 0..1 (desktop only).
  final List<double>? wordSegments;

  final String? songTitle;
  final String? artistName;
  final String? albumName;
  final String? coverUrl;

  const FloatingLyricsPayload({
    required this.text,
    this.translation,
    this.progress = 0,
    this.nextText = '',
    this.highlightProgress = 0,
    this.highlightRate = 0,
    this.isPlaying = false,
    this.hasSong = false,
    this.lineIndex = -1,
    this.nextTranslation,
    this.wordSegments,
    this.songTitle,
    this.artistName,
    this.albumName,
    this.coverUrl,
  });

  FloatingLyricsPayload copyWith({
    String? text,
    String? translation,
    double? progress,
    String? nextText,
    double? highlightProgress,
    double? highlightRate,
    bool? isPlaying,
    bool? hasSong,
    int? lineIndex,
    String? nextTranslation,
    List<double>? wordSegments,
    String? songTitle,
    String? artistName,
    String? albumName,
    String? coverUrl,
  }) {
    return FloatingLyricsPayload(
      text: text ?? this.text,
      translation: translation ?? this.translation,
      progress: progress ?? this.progress,
      nextText: nextText ?? this.nextText,
      highlightProgress: highlightProgress ?? this.highlightProgress,
      highlightRate: highlightRate ?? this.highlightRate,
      isPlaying: isPlaying ?? this.isPlaying,
      hasSong: hasSong ?? this.hasSong,
      lineIndex: lineIndex ?? this.lineIndex,
      nextTranslation: nextTranslation ?? this.nextTranslation,
      wordSegments: wordSegments ?? this.wordSegments,
      songTitle: songTitle ?? this.songTitle,
      artistName: artistName ?? this.artistName,
      albumName: albumName ?? this.albumName,
      coverUrl: coverUrl ?? this.coverUrl,
    );
  }

  /// The Android overlay's map. Deliberately limited to the pre-desktop keys:
  /// the Kotlin side is frozen, and extra keys would only widen the surface it
  /// has to tolerate (docs/desktop-lyrics-protocol.md, section 5).
  ///
  /// The desktop style travels through [LyricsOverlayConfig] instead, so this
  /// map stays byte-compatible with the payload the Android build has always
  /// parsed.
  Map<String, Object?> toJson(FloatingLyricsSettings settings) {
    return {
      'enabled': settings.enabled,
      'textColor': settings.textColor.toARGB32(),
      'highlightColor': settings.highlightColor.toARGB32(),
      'backgroundColor': settings.backgroundColor.toARGB32(),
      'fontSize': settings.fontSize,
      'strokeWidth': settings.strokeWidth,
      'shadowOpacity': settings.shadowOpacity,
      'width': settings.width,
      'height': settings.height,
      'isLocked': settings.isLocked,
      'positionY': settings.positionY,
      'text': text,
      'translation': translation,
      'progress': progress.clamp(0, 1),
      'nextText': nextText,
      'highlightProgress': highlightProgress.clamp(0.0, 1.0),
      'highlightRate': highlightRate < 0 ? 0.0 : highlightRate,
      'isPlaying': isPlaying,
      'hasSong': hasSong,
    };
  }
}

double? _readRatio(Object? value) {
  if (value is! num) return null;
  final ratio = value.toDouble();
  if (ratio.isNaN) return null;
  return ratio.clamp(0.0, 1.0).toDouble();
}
