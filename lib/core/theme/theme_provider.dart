import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

const _themeBoxName = 'settings';
const _themeKey = 'theme_mode';

/// User-selectable theme mode with Hive persistence.
final themeModeProvider =
    StateNotifierProvider<ThemeModeNotifier, ThemeMode>((ref) {
  return ThemeModeNotifier();
});

class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier() : super(ThemeMode.system) {
    _load();
  }

  Future<void> _load() async {
    try {
      final box = await Hive.openBox(_themeBoxName);
      final index = box.get(_themeKey, defaultValue: 0) as int;
      if (!mounted) return;
      state = ThemeMode.values[index.clamp(0, ThemeMode.values.length - 1)];
    } catch (e, s) {
      debugPrint('ThemeModeNotifier load failed: $e');
      debugPrint('$s');
    }
  }

  Future<void> setMode(ThemeMode mode) async {
    state = mode;
    try {
      final box = await Hive.openBox(_themeBoxName);
      await box.put(_themeKey, mode.index);
    } catch (e, s) {
      debugPrint('ThemeModeNotifier save failed: $e');
      debugPrint('$s');
    }
  }
}
