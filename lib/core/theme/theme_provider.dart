import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'app_theme.dart';

const _themeBoxName = 'settings';
const _themeModeKey = 'theme_mode';
const _themeSeedColorKey = 'theme_seed_color';

@immutable
class ThemeSettings {
  final ThemeMode mode;
  final Color seedColor;

  const ThemeSettings({
    this.mode = ThemeMode.system,
    this.seedColor = AppTheme.defaultSeedColor,
  });

  ThemeSettings copyWith({ThemeMode? mode, Color? seedColor}) {
    return ThemeSettings(
      mode: mode ?? this.mode,
      seedColor: seedColor ?? this.seedColor,
    );
  }
}

/// User-selectable theme mode and seed color with Hive persistence.
final themeSettingsProvider =
    StateNotifierProvider<ThemeSettingsNotifier, ThemeSettings>((ref) {
      return ThemeSettingsNotifier();
    });

/// Compatibility provider for existing call sites that only need ThemeMode.
final themeModeProvider = Provider<ThemeMode>((ref) {
  return ref.watch(themeSettingsProvider.select((settings) => settings.mode));
});

class ThemeSettingsNotifier extends StateNotifier<ThemeSettings> {
  late final Future<void> ready = _load();

  ThemeSettingsNotifier() : super(const ThemeSettings());

  Future<void> _load() async {
    try {
      final box = await Hive.openBox(_themeBoxName);
      final modeIndex = box.get(_themeModeKey, defaultValue: 0) as int;
      final seedColorValue =
          box.get(
                _themeSeedColorKey,
                defaultValue: AppTheme.defaultSeedColor.toARGB32(),
              )
              as int;
      if (!mounted) return;
      state = ThemeSettings(
        mode: ThemeMode.values[modeIndex.clamp(0, ThemeMode.values.length - 1)],
        seedColor: Color(seedColorValue),
      );
    } catch (e, s) {
      debugPrint('ThemeSettingsNotifier load failed: $e');
      debugPrint('$s');
    }
  }

  Future<void> setMode(ThemeMode mode) async {
    state = state.copyWith(mode: mode);
    try {
      final box = await Hive.openBox(_themeBoxName);
      await box.put(_themeModeKey, mode.index);
    } catch (e, s) {
      debugPrint('ThemeSettingsNotifier save mode failed: $e');
      debugPrint('$s');
    }
  }

  Future<void> setSeedColor(Color color) async {
    state = state.copyWith(seedColor: color);
    try {
      final box = await Hive.openBox(_themeBoxName);
      await box.put(_themeSeedColorKey, color.toARGB32());
    } catch (e, s) {
      debugPrint('ThemeSettingsNotifier save seed color failed: $e');
      debugPrint('$s');
    }
  }
}
