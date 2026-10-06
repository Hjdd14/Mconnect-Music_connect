import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/core/database/app_database.dart';
import 'package:mconnect/features/smart_playlists/data/smart_playlist_snapshot_repository.dart';
import 'package:mconnect/features/smart_playlists/presentation/providers/smart_playlists_provider.dart';
import 'package:mconnect/features/smart_playlists/data/smart_playlist_repository.dart';
import 'package:mconnect/models/artist.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/song.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test('a generated result can be saved and reopened', () async {
    final repository = DriftSmartPlaylistSnapshotRepository(db);
    final songs = [
      _song('1', PlatformType.netease, '第一首'),
      _song('2', PlatformType.qq, '第二首'),
    ];

    final saved = await repository.save(
      'rule-1',
      songs,
      generatedAt: DateTime(2026, 5, 30, 9),
    );
    expect(saved.songs, hasLength(2));

    final reopened = await repository.load('rule-1');
    expect(reopened, isNotNull);
    expect(reopened!.songs.map((song) => song.id), ['1', '2']);
    expect(reopened.songs.first.platform, PlatformType.netease);
    expect(reopened.songs.first.name, '第一首');
    expect(reopened.missingSongCount, 0);
    expect(reopened.generatedAt, DateTime(2026, 5, 30, 9));

    // Saving again replaces the previous result rather than appending to it.
    await repository.save('rule-1', [songs.first]);
    expect((await repository.load('rule-1'))!.songs, hasLength(1));
    expect(await repository.loadAll(), hasLength(1));
  });

  test('a snapshot whose songs are gone reports the missing count', () async {
    final repository = DriftSmartPlaylistSnapshotRepository(db);
    await repository.save('rule-1', [_song('1', PlatformType.netease, '第一首')]);

    // Simulate the cached song row being evicted (or a hand-edited database).
    await db.delete(db.songs).go();

    final reopened = await repository.load('rule-1');
    expect(reopened!.songs, isEmpty);
    expect(reopened.missingSongCount, 1);
  });

  test('deleting a rule drops its snapshot', () async {
    final repository = DriftSmartPlaylistSnapshotRepository(db);
    await repository.save('rule-1', [_song('1', PlatformType.netease, 'A')]);
    await repository.save('rule-2', [_song('2', PlatformType.netease, 'B')]);

    expect(await repository.loadAll(), hasLength(2));
    await repository.deleteMissing({'rule-1'});
    final remaining = await repository.loadAll();
    expect(remaining.keys, ['rule-1']);

    await repository.delete('rule-1');
    expect(await repository.loadAll(), isEmpty);

    await repository.save('rule-1', [_song('1', PlatformType.netease, 'A')]);
    await repository.clear();
    expect(await repository.loadAll(), isEmpty);
  });

  test('the notifier exposes a saved result and prunes deleted rules', () async {
    final rulesRepository = MemorySmartPlaylistRepository();
    final snapshots = MemorySmartPlaylistSnapshotRepository();
    final notifier = SmartPlaylistsNotifier(
      repository: rulesRepository,
      snapshotRepository: snapshots,
    );
    await notifier.ready;

    final rule = await notifier.createRule(name: '规则一');
    final songs = [
      _song('1', PlatformType.netease, '第一首'),
      _song('2', PlatformType.qq, '第二首'),
    ];

    final saved = await notifier.saveSnapshot(rule.id, songs);
    expect(saved, isNotNull);
    expect(notifier.state.snapshotFor(rule.id)!.songs, hasLength(2));
    expect(notifier.state.error, isNull);

    await notifier.deleteRule(rule.id);
    expect(notifier.state.snapshotFor(rule.id), isNull);
    expect(await snapshots.loadAll(), isEmpty);
  });

  test('a snapshot save failure is reported instead of silently dropped', () async {
    final notifier = SmartPlaylistsNotifier(
      repository: MemorySmartPlaylistRepository(),
      snapshotRepository: _FailingSnapshotRepository(),
    );
    await notifier.ready;

    final song = _song('1', PlatformType.netease, '第一首');
    final saved = await notifier.saveSnapshot('rule-1', [song]);

    expect(saved, isNull);
    expect(notifier.state.error, '生成结果保存失败');
    expect(notifier.state.isSaving, isFalse);
  });

  test('rules without a snapshot repository still work', () async {
    final notifier = SmartPlaylistsNotifier(
      repository: MemorySmartPlaylistRepository(),
    );
    await notifier.ready;

    final rule = await notifier.createRule(name: '规则');
    expect(notifier.state.rules.single, rule);
    expect(await notifier.saveSnapshot(rule.id, const []), isNull);
    expect(notifier.state.error, isNull);
  });
}

Song _song(String id, PlatformType platform, String name) {
  return Song(
    id: id,
    platform: platform,
    name: name,
    artists: const [Artist(id: '', name: '歌手')],
    duration: const Duration(minutes: 3),
  );
}

class _FailingSnapshotRepository implements SmartPlaylistSnapshotRepository {
  @override
  Future<SavedSmartPlaylist?> load(String ruleId) async => null;

  @override
  Future<Map<String, SavedSmartPlaylist>> loadAll() async => const {};

  @override
  Future<SavedSmartPlaylist> save(
    String ruleId,
    List<Song> songs, {
    DateTime? generatedAt,
  }) async {
    throw StateError('disk full');
  }

  @override
  Future<void> delete(String ruleId) async {}

  @override
  Future<void> deleteMissing(Set<String> ruleIds) async {}

  @override
  Future<void> clear() async {}
}
