import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Visual language used by the app chrome.
///
/// [UiStyle.material] is the default and must stay behaviourally identical to
/// the pre-existing Material look (see docs/mconnect-improvement-plan.md, I-8).
/// [UiStyle.miuix] opts into the Miuix-flavoured chrome.
enum UiStyle { material, miuix }

const _uiStyleBoxName = 'settings';
const _uiStyleKey = 'ui_style';

@immutable
class UiStyleSettings {
  final UiStyle style;

  const UiStyleSettings({this.style = UiStyle.material});

  UiStyleSettings copyWith({UiStyle? style}) {
    return UiStyleSettings(style: style ?? this.style);
  }

  Map<String, dynamic> toJson() => {'style': style.name};

  /// Parses [raw] defensively: an unknown or malformed value always falls back
  /// to [UiStyle.material]. This is deliberate — unlike
  /// `FloatingLyricsSettings.fromJson`, a corrupted Hive value must never be
  /// able to put the UI into an unvalidated style.
  factory UiStyleSettings.fromJson(Object? raw) {
    final parsed = UiStyle.values.firstWhere(
      (style) => style.name == raw,
      orElse: () => UiStyle.material,
    );
    return UiStyleSettings(style: parsed);
  }

  @override
  bool operator ==(Object other) {
    return other is UiStyleSettings && other.style == style;
  }

  @override
  int get hashCode => style.hashCode;

  @override
  String toString() => 'UiStyleSettings(style: $style)';
}

/// User-selectable UI style with Hive persistence.
final uiStyleProvider =
    StateNotifierProvider<UiStyleNotifier, UiStyleSettings>((ref) {
      return UiStyleNotifier();
    });

class UiStyleNotifier extends StateNotifier<UiStyleSettings> {
  Future<void> ready = Future.value();

  /// [initialStyle] seeds the state so tests can start from a known style;
  /// when it is omitted the persisted `ui_style` value is loaded instead and
  /// an absent/corrupted value resolves to [UiStyle.material].
  UiStyleNotifier({UiStyle? initialStyle})
    : super(UiStyleSettings(style: initialStyle ?? UiStyle.material)) {
    if (initialStyle == null) {
      _load();
    }
  }

  void _load() {
    try {
      // `main.dart` always opens this box before the app is built; when it is
      // missing (unit tests that never touch Hive) there is simply nothing to
      // restore and the default [UiStyle.material] already holds.
      if (!Hive.isBoxOpen(_uiStyleBoxName)) return;
      final stored = UiStyleSettings.fromJson(
        Hive.box(_uiStyleBoxName).get(_uiStyleKey),
      );
      if (!mounted) return;
      state = stored;
    } catch (e, s) {
      debugPrint('UiStyleNotifier load failed: $e');
      debugPrint('$s');
    }
  }

  Future<void> setStyle(UiStyle style) async {
    state = state.copyWith(style: style);
    try {
      final box = await Hive.openBox(_uiStyleBoxName);
      await box.put(_uiStyleKey, state.toJson()['style']);
    } catch (e, s) {
      debugPrint('UiStyleNotifier save style failed: $e');
      debugPrint('$s');
    }
  }
}
