import 'package:hive_flutter/hive_flutter.dart';

import '../presentation/providers/offline_cache_provider.dart';

const offlineCacheSettingsBoxName = 'settings';
const offlineCacheSettingsKey = 'offline_cache_settings';

class CacheSettingsRepository {
  const CacheSettingsRepository();

  Future<OfflineCacheSettings> load() async {
    final box = await Hive.openBox(offlineCacheSettingsBoxName);
    return OfflineCacheSettings.fromJson(box.get(offlineCacheSettingsKey));
  }

  Future<void> save(OfflineCacheSettings settings) async {
    final box = await Hive.openBox(offlineCacheSettingsBoxName);
    await box.put(offlineCacheSettingsKey, settings.toJson());
  }
}
