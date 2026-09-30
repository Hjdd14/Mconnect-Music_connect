import 'package:flutter/material.dart';

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
  });

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
    };
  }

  factory FloatingLyricsSettings.fromJson(Map<dynamic, dynamic> json) {
    return FloatingLyricsSettings(
      enabled: json['enabled'] as bool? ?? false,
      textColor: Color(
        json['textColor'] as int? ?? const Color(0xFFFFFFFF).toARGB32(),
      ),
      highlightColor: Color(
        json['highlightColor'] as int? ?? const Color(0xFFFFD44A).toARGB32(),
      ),
      backgroundColor: Color(
        json['backgroundColor'] as int? ?? Colors.transparent.toARGB32(),
      ),
      fontSize: (json['fontSize'] as num?)?.toDouble() ?? 23,
      strokeWidth: (json['strokeWidth'] as num?)?.toDouble() ?? 0.7,
      shadowOpacity: (json['shadowOpacity'] as num?)?.toDouble() ?? 0.78,
      width: (json['width'] as num?)?.toDouble() ?? 320,
      height: (json['height'] as num?)?.toDouble() ?? 92,
      isLocked: json['isLocked'] as bool? ?? false,
      positionY: (json['positionY'] as num?)?.toDouble() ?? 160,
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

  const FloatingLyricsPayload({
    required this.text,
    this.translation,
    this.progress = 0,
    this.nextText = '',
    this.highlightProgress = 0,
    this.highlightRate = 0,
    this.isPlaying = false,
    this.hasSong = false,
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
    );
  }

  Map<String, Object?> toJson(FloatingLyricsSettings settings) {
    return {
      ...settings.toJson(),
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
