import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/cache_settings_repository.dart';

@immutable
class OfflineCacheSettings {
  final int sizeLimitMb;
  final bool wifiOnly;
  final bool autoRetry;
  final bool autoCleanup;
  final bool offlineMode;

  const OfflineCacheSettings({
    this.sizeLimitMb = 1024,
    this.wifiOnly = true,
    this.autoRetry = true,
    this.autoCleanup = true,
    this.offlineMode = false,
  });

  OfflineCacheSettings copyWith({
    int? sizeLimitMb,
    bool? wifiOnly,
    bool? autoRetry,
    bool? autoCleanup,
    bool? offlineMode,
  }) {
    return OfflineCacheSettings(
      sizeLimitMb: sizeLimitMb ?? this.sizeLimitMb,
      wifiOnly: wifiOnly ?? this.wifiOnly,
      autoRetry: autoRetry ?? this.autoRetry,
      autoCleanup: autoCleanup ?? this.autoCleanup,
      offlineMode: offlineMode ?? this.offlineMode,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'sizeLimitMb': sizeLimitMb,
      'wifiOnly': wifiOnly,
      'autoRetry': autoRetry,
      'autoCleanup': autoCleanup,
      'offlineMode': offlineMode,
    };
  }

  static OfflineCacheSettings fromJson(dynamic value) {
    if (value is! Map) return const OfflineCacheSettings();
    return OfflineCacheSettings(
      sizeLimitMb: _clampSizeLimit(_intValue(value['sizeLimitMb']) ?? 1024),
      wifiOnly: value['wifiOnly'] != false,
      autoRetry: value['autoRetry'] != false,
      autoCleanup: value['autoCleanup'] != false,
      offlineMode: value['offlineMode'] == true,
    );
  }

  static int _clampSizeLimit(int value) => value.clamp(128, 32768);

  static int? _intValue(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '');
  }
}

final offlineCacheSettingsProvider =
    StateNotifierProvider<OfflineCacheSettingsNotifier, OfflineCacheSettings>(
      (ref) => OfflineCacheSettingsNotifier(),
    );

class OfflineCacheSettingsNotifier extends StateNotifier<OfflineCacheSettings> {
  final CacheSettingsRepository _repository;
  late final Future<void> ready;

  OfflineCacheSettingsNotifier({CacheSettingsRepository? repository})
    : _repository = repository ?? const CacheSettingsRepository(),
      super(const OfflineCacheSettings()) {
    ready = _load();
  }

  Future<void> _load() async {
    try {
      final settings = await _repository.load();
      if (mounted) state = settings;
    } catch (e, s) {
      debugPrint('OfflineCacheSettingsNotifier load failed: $e');
      debugPrint('$s');
    }
  }

  Future<void> setSizeLimitMb(int value) {
    return _save(
      state.copyWith(sizeLimitMb: OfflineCacheSettings._clampSizeLimit(value)),
    );
  }

  Future<void> setWifiOnly(bool value) {
    return _save(state.copyWith(wifiOnly: value));
  }

  Future<void> setAutoRetry(bool value) {
    return _save(state.copyWith(autoRetry: value));
  }

  Future<void> setAutoCleanup(bool value) {
    return _save(state.copyWith(autoCleanup: value));
  }

  Future<void> setOfflineMode(bool value) {
    return _save(state.copyWith(offlineMode: value));
  }

  Future<void> _save(OfflineCacheSettings settings) async {
    state = settings;
    try {
      await _repository.save(settings);
    } catch (e, s) {
      debugPrint('OfflineCacheSettingsNotifier save failed: $e');
      debugPrint('$s');
    }
  }
}
