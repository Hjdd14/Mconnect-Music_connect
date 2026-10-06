import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/core/database/app_database.dart';
import 'package:mconnect/core/database/song_record_mapping.dart';
import 'package:mconnect/features/backup/data/backup_service.dart';
import 'package:mconnect/features/backup/data/backup_store.dart';
import 'package:mconnect/features/backup/domain/backup_models.dart';
import 'package:mconnect/features/library/data/my_playlists_repository.dart';
import 'package:mconnect/features/smart_playlists/data/smart_playlist_repository.dart';
import 'package:mconnect/features/smart_playlists/data/smart_playlist_snapshot_repository.dart';
import 'package:mconnect/features/smart_playlists/domain/smart_playlist_rule.dart';
import 'package:mconnect/features/stats/data/listening_stats_repository.dart';
import 'package:mconnect/models/album.dart';
import 'package:mconnect/models/artist.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/song.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;
  late AppDatabase db;
  late MyPlaylistsRepository playlists;
  late MemorySmartPlaylistRepository rules;
  late MemorySettingsSnapshotSource settings;
  late AppBackupStore store;
  late BackupService service;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('mconnect_backup_test');
    db = AppDatabase.forTesting(NativeDatabase.memory());
    playlists = MyPlaylistsRepository(storageDirectory: tempDir);
    rules = MemorySmartPlaylistRepository();
    settings = MemorySettingsSnapshotSource();
    store = AppBackupStore(
      database: db,
      playlists: playlists,
      smartRules: rules,
      settings: settings,
    );
    service = BackupService(
      store: store,
      appVersion: 'v1.3.2',
      clock: () => DateTime(2026, 5, 30, 10, 20, 30),
    );
  });

  tearDown(() async {
    await db.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  /// Both directions of the equivalence check read the same set of observable
  /// facts, so "equal" means the user would not be able to tell the difference.
  Future<Map<String, Object?>> snapshotFacts() async {
    final stats = await DriftListeningStatsRepository(db).load();
    final playlistFacts = <String, List<String>>{};
    for (final playlist in await playlists.getPlaylists()) {
      final songs = await playlists.getSongs(playlist.editableId);
      playlistFacts[playlist.name] =
          (songs.map((song) => '${song.platform.name}:${song.id}').toList()
            ..sort());
    }
    final likeRows = await db.likesDao.getAllLikeRows();
    return {
      'likes': (likeRows.map((row) => '${row.platform}:${row.songId}').toList()
        ..sort()),
      'songs': (await db.songsDao.getAllSongs()).length,
      'playlists': playlistFacts,
      'rules': (await rules.loadRules()).map((rule) => rule.toJson()).toList(),
      'settings': settings.values,
      'totalPlayCount': stats.totalPlayCount,
      'totalListenMs': stats.totalListenDuration.inMilliseconds,
      'totalSongCount': stats.totalSongCount,
      'playEvents': await db.statsDao.countPlayEvents(),
    };
  }

  Future<void> seed() async {
    final likeSong = _song('like-1', PlatformType.netease, '收藏曲');
    final secondLike = _song('like-2', PlatformType.qq, '收藏曲二');
    await db.songsDao.insertSongs([
      songsCompanionFromSong(likeSong),
      songsCompanionFromSong(secondLike),
    ]);
    await db.likesDao.likeSong(likeSong.id, likeSong.platform.name);
    await db.likesDao.likeSong(secondLike.id, secondLike.platform.name);

    final stats = DriftListeningStatsRepository(db);
    await stats.recordSongStarted(likeSong, at: DateTime(2026, 5, 29, 9));
    await stats.addListenedDuration(
      likeSong,
      const Duration(minutes: 4),
      at: DateTime(2026, 5, 29, 9, 4),
    );
    await stats.recordSongStarted(secondLike, at: DateTime(2026, 5, 30, 20));
    await stats.addListenedDuration(
      secondLike,
      const Duration(minutes: 2),
      at: DateTime(2026, 5, 30, 20, 2),
    );

    final playlist = await playlists.createPlaylist('我的夜曲');
    await playlists.addSong(playlist.editableId, likeSong);
    await playlists.addSong(playlist.editableId, secondLike);

    await rules.saveRules([
      SmartPlaylistRule.create(
        name: '常听收藏',
        platforms: const {PlatformType.netease},
        likedOnly: true,
      ),
    ]);

    await settings.write({
      'theme_mode': 'dark',
      'app_background_settings': {'scale': 1.5, 'offsetX': 0},
      'floating_lyrics_enabled': true,
    });
  }

  test('export → wipe → import restores exactly the same user data', () async {
    await seed();
    final before = await snapshotFacts();
    expect(before['likes'], hasLength(2));
    expect(before['playlists'], hasLength(1));
    expect(before['totalListenMs'], const Duration(minutes: 6).inMilliseconds);

    final json = await service.exportToJson();

    await store.clearAll();
    final wiped = await snapshotFacts();
    expect(wiped['likes'], isEmpty);
    expect(wiped['songs'], 0);
    expect(wiped['playlists'], isEmpty);
    expect(wiped['rules'], isEmpty);
    expect(wiped['settings'], isEmpty);
    expect(wiped['totalPlayCount'], 0);

    final report = await service.importFromJson(json);
    expect(report.likes, 2);
    expect(report.playEvents, 2);

    expect(await snapshotFacts(), before);
  });

  test('importing the same file twice is idempotent', () async {
    await seed();
    final json = await service.exportToJson();
    await store.clearAll();

    await service.importFromJson(json);
    final once = await snapshotFacts();
    await service.importFromJson(json);
    final twice = await snapshotFacts();

    expect(twice['likes'], once['likes']);
    expect(twice['playEvents'], once['playEvents']);
    expect(twice['totalPlayCount'], once['totalPlayCount']);
    expect(twice['totalListenMs'], once['totalListenMs']);
    expect(twice['songs'], once['songs']);
  });

  test('import merges into existing data instead of replacing it', () async {
    await seed();
    final json = await service.exportToJson();
    // A like that exists only locally must survive the import.
    await db.likesDao.likeSong('local-only', PlatformType.kugou.name);

    final report = await service.importFromJson(json);

    expect(report.likes, 2);
    final likes = await db.likesDao.getAllLikeRows();
    expect(
      likes.map((row) => '${row.platform}:${row.songId}').toSet(),
      contains('kugou:local-only'),
    );
    // Settings the file does not carry are kept.
    await settings.write({'local_only_flag': true});
    await service.importFromJson(json);
    expect(settings.values['local_only_flag'], isTrue);
    expect(settings.values['theme_mode'], 'dark');
  });

  test('a backup from a newer app version is refused without writing', () async {
    await seed();
    final json = await service.exportToJson();
    await store.clearAll();

    final decoded = jsonDecode(json) as Map<String, dynamic>;
    (decoded['manifest'] as Map<String, dynamic>)['version'] =
        backupFormatVersion + 1;

    expect(
      () => service.importFromJson(jsonEncode(decoded)),
      throwsA(isA<BackupFormatException>()),
    );
    expect((await snapshotFacts())['likes'], isEmpty);
  });

  test('a corrupt file is rejected before anything is written', () async {
    await seed();
    final before = await snapshotFacts();

    await expectLater(
      service.importFromJson('{not json'),
      throwsA(isA<BackupFormatException>()),
    );
    await expectLater(
      service.importFromJson(''),
      throwsA(isA<BackupFormatException>()),
    );
    await expectLater(
      service.importFromJson('[1,2,3]'),
      throwsA(isA<BackupFormatException>()),
    );

    // A file whose manifest is fine but whose body is broken must also fail
    // *before* import, not halfway through it.
    await expectLater(
      service.importFromJson(
        jsonEncode({
          'manifest': {
            'version': backupFormatVersion,
            'exportedAt': '2026-05-30T10:00:00.000',
            'appVersion': 'v1.3.2',
          },
          'likes': [
            {'songId': 'x'},
          ],
        }),
      ),
      throwsA(isA<BackupFormatException>()),
    );

    expect(await snapshotFacts(), before);
  });

  test('inspect reports the file contents without importing', () async {
    await seed();
    final json = await service.exportToJson();

    final summary = service.inspect(json);
    expect(summary.songCount, greaterThanOrEqualTo(2));
    expect(summary.likeCount, 2);
    expect(summary.playlistCount, 1);
    expect(summary.smartRuleCount, 1);
    expect(summary.playEventCount, 2);
    expect(summary.settingsKeyCount, 3);
    expect(summary.manifest.appVersion, 'v1.3.2');
  });

  test('exportToFile writes a parseable file next to the app documents', () async {
    await seed();
    final dir = Directory(p.join(tempDir.path, 'exports'));
    final file = await service.exportToFile(directory: dir);

    expect(await file.exists(), isTrue);
    expect(p.basename(file.path), startsWith(BackupService.filePrefix));
    final summary = service.inspect(await file.readAsString());
    expect(summary.likeCount, 2);
  });

  test('imported playlists dedupe the same recording across platforms', () async {
    final netease = _song('n1', PlatformType.netease, '夜曲');
    final qq = _song('q1', PlatformType.qq, '夜曲');
    // Sanity: these two really are the same recording by `dedupeKey`.
    expect(BackupSong.fromSong(netease).dedupeKey,
        BackupSong.fromSong(qq).dedupeKey);

    final data = BackupData(
      songs: [BackupSong.fromSong(netease), BackupSong.fromSong(qq)],
      playlists: [
        BackupPlaylist(
          id: 'imported',
          name: '去重歌单',
          songs: [BackupSong.fromSong(netease), BackupSong.fromSong(qq)],
        ),
      ],
    );

    await store.restore(data);

    final created = (await playlists.getPlaylists()).single;
    final songs = await playlists.getSongs(created.editableId);
    expect(songs, hasLength(1), reason: 'cross-platform duplicates merge');
  });

  test('imported playlists with the same name merge into the local one', () async {
    final existing = await playlists.createPlaylist('合并目标');
    await playlists.addSong(
      existing.editableId,
      _song('keep', PlatformType.netease, '保留曲'),
    );

    final data = BackupData(
      playlists: [
        BackupPlaylist(
          id: 'imported',
          name: '合并目标',
          songs: [BackupSong.fromSong(_song('added', PlatformType.qq, '新增曲'))],
        ),
      ],
    );

    final report = await store.restore(data);

    expect(report.playlistsMerged, 1);
    expect(report.playlistsCreated, 0);
    expect(await playlists.getPlaylists(), hasLength(1));
    final songs = await playlists.getSongs(existing.editableId);
    expect(songs, hasLength(2));
  });

  test('a newer smart-playlist rule from the file wins, an older one does not', () async {
    final older = SmartPlaylistRule(
      id: 'rule-shared',
      name: '本地规则',
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );
    await rules.saveRules([older]);

    final newer = SmartPlaylistRule(
      id: 'rule-shared',
      name: '备份规则',
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 5, 1),
    );

    var report = await store.restore(
      BackupData(smartRules: [newer.toJson()]),
    );
    expect(report.smartRulesUpdated, 1);
    expect((await rules.loadRules()).single.name, '备份规则');

    report = await store.restore(BackupData(smartRules: [older.toJson()]));
    expect(report.smartRulesUpdated, 0);
    expect((await rules.loadRules()).single.name, '备份规则');
  });

  test('saved smart playlists survive the round trip', () async {
    final snapshots = DriftSmartPlaylistSnapshotRepository(db);
    final song = _song('snap-1', PlatformType.netease, '快照曲');
    await snapshots.save('rule-1', [song], generatedAt: DateTime(2026, 5, 1));

    final json = await service.exportToJson();
    await store.clearAll();

    // The snapshot itself is not part of the backup; it becomes playable again
    // because the import restores the songs it points at.
    expect((await snapshots.load('rule-1'))!.songs, isEmpty);

    await service.importFromJson(json);

    final restored = await DriftSmartPlaylistSnapshotRepository(db).load('rule-1');
    expect(restored!.songs.single.id, 'snap-1');
    expect(restored.songs.single.platform, PlatformType.netease);
    expect(restored.generatedAt, DateTime(2026, 5, 1));
  });
}

Song _song(String id, PlatformType platform, String name) {
  return Song(
    id: id,
    platform: platform,
    name: name,
    artists: const [Artist(id: '', name: '歌手')],
    album: const Album(id: '', name: '专辑'),
    duration: const Duration(minutes: 4),
  );
}
