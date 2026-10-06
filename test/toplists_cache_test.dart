import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/core/database/app_database.dart';
import 'package:mconnect/features/toplist/data/toplists_cache_store.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/toplist.dart';

void main() {
  late AppDatabase db;
  late ToplistsCacheStore store;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    store = ToplistsCacheStore(database: db);
  });

  tearDown(() async {
    await db.close();
  });

  test('榜单目录可以按平台写入并读回（含分组与更新频率）', () async {
    await store.saveForPlatform(PlatformType.qq, const [
      ToplistFixture.hot,
      ToplistFixture.soaring,
    ]);

    final rows = await store.byPlatform(PlatformType.qq);

    expect(rows.map((row) => row.id), ['26', '62']);
    expect(rows.first.name, '热歌榜');
    expect(rows.first.songCount, 300);
    expect(rows.first.updateFrequency, '每日更新');
    expect(rows.first.groupName, '巅峰榜');
    expect(rows.first.intro, contains('300'));
    expect(await store.lastFetchedAt(PlatformType.qq), isNotNull);
  });

  test('重复写入是替换而不是追加', () async {
    await store.saveForPlatform(PlatformType.qq, const [
      ToplistFixture.hot,
      ToplistFixture.soaring,
    ]);
    await store.saveForPlatform(PlatformType.qq, const [ToplistFixture.hot]);

    final rows = await store.byPlatform(PlatformType.qq);

    expect(rows, hasLength(1));
    expect(rows.single.id, '26');
  });

  test('all() 按平台分组，未知平台行被丢弃而不是抛异常', () async {
    await store.saveForPlatform(PlatformType.qq, const [ToplistFixture.hot]);
    await store.saveForPlatform(PlatformType.netease, const [
      ToplistFixture.neteaseSoaring,
    ]);
    // A row written by an older build / removed platform.
    await db.toplistsCacheDao.replaceForPlatform('spotify', [
      ToplistsCacheCompanion.insert(
        platform: 'spotify',
        toplistId: '1',
        name: 'Legacy Chart',
        fetchedAt: 0,
      ),
    ]);

    final grouped = await store.all();

    expect(grouped.keys, containsAll(<PlatformType>[
      PlatformType.qq,
      PlatformType.netease,
    ]));
    expect(grouped[PlatformType.qq]!.single.name, '热歌榜');
    expect(grouped.values.expand((rows) => rows).length, 2);
  });

  test('平台之间互不覆盖，clearAll 清空全部', () async {
    await store.saveForPlatform(PlatformType.qq, const [ToplistFixture.hot]);
    await store.saveForPlatform(PlatformType.netease, const [
      ToplistFixture.neteaseSoaring,
    ]);

    await db.toplistsCacheDao.clearPlatform(PlatformType.qq.name);
    expect(await store.byPlatform(PlatformType.qq), isEmpty);
    expect(await store.byPlatform(PlatformType.netease), hasLength(1));

    await store.clearAll();
    expect(await store.all(), isEmpty);
  });

  test('写入空列表会清空该平台（刷新拿到空目录时不保留旧数据）', () async {
    await store.saveForPlatform(PlatformType.qq, const [ToplistFixture.hot]);
    await store.saveForPlatform(PlatformType.qq, const []);

    expect(await store.byPlatform(PlatformType.qq), isEmpty);
    expect((await store.all())[PlatformType.qq], isNull);
  });
}

/// Charts used by the cache tests — values copied from QQ's live `GetAll`
/// catalogue and 网易云's `/api/toplist`.
class ToplistFixture {
  ToplistFixture._();

  static const hot = Toplist(
    id: '26',
    name: '热歌榜',
    coverUrl: 'http://y.gtimg.cn/music/photo_new/T003R300x300M000001xEeb01e5Jyf.jpg',
    updateFrequency: '每日更新',
    songCount: 300,
    period: '2026-10-06',
    groupName: '巅峰榜',
    intro: '1.榜单定义：QQ音乐站内播放热度前300首歌曲。',
  );

  static const soaring = Toplist(
    id: '62',
    name: '飙升榜',
    updateFrequency: '每日更新',
    songCount: 100,
    period: '2026-10-06',
    groupName: '巅峰榜',
  );

  static const neteaseSoaring = Toplist(
    id: '19723756',
    name: '云音乐飙升榜',
    updateFrequency: '每天更新',
    songCount: 100,
  );
}
