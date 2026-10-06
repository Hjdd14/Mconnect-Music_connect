import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../../core/database/app_database.dart';
import '../../../models/song.dart';
import '../../library/data/my_playlists_repository.dart';
import '../../smart_playlists/data/smart_playlist_repository.dart';
import '../../smart_playlists/domain/smart_playlist_rule.dart';
import '../domain/backup_models.dart';

/// Storage boundary for the app's user data.
///
/// The backup feature owns *what* a backup contains and *how* it merges; this
/// interface owns *where* the data lives. That split is what makes the
/// "export → wipe → import equals the original" test possible without a device.
abstract class BackupStore {
  int get schemaVersion;

  Future<BackupData> collect();

  /// Wipes exactly what [collect] exports, so the round-trip test is meaningful.
  Future<void> clearAll();

  Future<BackupImportReport> restore(BackupData data);
}

/// Hive-backed `settings` box (theme, background, lyrics, audio effects, offline
/// cache — all five live in this one box).
abstract class SettingsSnapshotSource {
  Future<Map<String, dynamic>> read();
  Future<void> write(Map<String, dynamic> values);
  Future<void> clear();
}

class HiveSettingsSnapshotSource implements SettingsSnapshotSource {
  static const String boxName = 'settings';

  const HiveSettingsSnapshotSource();

  @override
  Future<Map<String, dynamic>> read() async {
    final box = await Hive.openBox(boxName);
    final result = <String, dynamic>{};
    for (final key in box.keys) {
      final value = box.get(key);
      if (value == null) continue;
      // Only JSON-safe values can travel in the backup file; anything else is
      // reported and skipped rather than silently serialised to a broken value.
      try {
        result[key.toString()] = _jsonSafe(value);
      } catch (e) {
        debugPrint('Backup: skipping non-JSON setting "$key": $e');
      }
    }
    return result;
  }

  @override
  Future<void> write(Map<String, dynamic> values) async {
    if (values.isEmpty) return;
    final box = await Hive.openBox(boxName);
    // Merge, never replace: keys the backup does not carry stay as they are.
    await box.putAll(values);
  }

  @override
  Future<void> clear() async {
    final box = await Hive.openBox(boxName);
    await box.clear();
  }
}

class MemorySettingsSnapshotSource implements SettingsSnapshotSource {
  MemorySettingsSnapshotSource([Map<String, dynamic>? initial])
    : _values = Map<String, dynamic>.from(initial ?? const {});

  final Map<String, dynamic> _values;

  Map<String, dynamic> get values => Map<String, dynamic>.unmodifiable(_values);

  @override
  Future<Map<String, dynamic>> read() async => Map<String, dynamic>.from(_values);

  @override
  Future<void> write(Map<String, dynamic> values) async {
    _values.addAll(values);
  }

  @override
  Future<void> clear() async => _values.clear();
}

/// The real store: drift tables + the JSON playlist file + the Hive settings box
/// + the Hive smart-playlist rules.
class AppBackupStore implements BackupStore {
  AppBackupStore({
    required this.database,
    this.playlists = const MyPlaylistsRepository(),
    this.smartRules = const HiveSmartPlaylistRepository(),
    this.settings = const HiveSettingsSnapshotSource(),
  });

  final AppDatabase database;
  final MyPlaylistsRepository playlists;
  final SmartPlaylistRepository smartRules;
  final SettingsSnapshotSource settings;

  @override
  int get schemaVersion => database.schemaVersion;

  @override
  Future<BackupData> collect() async {
    final songRows = await database.songsDao.getAllSongs();
    final likeRows = await database.likesDao.getAllLikeRows();
    final eventRows = await database.statsDao.allPlayEvents();

    final playlistEntries = <BackupPlaylist>[];
    for (final playlist in await playlists.getPlaylists()) {
      final songs = await playlists.getSongs(playlist.editableId);
      playlistEntries.add(
        BackupPlaylist(
          id: playlist.editableId,
          name: playlist.name,
          songs: songs.map(BackupSong.fromSong).toList(),
        ),
      );
    }

    return BackupData(
      songs: [
        for (final row in songRows)
          BackupSong(
            id: row.id,
            platform: row.platform,
            name: row.name,
            artists: row.artists,
            albumName: row.albumName,
            albumCover: row.albumCover,
            durationMs: row.durationMs,
            fingerprint: row.fingerprint,
            albumId: row.albumId,
            artistId: row.artistId,
            trackNumber: row.trackNumber,
          ),
      ],
      likes: [
        for (final row in likeRows)
          BackupLike(
            songId: row.songId,
            platform: row.platform,
            addedAt: row.addedAt,
          ),
      ],
      playEvents: [
        for (final row in eventRows)
          BackupPlayEvent(
            songId: row.songId,
            platform: row.platform,
            startedAt: row.startedAt,
            endedAt: row.endedAt,
            durationListened: row.durationListened,
            completedRatio: row.completedRatio,
            source: row.source,
          ),
      ],
      playlists: playlistEntries,
      smartRules: [
        for (final rule in await smartRules.loadRules()) rule.toJson(),
      ],
      settings: await settings.read(),
    );
  }

  @override
  Future<void> clearAll() async {
    await database.transaction(() async {
      await database.delete(database.userLikes).go();
      await database.statsDao.clearAll();
      await database.delete(database.songs).go();
    });
    for (final playlist in await playlists.getPlaylists()) {
      await playlists.deletePlaylist(playlist.editableId);
    }
    await smartRules.saveRules(const []);
    await settings.clear();
  }

  @override
  Future<BackupImportReport> restore(BackupData data) async {
    var playlistsCreated = 0;
    var playlistsMerged = 0;
    var rulesAdded = 0;
    var rulesUpdated = 0;

    // Songs first: likes and play events reference `(id, platform)`.
    await database.songsDao.replaceSongRecords(
      data.songs
          .map(
            (song) => SongRecord(
              id: song.id,
              platform: song.platform,
              name: song.name,
              artists: song.artists,
              albumName: song.albumName,
              albumCover: song.albumCover,
              durationMs: song.durationMs,
              fingerprint: song.fingerprint,
              albumId: song.albumId,
              artistId: song.artistId,
              trackNumber: song.trackNumber,
            ),
          )
          .toList(),
    );

    await database.likesDao.restoreLikeRows(
      data.likes
          .map(
            (like) => UserLike(
              id: 0,
              songId: like.songId,
              platform: like.platform,
              addedAt: like.addedAt,
            ),
          )
          .toList(),
    );

    final playEvents = await database.statsDao.restorePlayEvents(
      data.playEvents
          .map(
            (event) => PlayEvent(
              id: 0,
              songId: event.songId,
              platform: event.platform,
              startedAt: event.startedAt,
              endedAt: event.endedAt,
              durationListened: event.durationListened,
              completedRatio: event.completedRatio,
              source: event.source,
            ),
          )
          .toList(),
    );

    final existingPlaylists = await playlists.getPlaylists();
    for (final imported in data.playlists) {
      final match = existingPlaylists
          .where((playlist) => playlist.name == imported.name)
          .toList();
      if (match.isEmpty) {
        final created = await playlists.createPlaylist(imported.name);
        final added = await _addSongs(created.editableId, imported.songs);
        if (added > 0) playlistsCreated += 1;
      } else {
        await _addSongs(match.first.editableId, imported.songs);
        playlistsMerged += 1;
      }
    }

    final existingRules = await smartRules.loadRules();
    final byId = {for (final rule in existingRules) rule.id: rule};
    for (final json in data.smartRules) {
      final rule = SmartPlaylistRule.fromJson(json);
      final existing = byId[rule.id];
      if (existing == null) {
        byId[rule.id] = rule;
        rulesAdded += 1;
      } else if (rule.updatedAt.isAfter(existing.updatedAt)) {
        byId[rule.id] = rule;
        rulesUpdated += 1;
      }
    }
    await smartRules.saveRules(byId.values.toList());

    await settings.write(data.settings);

    return BackupImportReport(
      songs: data.songs.length,
      likes: data.likes.length,
      playEvents: playEvents,
      playlistsCreated: playlistsCreated,
      playlistsMerged: playlistsMerged,
      smartRulesAdded: rulesAdded,
      smartRulesUpdated: rulesUpdated,
      settingsKeys: data.settings.length,
    );
  }

  /// Adds imported songs to a playlist, deduping on `(platform, id)` **and** on
  /// `Song.dedupeKey` so the same recording from two platforms lands once.
  Future<int> _addSongs(String playlistId, List<BackupSong> songs) async {
    final existing = await playlists.getSongs(playlistId);
    final seenKeys = {for (final song in existing) _key(song)};
    final seenDedupe = {for (final song in existing) song.dedupeKey};
    var added = 0;
    for (final song in songs) {
      final key = song.key;
      final dedupe = song.dedupeKey;
      if (seenKeys.contains(key) || seenDedupe.contains(dedupe)) continue;
      final ok = await playlists.addSong(playlistId, song.toSong());
      if (!ok) continue;
      seenKeys.add(key);
      seenDedupe.add(dedupe);
      added += 1;
    }
    return added;
  }

  static String _key(Song song) => '${song.platform.name}:${song.id}';
}

dynamic _jsonSafe(dynamic value) {
  if (value == null || value is num || value is bool || value is String) {
    return value;
  }
  if (value is List) return value.map(_jsonSafe).toList();
  if (value is Map) {
    return value.map(
      (key, item) => MapEntry(key.toString(), _jsonSafe(item)),
    );
  }
  throw FormatException('unsupported value type ${value.runtimeType}');
}
