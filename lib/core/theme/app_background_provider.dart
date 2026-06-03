import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

const _backgroundBoxName = 'settings';
const _backgroundSettingsKey = 'app_background_settings';

@immutable
class AppBackgroundSettings {
  final String? imagePath;
  final double imageWidth;
  final double imageHeight;
  final double scale;
  final double offsetX;
  final double offsetY;
  final double cropViewportWidth;
  final double cropViewportHeight;

  const AppBackgroundSettings({
    this.imagePath,
    this.imageWidth = 0,
    this.imageHeight = 0,
    this.scale = 1,
    this.offsetX = 0,
    this.offsetY = 0,
    this.cropViewportWidth = 0,
    this.cropViewportHeight = 0,
  });

  bool get enabled => imagePath != null && imagePath!.trim().isNotEmpty;
  bool get hasCropViewport => cropViewportWidth > 0 && cropViewportHeight > 0;

  AppBackgroundSettings copyWith({
    String? Function()? imagePath,
    double? imageWidth,
    double? imageHeight,
    double? scale,
    double? offsetX,
    double? offsetY,
    double? cropViewportWidth,
    double? cropViewportHeight,
  }) {
    return AppBackgroundSettings(
      imagePath: imagePath != null ? imagePath() : this.imagePath,
      imageWidth: imageWidth ?? this.imageWidth,
      imageHeight: imageHeight ?? this.imageHeight,
      scale: scale ?? this.scale,
      offsetX: offsetX ?? this.offsetX,
      offsetY: offsetY ?? this.offsetY,
      cropViewportWidth: cropViewportWidth ?? this.cropViewportWidth,
      cropViewportHeight: cropViewportHeight ?? this.cropViewportHeight,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'imagePath': imagePath,
      'imageWidth': imageWidth,
      'imageHeight': imageHeight,
      'scale': scale,
      'offsetX': offsetX,
      'offsetY': offsetY,
      'cropViewportWidth': cropViewportWidth,
      'cropViewportHeight': cropViewportHeight,
    };
  }

  factory AppBackgroundSettings.fromJson(Object? value) {
    if (value is! Map) return const AppBackgroundSettings();
    return AppBackgroundSettings(
      imagePath: value['imagePath'] as String?,
      imageWidth: (value['imageWidth'] as num?)?.toDouble() ?? 0,
      imageHeight: (value['imageHeight'] as num?)?.toDouble() ?? 0,
      scale: (value['scale'] as num?)?.toDouble().clamp(1, 4).toDouble() ?? 1,
      offsetX: (value['offsetX'] as num?)?.toDouble() ?? 0,
      offsetY: (value['offsetY'] as num?)?.toDouble() ?? 0,
      cropViewportWidth: (value['cropViewportWidth'] as num?)?.toDouble() ?? 0,
      cropViewportHeight:
          (value['cropViewportHeight'] as num?)?.toDouble() ?? 0,
    );
  }
}

final appBackgroundSettingsProvider =
    StateNotifierProvider<AppBackgroundSettingsNotifier, AppBackgroundSettings>(
      (ref) => AppBackgroundSettingsNotifier(),
    );

class AppBackgroundSettingsNotifier
    extends StateNotifier<AppBackgroundSettings> {
  Future<void> ready = Future.value();
  AppBackgroundSettings get current => state;

  AppBackgroundSettingsNotifier() : super(_restoreSynchronously()) {
    ready = _load();
  }

  static AppBackgroundSettings _restoreSynchronously() {
    try {
      if (!Hive.isBoxOpen(_backgroundBoxName)) {
        return const AppBackgroundSettings();
      }
      final box = Hive.box(_backgroundBoxName);
      return AppBackgroundSettings.fromJson(box.get(_backgroundSettingsKey));
    } catch (e, s) {
      debugPrint('AppBackgroundSettingsNotifier sync load failed: $e');
      debugPrint('$s');
      return const AppBackgroundSettings();
    }
  }

  Future<void> _load() async {
    try {
      if (!Hive.isBoxOpen(_backgroundBoxName)) return;
      final box = Hive.box(_backgroundBoxName);
      final restored = AppBackgroundSettings.fromJson(
        box.get(_backgroundSettingsKey),
      );
      if (!mounted) return;
      state = restored;
    } catch (e, s) {
      debugPrint('AppBackgroundSettingsNotifier load failed: $e');
      debugPrint('$s');
    }
  }

  Future<void> save(AppBackgroundSettings settings) async {
    final next = settings.copyWith(
      scale: settings.scale.clamp(1, 4).toDouble(),
    );
    state = next;
    try {
      final box = await Hive.openBox(_backgroundBoxName);
      await box.put(_backgroundSettingsKey, next.toJson());
    } catch (e, s) {
      debugPrint('AppBackgroundSettingsNotifier save failed: $e');
      debugPrint('$s');
    }
  }

  Future<void> clear() async {
    state = const AppBackgroundSettings();
    try {
      final box = await Hive.openBox(_backgroundBoxName);
      await box.delete(_backgroundSettingsKey);
    } catch (e, s) {
      debugPrint('AppBackgroundSettingsNotifier clear failed: $e');
      debugPrint('$s');
    }
  }
}
