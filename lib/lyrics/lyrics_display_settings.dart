import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'models/lyrics_line.dart';

/// W2-A 批次 3：播放页歌词的显示偏好（三态 + 字号 + 行距）。
///
/// 全局偏好（不是按歌的），落 Hive 的 `settings` 盒；盒子打不开时静默退回默认值，
/// 绝不因为读设置失败把播放页弄崩。

const _settingsBoxName = 'settings';
const _modeKey = 'lyrics_display_mode';
const _fontSizeKey = 'lyrics_font_size';
const _lineHeightKey = 'lyrics_line_height';

/// 三态：原文 / 双语 / 仅译文。
enum LyricsDisplayMode {
  /// 只显示原文，译文整行不出现。
  original,

  /// 原文 + 紧跟其下的译文（默认，也是改动前的行为）。
  bilingual,

  /// 只显示译文；没有译文的行退回原文，绝不显示空行。
  translationOnly;

  /// 控件上的标签。硬编码中文与播放页其它控件一致；l10n（W3-D）拥有 `lib/l10n/**`。
  String get displayName => switch (this) {
    LyricsDisplayMode.original => '原文',
    LyricsDisplayMode.bilingual => '双语',
    LyricsDisplayMode.translationOnly => '仅译文',
  };
}

/// 播放页歌词的字号与行距。
///
/// 默认值刻意等于改动前的硬编码（16 / 1.5），所以不动设置时像素不变：
/// 当前行 = 字号 + 4，译文行 = 字号 − 4（当前行 − 2），译文行距 = 行距 − 0.1。
@immutable
class LyricsTypography {
  final double fontSize;
  final double lineHeight;

  const LyricsTypography({this.fontSize = 16, this.lineHeight = 1.5});

  static const double minFontSize = 12;
  static const double maxFontSize = 28;
  static const double minLineHeight = 1.1;
  static const double maxLineHeight = 2.2;
  static const double fontStep = 2;
  static const double lineHeightStep = 0.1;

  double mainSize({required bool current}) => fontSize + (current ? 4 : 0);

  double translationSize({required bool current}) =>
      fontSize - 4 + (current ? 2 : 0);

  double get translationLineHeight => lineHeight - 0.1;

  LyricsTypography copyWith({double? fontSize, double? lineHeight}) {
    return LyricsTypography(
      fontSize: fontSize ?? this.fontSize,
      lineHeight: lineHeight ?? this.lineHeight,
    );
  }

  LyricsTypography clamped() => LyricsTypography(
    fontSize: fontSize.clamp(minFontSize, maxFontSize),
    lineHeight: lineHeight.clamp(minLineHeight, maxLineHeight),
  );

  @override
  bool operator ==(Object other) =>
      other is LyricsTypography &&
      other.fontSize == fontSize &&
      other.lineHeight == lineHeight;

  @override
  int get hashCode => Object.hash(fontSize, lineHeight);
}

/// The line a widget should render in [mode].
///
/// One definition instead of a branch at every render site: `original` clears the
/// translation (keeping the word timing), and `translationOnly` promotes the
/// translation to the main text — dropping the word timing, which belongs to the
/// original text and would be misaligned on the translation. A line with no
/// translation always stays as it is.
LyricsLine displayLineFor(LyricsLine line, LyricsDisplayMode mode) {
  switch (mode) {
    case LyricsDisplayMode.bilingual:
      return line;
    case LyricsDisplayMode.original:
      if (!line.hasTranslation) return line;
      return LyricsLine(
        timestamp: line.timestamp,
        text: line.text,
        words: line.words,
      );
    case LyricsDisplayMode.translationOnly:
      if (!line.hasTranslation) return line;
      return LyricsLine(
        timestamp: line.timestamp,
        text: line.translation!.trim(),
      );
  }
}

class LyricsDisplayModeNotifier extends StateNotifier<LyricsDisplayMode> {
  final Future<void> Function(String value)? _persist;

  LyricsDisplayModeNotifier({
    LyricsDisplayMode initial = LyricsDisplayMode.bilingual,
    this._persist,
  }) : super(initial);

  Future<void> setMode(LyricsDisplayMode mode) async {
    state = mode;
    final persist = _persist;
    if (persist == null) return;
    try {
      await persist(mode.name);
    } catch (e, s) {
      debugPrint('LyricsDisplayModeNotifier persist failed: $e');
      debugPrint('$s');
    }
  }
}

class LyricsTypographyNotifier extends StateNotifier<LyricsTypography> {
  final Future<void> Function(LyricsTypography typography)? _persist;

  LyricsTypographyNotifier({
    LyricsTypography initial = const LyricsTypography(),
    this._persist,
  }) : super(initial.clamped());

  Future<void> setFontSize(double fontSize) =>
      _apply(state.copyWith(fontSize: fontSize));

  Future<void> setLineHeight(double lineHeight) =>
      _apply(state.copyWith(lineHeight: lineHeight));

  Future<void> adjustFontSize(double delta) =>
      setFontSize(state.fontSize + delta);

  Future<void> adjustLineHeight(double delta) =>
      setLineHeight(state.lineHeight + delta);

  Future<void> reset() => _apply(const LyricsTypography());

  Future<void> _apply(LyricsTypography next) async {
    state = next.clamped();
    final persist = _persist;
    if (persist == null) return;
    try {
      await persist(state);
    } catch (e, s) {
      debugPrint('LyricsTypographyNotifier persist failed: $e');
      debugPrint('$s');
    }
  }
}

final lyricsDisplayModeProvider =
    StateNotifierProvider<LyricsDisplayModeNotifier, LyricsDisplayMode>((ref) {
      return LyricsDisplayModeNotifier(
        initial: _readPersistedMode(),
        persist: (value) async {
          final box = await Hive.openBox(_settingsBoxName);
          await box.put(_modeKey, value);
        },
      );
    });

final lyricsTypographyProvider =
    StateNotifierProvider<LyricsTypographyNotifier, LyricsTypography>((ref) {
      return LyricsTypographyNotifier(
        initial: _readPersistedTypography(),
        persist: (typography) async {
          final box = await Hive.openBox(_settingsBoxName);
          await box.put(_fontSizeKey, typography.fontSize);
          await box.put(_lineHeightKey, typography.lineHeight);
        },
      );
    });

LyricsDisplayMode _readPersistedMode() {
  final raw = _readSetting(_modeKey);
  if (raw is String) {
    for (final mode in LyricsDisplayMode.values) {
      if (mode.name == raw) return mode;
    }
  }
  return LyricsDisplayMode.bilingual;
}

LyricsTypography _readPersistedTypography() {
  final fontSize = _readSetting(_fontSizeKey);
  final lineHeight = _readSetting(_lineHeightKey);
  return LyricsTypography(
    fontSize: fontSize is num ? fontSize.toDouble() : 16,
    lineHeight: lineHeight is num ? lineHeight.toDouble() : 1.5,
  ).clamped();
}

Object? _readSetting(String key) {
  try {
    // `Hive.box` throws when the box was never opened — e.g. in widget tests.
    if (!Hive.isBoxOpen(_settingsBoxName)) return null;
    return Hive.box(_settingsBoxName).get(key);
  } catch (e) {
    debugPrint('LyricsDisplaySettings read failed: $e');
    return null;
  }
}
