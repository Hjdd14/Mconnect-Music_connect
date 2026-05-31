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

  const FloatingLyricsSettings({
    this.enabled = false,
    this.textColor = const Color(0xFFFFF4F8),
    this.highlightColor = const Color(0xFFFFD44A),
    this.backgroundColor = Colors.transparent,
    this.fontSize = 23,
    this.strokeWidth = 0.7,
    this.shadowOpacity = 0.78,
    this.width = 320,
    this.height = 92,
    this.isLocked = false,
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
    };
  }

  factory FloatingLyricsSettings.fromJson(Map<dynamic, dynamic> json) {
    return FloatingLyricsSettings(
      enabled: json['enabled'] as bool? ?? false,
      textColor: Color(
        json['textColor'] as int? ?? const Color(0xFFFFF4F8).toARGB32(),
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
    );
  }
}

@immutable
class FloatingLyricsPayload {
  final String text;
  final String? translation;
  final double progress;

  const FloatingLyricsPayload({
    required this.text,
    this.translation,
    this.progress = 0,
  });

  Map<String, Object?> toJson(FloatingLyricsSettings settings) {
    return {
      ...settings.toJson(),
      'text': text,
      'translation': translation,
      'progress': progress.clamp(0, 1),
    };
  }
}
