import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mconnect/features/download/presentation/providers/download_provider.dart';
import 'package:mconnect/features/offline_cache/presentation/providers/offline_cache_provider.dart';
import 'package:mconnect/models/artist.dart';
import 'package:mconnect/models/audio_quality.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/song.dart';

import 'download_fakes.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('mconnect_cache_test_');
    Hive.init(tempDir.path);
  });

  tearDown(() async {
    await Hive.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('offline cache settings default to conservative behavior', () async {
    final notifier = OfflineCacheSettingsNotifier();
    await notifier.ready;

    expect(notifier.state.sizeLimitMb, 1024);
    expect(notifier.state.wifiOnly, isTrue);
    expect(notifier.state.autoRetry, isTrue);
    expect(notifier.state.autoCleanup, isTrue);
    expect(notifier.state.offlineMode, isFalse);
  });

  test('offline cache settings persist user choices', () async {
    final notifier = OfflineCacheSettingsNotifier();
    await notifier.ready;

    await notifier.setSizeLimitMb(2048);
    await notifier.setWifiOnly(false);
    await notifier.setAutoRetry(false);
    await notifier.setAutoCleanup(false);
    await notifier.setOfflineMode(true);

    final restored = OfflineCacheSettingsNotifier();
    await restored.ready;

    expect(restored.state.sizeLimitMb, 2048);
    expect(restored.state.wifiOnly, isFalse);
    expect(restored.state.autoRetry, isFalse);
    expect(restored.state.autoCleanup, isFalse);
    expect(restored.state.offlineMode, isTrue);
  });

  test(
    'download notifier enqueues a song list for offline cache once',
    () async {
      final manager = FakeDownloadManager();
      final notifier = DownloadNotifier(
        manager: manager,
        taskStore: MemoryDownloadTaskStore([]),
      );
      addTearDown(notifier.dispose);

      await notifier.cacheSongs([
        _song('s1'),
        _song('s1'),
        _song('s2'),
      ], quality: AudioLevel.low);
      await pumpEventQueue();

      expect(notifier.state.tasks, hasLength(2));
      expect(notifier.state.tasks.map((task) => task.id), [
        'netease_s1_low_cache',
        'netease_s2_low_cache',
      ]);
      expect(
        manager.started,
        ['netease_s1_low_cache', 'netease_s2_low_cache'],
        reason: 'the cache queue must really start downloads (P0-1)',
      );
    },
  );

  test('the four switches are handed to the download queue', () async {
    final notifier = OfflineCacheSettingsNotifier();
    await notifier.ready;

    final defaults = notifier.state.toQueuePolicy();
    expect(defaults.wifiOnly, isTrue);
    expect(defaults.autoRetry, isTrue);
    expect(defaults.autoCleanup, isTrue);
    expect(defaults.offlineMode, isFalse);
    expect(defaults.sizeLimitMb, 1024);

    await notifier.setWifiOnly(false);
    await notifier.setAutoRetry(false);
    await notifier.setAutoCleanup(false);
    await notifier.setOfflineMode(true);
    await notifier.setSizeLimitMb(2048);

    final updated = notifier.state.toQueuePolicy();
    expect(updated.wifiOnly, isFalse);
    expect(updated.autoRetry, isFalse);
    expect(updated.autoCleanup, isFalse);
    expect(updated.offlineMode, isTrue);
    expect(updated.sizeLimitMb, 2048);
  });
}

Song _song(String id) => Song(
  id: id,
  platform: PlatformType.netease,
  name: 'Song $id',
  artists: const [Artist(id: 'a1', name: 'Artist')],
);
