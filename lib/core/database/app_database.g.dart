// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
mixin _$SongsDaoMixin on DatabaseAccessor<AppDatabase> {
  $SongsTable get songs => attachedDatabase.songs;
  $ListeningHistoryTable get listeningHistory =>
      attachedDatabase.listeningHistory;
  $UserLikesTable get userLikes => attachedDatabase.userLikes;
  $LyricsCacheTable get lyricsCache => attachedDatabase.lyricsCache;
  SongsDaoManager get managers => SongsDaoManager(this);
}

class SongsDaoManager {
  final _$SongsDaoMixin _db;
  SongsDaoManager(this._db);
  $$SongsTableTableManager get songs =>
      $$SongsTableTableManager(_db.attachedDatabase, _db.songs);
  $$ListeningHistoryTableTableManager get listeningHistory =>
      $$ListeningHistoryTableTableManager(
        _db.attachedDatabase,
        _db.listeningHistory,
      );
  $$UserLikesTableTableManager get userLikes =>
      $$UserLikesTableTableManager(_db.attachedDatabase, _db.userLikes);
  $$LyricsCacheTableTableManager get lyricsCache =>
      $$LyricsCacheTableTableManager(_db.attachedDatabase, _db.lyricsCache);
}

mixin _$HistoryDaoMixin on DatabaseAccessor<AppDatabase> {
  $SongsTable get songs => attachedDatabase.songs;
  $ListeningHistoryTable get listeningHistory =>
      attachedDatabase.listeningHistory;
  HistoryDaoManager get managers => HistoryDaoManager(this);
}

class HistoryDaoManager {
  final _$HistoryDaoMixin _db;
  HistoryDaoManager(this._db);
  $$SongsTableTableManager get songs =>
      $$SongsTableTableManager(_db.attachedDatabase, _db.songs);
  $$ListeningHistoryTableTableManager get listeningHistory =>
      $$ListeningHistoryTableTableManager(
        _db.attachedDatabase,
        _db.listeningHistory,
      );
}

mixin _$LikesDaoMixin on DatabaseAccessor<AppDatabase> {
  $SongsTable get songs => attachedDatabase.songs;
  $UserLikesTable get userLikes => attachedDatabase.userLikes;
  LikesDaoManager get managers => LikesDaoManager(this);
}

class LikesDaoManager {
  final _$LikesDaoMixin _db;
  LikesDaoManager(this._db);
  $$SongsTableTableManager get songs =>
      $$SongsTableTableManager(_db.attachedDatabase, _db.songs);
  $$UserLikesTableTableManager get userLikes =>
      $$UserLikesTableTableManager(_db.attachedDatabase, _db.userLikes);
}

mixin _$LyricsCacheDaoMixin on DatabaseAccessor<AppDatabase> {
  $LyricsCacheTable get lyricsCache => attachedDatabase.lyricsCache;
  LyricsCacheDaoManager get managers => LyricsCacheDaoManager(this);
}

class LyricsCacheDaoManager {
  final _$LyricsCacheDaoMixin _db;
  LyricsCacheDaoManager(this._db);
  $$LyricsCacheTableTableManager get lyricsCache =>
      $$LyricsCacheTableTableManager(_db.attachedDatabase, _db.lyricsCache);
}

mixin _$StatsDaoMixin on DatabaseAccessor<AppDatabase> {
  $SongsTable get songs => attachedDatabase.songs;
  $PlayEventsTable get playEvents => attachedDatabase.playEvents;
  $DailyStatsTable get dailyStats => attachedDatabase.dailyStats;
  StatsDaoManager get managers => StatsDaoManager(this);
}

class StatsDaoManager {
  final _$StatsDaoMixin _db;
  StatsDaoManager(this._db);
  $$SongsTableTableManager get songs =>
      $$SongsTableTableManager(_db.attachedDatabase, _db.songs);
  $$PlayEventsTableTableManager get playEvents =>
      $$PlayEventsTableTableManager(_db.attachedDatabase, _db.playEvents);
  $$DailyStatsTableTableManager get dailyStats =>
      $$DailyStatsTableTableManager(_db.attachedDatabase, _db.dailyStats);
}

mixin _$LocalTracksDaoMixin on DatabaseAccessor<AppDatabase> {
  $LocalTracksTable get localTracks => attachedDatabase.localTracks;
  LocalTracksDaoManager get managers => LocalTracksDaoManager(this);
}

class LocalTracksDaoManager {
  final _$LocalTracksDaoMixin _db;
  LocalTracksDaoManager(this._db);
  $$LocalTracksTableTableManager get localTracks =>
      $$LocalTracksTableTableManager(_db.attachedDatabase, _db.localTracks);
}

mixin _$ToplistsCacheDaoMixin on DatabaseAccessor<AppDatabase> {
  $ToplistsCacheTable get toplistsCache => attachedDatabase.toplistsCache;
  ToplistsCacheDaoManager get managers => ToplistsCacheDaoManager(this);
}

class ToplistsCacheDaoManager {
  final _$ToplistsCacheDaoMixin _db;
  ToplistsCacheDaoManager(this._db);
  $$ToplistsCacheTableTableManager get toplistsCache =>
      $$ToplistsCacheTableTableManager(_db.attachedDatabase, _db.toplistsCache);
}

mixin _$SmartPlaylistSnapshotsDaoMixin on DatabaseAccessor<AppDatabase> {
  $SmartPlaylistSnapshotsTable get smartPlaylistSnapshots =>
      attachedDatabase.smartPlaylistSnapshots;
  SmartPlaylistSnapshotsDaoManager get managers =>
      SmartPlaylistSnapshotsDaoManager(this);
}

class SmartPlaylistSnapshotsDaoManager {
  final _$SmartPlaylistSnapshotsDaoMixin _db;
  SmartPlaylistSnapshotsDaoManager(this._db);
  $$SmartPlaylistSnapshotsTableTableManager get smartPlaylistSnapshots =>
      $$SmartPlaylistSnapshotsTableTableManager(
        _db.attachedDatabase,
        _db.smartPlaylistSnapshots,
      );
}

class $SongsTable extends Songs with TableInfo<$SongsTable, SongRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SongsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _platformMeta = const VerificationMeta(
    'platform',
  );
  @override
  late final GeneratedColumn<String> platform = GeneratedColumn<String>(
    'platform',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _artistsMeta = const VerificationMeta(
    'artists',
  );
  @override
  late final GeneratedColumn<String> artists = GeneratedColumn<String>(
    'artists',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _albumNameMeta = const VerificationMeta(
    'albumName',
  );
  @override
  late final GeneratedColumn<String> albumName = GeneratedColumn<String>(
    'album_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _albumCoverMeta = const VerificationMeta(
    'albumCover',
  );
  @override
  late final GeneratedColumn<String> albumCover = GeneratedColumn<String>(
    'album_cover',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _durationMsMeta = const VerificationMeta(
    'durationMs',
  );
  @override
  late final GeneratedColumn<int> durationMs = GeneratedColumn<int>(
    'duration_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _fingerprintMeta = const VerificationMeta(
    'fingerprint',
  );
  @override
  late final GeneratedColumn<String> fingerprint = GeneratedColumn<String>(
    'fingerprint',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _albumIdMeta = const VerificationMeta(
    'albumId',
  );
  @override
  late final GeneratedColumn<String> albumId = GeneratedColumn<String>(
    'album_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _artistIdMeta = const VerificationMeta(
    'artistId',
  );
  @override
  late final GeneratedColumn<String> artistId = GeneratedColumn<String>(
    'artist_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _trackNumberMeta = const VerificationMeta(
    'trackNumber',
  );
  @override
  late final GeneratedColumn<int> trackNumber = GeneratedColumn<int>(
    'track_number',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    platform,
    name,
    artists,
    albumName,
    albumCover,
    durationMs,
    fingerprint,
    albumId,
    artistId,
    trackNumber,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'songs';
  @override
  VerificationContext validateIntegrity(
    Insertable<SongRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('platform')) {
      context.handle(
        _platformMeta,
        platform.isAcceptableOrUnknown(data['platform']!, _platformMeta),
      );
    } else if (isInserting) {
      context.missing(_platformMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('artists')) {
      context.handle(
        _artistsMeta,
        artists.isAcceptableOrUnknown(data['artists']!, _artistsMeta),
      );
    } else if (isInserting) {
      context.missing(_artistsMeta);
    }
    if (data.containsKey('album_name')) {
      context.handle(
        _albumNameMeta,
        albumName.isAcceptableOrUnknown(data['album_name']!, _albumNameMeta),
      );
    }
    if (data.containsKey('album_cover')) {
      context.handle(
        _albumCoverMeta,
        albumCover.isAcceptableOrUnknown(data['album_cover']!, _albumCoverMeta),
      );
    }
    if (data.containsKey('duration_ms')) {
      context.handle(
        _durationMsMeta,
        durationMs.isAcceptableOrUnknown(data['duration_ms']!, _durationMsMeta),
      );
    }
    if (data.containsKey('fingerprint')) {
      context.handle(
        _fingerprintMeta,
        fingerprint.isAcceptableOrUnknown(
          data['fingerprint']!,
          _fingerprintMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_fingerprintMeta);
    }
    if (data.containsKey('album_id')) {
      context.handle(
        _albumIdMeta,
        albumId.isAcceptableOrUnknown(data['album_id']!, _albumIdMeta),
      );
    }
    if (data.containsKey('artist_id')) {
      context.handle(
        _artistIdMeta,
        artistId.isAcceptableOrUnknown(data['artist_id']!, _artistIdMeta),
      );
    }
    if (data.containsKey('track_number')) {
      context.handle(
        _trackNumberMeta,
        trackNumber.isAcceptableOrUnknown(
          data['track_number']!,
          _trackNumberMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id, platform};
  @override
  SongRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SongRecord(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      platform: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}platform'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      artists: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}artists'],
      )!,
      albumName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}album_name'],
      ),
      albumCover: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}album_cover'],
      ),
      durationMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_ms'],
      )!,
      fingerprint: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}fingerprint'],
      )!,
      albumId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}album_id'],
      ),
      artistId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}artist_id'],
      ),
      trackNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}track_number'],
      ),
    );
  }

  @override
  $SongsTable createAlias(String alias) {
    return $SongsTable(attachedDatabase, alias);
  }
}

class SongRecord extends DataClass implements Insertable<SongRecord> {
  final String id;
  final String platform;
  final String name;
  final String artists;
  final String? albumName;
  final String? albumCover;
  final int durationMs;
  final String fingerprint;

  /// Owning-platform album id, so a cached song can open the album page.
  final String? albumId;

  /// Owning-platform primary artist id, so a cached song can open the artist
  /// page. Rows written before schema v2 leave this null; the UI falls back to
  /// a name search for those (see the migration notes in `docs/`).
  final String? artistId;

  /// 1-based track number inside the album.
  final int? trackNumber;
  const SongRecord({
    required this.id,
    required this.platform,
    required this.name,
    required this.artists,
    this.albumName,
    this.albumCover,
    required this.durationMs,
    required this.fingerprint,
    this.albumId,
    this.artistId,
    this.trackNumber,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['platform'] = Variable<String>(platform);
    map['name'] = Variable<String>(name);
    map['artists'] = Variable<String>(artists);
    if (!nullToAbsent || albumName != null) {
      map['album_name'] = Variable<String>(albumName);
    }
    if (!nullToAbsent || albumCover != null) {
      map['album_cover'] = Variable<String>(albumCover);
    }
    map['duration_ms'] = Variable<int>(durationMs);
    map['fingerprint'] = Variable<String>(fingerprint);
    if (!nullToAbsent || albumId != null) {
      map['album_id'] = Variable<String>(albumId);
    }
    if (!nullToAbsent || artistId != null) {
      map['artist_id'] = Variable<String>(artistId);
    }
    if (!nullToAbsent || trackNumber != null) {
      map['track_number'] = Variable<int>(trackNumber);
    }
    return map;
  }

  SongsCompanion toCompanion(bool nullToAbsent) {
    return SongsCompanion(
      id: Value(id),
      platform: Value(platform),
      name: Value(name),
      artists: Value(artists),
      albumName: albumName == null && nullToAbsent
          ? const Value.absent()
          : Value(albumName),
      albumCover: albumCover == null && nullToAbsent
          ? const Value.absent()
          : Value(albumCover),
      durationMs: Value(durationMs),
      fingerprint: Value(fingerprint),
      albumId: albumId == null && nullToAbsent
          ? const Value.absent()
          : Value(albumId),
      artistId: artistId == null && nullToAbsent
          ? const Value.absent()
          : Value(artistId),
      trackNumber: trackNumber == null && nullToAbsent
          ? const Value.absent()
          : Value(trackNumber),
    );
  }

  factory SongRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SongRecord(
      id: serializer.fromJson<String>(json['id']),
      platform: serializer.fromJson<String>(json['platform']),
      name: serializer.fromJson<String>(json['name']),
      artists: serializer.fromJson<String>(json['artists']),
      albumName: serializer.fromJson<String?>(json['albumName']),
      albumCover: serializer.fromJson<String?>(json['albumCover']),
      durationMs: serializer.fromJson<int>(json['durationMs']),
      fingerprint: serializer.fromJson<String>(json['fingerprint']),
      albumId: serializer.fromJson<String?>(json['albumId']),
      artistId: serializer.fromJson<String?>(json['artistId']),
      trackNumber: serializer.fromJson<int?>(json['trackNumber']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'platform': serializer.toJson<String>(platform),
      'name': serializer.toJson<String>(name),
      'artists': serializer.toJson<String>(artists),
      'albumName': serializer.toJson<String?>(albumName),
      'albumCover': serializer.toJson<String?>(albumCover),
      'durationMs': serializer.toJson<int>(durationMs),
      'fingerprint': serializer.toJson<String>(fingerprint),
      'albumId': serializer.toJson<String?>(albumId),
      'artistId': serializer.toJson<String?>(artistId),
      'trackNumber': serializer.toJson<int?>(trackNumber),
    };
  }

  SongRecord copyWith({
    String? id,
    String? platform,
    String? name,
    String? artists,
    Value<String?> albumName = const Value.absent(),
    Value<String?> albumCover = const Value.absent(),
    int? durationMs,
    String? fingerprint,
    Value<String?> albumId = const Value.absent(),
    Value<String?> artistId = const Value.absent(),
    Value<int?> trackNumber = const Value.absent(),
  }) => SongRecord(
    id: id ?? this.id,
    platform: platform ?? this.platform,
    name: name ?? this.name,
    artists: artists ?? this.artists,
    albumName: albumName.present ? albumName.value : this.albumName,
    albumCover: albumCover.present ? albumCover.value : this.albumCover,
    durationMs: durationMs ?? this.durationMs,
    fingerprint: fingerprint ?? this.fingerprint,
    albumId: albumId.present ? albumId.value : this.albumId,
    artistId: artistId.present ? artistId.value : this.artistId,
    trackNumber: trackNumber.present ? trackNumber.value : this.trackNumber,
  );
  SongRecord copyWithCompanion(SongsCompanion data) {
    return SongRecord(
      id: data.id.present ? data.id.value : this.id,
      platform: data.platform.present ? data.platform.value : this.platform,
      name: data.name.present ? data.name.value : this.name,
      artists: data.artists.present ? data.artists.value : this.artists,
      albumName: data.albumName.present ? data.albumName.value : this.albumName,
      albumCover: data.albumCover.present
          ? data.albumCover.value
          : this.albumCover,
      durationMs: data.durationMs.present
          ? data.durationMs.value
          : this.durationMs,
      fingerprint: data.fingerprint.present
          ? data.fingerprint.value
          : this.fingerprint,
      albumId: data.albumId.present ? data.albumId.value : this.albumId,
      artistId: data.artistId.present ? data.artistId.value : this.artistId,
      trackNumber: data.trackNumber.present
          ? data.trackNumber.value
          : this.trackNumber,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SongRecord(')
          ..write('id: $id, ')
          ..write('platform: $platform, ')
          ..write('name: $name, ')
          ..write('artists: $artists, ')
          ..write('albumName: $albumName, ')
          ..write('albumCover: $albumCover, ')
          ..write('durationMs: $durationMs, ')
          ..write('fingerprint: $fingerprint, ')
          ..write('albumId: $albumId, ')
          ..write('artistId: $artistId, ')
          ..write('trackNumber: $trackNumber')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    platform,
    name,
    artists,
    albumName,
    albumCover,
    durationMs,
    fingerprint,
    albumId,
    artistId,
    trackNumber,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SongRecord &&
          other.id == this.id &&
          other.platform == this.platform &&
          other.name == this.name &&
          other.artists == this.artists &&
          other.albumName == this.albumName &&
          other.albumCover == this.albumCover &&
          other.durationMs == this.durationMs &&
          other.fingerprint == this.fingerprint &&
          other.albumId == this.albumId &&
          other.artistId == this.artistId &&
          other.trackNumber == this.trackNumber);
}

class SongsCompanion extends UpdateCompanion<SongRecord> {
  final Value<String> id;
  final Value<String> platform;
  final Value<String> name;
  final Value<String> artists;
  final Value<String?> albumName;
  final Value<String?> albumCover;
  final Value<int> durationMs;
  final Value<String> fingerprint;
  final Value<String?> albumId;
  final Value<String?> artistId;
  final Value<int?> trackNumber;
  final Value<int> rowid;
  const SongsCompanion({
    this.id = const Value.absent(),
    this.platform = const Value.absent(),
    this.name = const Value.absent(),
    this.artists = const Value.absent(),
    this.albumName = const Value.absent(),
    this.albumCover = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.fingerprint = const Value.absent(),
    this.albumId = const Value.absent(),
    this.artistId = const Value.absent(),
    this.trackNumber = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SongsCompanion.insert({
    required String id,
    required String platform,
    required String name,
    required String artists,
    this.albumName = const Value.absent(),
    this.albumCover = const Value.absent(),
    this.durationMs = const Value.absent(),
    required String fingerprint,
    this.albumId = const Value.absent(),
    this.artistId = const Value.absent(),
    this.trackNumber = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       platform = Value(platform),
       name = Value(name),
       artists = Value(artists),
       fingerprint = Value(fingerprint);
  static Insertable<SongRecord> custom({
    Expression<String>? id,
    Expression<String>? platform,
    Expression<String>? name,
    Expression<String>? artists,
    Expression<String>? albumName,
    Expression<String>? albumCover,
    Expression<int>? durationMs,
    Expression<String>? fingerprint,
    Expression<String>? albumId,
    Expression<String>? artistId,
    Expression<int>? trackNumber,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (platform != null) 'platform': platform,
      if (name != null) 'name': name,
      if (artists != null) 'artists': artists,
      if (albumName != null) 'album_name': albumName,
      if (albumCover != null) 'album_cover': albumCover,
      if (durationMs != null) 'duration_ms': durationMs,
      if (fingerprint != null) 'fingerprint': fingerprint,
      if (albumId != null) 'album_id': albumId,
      if (artistId != null) 'artist_id': artistId,
      if (trackNumber != null) 'track_number': trackNumber,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SongsCompanion copyWith({
    Value<String>? id,
    Value<String>? platform,
    Value<String>? name,
    Value<String>? artists,
    Value<String?>? albumName,
    Value<String?>? albumCover,
    Value<int>? durationMs,
    Value<String>? fingerprint,
    Value<String?>? albumId,
    Value<String?>? artistId,
    Value<int?>? trackNumber,
    Value<int>? rowid,
  }) {
    return SongsCompanion(
      id: id ?? this.id,
      platform: platform ?? this.platform,
      name: name ?? this.name,
      artists: artists ?? this.artists,
      albumName: albumName ?? this.albumName,
      albumCover: albumCover ?? this.albumCover,
      durationMs: durationMs ?? this.durationMs,
      fingerprint: fingerprint ?? this.fingerprint,
      albumId: albumId ?? this.albumId,
      artistId: artistId ?? this.artistId,
      trackNumber: trackNumber ?? this.trackNumber,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (platform.present) {
      map['platform'] = Variable<String>(platform.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (artists.present) {
      map['artists'] = Variable<String>(artists.value);
    }
    if (albumName.present) {
      map['album_name'] = Variable<String>(albumName.value);
    }
    if (albumCover.present) {
      map['album_cover'] = Variable<String>(albumCover.value);
    }
    if (durationMs.present) {
      map['duration_ms'] = Variable<int>(durationMs.value);
    }
    if (fingerprint.present) {
      map['fingerprint'] = Variable<String>(fingerprint.value);
    }
    if (albumId.present) {
      map['album_id'] = Variable<String>(albumId.value);
    }
    if (artistId.present) {
      map['artist_id'] = Variable<String>(artistId.value);
    }
    if (trackNumber.present) {
      map['track_number'] = Variable<int>(trackNumber.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SongsCompanion(')
          ..write('id: $id, ')
          ..write('platform: $platform, ')
          ..write('name: $name, ')
          ..write('artists: $artists, ')
          ..write('albumName: $albumName, ')
          ..write('albumCover: $albumCover, ')
          ..write('durationMs: $durationMs, ')
          ..write('fingerprint: $fingerprint, ')
          ..write('albumId: $albumId, ')
          ..write('artistId: $artistId, ')
          ..write('trackNumber: $trackNumber, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ListeningHistoryTable extends ListeningHistory
    with TableInfo<$ListeningHistoryTable, ListeningHistoryEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ListeningHistoryTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _songIdMeta = const VerificationMeta('songId');
  @override
  late final GeneratedColumn<String> songId = GeneratedColumn<String>(
    'song_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _platformMeta = const VerificationMeta(
    'platform',
  );
  @override
  late final GeneratedColumn<String> platform = GeneratedColumn<String>(
    'platform',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _listenedAtMeta = const VerificationMeta(
    'listenedAt',
  );
  @override
  late final GeneratedColumn<int> listenedAt = GeneratedColumn<int>(
    'listened_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _durationListenedMeta = const VerificationMeta(
    'durationListened',
  );
  @override
  late final GeneratedColumn<int> durationListened = GeneratedColumn<int>(
    'duration_listened',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    songId,
    platform,
    listenedAt,
    durationListened,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'listening_history';
  @override
  VerificationContext validateIntegrity(
    Insertable<ListeningHistoryEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('song_id')) {
      context.handle(
        _songIdMeta,
        songId.isAcceptableOrUnknown(data['song_id']!, _songIdMeta),
      );
    } else if (isInserting) {
      context.missing(_songIdMeta);
    }
    if (data.containsKey('platform')) {
      context.handle(
        _platformMeta,
        platform.isAcceptableOrUnknown(data['platform']!, _platformMeta),
      );
    } else if (isInserting) {
      context.missing(_platformMeta);
    }
    if (data.containsKey('listened_at')) {
      context.handle(
        _listenedAtMeta,
        listenedAt.isAcceptableOrUnknown(data['listened_at']!, _listenedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_listenedAtMeta);
    }
    if (data.containsKey('duration_listened')) {
      context.handle(
        _durationListenedMeta,
        durationListened.isAcceptableOrUnknown(
          data['duration_listened']!,
          _durationListenedMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {songId, platform, listenedAt},
  ];
  @override
  ListeningHistoryEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ListeningHistoryEntry(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      songId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}song_id'],
      )!,
      platform: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}platform'],
      )!,
      listenedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}listened_at'],
      )!,
      durationListened: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_listened'],
      )!,
    );
  }

  @override
  $ListeningHistoryTable createAlias(String alias) {
    return $ListeningHistoryTable(attachedDatabase, alias);
  }
}

class ListeningHistoryEntry extends DataClass
    implements Insertable<ListeningHistoryEntry> {
  final int id;
  final String songId;
  final String platform;
  final int listenedAt;
  final int durationListened;
  const ListeningHistoryEntry({
    required this.id,
    required this.songId,
    required this.platform,
    required this.listenedAt,
    required this.durationListened,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['song_id'] = Variable<String>(songId);
    map['platform'] = Variable<String>(platform);
    map['listened_at'] = Variable<int>(listenedAt);
    map['duration_listened'] = Variable<int>(durationListened);
    return map;
  }

  ListeningHistoryCompanion toCompanion(bool nullToAbsent) {
    return ListeningHistoryCompanion(
      id: Value(id),
      songId: Value(songId),
      platform: Value(platform),
      listenedAt: Value(listenedAt),
      durationListened: Value(durationListened),
    );
  }

  factory ListeningHistoryEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ListeningHistoryEntry(
      id: serializer.fromJson<int>(json['id']),
      songId: serializer.fromJson<String>(json['songId']),
      platform: serializer.fromJson<String>(json['platform']),
      listenedAt: serializer.fromJson<int>(json['listenedAt']),
      durationListened: serializer.fromJson<int>(json['durationListened']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'songId': serializer.toJson<String>(songId),
      'platform': serializer.toJson<String>(platform),
      'listenedAt': serializer.toJson<int>(listenedAt),
      'durationListened': serializer.toJson<int>(durationListened),
    };
  }

  ListeningHistoryEntry copyWith({
    int? id,
    String? songId,
    String? platform,
    int? listenedAt,
    int? durationListened,
  }) => ListeningHistoryEntry(
    id: id ?? this.id,
    songId: songId ?? this.songId,
    platform: platform ?? this.platform,
    listenedAt: listenedAt ?? this.listenedAt,
    durationListened: durationListened ?? this.durationListened,
  );
  ListeningHistoryEntry copyWithCompanion(ListeningHistoryCompanion data) {
    return ListeningHistoryEntry(
      id: data.id.present ? data.id.value : this.id,
      songId: data.songId.present ? data.songId.value : this.songId,
      platform: data.platform.present ? data.platform.value : this.platform,
      listenedAt: data.listenedAt.present
          ? data.listenedAt.value
          : this.listenedAt,
      durationListened: data.durationListened.present
          ? data.durationListened.value
          : this.durationListened,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ListeningHistoryEntry(')
          ..write('id: $id, ')
          ..write('songId: $songId, ')
          ..write('platform: $platform, ')
          ..write('listenedAt: $listenedAt, ')
          ..write('durationListened: $durationListened')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, songId, platform, listenedAt, durationListened);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ListeningHistoryEntry &&
          other.id == this.id &&
          other.songId == this.songId &&
          other.platform == this.platform &&
          other.listenedAt == this.listenedAt &&
          other.durationListened == this.durationListened);
}

class ListeningHistoryCompanion extends UpdateCompanion<ListeningHistoryEntry> {
  final Value<int> id;
  final Value<String> songId;
  final Value<String> platform;
  final Value<int> listenedAt;
  final Value<int> durationListened;
  const ListeningHistoryCompanion({
    this.id = const Value.absent(),
    this.songId = const Value.absent(),
    this.platform = const Value.absent(),
    this.listenedAt = const Value.absent(),
    this.durationListened = const Value.absent(),
  });
  ListeningHistoryCompanion.insert({
    this.id = const Value.absent(),
    required String songId,
    required String platform,
    required int listenedAt,
    this.durationListened = const Value.absent(),
  }) : songId = Value(songId),
       platform = Value(platform),
       listenedAt = Value(listenedAt);
  static Insertable<ListeningHistoryEntry> custom({
    Expression<int>? id,
    Expression<String>? songId,
    Expression<String>? platform,
    Expression<int>? listenedAt,
    Expression<int>? durationListened,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (songId != null) 'song_id': songId,
      if (platform != null) 'platform': platform,
      if (listenedAt != null) 'listened_at': listenedAt,
      if (durationListened != null) 'duration_listened': durationListened,
    });
  }

  ListeningHistoryCompanion copyWith({
    Value<int>? id,
    Value<String>? songId,
    Value<String>? platform,
    Value<int>? listenedAt,
    Value<int>? durationListened,
  }) {
    return ListeningHistoryCompanion(
      id: id ?? this.id,
      songId: songId ?? this.songId,
      platform: platform ?? this.platform,
      listenedAt: listenedAt ?? this.listenedAt,
      durationListened: durationListened ?? this.durationListened,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (songId.present) {
      map['song_id'] = Variable<String>(songId.value);
    }
    if (platform.present) {
      map['platform'] = Variable<String>(platform.value);
    }
    if (listenedAt.present) {
      map['listened_at'] = Variable<int>(listenedAt.value);
    }
    if (durationListened.present) {
      map['duration_listened'] = Variable<int>(durationListened.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ListeningHistoryCompanion(')
          ..write('id: $id, ')
          ..write('songId: $songId, ')
          ..write('platform: $platform, ')
          ..write('listenedAt: $listenedAt, ')
          ..write('durationListened: $durationListened')
          ..write(')'))
        .toString();
  }
}

class $UserLikesTable extends UserLikes
    with TableInfo<$UserLikesTable, UserLike> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $UserLikesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _songIdMeta = const VerificationMeta('songId');
  @override
  late final GeneratedColumn<String> songId = GeneratedColumn<String>(
    'song_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _platformMeta = const VerificationMeta(
    'platform',
  );
  @override
  late final GeneratedColumn<String> platform = GeneratedColumn<String>(
    'platform',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _addedAtMeta = const VerificationMeta(
    'addedAt',
  );
  @override
  late final GeneratedColumn<int> addedAt = GeneratedColumn<int>(
    'added_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, songId, platform, addedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'user_likes';
  @override
  VerificationContext validateIntegrity(
    Insertable<UserLike> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('song_id')) {
      context.handle(
        _songIdMeta,
        songId.isAcceptableOrUnknown(data['song_id']!, _songIdMeta),
      );
    } else if (isInserting) {
      context.missing(_songIdMeta);
    }
    if (data.containsKey('platform')) {
      context.handle(
        _platformMeta,
        platform.isAcceptableOrUnknown(data['platform']!, _platformMeta),
      );
    } else if (isInserting) {
      context.missing(_platformMeta);
    }
    if (data.containsKey('added_at')) {
      context.handle(
        _addedAtMeta,
        addedAt.isAcceptableOrUnknown(data['added_at']!, _addedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_addedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {songId, platform},
  ];
  @override
  UserLike map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return UserLike(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      songId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}song_id'],
      )!,
      platform: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}platform'],
      )!,
      addedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}added_at'],
      )!,
    );
  }

  @override
  $UserLikesTable createAlias(String alias) {
    return $UserLikesTable(attachedDatabase, alias);
  }
}

class UserLike extends DataClass implements Insertable<UserLike> {
  final int id;
  final String songId;
  final String platform;
  final int addedAt;
  const UserLike({
    required this.id,
    required this.songId,
    required this.platform,
    required this.addedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['song_id'] = Variable<String>(songId);
    map['platform'] = Variable<String>(platform);
    map['added_at'] = Variable<int>(addedAt);
    return map;
  }

  UserLikesCompanion toCompanion(bool nullToAbsent) {
    return UserLikesCompanion(
      id: Value(id),
      songId: Value(songId),
      platform: Value(platform),
      addedAt: Value(addedAt),
    );
  }

  factory UserLike.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return UserLike(
      id: serializer.fromJson<int>(json['id']),
      songId: serializer.fromJson<String>(json['songId']),
      platform: serializer.fromJson<String>(json['platform']),
      addedAt: serializer.fromJson<int>(json['addedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'songId': serializer.toJson<String>(songId),
      'platform': serializer.toJson<String>(platform),
      'addedAt': serializer.toJson<int>(addedAt),
    };
  }

  UserLike copyWith({
    int? id,
    String? songId,
    String? platform,
    int? addedAt,
  }) => UserLike(
    id: id ?? this.id,
    songId: songId ?? this.songId,
    platform: platform ?? this.platform,
    addedAt: addedAt ?? this.addedAt,
  );
  UserLike copyWithCompanion(UserLikesCompanion data) {
    return UserLike(
      id: data.id.present ? data.id.value : this.id,
      songId: data.songId.present ? data.songId.value : this.songId,
      platform: data.platform.present ? data.platform.value : this.platform,
      addedAt: data.addedAt.present ? data.addedAt.value : this.addedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('UserLike(')
          ..write('id: $id, ')
          ..write('songId: $songId, ')
          ..write('platform: $platform, ')
          ..write('addedAt: $addedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, songId, platform, addedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is UserLike &&
          other.id == this.id &&
          other.songId == this.songId &&
          other.platform == this.platform &&
          other.addedAt == this.addedAt);
}

class UserLikesCompanion extends UpdateCompanion<UserLike> {
  final Value<int> id;
  final Value<String> songId;
  final Value<String> platform;
  final Value<int> addedAt;
  const UserLikesCompanion({
    this.id = const Value.absent(),
    this.songId = const Value.absent(),
    this.platform = const Value.absent(),
    this.addedAt = const Value.absent(),
  });
  UserLikesCompanion.insert({
    this.id = const Value.absent(),
    required String songId,
    required String platform,
    required int addedAt,
  }) : songId = Value(songId),
       platform = Value(platform),
       addedAt = Value(addedAt);
  static Insertable<UserLike> custom({
    Expression<int>? id,
    Expression<String>? songId,
    Expression<String>? platform,
    Expression<int>? addedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (songId != null) 'song_id': songId,
      if (platform != null) 'platform': platform,
      if (addedAt != null) 'added_at': addedAt,
    });
  }

  UserLikesCompanion copyWith({
    Value<int>? id,
    Value<String>? songId,
    Value<String>? platform,
    Value<int>? addedAt,
  }) {
    return UserLikesCompanion(
      id: id ?? this.id,
      songId: songId ?? this.songId,
      platform: platform ?? this.platform,
      addedAt: addedAt ?? this.addedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (songId.present) {
      map['song_id'] = Variable<String>(songId.value);
    }
    if (platform.present) {
      map['platform'] = Variable<String>(platform.value);
    }
    if (addedAt.present) {
      map['added_at'] = Variable<int>(addedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('UserLikesCompanion(')
          ..write('id: $id, ')
          ..write('songId: $songId, ')
          ..write('platform: $platform, ')
          ..write('addedAt: $addedAt')
          ..write(')'))
        .toString();
  }
}

class $LyricsCacheTable extends LyricsCache
    with TableInfo<$LyricsCacheTable, LyricsCacheData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LyricsCacheTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _songIdMeta = const VerificationMeta('songId');
  @override
  late final GeneratedColumn<String> songId = GeneratedColumn<String>(
    'song_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _platformMeta = const VerificationMeta(
    'platform',
  );
  @override
  late final GeneratedColumn<String> platform = GeneratedColumn<String>(
    'platform',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _contentMeta = const VerificationMeta(
    'content',
  );
  @override
  late final GeneratedColumn<String> content = GeneratedColumn<String>(
    'content',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _formatMeta = const VerificationMeta('format');
  @override
  late final GeneratedColumn<String> format = GeneratedColumn<String>(
    'format',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _syncedAtMeta = const VerificationMeta(
    'syncedAt',
  );
  @override
  late final GeneratedColumn<int> syncedAt = GeneratedColumn<int>(
    'synced_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    songId,
    platform,
    content,
    format,
    syncedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'lyrics_cache';
  @override
  VerificationContext validateIntegrity(
    Insertable<LyricsCacheData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('song_id')) {
      context.handle(
        _songIdMeta,
        songId.isAcceptableOrUnknown(data['song_id']!, _songIdMeta),
      );
    } else if (isInserting) {
      context.missing(_songIdMeta);
    }
    if (data.containsKey('platform')) {
      context.handle(
        _platformMeta,
        platform.isAcceptableOrUnknown(data['platform']!, _platformMeta),
      );
    } else if (isInserting) {
      context.missing(_platformMeta);
    }
    if (data.containsKey('content')) {
      context.handle(
        _contentMeta,
        content.isAcceptableOrUnknown(data['content']!, _contentMeta),
      );
    } else if (isInserting) {
      context.missing(_contentMeta);
    }
    if (data.containsKey('format')) {
      context.handle(
        _formatMeta,
        format.isAcceptableOrUnknown(data['format']!, _formatMeta),
      );
    } else if (isInserting) {
      context.missing(_formatMeta);
    }
    if (data.containsKey('synced_at')) {
      context.handle(
        _syncedAtMeta,
        syncedAt.isAcceptableOrUnknown(data['synced_at']!, _syncedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_syncedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {songId, platform};
  @override
  LyricsCacheData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LyricsCacheData(
      songId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}song_id'],
      )!,
      platform: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}platform'],
      )!,
      content: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content'],
      )!,
      format: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}format'],
      )!,
      syncedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}synced_at'],
      )!,
    );
  }

  @override
  $LyricsCacheTable createAlias(String alias) {
    return $LyricsCacheTable(attachedDatabase, alias);
  }
}

class LyricsCacheData extends DataClass implements Insertable<LyricsCacheData> {
  final String songId;
  final String platform;
  final String content;
  final String format;
  final int syncedAt;
  const LyricsCacheData({
    required this.songId,
    required this.platform,
    required this.content,
    required this.format,
    required this.syncedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['song_id'] = Variable<String>(songId);
    map['platform'] = Variable<String>(platform);
    map['content'] = Variable<String>(content);
    map['format'] = Variable<String>(format);
    map['synced_at'] = Variable<int>(syncedAt);
    return map;
  }

  LyricsCacheCompanion toCompanion(bool nullToAbsent) {
    return LyricsCacheCompanion(
      songId: Value(songId),
      platform: Value(platform),
      content: Value(content),
      format: Value(format),
      syncedAt: Value(syncedAt),
    );
  }

  factory LyricsCacheData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LyricsCacheData(
      songId: serializer.fromJson<String>(json['songId']),
      platform: serializer.fromJson<String>(json['platform']),
      content: serializer.fromJson<String>(json['content']),
      format: serializer.fromJson<String>(json['format']),
      syncedAt: serializer.fromJson<int>(json['syncedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'songId': serializer.toJson<String>(songId),
      'platform': serializer.toJson<String>(platform),
      'content': serializer.toJson<String>(content),
      'format': serializer.toJson<String>(format),
      'syncedAt': serializer.toJson<int>(syncedAt),
    };
  }

  LyricsCacheData copyWith({
    String? songId,
    String? platform,
    String? content,
    String? format,
    int? syncedAt,
  }) => LyricsCacheData(
    songId: songId ?? this.songId,
    platform: platform ?? this.platform,
    content: content ?? this.content,
    format: format ?? this.format,
    syncedAt: syncedAt ?? this.syncedAt,
  );
  LyricsCacheData copyWithCompanion(LyricsCacheCompanion data) {
    return LyricsCacheData(
      songId: data.songId.present ? data.songId.value : this.songId,
      platform: data.platform.present ? data.platform.value : this.platform,
      content: data.content.present ? data.content.value : this.content,
      format: data.format.present ? data.format.value : this.format,
      syncedAt: data.syncedAt.present ? data.syncedAt.value : this.syncedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LyricsCacheData(')
          ..write('songId: $songId, ')
          ..write('platform: $platform, ')
          ..write('content: $content, ')
          ..write('format: $format, ')
          ..write('syncedAt: $syncedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(songId, platform, content, format, syncedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LyricsCacheData &&
          other.songId == this.songId &&
          other.platform == this.platform &&
          other.content == this.content &&
          other.format == this.format &&
          other.syncedAt == this.syncedAt);
}

class LyricsCacheCompanion extends UpdateCompanion<LyricsCacheData> {
  final Value<String> songId;
  final Value<String> platform;
  final Value<String> content;
  final Value<String> format;
  final Value<int> syncedAt;
  final Value<int> rowid;
  const LyricsCacheCompanion({
    this.songId = const Value.absent(),
    this.platform = const Value.absent(),
    this.content = const Value.absent(),
    this.format = const Value.absent(),
    this.syncedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LyricsCacheCompanion.insert({
    required String songId,
    required String platform,
    required String content,
    required String format,
    required int syncedAt,
    this.rowid = const Value.absent(),
  }) : songId = Value(songId),
       platform = Value(platform),
       content = Value(content),
       format = Value(format),
       syncedAt = Value(syncedAt);
  static Insertable<LyricsCacheData> custom({
    Expression<String>? songId,
    Expression<String>? platform,
    Expression<String>? content,
    Expression<String>? format,
    Expression<int>? syncedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (songId != null) 'song_id': songId,
      if (platform != null) 'platform': platform,
      if (content != null) 'content': content,
      if (format != null) 'format': format,
      if (syncedAt != null) 'synced_at': syncedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LyricsCacheCompanion copyWith({
    Value<String>? songId,
    Value<String>? platform,
    Value<String>? content,
    Value<String>? format,
    Value<int>? syncedAt,
    Value<int>? rowid,
  }) {
    return LyricsCacheCompanion(
      songId: songId ?? this.songId,
      platform: platform ?? this.platform,
      content: content ?? this.content,
      format: format ?? this.format,
      syncedAt: syncedAt ?? this.syncedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (songId.present) {
      map['song_id'] = Variable<String>(songId.value);
    }
    if (platform.present) {
      map['platform'] = Variable<String>(platform.value);
    }
    if (content.present) {
      map['content'] = Variable<String>(content.value);
    }
    if (format.present) {
      map['format'] = Variable<String>(format.value);
    }
    if (syncedAt.present) {
      map['synced_at'] = Variable<int>(syncedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LyricsCacheCompanion(')
          ..write('songId: $songId, ')
          ..write('platform: $platform, ')
          ..write('content: $content, ')
          ..write('format: $format, ')
          ..write('syncedAt: $syncedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalTracksTable extends LocalTracks
    with TableInfo<$LocalTracksTable, LocalTrack> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalTracksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _pathMeta = const VerificationMeta('path');
  @override
  late final GeneratedColumn<String> path = GeneratedColumn<String>(
    'path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _mtimeMeta = const VerificationMeta('mtime');
  @override
  late final GeneratedColumn<int> mtime = GeneratedColumn<int>(
    'mtime',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sizeMeta = const VerificationMeta('size');
  @override
  late final GeneratedColumn<int> size = GeneratedColumn<int>(
    'size',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _artistNameMeta = const VerificationMeta(
    'artistName',
  );
  @override
  late final GeneratedColumn<String> artistName = GeneratedColumn<String>(
    'artist_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _albumNameMeta = const VerificationMeta(
    'albumName',
  );
  @override
  late final GeneratedColumn<String> albumName = GeneratedColumn<String>(
    'album_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _durationMsMeta = const VerificationMeta(
    'durationMs',
  );
  @override
  late final GeneratedColumn<int> durationMs = GeneratedColumn<int>(
    'duration_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _trackNumberMeta = const VerificationMeta(
    'trackNumber',
  );
  @override
  late final GeneratedColumn<int> trackNumber = GeneratedColumn<int>(
    'track_number',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _coverPathMeta = const VerificationMeta(
    'coverPath',
  );
  @override
  late final GeneratedColumn<String> coverPath = GeneratedColumn<String>(
    'cover_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _scannedAtMeta = const VerificationMeta(
    'scannedAt',
  );
  @override
  late final GeneratedColumn<int> scannedAt = GeneratedColumn<int>(
    'scanned_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    path,
    mtime,
    size,
    title,
    artistName,
    albumName,
    durationMs,
    trackNumber,
    coverPath,
    scannedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_tracks';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalTrack> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('path')) {
      context.handle(
        _pathMeta,
        path.isAcceptableOrUnknown(data['path']!, _pathMeta),
      );
    } else if (isInserting) {
      context.missing(_pathMeta);
    }
    if (data.containsKey('mtime')) {
      context.handle(
        _mtimeMeta,
        mtime.isAcceptableOrUnknown(data['mtime']!, _mtimeMeta),
      );
    } else if (isInserting) {
      context.missing(_mtimeMeta);
    }
    if (data.containsKey('size')) {
      context.handle(
        _sizeMeta,
        size.isAcceptableOrUnknown(data['size']!, _sizeMeta),
      );
    } else if (isInserting) {
      context.missing(_sizeMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    }
    if (data.containsKey('artist_name')) {
      context.handle(
        _artistNameMeta,
        artistName.isAcceptableOrUnknown(data['artist_name']!, _artistNameMeta),
      );
    }
    if (data.containsKey('album_name')) {
      context.handle(
        _albumNameMeta,
        albumName.isAcceptableOrUnknown(data['album_name']!, _albumNameMeta),
      );
    }
    if (data.containsKey('duration_ms')) {
      context.handle(
        _durationMsMeta,
        durationMs.isAcceptableOrUnknown(data['duration_ms']!, _durationMsMeta),
      );
    }
    if (data.containsKey('track_number')) {
      context.handle(
        _trackNumberMeta,
        trackNumber.isAcceptableOrUnknown(
          data['track_number']!,
          _trackNumberMeta,
        ),
      );
    }
    if (data.containsKey('cover_path')) {
      context.handle(
        _coverPathMeta,
        coverPath.isAcceptableOrUnknown(data['cover_path']!, _coverPathMeta),
      );
    }
    if (data.containsKey('scanned_at')) {
      context.handle(
        _scannedAtMeta,
        scannedAt.isAcceptableOrUnknown(data['scanned_at']!, _scannedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {path};
  @override
  LocalTrack map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalTrack(
      path: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}path'],
      )!,
      mtime: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}mtime'],
      )!,
      size: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}size'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      ),
      artistName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}artist_name'],
      ),
      albumName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}album_name'],
      ),
      durationMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_ms'],
      )!,
      trackNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}track_number'],
      ),
      coverPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cover_path'],
      ),
      scannedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}scanned_at'],
      ),
    );
  }

  @override
  $LocalTracksTable createAlias(String alias) {
    return $LocalTracksTable(attachedDatabase, alias);
  }
}

class LocalTrack extends DataClass implements Insertable<LocalTrack> {
  final String path;
  final int mtime;
  final int size;
  final String? title;
  final String? artistName;
  final String? albumName;
  final int durationMs;
  final int? trackNumber;
  final String? coverPath;
  final int? scannedAt;
  const LocalTrack({
    required this.path,
    required this.mtime,
    required this.size,
    this.title,
    this.artistName,
    this.albumName,
    required this.durationMs,
    this.trackNumber,
    this.coverPath,
    this.scannedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['path'] = Variable<String>(path);
    map['mtime'] = Variable<int>(mtime);
    map['size'] = Variable<int>(size);
    if (!nullToAbsent || title != null) {
      map['title'] = Variable<String>(title);
    }
    if (!nullToAbsent || artistName != null) {
      map['artist_name'] = Variable<String>(artistName);
    }
    if (!nullToAbsent || albumName != null) {
      map['album_name'] = Variable<String>(albumName);
    }
    map['duration_ms'] = Variable<int>(durationMs);
    if (!nullToAbsent || trackNumber != null) {
      map['track_number'] = Variable<int>(trackNumber);
    }
    if (!nullToAbsent || coverPath != null) {
      map['cover_path'] = Variable<String>(coverPath);
    }
    if (!nullToAbsent || scannedAt != null) {
      map['scanned_at'] = Variable<int>(scannedAt);
    }
    return map;
  }

  LocalTracksCompanion toCompanion(bool nullToAbsent) {
    return LocalTracksCompanion(
      path: Value(path),
      mtime: Value(mtime),
      size: Value(size),
      title: title == null && nullToAbsent
          ? const Value.absent()
          : Value(title),
      artistName: artistName == null && nullToAbsent
          ? const Value.absent()
          : Value(artistName),
      albumName: albumName == null && nullToAbsent
          ? const Value.absent()
          : Value(albumName),
      durationMs: Value(durationMs),
      trackNumber: trackNumber == null && nullToAbsent
          ? const Value.absent()
          : Value(trackNumber),
      coverPath: coverPath == null && nullToAbsent
          ? const Value.absent()
          : Value(coverPath),
      scannedAt: scannedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(scannedAt),
    );
  }

  factory LocalTrack.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalTrack(
      path: serializer.fromJson<String>(json['path']),
      mtime: serializer.fromJson<int>(json['mtime']),
      size: serializer.fromJson<int>(json['size']),
      title: serializer.fromJson<String?>(json['title']),
      artistName: serializer.fromJson<String?>(json['artistName']),
      albumName: serializer.fromJson<String?>(json['albumName']),
      durationMs: serializer.fromJson<int>(json['durationMs']),
      trackNumber: serializer.fromJson<int?>(json['trackNumber']),
      coverPath: serializer.fromJson<String?>(json['coverPath']),
      scannedAt: serializer.fromJson<int?>(json['scannedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'path': serializer.toJson<String>(path),
      'mtime': serializer.toJson<int>(mtime),
      'size': serializer.toJson<int>(size),
      'title': serializer.toJson<String?>(title),
      'artistName': serializer.toJson<String?>(artistName),
      'albumName': serializer.toJson<String?>(albumName),
      'durationMs': serializer.toJson<int>(durationMs),
      'trackNumber': serializer.toJson<int?>(trackNumber),
      'coverPath': serializer.toJson<String?>(coverPath),
      'scannedAt': serializer.toJson<int?>(scannedAt),
    };
  }

  LocalTrack copyWith({
    String? path,
    int? mtime,
    int? size,
    Value<String?> title = const Value.absent(),
    Value<String?> artistName = const Value.absent(),
    Value<String?> albumName = const Value.absent(),
    int? durationMs,
    Value<int?> trackNumber = const Value.absent(),
    Value<String?> coverPath = const Value.absent(),
    Value<int?> scannedAt = const Value.absent(),
  }) => LocalTrack(
    path: path ?? this.path,
    mtime: mtime ?? this.mtime,
    size: size ?? this.size,
    title: title.present ? title.value : this.title,
    artistName: artistName.present ? artistName.value : this.artistName,
    albumName: albumName.present ? albumName.value : this.albumName,
    durationMs: durationMs ?? this.durationMs,
    trackNumber: trackNumber.present ? trackNumber.value : this.trackNumber,
    coverPath: coverPath.present ? coverPath.value : this.coverPath,
    scannedAt: scannedAt.present ? scannedAt.value : this.scannedAt,
  );
  LocalTrack copyWithCompanion(LocalTracksCompanion data) {
    return LocalTrack(
      path: data.path.present ? data.path.value : this.path,
      mtime: data.mtime.present ? data.mtime.value : this.mtime,
      size: data.size.present ? data.size.value : this.size,
      title: data.title.present ? data.title.value : this.title,
      artistName: data.artistName.present
          ? data.artistName.value
          : this.artistName,
      albumName: data.albumName.present ? data.albumName.value : this.albumName,
      durationMs: data.durationMs.present
          ? data.durationMs.value
          : this.durationMs,
      trackNumber: data.trackNumber.present
          ? data.trackNumber.value
          : this.trackNumber,
      coverPath: data.coverPath.present ? data.coverPath.value : this.coverPath,
      scannedAt: data.scannedAt.present ? data.scannedAt.value : this.scannedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalTrack(')
          ..write('path: $path, ')
          ..write('mtime: $mtime, ')
          ..write('size: $size, ')
          ..write('title: $title, ')
          ..write('artistName: $artistName, ')
          ..write('albumName: $albumName, ')
          ..write('durationMs: $durationMs, ')
          ..write('trackNumber: $trackNumber, ')
          ..write('coverPath: $coverPath, ')
          ..write('scannedAt: $scannedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    path,
    mtime,
    size,
    title,
    artistName,
    albumName,
    durationMs,
    trackNumber,
    coverPath,
    scannedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalTrack &&
          other.path == this.path &&
          other.mtime == this.mtime &&
          other.size == this.size &&
          other.title == this.title &&
          other.artistName == this.artistName &&
          other.albumName == this.albumName &&
          other.durationMs == this.durationMs &&
          other.trackNumber == this.trackNumber &&
          other.coverPath == this.coverPath &&
          other.scannedAt == this.scannedAt);
}

class LocalTracksCompanion extends UpdateCompanion<LocalTrack> {
  final Value<String> path;
  final Value<int> mtime;
  final Value<int> size;
  final Value<String?> title;
  final Value<String?> artistName;
  final Value<String?> albumName;
  final Value<int> durationMs;
  final Value<int?> trackNumber;
  final Value<String?> coverPath;
  final Value<int?> scannedAt;
  final Value<int> rowid;
  const LocalTracksCompanion({
    this.path = const Value.absent(),
    this.mtime = const Value.absent(),
    this.size = const Value.absent(),
    this.title = const Value.absent(),
    this.artistName = const Value.absent(),
    this.albumName = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.trackNumber = const Value.absent(),
    this.coverPath = const Value.absent(),
    this.scannedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalTracksCompanion.insert({
    required String path,
    required int mtime,
    required int size,
    this.title = const Value.absent(),
    this.artistName = const Value.absent(),
    this.albumName = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.trackNumber = const Value.absent(),
    this.coverPath = const Value.absent(),
    this.scannedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : path = Value(path),
       mtime = Value(mtime),
       size = Value(size);
  static Insertable<LocalTrack> custom({
    Expression<String>? path,
    Expression<int>? mtime,
    Expression<int>? size,
    Expression<String>? title,
    Expression<String>? artistName,
    Expression<String>? albumName,
    Expression<int>? durationMs,
    Expression<int>? trackNumber,
    Expression<String>? coverPath,
    Expression<int>? scannedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (path != null) 'path': path,
      if (mtime != null) 'mtime': mtime,
      if (size != null) 'size': size,
      if (title != null) 'title': title,
      if (artistName != null) 'artist_name': artistName,
      if (albumName != null) 'album_name': albumName,
      if (durationMs != null) 'duration_ms': durationMs,
      if (trackNumber != null) 'track_number': trackNumber,
      if (coverPath != null) 'cover_path': coverPath,
      if (scannedAt != null) 'scanned_at': scannedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalTracksCompanion copyWith({
    Value<String>? path,
    Value<int>? mtime,
    Value<int>? size,
    Value<String?>? title,
    Value<String?>? artistName,
    Value<String?>? albumName,
    Value<int>? durationMs,
    Value<int?>? trackNumber,
    Value<String?>? coverPath,
    Value<int?>? scannedAt,
    Value<int>? rowid,
  }) {
    return LocalTracksCompanion(
      path: path ?? this.path,
      mtime: mtime ?? this.mtime,
      size: size ?? this.size,
      title: title ?? this.title,
      artistName: artistName ?? this.artistName,
      albumName: albumName ?? this.albumName,
      durationMs: durationMs ?? this.durationMs,
      trackNumber: trackNumber ?? this.trackNumber,
      coverPath: coverPath ?? this.coverPath,
      scannedAt: scannedAt ?? this.scannedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (path.present) {
      map['path'] = Variable<String>(path.value);
    }
    if (mtime.present) {
      map['mtime'] = Variable<int>(mtime.value);
    }
    if (size.present) {
      map['size'] = Variable<int>(size.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (artistName.present) {
      map['artist_name'] = Variable<String>(artistName.value);
    }
    if (albumName.present) {
      map['album_name'] = Variable<String>(albumName.value);
    }
    if (durationMs.present) {
      map['duration_ms'] = Variable<int>(durationMs.value);
    }
    if (trackNumber.present) {
      map['track_number'] = Variable<int>(trackNumber.value);
    }
    if (coverPath.present) {
      map['cover_path'] = Variable<String>(coverPath.value);
    }
    if (scannedAt.present) {
      map['scanned_at'] = Variable<int>(scannedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalTracksCompanion(')
          ..write('path: $path, ')
          ..write('mtime: $mtime, ')
          ..write('size: $size, ')
          ..write('title: $title, ')
          ..write('artistName: $artistName, ')
          ..write('albumName: $albumName, ')
          ..write('durationMs: $durationMs, ')
          ..write('trackNumber: $trackNumber, ')
          ..write('coverPath: $coverPath, ')
          ..write('scannedAt: $scannedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ToplistsCacheTable extends ToplistsCache
    with TableInfo<$ToplistsCacheTable, ToplistCacheRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ToplistsCacheTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _platformMeta = const VerificationMeta(
    'platform',
  );
  @override
  late final GeneratedColumn<String> platform = GeneratedColumn<String>(
    'platform',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _toplistIdMeta = const VerificationMeta(
    'toplistId',
  );
  @override
  late final GeneratedColumn<String> toplistId = GeneratedColumn<String>(
    'toplist_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _coverUrlMeta = const VerificationMeta(
    'coverUrl',
  );
  @override
  late final GeneratedColumn<String> coverUrl = GeneratedColumn<String>(
    'cover_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _updateFrequencyMeta = const VerificationMeta(
    'updateFrequency',
  );
  @override
  late final GeneratedColumn<String> updateFrequency = GeneratedColumn<String>(
    'update_frequency',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _periodMeta = const VerificationMeta('period');
  @override
  late final GeneratedColumn<String> period = GeneratedColumn<String>(
    'period',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _songCountMeta = const VerificationMeta(
    'songCount',
  );
  @override
  late final GeneratedColumn<int> songCount = GeneratedColumn<int>(
    'song_count',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _groupNameMeta = const VerificationMeta(
    'groupName',
  );
  @override
  late final GeneratedColumn<String> groupName = GeneratedColumn<String>(
    'group_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _introMeta = const VerificationMeta('intro');
  @override
  late final GeneratedColumn<String> intro = GeneratedColumn<String>(
    'intro',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _fetchedAtMeta = const VerificationMeta(
    'fetchedAt',
  );
  @override
  late final GeneratedColumn<int> fetchedAt = GeneratedColumn<int>(
    'fetched_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    platform,
    toplistId,
    name,
    coverUrl,
    updateFrequency,
    period,
    songCount,
    groupName,
    intro,
    fetchedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'toplists_cache';
  @override
  VerificationContext validateIntegrity(
    Insertable<ToplistCacheRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('platform')) {
      context.handle(
        _platformMeta,
        platform.isAcceptableOrUnknown(data['platform']!, _platformMeta),
      );
    } else if (isInserting) {
      context.missing(_platformMeta);
    }
    if (data.containsKey('toplist_id')) {
      context.handle(
        _toplistIdMeta,
        toplistId.isAcceptableOrUnknown(data['toplist_id']!, _toplistIdMeta),
      );
    } else if (isInserting) {
      context.missing(_toplistIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('cover_url')) {
      context.handle(
        _coverUrlMeta,
        coverUrl.isAcceptableOrUnknown(data['cover_url']!, _coverUrlMeta),
      );
    }
    if (data.containsKey('update_frequency')) {
      context.handle(
        _updateFrequencyMeta,
        updateFrequency.isAcceptableOrUnknown(
          data['update_frequency']!,
          _updateFrequencyMeta,
        ),
      );
    }
    if (data.containsKey('period')) {
      context.handle(
        _periodMeta,
        period.isAcceptableOrUnknown(data['period']!, _periodMeta),
      );
    }
    if (data.containsKey('song_count')) {
      context.handle(
        _songCountMeta,
        songCount.isAcceptableOrUnknown(data['song_count']!, _songCountMeta),
      );
    }
    if (data.containsKey('group_name')) {
      context.handle(
        _groupNameMeta,
        groupName.isAcceptableOrUnknown(data['group_name']!, _groupNameMeta),
      );
    }
    if (data.containsKey('intro')) {
      context.handle(
        _introMeta,
        intro.isAcceptableOrUnknown(data['intro']!, _introMeta),
      );
    }
    if (data.containsKey('fetched_at')) {
      context.handle(
        _fetchedAtMeta,
        fetchedAt.isAcceptableOrUnknown(data['fetched_at']!, _fetchedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_fetchedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {platform, toplistId};
  @override
  ToplistCacheRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ToplistCacheRow(
      platform: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}platform'],
      )!,
      toplistId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}toplist_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      coverUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cover_url'],
      ),
      updateFrequency: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}update_frequency'],
      ),
      period: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}period'],
      ),
      songCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}song_count'],
      ),
      groupName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}group_name'],
      ),
      intro: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}intro'],
      ),
      fetchedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}fetched_at'],
      )!,
    );
  }

  @override
  $ToplistsCacheTable createAlias(String alias) {
    return $ToplistsCacheTable(attachedDatabase, alias);
  }
}

class ToplistCacheRow extends DataClass implements Insertable<ToplistCacheRow> {
  final String platform;
  final String toplistId;
  final String name;
  final String? coverUrl;
  final String? updateFrequency;
  final String? period;
  final int? songCount;
  final String? groupName;
  final String? intro;
  final int fetchedAt;
  const ToplistCacheRow({
    required this.platform,
    required this.toplistId,
    required this.name,
    this.coverUrl,
    this.updateFrequency,
    this.period,
    this.songCount,
    this.groupName,
    this.intro,
    required this.fetchedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['platform'] = Variable<String>(platform);
    map['toplist_id'] = Variable<String>(toplistId);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || coverUrl != null) {
      map['cover_url'] = Variable<String>(coverUrl);
    }
    if (!nullToAbsent || updateFrequency != null) {
      map['update_frequency'] = Variable<String>(updateFrequency);
    }
    if (!nullToAbsent || period != null) {
      map['period'] = Variable<String>(period);
    }
    if (!nullToAbsent || songCount != null) {
      map['song_count'] = Variable<int>(songCount);
    }
    if (!nullToAbsent || groupName != null) {
      map['group_name'] = Variable<String>(groupName);
    }
    if (!nullToAbsent || intro != null) {
      map['intro'] = Variable<String>(intro);
    }
    map['fetched_at'] = Variable<int>(fetchedAt);
    return map;
  }

  ToplistsCacheCompanion toCompanion(bool nullToAbsent) {
    return ToplistsCacheCompanion(
      platform: Value(platform),
      toplistId: Value(toplistId),
      name: Value(name),
      coverUrl: coverUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(coverUrl),
      updateFrequency: updateFrequency == null && nullToAbsent
          ? const Value.absent()
          : Value(updateFrequency),
      period: period == null && nullToAbsent
          ? const Value.absent()
          : Value(period),
      songCount: songCount == null && nullToAbsent
          ? const Value.absent()
          : Value(songCount),
      groupName: groupName == null && nullToAbsent
          ? const Value.absent()
          : Value(groupName),
      intro: intro == null && nullToAbsent
          ? const Value.absent()
          : Value(intro),
      fetchedAt: Value(fetchedAt),
    );
  }

  factory ToplistCacheRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ToplistCacheRow(
      platform: serializer.fromJson<String>(json['platform']),
      toplistId: serializer.fromJson<String>(json['toplistId']),
      name: serializer.fromJson<String>(json['name']),
      coverUrl: serializer.fromJson<String?>(json['coverUrl']),
      updateFrequency: serializer.fromJson<String?>(json['updateFrequency']),
      period: serializer.fromJson<String?>(json['period']),
      songCount: serializer.fromJson<int?>(json['songCount']),
      groupName: serializer.fromJson<String?>(json['groupName']),
      intro: serializer.fromJson<String?>(json['intro']),
      fetchedAt: serializer.fromJson<int>(json['fetchedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'platform': serializer.toJson<String>(platform),
      'toplistId': serializer.toJson<String>(toplistId),
      'name': serializer.toJson<String>(name),
      'coverUrl': serializer.toJson<String?>(coverUrl),
      'updateFrequency': serializer.toJson<String?>(updateFrequency),
      'period': serializer.toJson<String?>(period),
      'songCount': serializer.toJson<int?>(songCount),
      'groupName': serializer.toJson<String?>(groupName),
      'intro': serializer.toJson<String?>(intro),
      'fetchedAt': serializer.toJson<int>(fetchedAt),
    };
  }

  ToplistCacheRow copyWith({
    String? platform,
    String? toplistId,
    String? name,
    Value<String?> coverUrl = const Value.absent(),
    Value<String?> updateFrequency = const Value.absent(),
    Value<String?> period = const Value.absent(),
    Value<int?> songCount = const Value.absent(),
    Value<String?> groupName = const Value.absent(),
    Value<String?> intro = const Value.absent(),
    int? fetchedAt,
  }) => ToplistCacheRow(
    platform: platform ?? this.platform,
    toplistId: toplistId ?? this.toplistId,
    name: name ?? this.name,
    coverUrl: coverUrl.present ? coverUrl.value : this.coverUrl,
    updateFrequency: updateFrequency.present
        ? updateFrequency.value
        : this.updateFrequency,
    period: period.present ? period.value : this.period,
    songCount: songCount.present ? songCount.value : this.songCount,
    groupName: groupName.present ? groupName.value : this.groupName,
    intro: intro.present ? intro.value : this.intro,
    fetchedAt: fetchedAt ?? this.fetchedAt,
  );
  ToplistCacheRow copyWithCompanion(ToplistsCacheCompanion data) {
    return ToplistCacheRow(
      platform: data.platform.present ? data.platform.value : this.platform,
      toplistId: data.toplistId.present ? data.toplistId.value : this.toplistId,
      name: data.name.present ? data.name.value : this.name,
      coverUrl: data.coverUrl.present ? data.coverUrl.value : this.coverUrl,
      updateFrequency: data.updateFrequency.present
          ? data.updateFrequency.value
          : this.updateFrequency,
      period: data.period.present ? data.period.value : this.period,
      songCount: data.songCount.present ? data.songCount.value : this.songCount,
      groupName: data.groupName.present ? data.groupName.value : this.groupName,
      intro: data.intro.present ? data.intro.value : this.intro,
      fetchedAt: data.fetchedAt.present ? data.fetchedAt.value : this.fetchedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ToplistCacheRow(')
          ..write('platform: $platform, ')
          ..write('toplistId: $toplistId, ')
          ..write('name: $name, ')
          ..write('coverUrl: $coverUrl, ')
          ..write('updateFrequency: $updateFrequency, ')
          ..write('period: $period, ')
          ..write('songCount: $songCount, ')
          ..write('groupName: $groupName, ')
          ..write('intro: $intro, ')
          ..write('fetchedAt: $fetchedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    platform,
    toplistId,
    name,
    coverUrl,
    updateFrequency,
    period,
    songCount,
    groupName,
    intro,
    fetchedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ToplistCacheRow &&
          other.platform == this.platform &&
          other.toplistId == this.toplistId &&
          other.name == this.name &&
          other.coverUrl == this.coverUrl &&
          other.updateFrequency == this.updateFrequency &&
          other.period == this.period &&
          other.songCount == this.songCount &&
          other.groupName == this.groupName &&
          other.intro == this.intro &&
          other.fetchedAt == this.fetchedAt);
}

class ToplistsCacheCompanion extends UpdateCompanion<ToplistCacheRow> {
  final Value<String> platform;
  final Value<String> toplistId;
  final Value<String> name;
  final Value<String?> coverUrl;
  final Value<String?> updateFrequency;
  final Value<String?> period;
  final Value<int?> songCount;
  final Value<String?> groupName;
  final Value<String?> intro;
  final Value<int> fetchedAt;
  final Value<int> rowid;
  const ToplistsCacheCompanion({
    this.platform = const Value.absent(),
    this.toplistId = const Value.absent(),
    this.name = const Value.absent(),
    this.coverUrl = const Value.absent(),
    this.updateFrequency = const Value.absent(),
    this.period = const Value.absent(),
    this.songCount = const Value.absent(),
    this.groupName = const Value.absent(),
    this.intro = const Value.absent(),
    this.fetchedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ToplistsCacheCompanion.insert({
    required String platform,
    required String toplistId,
    required String name,
    this.coverUrl = const Value.absent(),
    this.updateFrequency = const Value.absent(),
    this.period = const Value.absent(),
    this.songCount = const Value.absent(),
    this.groupName = const Value.absent(),
    this.intro = const Value.absent(),
    required int fetchedAt,
    this.rowid = const Value.absent(),
  }) : platform = Value(platform),
       toplistId = Value(toplistId),
       name = Value(name),
       fetchedAt = Value(fetchedAt);
  static Insertable<ToplistCacheRow> custom({
    Expression<String>? platform,
    Expression<String>? toplistId,
    Expression<String>? name,
    Expression<String>? coverUrl,
    Expression<String>? updateFrequency,
    Expression<String>? period,
    Expression<int>? songCount,
    Expression<String>? groupName,
    Expression<String>? intro,
    Expression<int>? fetchedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (platform != null) 'platform': platform,
      if (toplistId != null) 'toplist_id': toplistId,
      if (name != null) 'name': name,
      if (coverUrl != null) 'cover_url': coverUrl,
      if (updateFrequency != null) 'update_frequency': updateFrequency,
      if (period != null) 'period': period,
      if (songCount != null) 'song_count': songCount,
      if (groupName != null) 'group_name': groupName,
      if (intro != null) 'intro': intro,
      if (fetchedAt != null) 'fetched_at': fetchedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ToplistsCacheCompanion copyWith({
    Value<String>? platform,
    Value<String>? toplistId,
    Value<String>? name,
    Value<String?>? coverUrl,
    Value<String?>? updateFrequency,
    Value<String?>? period,
    Value<int?>? songCount,
    Value<String?>? groupName,
    Value<String?>? intro,
    Value<int>? fetchedAt,
    Value<int>? rowid,
  }) {
    return ToplistsCacheCompanion(
      platform: platform ?? this.platform,
      toplistId: toplistId ?? this.toplistId,
      name: name ?? this.name,
      coverUrl: coverUrl ?? this.coverUrl,
      updateFrequency: updateFrequency ?? this.updateFrequency,
      period: period ?? this.period,
      songCount: songCount ?? this.songCount,
      groupName: groupName ?? this.groupName,
      intro: intro ?? this.intro,
      fetchedAt: fetchedAt ?? this.fetchedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (platform.present) {
      map['platform'] = Variable<String>(platform.value);
    }
    if (toplistId.present) {
      map['toplist_id'] = Variable<String>(toplistId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (coverUrl.present) {
      map['cover_url'] = Variable<String>(coverUrl.value);
    }
    if (updateFrequency.present) {
      map['update_frequency'] = Variable<String>(updateFrequency.value);
    }
    if (period.present) {
      map['period'] = Variable<String>(period.value);
    }
    if (songCount.present) {
      map['song_count'] = Variable<int>(songCount.value);
    }
    if (groupName.present) {
      map['group_name'] = Variable<String>(groupName.value);
    }
    if (intro.present) {
      map['intro'] = Variable<String>(intro.value);
    }
    if (fetchedAt.present) {
      map['fetched_at'] = Variable<int>(fetchedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ToplistsCacheCompanion(')
          ..write('platform: $platform, ')
          ..write('toplistId: $toplistId, ')
          ..write('name: $name, ')
          ..write('coverUrl: $coverUrl, ')
          ..write('updateFrequency: $updateFrequency, ')
          ..write('period: $period, ')
          ..write('songCount: $songCount, ')
          ..write('groupName: $groupName, ')
          ..write('intro: $intro, ')
          ..write('fetchedAt: $fetchedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PlayEventsTable extends PlayEvents
    with TableInfo<$PlayEventsTable, PlayEvent> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PlayEventsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _songIdMeta = const VerificationMeta('songId');
  @override
  late final GeneratedColumn<String> songId = GeneratedColumn<String>(
    'song_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _platformMeta = const VerificationMeta(
    'platform',
  );
  @override
  late final GeneratedColumn<String> platform = GeneratedColumn<String>(
    'platform',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _startedAtMeta = const VerificationMeta(
    'startedAt',
  );
  @override
  late final GeneratedColumn<int> startedAt = GeneratedColumn<int>(
    'started_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _endedAtMeta = const VerificationMeta(
    'endedAt',
  );
  @override
  late final GeneratedColumn<int> endedAt = GeneratedColumn<int>(
    'ended_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _durationListenedMeta = const VerificationMeta(
    'durationListened',
  );
  @override
  late final GeneratedColumn<int> durationListened = GeneratedColumn<int>(
    'duration_listened',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _completedRatioMeta = const VerificationMeta(
    'completedRatio',
  );
  @override
  late final GeneratedColumn<double> completedRatio = GeneratedColumn<double>(
    'completed_ratio',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
    'source',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    songId,
    platform,
    startedAt,
    endedAt,
    durationListened,
    completedRatio,
    source,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'play_events';
  @override
  VerificationContext validateIntegrity(
    Insertable<PlayEvent> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('song_id')) {
      context.handle(
        _songIdMeta,
        songId.isAcceptableOrUnknown(data['song_id']!, _songIdMeta),
      );
    } else if (isInserting) {
      context.missing(_songIdMeta);
    }
    if (data.containsKey('platform')) {
      context.handle(
        _platformMeta,
        platform.isAcceptableOrUnknown(data['platform']!, _platformMeta),
      );
    } else if (isInserting) {
      context.missing(_platformMeta);
    }
    if (data.containsKey('started_at')) {
      context.handle(
        _startedAtMeta,
        startedAt.isAcceptableOrUnknown(data['started_at']!, _startedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_startedAtMeta);
    }
    if (data.containsKey('ended_at')) {
      context.handle(
        _endedAtMeta,
        endedAt.isAcceptableOrUnknown(data['ended_at']!, _endedAtMeta),
      );
    }
    if (data.containsKey('duration_listened')) {
      context.handle(
        _durationListenedMeta,
        durationListened.isAcceptableOrUnknown(
          data['duration_listened']!,
          _durationListenedMeta,
        ),
      );
    }
    if (data.containsKey('completed_ratio')) {
      context.handle(
        _completedRatioMeta,
        completedRatio.isAcceptableOrUnknown(
          data['completed_ratio']!,
          _completedRatioMeta,
        ),
      );
    }
    if (data.containsKey('source')) {
      context.handle(
        _sourceMeta,
        source.isAcceptableOrUnknown(data['source']!, _sourceMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PlayEvent map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PlayEvent(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      songId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}song_id'],
      )!,
      platform: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}platform'],
      )!,
      startedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}started_at'],
      )!,
      endedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}ended_at'],
      ),
      durationListened: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_listened'],
      )!,
      completedRatio: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}completed_ratio'],
      )!,
      source: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source'],
      ),
    );
  }

  @override
  $PlayEventsTable createAlias(String alias) {
    return $PlayEventsTable(attachedDatabase, alias);
  }
}

class PlayEvent extends DataClass implements Insertable<PlayEvent> {
  final int id;
  final String songId;
  final String platform;
  final int startedAt;
  final int? endedAt;
  final int durationListened;
  final double completedRatio;

  /// `play` / `resume` / `skip` / `seek` — lets the UI stop counting a
  /// pause-and-resume as a brand new play.
  final String? source;
  const PlayEvent({
    required this.id,
    required this.songId,
    required this.platform,
    required this.startedAt,
    this.endedAt,
    required this.durationListened,
    required this.completedRatio,
    this.source,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['song_id'] = Variable<String>(songId);
    map['platform'] = Variable<String>(platform);
    map['started_at'] = Variable<int>(startedAt);
    if (!nullToAbsent || endedAt != null) {
      map['ended_at'] = Variable<int>(endedAt);
    }
    map['duration_listened'] = Variable<int>(durationListened);
    map['completed_ratio'] = Variable<double>(completedRatio);
    if (!nullToAbsent || source != null) {
      map['source'] = Variable<String>(source);
    }
    return map;
  }

  PlayEventsCompanion toCompanion(bool nullToAbsent) {
    return PlayEventsCompanion(
      id: Value(id),
      songId: Value(songId),
      platform: Value(platform),
      startedAt: Value(startedAt),
      endedAt: endedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(endedAt),
      durationListened: Value(durationListened),
      completedRatio: Value(completedRatio),
      source: source == null && nullToAbsent
          ? const Value.absent()
          : Value(source),
    );
  }

  factory PlayEvent.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PlayEvent(
      id: serializer.fromJson<int>(json['id']),
      songId: serializer.fromJson<String>(json['songId']),
      platform: serializer.fromJson<String>(json['platform']),
      startedAt: serializer.fromJson<int>(json['startedAt']),
      endedAt: serializer.fromJson<int?>(json['endedAt']),
      durationListened: serializer.fromJson<int>(json['durationListened']),
      completedRatio: serializer.fromJson<double>(json['completedRatio']),
      source: serializer.fromJson<String?>(json['source']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'songId': serializer.toJson<String>(songId),
      'platform': serializer.toJson<String>(platform),
      'startedAt': serializer.toJson<int>(startedAt),
      'endedAt': serializer.toJson<int?>(endedAt),
      'durationListened': serializer.toJson<int>(durationListened),
      'completedRatio': serializer.toJson<double>(completedRatio),
      'source': serializer.toJson<String?>(source),
    };
  }

  PlayEvent copyWith({
    int? id,
    String? songId,
    String? platform,
    int? startedAt,
    Value<int?> endedAt = const Value.absent(),
    int? durationListened,
    double? completedRatio,
    Value<String?> source = const Value.absent(),
  }) => PlayEvent(
    id: id ?? this.id,
    songId: songId ?? this.songId,
    platform: platform ?? this.platform,
    startedAt: startedAt ?? this.startedAt,
    endedAt: endedAt.present ? endedAt.value : this.endedAt,
    durationListened: durationListened ?? this.durationListened,
    completedRatio: completedRatio ?? this.completedRatio,
    source: source.present ? source.value : this.source,
  );
  PlayEvent copyWithCompanion(PlayEventsCompanion data) {
    return PlayEvent(
      id: data.id.present ? data.id.value : this.id,
      songId: data.songId.present ? data.songId.value : this.songId,
      platform: data.platform.present ? data.platform.value : this.platform,
      startedAt: data.startedAt.present ? data.startedAt.value : this.startedAt,
      endedAt: data.endedAt.present ? data.endedAt.value : this.endedAt,
      durationListened: data.durationListened.present
          ? data.durationListened.value
          : this.durationListened,
      completedRatio: data.completedRatio.present
          ? data.completedRatio.value
          : this.completedRatio,
      source: data.source.present ? data.source.value : this.source,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PlayEvent(')
          ..write('id: $id, ')
          ..write('songId: $songId, ')
          ..write('platform: $platform, ')
          ..write('startedAt: $startedAt, ')
          ..write('endedAt: $endedAt, ')
          ..write('durationListened: $durationListened, ')
          ..write('completedRatio: $completedRatio, ')
          ..write('source: $source')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    songId,
    platform,
    startedAt,
    endedAt,
    durationListened,
    completedRatio,
    source,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PlayEvent &&
          other.id == this.id &&
          other.songId == this.songId &&
          other.platform == this.platform &&
          other.startedAt == this.startedAt &&
          other.endedAt == this.endedAt &&
          other.durationListened == this.durationListened &&
          other.completedRatio == this.completedRatio &&
          other.source == this.source);
}

class PlayEventsCompanion extends UpdateCompanion<PlayEvent> {
  final Value<int> id;
  final Value<String> songId;
  final Value<String> platform;
  final Value<int> startedAt;
  final Value<int?> endedAt;
  final Value<int> durationListened;
  final Value<double> completedRatio;
  final Value<String?> source;
  const PlayEventsCompanion({
    this.id = const Value.absent(),
    this.songId = const Value.absent(),
    this.platform = const Value.absent(),
    this.startedAt = const Value.absent(),
    this.endedAt = const Value.absent(),
    this.durationListened = const Value.absent(),
    this.completedRatio = const Value.absent(),
    this.source = const Value.absent(),
  });
  PlayEventsCompanion.insert({
    this.id = const Value.absent(),
    required String songId,
    required String platform,
    required int startedAt,
    this.endedAt = const Value.absent(),
    this.durationListened = const Value.absent(),
    this.completedRatio = const Value.absent(),
    this.source = const Value.absent(),
  }) : songId = Value(songId),
       platform = Value(platform),
       startedAt = Value(startedAt);
  static Insertable<PlayEvent> custom({
    Expression<int>? id,
    Expression<String>? songId,
    Expression<String>? platform,
    Expression<int>? startedAt,
    Expression<int>? endedAt,
    Expression<int>? durationListened,
    Expression<double>? completedRatio,
    Expression<String>? source,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (songId != null) 'song_id': songId,
      if (platform != null) 'platform': platform,
      if (startedAt != null) 'started_at': startedAt,
      if (endedAt != null) 'ended_at': endedAt,
      if (durationListened != null) 'duration_listened': durationListened,
      if (completedRatio != null) 'completed_ratio': completedRatio,
      if (source != null) 'source': source,
    });
  }

  PlayEventsCompanion copyWith({
    Value<int>? id,
    Value<String>? songId,
    Value<String>? platform,
    Value<int>? startedAt,
    Value<int?>? endedAt,
    Value<int>? durationListened,
    Value<double>? completedRatio,
    Value<String?>? source,
  }) {
    return PlayEventsCompanion(
      id: id ?? this.id,
      songId: songId ?? this.songId,
      platform: platform ?? this.platform,
      startedAt: startedAt ?? this.startedAt,
      endedAt: endedAt ?? this.endedAt,
      durationListened: durationListened ?? this.durationListened,
      completedRatio: completedRatio ?? this.completedRatio,
      source: source ?? this.source,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (songId.present) {
      map['song_id'] = Variable<String>(songId.value);
    }
    if (platform.present) {
      map['platform'] = Variable<String>(platform.value);
    }
    if (startedAt.present) {
      map['started_at'] = Variable<int>(startedAt.value);
    }
    if (endedAt.present) {
      map['ended_at'] = Variable<int>(endedAt.value);
    }
    if (durationListened.present) {
      map['duration_listened'] = Variable<int>(durationListened.value);
    }
    if (completedRatio.present) {
      map['completed_ratio'] = Variable<double>(completedRatio.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PlayEventsCompanion(')
          ..write('id: $id, ')
          ..write('songId: $songId, ')
          ..write('platform: $platform, ')
          ..write('startedAt: $startedAt, ')
          ..write('endedAt: $endedAt, ')
          ..write('durationListened: $durationListened, ')
          ..write('completedRatio: $completedRatio, ')
          ..write('source: $source')
          ..write(')'))
        .toString();
  }
}

class $DailyStatsTable extends DailyStats
    with TableInfo<$DailyStatsTable, DailyStat> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DailyStatsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _dayMeta = const VerificationMeta('day');
  @override
  late final GeneratedColumn<String> day = GeneratedColumn<String>(
    'day',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _songIdMeta = const VerificationMeta('songId');
  @override
  late final GeneratedColumn<String> songId = GeneratedColumn<String>(
    'song_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _platformMeta = const VerificationMeta(
    'platform',
  );
  @override
  late final GeneratedColumn<String> platform = GeneratedColumn<String>(
    'platform',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _playCountMeta = const VerificationMeta(
    'playCount',
  );
  @override
  late final GeneratedColumn<int> playCount = GeneratedColumn<int>(
    'play_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _listenMsMeta = const VerificationMeta(
    'listenMs',
  );
  @override
  late final GeneratedColumn<int> listenMs = GeneratedColumn<int>(
    'listen_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    day,
    songId,
    platform,
    playCount,
    listenMs,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'daily_stats';
  @override
  VerificationContext validateIntegrity(
    Insertable<DailyStat> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('day')) {
      context.handle(
        _dayMeta,
        day.isAcceptableOrUnknown(data['day']!, _dayMeta),
      );
    } else if (isInserting) {
      context.missing(_dayMeta);
    }
    if (data.containsKey('song_id')) {
      context.handle(
        _songIdMeta,
        songId.isAcceptableOrUnknown(data['song_id']!, _songIdMeta),
      );
    } else if (isInserting) {
      context.missing(_songIdMeta);
    }
    if (data.containsKey('platform')) {
      context.handle(
        _platformMeta,
        platform.isAcceptableOrUnknown(data['platform']!, _platformMeta),
      );
    } else if (isInserting) {
      context.missing(_platformMeta);
    }
    if (data.containsKey('play_count')) {
      context.handle(
        _playCountMeta,
        playCount.isAcceptableOrUnknown(data['play_count']!, _playCountMeta),
      );
    }
    if (data.containsKey('listen_ms')) {
      context.handle(
        _listenMsMeta,
        listenMs.isAcceptableOrUnknown(data['listen_ms']!, _listenMsMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {day, songId, platform};
  @override
  DailyStat map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DailyStat(
      day: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}day'],
      )!,
      songId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}song_id'],
      )!,
      platform: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}platform'],
      )!,
      playCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}play_count'],
      )!,
      listenMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}listen_ms'],
      )!,
    );
  }

  @override
  $DailyStatsTable createAlias(String alias) {
    return $DailyStatsTable(attachedDatabase, alias);
  }
}

class DailyStat extends DataClass implements Insertable<DailyStat> {
  final String day;
  final String songId;
  final String platform;
  final int playCount;
  final int listenMs;
  const DailyStat({
    required this.day,
    required this.songId,
    required this.platform,
    required this.playCount,
    required this.listenMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['day'] = Variable<String>(day);
    map['song_id'] = Variable<String>(songId);
    map['platform'] = Variable<String>(platform);
    map['play_count'] = Variable<int>(playCount);
    map['listen_ms'] = Variable<int>(listenMs);
    return map;
  }

  DailyStatsCompanion toCompanion(bool nullToAbsent) {
    return DailyStatsCompanion(
      day: Value(day),
      songId: Value(songId),
      platform: Value(platform),
      playCount: Value(playCount),
      listenMs: Value(listenMs),
    );
  }

  factory DailyStat.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DailyStat(
      day: serializer.fromJson<String>(json['day']),
      songId: serializer.fromJson<String>(json['songId']),
      platform: serializer.fromJson<String>(json['platform']),
      playCount: serializer.fromJson<int>(json['playCount']),
      listenMs: serializer.fromJson<int>(json['listenMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'day': serializer.toJson<String>(day),
      'songId': serializer.toJson<String>(songId),
      'platform': serializer.toJson<String>(platform),
      'playCount': serializer.toJson<int>(playCount),
      'listenMs': serializer.toJson<int>(listenMs),
    };
  }

  DailyStat copyWith({
    String? day,
    String? songId,
    String? platform,
    int? playCount,
    int? listenMs,
  }) => DailyStat(
    day: day ?? this.day,
    songId: songId ?? this.songId,
    platform: platform ?? this.platform,
    playCount: playCount ?? this.playCount,
    listenMs: listenMs ?? this.listenMs,
  );
  DailyStat copyWithCompanion(DailyStatsCompanion data) {
    return DailyStat(
      day: data.day.present ? data.day.value : this.day,
      songId: data.songId.present ? data.songId.value : this.songId,
      platform: data.platform.present ? data.platform.value : this.platform,
      playCount: data.playCount.present ? data.playCount.value : this.playCount,
      listenMs: data.listenMs.present ? data.listenMs.value : this.listenMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DailyStat(')
          ..write('day: $day, ')
          ..write('songId: $songId, ')
          ..write('platform: $platform, ')
          ..write('playCount: $playCount, ')
          ..write('listenMs: $listenMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(day, songId, platform, playCount, listenMs);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DailyStat &&
          other.day == this.day &&
          other.songId == this.songId &&
          other.platform == this.platform &&
          other.playCount == this.playCount &&
          other.listenMs == this.listenMs);
}

class DailyStatsCompanion extends UpdateCompanion<DailyStat> {
  final Value<String> day;
  final Value<String> songId;
  final Value<String> platform;
  final Value<int> playCount;
  final Value<int> listenMs;
  final Value<int> rowid;
  const DailyStatsCompanion({
    this.day = const Value.absent(),
    this.songId = const Value.absent(),
    this.platform = const Value.absent(),
    this.playCount = const Value.absent(),
    this.listenMs = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DailyStatsCompanion.insert({
    required String day,
    required String songId,
    required String platform,
    this.playCount = const Value.absent(),
    this.listenMs = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : day = Value(day),
       songId = Value(songId),
       platform = Value(platform);
  static Insertable<DailyStat> custom({
    Expression<String>? day,
    Expression<String>? songId,
    Expression<String>? platform,
    Expression<int>? playCount,
    Expression<int>? listenMs,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (day != null) 'day': day,
      if (songId != null) 'song_id': songId,
      if (platform != null) 'platform': platform,
      if (playCount != null) 'play_count': playCount,
      if (listenMs != null) 'listen_ms': listenMs,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DailyStatsCompanion copyWith({
    Value<String>? day,
    Value<String>? songId,
    Value<String>? platform,
    Value<int>? playCount,
    Value<int>? listenMs,
    Value<int>? rowid,
  }) {
    return DailyStatsCompanion(
      day: day ?? this.day,
      songId: songId ?? this.songId,
      platform: platform ?? this.platform,
      playCount: playCount ?? this.playCount,
      listenMs: listenMs ?? this.listenMs,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (day.present) {
      map['day'] = Variable<String>(day.value);
    }
    if (songId.present) {
      map['song_id'] = Variable<String>(songId.value);
    }
    if (platform.present) {
      map['platform'] = Variable<String>(platform.value);
    }
    if (playCount.present) {
      map['play_count'] = Variable<int>(playCount.value);
    }
    if (listenMs.present) {
      map['listen_ms'] = Variable<int>(listenMs.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DailyStatsCompanion(')
          ..write('day: $day, ')
          ..write('songId: $songId, ')
          ..write('platform: $platform, ')
          ..write('playCount: $playCount, ')
          ..write('listenMs: $listenMs, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SmartPlaylistSnapshotsTable extends SmartPlaylistSnapshots
    with TableInfo<$SmartPlaylistSnapshotsTable, SmartPlaylistSnapshot> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SmartPlaylistSnapshotsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _ruleIdMeta = const VerificationMeta('ruleId');
  @override
  late final GeneratedColumn<String> ruleId = GeneratedColumn<String>(
    'rule_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _songKeysMeta = const VerificationMeta(
    'songKeys',
  );
  @override
  late final GeneratedColumn<String> songKeys = GeneratedColumn<String>(
    'song_keys',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _generatedAtMeta = const VerificationMeta(
    'generatedAt',
  );
  @override
  late final GeneratedColumn<int> generatedAt = GeneratedColumn<int>(
    'generated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [ruleId, songKeys, generatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'smart_playlist_snapshots';
  @override
  VerificationContext validateIntegrity(
    Insertable<SmartPlaylistSnapshot> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('rule_id')) {
      context.handle(
        _ruleIdMeta,
        ruleId.isAcceptableOrUnknown(data['rule_id']!, _ruleIdMeta),
      );
    } else if (isInserting) {
      context.missing(_ruleIdMeta);
    }
    if (data.containsKey('song_keys')) {
      context.handle(
        _songKeysMeta,
        songKeys.isAcceptableOrUnknown(data['song_keys']!, _songKeysMeta),
      );
    } else if (isInserting) {
      context.missing(_songKeysMeta);
    }
    if (data.containsKey('generated_at')) {
      context.handle(
        _generatedAtMeta,
        generatedAt.isAcceptableOrUnknown(
          data['generated_at']!,
          _generatedAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_generatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {ruleId};
  @override
  SmartPlaylistSnapshot map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SmartPlaylistSnapshot(
      ruleId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}rule_id'],
      )!,
      songKeys: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}song_keys'],
      )!,
      generatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}generated_at'],
      )!,
    );
  }

  @override
  $SmartPlaylistSnapshotsTable createAlias(String alias) {
    return $SmartPlaylistSnapshotsTable(attachedDatabase, alias);
  }
}

class SmartPlaylistSnapshot extends DataClass
    implements Insertable<SmartPlaylistSnapshot> {
  final String ruleId;
  final String songKeys;
  final int generatedAt;
  const SmartPlaylistSnapshot({
    required this.ruleId,
    required this.songKeys,
    required this.generatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['rule_id'] = Variable<String>(ruleId);
    map['song_keys'] = Variable<String>(songKeys);
    map['generated_at'] = Variable<int>(generatedAt);
    return map;
  }

  SmartPlaylistSnapshotsCompanion toCompanion(bool nullToAbsent) {
    return SmartPlaylistSnapshotsCompanion(
      ruleId: Value(ruleId),
      songKeys: Value(songKeys),
      generatedAt: Value(generatedAt),
    );
  }

  factory SmartPlaylistSnapshot.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SmartPlaylistSnapshot(
      ruleId: serializer.fromJson<String>(json['ruleId']),
      songKeys: serializer.fromJson<String>(json['songKeys']),
      generatedAt: serializer.fromJson<int>(json['generatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'ruleId': serializer.toJson<String>(ruleId),
      'songKeys': serializer.toJson<String>(songKeys),
      'generatedAt': serializer.toJson<int>(generatedAt),
    };
  }

  SmartPlaylistSnapshot copyWith({
    String? ruleId,
    String? songKeys,
    int? generatedAt,
  }) => SmartPlaylistSnapshot(
    ruleId: ruleId ?? this.ruleId,
    songKeys: songKeys ?? this.songKeys,
    generatedAt: generatedAt ?? this.generatedAt,
  );
  SmartPlaylistSnapshot copyWithCompanion(
    SmartPlaylistSnapshotsCompanion data,
  ) {
    return SmartPlaylistSnapshot(
      ruleId: data.ruleId.present ? data.ruleId.value : this.ruleId,
      songKeys: data.songKeys.present ? data.songKeys.value : this.songKeys,
      generatedAt: data.generatedAt.present
          ? data.generatedAt.value
          : this.generatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SmartPlaylistSnapshot(')
          ..write('ruleId: $ruleId, ')
          ..write('songKeys: $songKeys, ')
          ..write('generatedAt: $generatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(ruleId, songKeys, generatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SmartPlaylistSnapshot &&
          other.ruleId == this.ruleId &&
          other.songKeys == this.songKeys &&
          other.generatedAt == this.generatedAt);
}

class SmartPlaylistSnapshotsCompanion
    extends UpdateCompanion<SmartPlaylistSnapshot> {
  final Value<String> ruleId;
  final Value<String> songKeys;
  final Value<int> generatedAt;
  final Value<int> rowid;
  const SmartPlaylistSnapshotsCompanion({
    this.ruleId = const Value.absent(),
    this.songKeys = const Value.absent(),
    this.generatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SmartPlaylistSnapshotsCompanion.insert({
    required String ruleId,
    required String songKeys,
    required int generatedAt,
    this.rowid = const Value.absent(),
  }) : ruleId = Value(ruleId),
       songKeys = Value(songKeys),
       generatedAt = Value(generatedAt);
  static Insertable<SmartPlaylistSnapshot> custom({
    Expression<String>? ruleId,
    Expression<String>? songKeys,
    Expression<int>? generatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (ruleId != null) 'rule_id': ruleId,
      if (songKeys != null) 'song_keys': songKeys,
      if (generatedAt != null) 'generated_at': generatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SmartPlaylistSnapshotsCompanion copyWith({
    Value<String>? ruleId,
    Value<String>? songKeys,
    Value<int>? generatedAt,
    Value<int>? rowid,
  }) {
    return SmartPlaylistSnapshotsCompanion(
      ruleId: ruleId ?? this.ruleId,
      songKeys: songKeys ?? this.songKeys,
      generatedAt: generatedAt ?? this.generatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (ruleId.present) {
      map['rule_id'] = Variable<String>(ruleId.value);
    }
    if (songKeys.present) {
      map['song_keys'] = Variable<String>(songKeys.value);
    }
    if (generatedAt.present) {
      map['generated_at'] = Variable<int>(generatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SmartPlaylistSnapshotsCompanion(')
          ..write('ruleId: $ruleId, ')
          ..write('songKeys: $songKeys, ')
          ..write('generatedAt: $generatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $SongsTable songs = $SongsTable(this);
  late final $ListeningHistoryTable listeningHistory = $ListeningHistoryTable(
    this,
  );
  late final $UserLikesTable userLikes = $UserLikesTable(this);
  late final $LyricsCacheTable lyricsCache = $LyricsCacheTable(this);
  late final $LocalTracksTable localTracks = $LocalTracksTable(this);
  late final $ToplistsCacheTable toplistsCache = $ToplistsCacheTable(this);
  late final $PlayEventsTable playEvents = $PlayEventsTable(this);
  late final $DailyStatsTable dailyStats = $DailyStatsTable(this);
  late final $SmartPlaylistSnapshotsTable smartPlaylistSnapshots =
      $SmartPlaylistSnapshotsTable(this);
  late final SongsDao songsDao = SongsDao(this as AppDatabase);
  late final HistoryDao historyDao = HistoryDao(this as AppDatabase);
  late final LikesDao likesDao = LikesDao(this as AppDatabase);
  late final LyricsCacheDao lyricsCacheDao = LyricsCacheDao(
    this as AppDatabase,
  );
  late final StatsDao statsDao = StatsDao(this as AppDatabase);
  late final LocalTracksDao localTracksDao = LocalTracksDao(
    this as AppDatabase,
  );
  late final ToplistsCacheDao toplistsCacheDao = ToplistsCacheDao(
    this as AppDatabase,
  );
  late final SmartPlaylistSnapshotsDao smartPlaylistSnapshotsDao =
      SmartPlaylistSnapshotsDao(this as AppDatabase);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    songs,
    listeningHistory,
    userLikes,
    lyricsCache,
    localTracks,
    toplistsCache,
    playEvents,
    dailyStats,
    smartPlaylistSnapshots,
  ];
}

typedef $$SongsTableCreateCompanionBuilder =
    SongsCompanion Function({
      required String id,
      required String platform,
      required String name,
      required String artists,
      Value<String?> albumName,
      Value<String?> albumCover,
      Value<int> durationMs,
      required String fingerprint,
      Value<String?> albumId,
      Value<String?> artistId,
      Value<int?> trackNumber,
      Value<int> rowid,
    });
typedef $$SongsTableUpdateCompanionBuilder =
    SongsCompanion Function({
      Value<String> id,
      Value<String> platform,
      Value<String> name,
      Value<String> artists,
      Value<String?> albumName,
      Value<String?> albumCover,
      Value<int> durationMs,
      Value<String> fingerprint,
      Value<String?> albumId,
      Value<String?> artistId,
      Value<int?> trackNumber,
      Value<int> rowid,
    });

class $$SongsTableFilterComposer extends Composer<_$AppDatabase, $SongsTable> {
  $$SongsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get platform => $composableBuilder(
    column: $table.platform,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get artists => $composableBuilder(
    column: $table.artists,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get albumName => $composableBuilder(
    column: $table.albumName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get albumCover => $composableBuilder(
    column: $table.albumCover,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fingerprint => $composableBuilder(
    column: $table.fingerprint,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get albumId => $composableBuilder(
    column: $table.albumId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get artistId => $composableBuilder(
    column: $table.artistId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get trackNumber => $composableBuilder(
    column: $table.trackNumber,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SongsTableOrderingComposer
    extends Composer<_$AppDatabase, $SongsTable> {
  $$SongsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get platform => $composableBuilder(
    column: $table.platform,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get artists => $composableBuilder(
    column: $table.artists,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get albumName => $composableBuilder(
    column: $table.albumName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get albumCover => $composableBuilder(
    column: $table.albumCover,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fingerprint => $composableBuilder(
    column: $table.fingerprint,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get albumId => $composableBuilder(
    column: $table.albumId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get artistId => $composableBuilder(
    column: $table.artistId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get trackNumber => $composableBuilder(
    column: $table.trackNumber,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SongsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SongsTable> {
  $$SongsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get platform =>
      $composableBuilder(column: $table.platform, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get artists =>
      $composableBuilder(column: $table.artists, builder: (column) => column);

  GeneratedColumn<String> get albumName =>
      $composableBuilder(column: $table.albumName, builder: (column) => column);

  GeneratedColumn<String> get albumCover => $composableBuilder(
    column: $table.albumCover,
    builder: (column) => column,
  );

  GeneratedColumn<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => column,
  );

  GeneratedColumn<String> get fingerprint => $composableBuilder(
    column: $table.fingerprint,
    builder: (column) => column,
  );

  GeneratedColumn<String> get albumId =>
      $composableBuilder(column: $table.albumId, builder: (column) => column);

  GeneratedColumn<String> get artistId =>
      $composableBuilder(column: $table.artistId, builder: (column) => column);

  GeneratedColumn<int> get trackNumber => $composableBuilder(
    column: $table.trackNumber,
    builder: (column) => column,
  );
}

class $$SongsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SongsTable,
          SongRecord,
          $$SongsTableFilterComposer,
          $$SongsTableOrderingComposer,
          $$SongsTableAnnotationComposer,
          $$SongsTableCreateCompanionBuilder,
          $$SongsTableUpdateCompanionBuilder,
          (SongRecord, BaseReferences<_$AppDatabase, $SongsTable, SongRecord>),
          SongRecord,
          PrefetchHooks Function()
        > {
  $$SongsTableTableManager(_$AppDatabase db, $SongsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SongsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SongsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SongsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> platform = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> artists = const Value.absent(),
                Value<String?> albumName = const Value.absent(),
                Value<String?> albumCover = const Value.absent(),
                Value<int> durationMs = const Value.absent(),
                Value<String> fingerprint = const Value.absent(),
                Value<String?> albumId = const Value.absent(),
                Value<String?> artistId = const Value.absent(),
                Value<int?> trackNumber = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SongsCompanion(
                id: id,
                platform: platform,
                name: name,
                artists: artists,
                albumName: albumName,
                albumCover: albumCover,
                durationMs: durationMs,
                fingerprint: fingerprint,
                albumId: albumId,
                artistId: artistId,
                trackNumber: trackNumber,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String platform,
                required String name,
                required String artists,
                Value<String?> albumName = const Value.absent(),
                Value<String?> albumCover = const Value.absent(),
                Value<int> durationMs = const Value.absent(),
                required String fingerprint,
                Value<String?> albumId = const Value.absent(),
                Value<String?> artistId = const Value.absent(),
                Value<int?> trackNumber = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SongsCompanion.insert(
                id: id,
                platform: platform,
                name: name,
                artists: artists,
                albumName: albumName,
                albumCover: albumCover,
                durationMs: durationMs,
                fingerprint: fingerprint,
                albumId: albumId,
                artistId: artistId,
                trackNumber: trackNumber,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SongsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SongsTable,
      SongRecord,
      $$SongsTableFilterComposer,
      $$SongsTableOrderingComposer,
      $$SongsTableAnnotationComposer,
      $$SongsTableCreateCompanionBuilder,
      $$SongsTableUpdateCompanionBuilder,
      (SongRecord, BaseReferences<_$AppDatabase, $SongsTable, SongRecord>),
      SongRecord,
      PrefetchHooks Function()
    >;
typedef $$ListeningHistoryTableCreateCompanionBuilder =
    ListeningHistoryCompanion Function({
      Value<int> id,
      required String songId,
      required String platform,
      required int listenedAt,
      Value<int> durationListened,
    });
typedef $$ListeningHistoryTableUpdateCompanionBuilder =
    ListeningHistoryCompanion Function({
      Value<int> id,
      Value<String> songId,
      Value<String> platform,
      Value<int> listenedAt,
      Value<int> durationListened,
    });

class $$ListeningHistoryTableFilterComposer
    extends Composer<_$AppDatabase, $ListeningHistoryTable> {
  $$ListeningHistoryTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get songId => $composableBuilder(
    column: $table.songId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get platform => $composableBuilder(
    column: $table.platform,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get listenedAt => $composableBuilder(
    column: $table.listenedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationListened => $composableBuilder(
    column: $table.durationListened,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ListeningHistoryTableOrderingComposer
    extends Composer<_$AppDatabase, $ListeningHistoryTable> {
  $$ListeningHistoryTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get songId => $composableBuilder(
    column: $table.songId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get platform => $composableBuilder(
    column: $table.platform,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get listenedAt => $composableBuilder(
    column: $table.listenedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationListened => $composableBuilder(
    column: $table.durationListened,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ListeningHistoryTableAnnotationComposer
    extends Composer<_$AppDatabase, $ListeningHistoryTable> {
  $$ListeningHistoryTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get songId =>
      $composableBuilder(column: $table.songId, builder: (column) => column);

  GeneratedColumn<String> get platform =>
      $composableBuilder(column: $table.platform, builder: (column) => column);

  GeneratedColumn<int> get listenedAt => $composableBuilder(
    column: $table.listenedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get durationListened => $composableBuilder(
    column: $table.durationListened,
    builder: (column) => column,
  );
}

class $$ListeningHistoryTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ListeningHistoryTable,
          ListeningHistoryEntry,
          $$ListeningHistoryTableFilterComposer,
          $$ListeningHistoryTableOrderingComposer,
          $$ListeningHistoryTableAnnotationComposer,
          $$ListeningHistoryTableCreateCompanionBuilder,
          $$ListeningHistoryTableUpdateCompanionBuilder,
          (
            ListeningHistoryEntry,
            BaseReferences<
              _$AppDatabase,
              $ListeningHistoryTable,
              ListeningHistoryEntry
            >,
          ),
          ListeningHistoryEntry,
          PrefetchHooks Function()
        > {
  $$ListeningHistoryTableTableManager(
    _$AppDatabase db,
    $ListeningHistoryTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ListeningHistoryTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ListeningHistoryTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ListeningHistoryTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> songId = const Value.absent(),
                Value<String> platform = const Value.absent(),
                Value<int> listenedAt = const Value.absent(),
                Value<int> durationListened = const Value.absent(),
              }) => ListeningHistoryCompanion(
                id: id,
                songId: songId,
                platform: platform,
                listenedAt: listenedAt,
                durationListened: durationListened,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String songId,
                required String platform,
                required int listenedAt,
                Value<int> durationListened = const Value.absent(),
              }) => ListeningHistoryCompanion.insert(
                id: id,
                songId: songId,
                platform: platform,
                listenedAt: listenedAt,
                durationListened: durationListened,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ListeningHistoryTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ListeningHistoryTable,
      ListeningHistoryEntry,
      $$ListeningHistoryTableFilterComposer,
      $$ListeningHistoryTableOrderingComposer,
      $$ListeningHistoryTableAnnotationComposer,
      $$ListeningHistoryTableCreateCompanionBuilder,
      $$ListeningHistoryTableUpdateCompanionBuilder,
      (
        ListeningHistoryEntry,
        BaseReferences<
          _$AppDatabase,
          $ListeningHistoryTable,
          ListeningHistoryEntry
        >,
      ),
      ListeningHistoryEntry,
      PrefetchHooks Function()
    >;
typedef $$UserLikesTableCreateCompanionBuilder =
    UserLikesCompanion Function({
      Value<int> id,
      required String songId,
      required String platform,
      required int addedAt,
    });
typedef $$UserLikesTableUpdateCompanionBuilder =
    UserLikesCompanion Function({
      Value<int> id,
      Value<String> songId,
      Value<String> platform,
      Value<int> addedAt,
    });

class $$UserLikesTableFilterComposer
    extends Composer<_$AppDatabase, $UserLikesTable> {
  $$UserLikesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get songId => $composableBuilder(
    column: $table.songId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get platform => $composableBuilder(
    column: $table.platform,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$UserLikesTableOrderingComposer
    extends Composer<_$AppDatabase, $UserLikesTable> {
  $$UserLikesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get songId => $composableBuilder(
    column: $table.songId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get platform => $composableBuilder(
    column: $table.platform,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$UserLikesTableAnnotationComposer
    extends Composer<_$AppDatabase, $UserLikesTable> {
  $$UserLikesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get songId =>
      $composableBuilder(column: $table.songId, builder: (column) => column);

  GeneratedColumn<String> get platform =>
      $composableBuilder(column: $table.platform, builder: (column) => column);

  GeneratedColumn<int> get addedAt =>
      $composableBuilder(column: $table.addedAt, builder: (column) => column);
}

class $$UserLikesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $UserLikesTable,
          UserLike,
          $$UserLikesTableFilterComposer,
          $$UserLikesTableOrderingComposer,
          $$UserLikesTableAnnotationComposer,
          $$UserLikesTableCreateCompanionBuilder,
          $$UserLikesTableUpdateCompanionBuilder,
          (UserLike, BaseReferences<_$AppDatabase, $UserLikesTable, UserLike>),
          UserLike,
          PrefetchHooks Function()
        > {
  $$UserLikesTableTableManager(_$AppDatabase db, $UserLikesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$UserLikesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$UserLikesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$UserLikesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> songId = const Value.absent(),
                Value<String> platform = const Value.absent(),
                Value<int> addedAt = const Value.absent(),
              }) => UserLikesCompanion(
                id: id,
                songId: songId,
                platform: platform,
                addedAt: addedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String songId,
                required String platform,
                required int addedAt,
              }) => UserLikesCompanion.insert(
                id: id,
                songId: songId,
                platform: platform,
                addedAt: addedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$UserLikesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $UserLikesTable,
      UserLike,
      $$UserLikesTableFilterComposer,
      $$UserLikesTableOrderingComposer,
      $$UserLikesTableAnnotationComposer,
      $$UserLikesTableCreateCompanionBuilder,
      $$UserLikesTableUpdateCompanionBuilder,
      (UserLike, BaseReferences<_$AppDatabase, $UserLikesTable, UserLike>),
      UserLike,
      PrefetchHooks Function()
    >;
typedef $$LyricsCacheTableCreateCompanionBuilder =
    LyricsCacheCompanion Function({
      required String songId,
      required String platform,
      required String content,
      required String format,
      required int syncedAt,
      Value<int> rowid,
    });
typedef $$LyricsCacheTableUpdateCompanionBuilder =
    LyricsCacheCompanion Function({
      Value<String> songId,
      Value<String> platform,
      Value<String> content,
      Value<String> format,
      Value<int> syncedAt,
      Value<int> rowid,
    });

class $$LyricsCacheTableFilterComposer
    extends Composer<_$AppDatabase, $LyricsCacheTable> {
  $$LyricsCacheTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get songId => $composableBuilder(
    column: $table.songId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get platform => $composableBuilder(
    column: $table.platform,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get format => $composableBuilder(
    column: $table.format,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get syncedAt => $composableBuilder(
    column: $table.syncedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LyricsCacheTableOrderingComposer
    extends Composer<_$AppDatabase, $LyricsCacheTable> {
  $$LyricsCacheTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get songId => $composableBuilder(
    column: $table.songId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get platform => $composableBuilder(
    column: $table.platform,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get format => $composableBuilder(
    column: $table.format,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get syncedAt => $composableBuilder(
    column: $table.syncedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LyricsCacheTableAnnotationComposer
    extends Composer<_$AppDatabase, $LyricsCacheTable> {
  $$LyricsCacheTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get songId =>
      $composableBuilder(column: $table.songId, builder: (column) => column);

  GeneratedColumn<String> get platform =>
      $composableBuilder(column: $table.platform, builder: (column) => column);

  GeneratedColumn<String> get content =>
      $composableBuilder(column: $table.content, builder: (column) => column);

  GeneratedColumn<String> get format =>
      $composableBuilder(column: $table.format, builder: (column) => column);

  GeneratedColumn<int> get syncedAt =>
      $composableBuilder(column: $table.syncedAt, builder: (column) => column);
}

class $$LyricsCacheTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LyricsCacheTable,
          LyricsCacheData,
          $$LyricsCacheTableFilterComposer,
          $$LyricsCacheTableOrderingComposer,
          $$LyricsCacheTableAnnotationComposer,
          $$LyricsCacheTableCreateCompanionBuilder,
          $$LyricsCacheTableUpdateCompanionBuilder,
          (
            LyricsCacheData,
            BaseReferences<_$AppDatabase, $LyricsCacheTable, LyricsCacheData>,
          ),
          LyricsCacheData,
          PrefetchHooks Function()
        > {
  $$LyricsCacheTableTableManager(_$AppDatabase db, $LyricsCacheTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LyricsCacheTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LyricsCacheTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LyricsCacheTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> songId = const Value.absent(),
                Value<String> platform = const Value.absent(),
                Value<String> content = const Value.absent(),
                Value<String> format = const Value.absent(),
                Value<int> syncedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LyricsCacheCompanion(
                songId: songId,
                platform: platform,
                content: content,
                format: format,
                syncedAt: syncedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String songId,
                required String platform,
                required String content,
                required String format,
                required int syncedAt,
                Value<int> rowid = const Value.absent(),
              }) => LyricsCacheCompanion.insert(
                songId: songId,
                platform: platform,
                content: content,
                format: format,
                syncedAt: syncedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LyricsCacheTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LyricsCacheTable,
      LyricsCacheData,
      $$LyricsCacheTableFilterComposer,
      $$LyricsCacheTableOrderingComposer,
      $$LyricsCacheTableAnnotationComposer,
      $$LyricsCacheTableCreateCompanionBuilder,
      $$LyricsCacheTableUpdateCompanionBuilder,
      (
        LyricsCacheData,
        BaseReferences<_$AppDatabase, $LyricsCacheTable, LyricsCacheData>,
      ),
      LyricsCacheData,
      PrefetchHooks Function()
    >;
typedef $$LocalTracksTableCreateCompanionBuilder =
    LocalTracksCompanion Function({
      required String path,
      required int mtime,
      required int size,
      Value<String?> title,
      Value<String?> artistName,
      Value<String?> albumName,
      Value<int> durationMs,
      Value<int?> trackNumber,
      Value<String?> coverPath,
      Value<int?> scannedAt,
      Value<int> rowid,
    });
typedef $$LocalTracksTableUpdateCompanionBuilder =
    LocalTracksCompanion Function({
      Value<String> path,
      Value<int> mtime,
      Value<int> size,
      Value<String?> title,
      Value<String?> artistName,
      Value<String?> albumName,
      Value<int> durationMs,
      Value<int?> trackNumber,
      Value<String?> coverPath,
      Value<int?> scannedAt,
      Value<int> rowid,
    });

class $$LocalTracksTableFilterComposer
    extends Composer<_$AppDatabase, $LocalTracksTable> {
  $$LocalTracksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get mtime => $composableBuilder(
    column: $table.mtime,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get size => $composableBuilder(
    column: $table.size,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get artistName => $composableBuilder(
    column: $table.artistName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get albumName => $composableBuilder(
    column: $table.albumName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get trackNumber => $composableBuilder(
    column: $table.trackNumber,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get coverPath => $composableBuilder(
    column: $table.coverPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get scannedAt => $composableBuilder(
    column: $table.scannedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalTracksTableOrderingComposer
    extends Composer<_$AppDatabase, $LocalTracksTable> {
  $$LocalTracksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get mtime => $composableBuilder(
    column: $table.mtime,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get size => $composableBuilder(
    column: $table.size,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get artistName => $composableBuilder(
    column: $table.artistName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get albumName => $composableBuilder(
    column: $table.albumName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get trackNumber => $composableBuilder(
    column: $table.trackNumber,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get coverPath => $composableBuilder(
    column: $table.coverPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get scannedAt => $composableBuilder(
    column: $table.scannedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalTracksTableAnnotationComposer
    extends Composer<_$AppDatabase, $LocalTracksTable> {
  $$LocalTracksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get path =>
      $composableBuilder(column: $table.path, builder: (column) => column);

  GeneratedColumn<int> get mtime =>
      $composableBuilder(column: $table.mtime, builder: (column) => column);

  GeneratedColumn<int> get size =>
      $composableBuilder(column: $table.size, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get artistName => $composableBuilder(
    column: $table.artistName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get albumName =>
      $composableBuilder(column: $table.albumName, builder: (column) => column);

  GeneratedColumn<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get trackNumber => $composableBuilder(
    column: $table.trackNumber,
    builder: (column) => column,
  );

  GeneratedColumn<String> get coverPath =>
      $composableBuilder(column: $table.coverPath, builder: (column) => column);

  GeneratedColumn<int> get scannedAt =>
      $composableBuilder(column: $table.scannedAt, builder: (column) => column);
}

class $$LocalTracksTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LocalTracksTable,
          LocalTrack,
          $$LocalTracksTableFilterComposer,
          $$LocalTracksTableOrderingComposer,
          $$LocalTracksTableAnnotationComposer,
          $$LocalTracksTableCreateCompanionBuilder,
          $$LocalTracksTableUpdateCompanionBuilder,
          (
            LocalTrack,
            BaseReferences<_$AppDatabase, $LocalTracksTable, LocalTrack>,
          ),
          LocalTrack,
          PrefetchHooks Function()
        > {
  $$LocalTracksTableTableManager(_$AppDatabase db, $LocalTracksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalTracksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalTracksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalTracksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> path = const Value.absent(),
                Value<int> mtime = const Value.absent(),
                Value<int> size = const Value.absent(),
                Value<String?> title = const Value.absent(),
                Value<String?> artistName = const Value.absent(),
                Value<String?> albumName = const Value.absent(),
                Value<int> durationMs = const Value.absent(),
                Value<int?> trackNumber = const Value.absent(),
                Value<String?> coverPath = const Value.absent(),
                Value<int?> scannedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalTracksCompanion(
                path: path,
                mtime: mtime,
                size: size,
                title: title,
                artistName: artistName,
                albumName: albumName,
                durationMs: durationMs,
                trackNumber: trackNumber,
                coverPath: coverPath,
                scannedAt: scannedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String path,
                required int mtime,
                required int size,
                Value<String?> title = const Value.absent(),
                Value<String?> artistName = const Value.absent(),
                Value<String?> albumName = const Value.absent(),
                Value<int> durationMs = const Value.absent(),
                Value<int?> trackNumber = const Value.absent(),
                Value<String?> coverPath = const Value.absent(),
                Value<int?> scannedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalTracksCompanion.insert(
                path: path,
                mtime: mtime,
                size: size,
                title: title,
                artistName: artistName,
                albumName: albumName,
                durationMs: durationMs,
                trackNumber: trackNumber,
                coverPath: coverPath,
                scannedAt: scannedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalTracksTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LocalTracksTable,
      LocalTrack,
      $$LocalTracksTableFilterComposer,
      $$LocalTracksTableOrderingComposer,
      $$LocalTracksTableAnnotationComposer,
      $$LocalTracksTableCreateCompanionBuilder,
      $$LocalTracksTableUpdateCompanionBuilder,
      (
        LocalTrack,
        BaseReferences<_$AppDatabase, $LocalTracksTable, LocalTrack>,
      ),
      LocalTrack,
      PrefetchHooks Function()
    >;
typedef $$ToplistsCacheTableCreateCompanionBuilder =
    ToplistsCacheCompanion Function({
      required String platform,
      required String toplistId,
      required String name,
      Value<String?> coverUrl,
      Value<String?> updateFrequency,
      Value<String?> period,
      Value<int?> songCount,
      Value<String?> groupName,
      Value<String?> intro,
      required int fetchedAt,
      Value<int> rowid,
    });
typedef $$ToplistsCacheTableUpdateCompanionBuilder =
    ToplistsCacheCompanion Function({
      Value<String> platform,
      Value<String> toplistId,
      Value<String> name,
      Value<String?> coverUrl,
      Value<String?> updateFrequency,
      Value<String?> period,
      Value<int?> songCount,
      Value<String?> groupName,
      Value<String?> intro,
      Value<int> fetchedAt,
      Value<int> rowid,
    });

class $$ToplistsCacheTableFilterComposer
    extends Composer<_$AppDatabase, $ToplistsCacheTable> {
  $$ToplistsCacheTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get platform => $composableBuilder(
    column: $table.platform,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get toplistId => $composableBuilder(
    column: $table.toplistId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get coverUrl => $composableBuilder(
    column: $table.coverUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get updateFrequency => $composableBuilder(
    column: $table.updateFrequency,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get period => $composableBuilder(
    column: $table.period,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get songCount => $composableBuilder(
    column: $table.songCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get groupName => $composableBuilder(
    column: $table.groupName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get intro => $composableBuilder(
    column: $table.intro,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get fetchedAt => $composableBuilder(
    column: $table.fetchedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ToplistsCacheTableOrderingComposer
    extends Composer<_$AppDatabase, $ToplistsCacheTable> {
  $$ToplistsCacheTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get platform => $composableBuilder(
    column: $table.platform,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get toplistId => $composableBuilder(
    column: $table.toplistId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get coverUrl => $composableBuilder(
    column: $table.coverUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get updateFrequency => $composableBuilder(
    column: $table.updateFrequency,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get period => $composableBuilder(
    column: $table.period,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get songCount => $composableBuilder(
    column: $table.songCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get groupName => $composableBuilder(
    column: $table.groupName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get intro => $composableBuilder(
    column: $table.intro,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get fetchedAt => $composableBuilder(
    column: $table.fetchedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ToplistsCacheTableAnnotationComposer
    extends Composer<_$AppDatabase, $ToplistsCacheTable> {
  $$ToplistsCacheTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get platform =>
      $composableBuilder(column: $table.platform, builder: (column) => column);

  GeneratedColumn<String> get toplistId =>
      $composableBuilder(column: $table.toplistId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get coverUrl =>
      $composableBuilder(column: $table.coverUrl, builder: (column) => column);

  GeneratedColumn<String> get updateFrequency => $composableBuilder(
    column: $table.updateFrequency,
    builder: (column) => column,
  );

  GeneratedColumn<String> get period =>
      $composableBuilder(column: $table.period, builder: (column) => column);

  GeneratedColumn<int> get songCount =>
      $composableBuilder(column: $table.songCount, builder: (column) => column);

  GeneratedColumn<String> get groupName =>
      $composableBuilder(column: $table.groupName, builder: (column) => column);

  GeneratedColumn<String> get intro =>
      $composableBuilder(column: $table.intro, builder: (column) => column);

  GeneratedColumn<int> get fetchedAt =>
      $composableBuilder(column: $table.fetchedAt, builder: (column) => column);
}

class $$ToplistsCacheTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ToplistsCacheTable,
          ToplistCacheRow,
          $$ToplistsCacheTableFilterComposer,
          $$ToplistsCacheTableOrderingComposer,
          $$ToplistsCacheTableAnnotationComposer,
          $$ToplistsCacheTableCreateCompanionBuilder,
          $$ToplistsCacheTableUpdateCompanionBuilder,
          (
            ToplistCacheRow,
            BaseReferences<_$AppDatabase, $ToplistsCacheTable, ToplistCacheRow>,
          ),
          ToplistCacheRow,
          PrefetchHooks Function()
        > {
  $$ToplistsCacheTableTableManager(_$AppDatabase db, $ToplistsCacheTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ToplistsCacheTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ToplistsCacheTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ToplistsCacheTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> platform = const Value.absent(),
                Value<String> toplistId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> coverUrl = const Value.absent(),
                Value<String?> updateFrequency = const Value.absent(),
                Value<String?> period = const Value.absent(),
                Value<int?> songCount = const Value.absent(),
                Value<String?> groupName = const Value.absent(),
                Value<String?> intro = const Value.absent(),
                Value<int> fetchedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ToplistsCacheCompanion(
                platform: platform,
                toplistId: toplistId,
                name: name,
                coverUrl: coverUrl,
                updateFrequency: updateFrequency,
                period: period,
                songCount: songCount,
                groupName: groupName,
                intro: intro,
                fetchedAt: fetchedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String platform,
                required String toplistId,
                required String name,
                Value<String?> coverUrl = const Value.absent(),
                Value<String?> updateFrequency = const Value.absent(),
                Value<String?> period = const Value.absent(),
                Value<int?> songCount = const Value.absent(),
                Value<String?> groupName = const Value.absent(),
                Value<String?> intro = const Value.absent(),
                required int fetchedAt,
                Value<int> rowid = const Value.absent(),
              }) => ToplistsCacheCompanion.insert(
                platform: platform,
                toplistId: toplistId,
                name: name,
                coverUrl: coverUrl,
                updateFrequency: updateFrequency,
                period: period,
                songCount: songCount,
                groupName: groupName,
                intro: intro,
                fetchedAt: fetchedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ToplistsCacheTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ToplistsCacheTable,
      ToplistCacheRow,
      $$ToplistsCacheTableFilterComposer,
      $$ToplistsCacheTableOrderingComposer,
      $$ToplistsCacheTableAnnotationComposer,
      $$ToplistsCacheTableCreateCompanionBuilder,
      $$ToplistsCacheTableUpdateCompanionBuilder,
      (
        ToplistCacheRow,
        BaseReferences<_$AppDatabase, $ToplistsCacheTable, ToplistCacheRow>,
      ),
      ToplistCacheRow,
      PrefetchHooks Function()
    >;
typedef $$PlayEventsTableCreateCompanionBuilder =
    PlayEventsCompanion Function({
      Value<int> id,
      required String songId,
      required String platform,
      required int startedAt,
      Value<int?> endedAt,
      Value<int> durationListened,
      Value<double> completedRatio,
      Value<String?> source,
    });
typedef $$PlayEventsTableUpdateCompanionBuilder =
    PlayEventsCompanion Function({
      Value<int> id,
      Value<String> songId,
      Value<String> platform,
      Value<int> startedAt,
      Value<int?> endedAt,
      Value<int> durationListened,
      Value<double> completedRatio,
      Value<String?> source,
    });

class $$PlayEventsTableFilterComposer
    extends Composer<_$AppDatabase, $PlayEventsTable> {
  $$PlayEventsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get songId => $composableBuilder(
    column: $table.songId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get platform => $composableBuilder(
    column: $table.platform,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get endedAt => $composableBuilder(
    column: $table.endedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationListened => $composableBuilder(
    column: $table.durationListened,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get completedRatio => $composableBuilder(
    column: $table.completedRatio,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PlayEventsTableOrderingComposer
    extends Composer<_$AppDatabase, $PlayEventsTable> {
  $$PlayEventsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get songId => $composableBuilder(
    column: $table.songId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get platform => $composableBuilder(
    column: $table.platform,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get endedAt => $composableBuilder(
    column: $table.endedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationListened => $composableBuilder(
    column: $table.durationListened,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get completedRatio => $composableBuilder(
    column: $table.completedRatio,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PlayEventsTableAnnotationComposer
    extends Composer<_$AppDatabase, $PlayEventsTable> {
  $$PlayEventsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get songId =>
      $composableBuilder(column: $table.songId, builder: (column) => column);

  GeneratedColumn<String> get platform =>
      $composableBuilder(column: $table.platform, builder: (column) => column);

  GeneratedColumn<int> get startedAt =>
      $composableBuilder(column: $table.startedAt, builder: (column) => column);

  GeneratedColumn<int> get endedAt =>
      $composableBuilder(column: $table.endedAt, builder: (column) => column);

  GeneratedColumn<int> get durationListened => $composableBuilder(
    column: $table.durationListened,
    builder: (column) => column,
  );

  GeneratedColumn<double> get completedRatio => $composableBuilder(
    column: $table.completedRatio,
    builder: (column) => column,
  );

  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);
}

class $$PlayEventsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PlayEventsTable,
          PlayEvent,
          $$PlayEventsTableFilterComposer,
          $$PlayEventsTableOrderingComposer,
          $$PlayEventsTableAnnotationComposer,
          $$PlayEventsTableCreateCompanionBuilder,
          $$PlayEventsTableUpdateCompanionBuilder,
          (
            PlayEvent,
            BaseReferences<_$AppDatabase, $PlayEventsTable, PlayEvent>,
          ),
          PlayEvent,
          PrefetchHooks Function()
        > {
  $$PlayEventsTableTableManager(_$AppDatabase db, $PlayEventsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PlayEventsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PlayEventsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PlayEventsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> songId = const Value.absent(),
                Value<String> platform = const Value.absent(),
                Value<int> startedAt = const Value.absent(),
                Value<int?> endedAt = const Value.absent(),
                Value<int> durationListened = const Value.absent(),
                Value<double> completedRatio = const Value.absent(),
                Value<String?> source = const Value.absent(),
              }) => PlayEventsCompanion(
                id: id,
                songId: songId,
                platform: platform,
                startedAt: startedAt,
                endedAt: endedAt,
                durationListened: durationListened,
                completedRatio: completedRatio,
                source: source,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String songId,
                required String platform,
                required int startedAt,
                Value<int?> endedAt = const Value.absent(),
                Value<int> durationListened = const Value.absent(),
                Value<double> completedRatio = const Value.absent(),
                Value<String?> source = const Value.absent(),
              }) => PlayEventsCompanion.insert(
                id: id,
                songId: songId,
                platform: platform,
                startedAt: startedAt,
                endedAt: endedAt,
                durationListened: durationListened,
                completedRatio: completedRatio,
                source: source,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PlayEventsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PlayEventsTable,
      PlayEvent,
      $$PlayEventsTableFilterComposer,
      $$PlayEventsTableOrderingComposer,
      $$PlayEventsTableAnnotationComposer,
      $$PlayEventsTableCreateCompanionBuilder,
      $$PlayEventsTableUpdateCompanionBuilder,
      (PlayEvent, BaseReferences<_$AppDatabase, $PlayEventsTable, PlayEvent>),
      PlayEvent,
      PrefetchHooks Function()
    >;
typedef $$DailyStatsTableCreateCompanionBuilder =
    DailyStatsCompanion Function({
      required String day,
      required String songId,
      required String platform,
      Value<int> playCount,
      Value<int> listenMs,
      Value<int> rowid,
    });
typedef $$DailyStatsTableUpdateCompanionBuilder =
    DailyStatsCompanion Function({
      Value<String> day,
      Value<String> songId,
      Value<String> platform,
      Value<int> playCount,
      Value<int> listenMs,
      Value<int> rowid,
    });

class $$DailyStatsTableFilterComposer
    extends Composer<_$AppDatabase, $DailyStatsTable> {
  $$DailyStatsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get day => $composableBuilder(
    column: $table.day,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get songId => $composableBuilder(
    column: $table.songId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get platform => $composableBuilder(
    column: $table.platform,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get playCount => $composableBuilder(
    column: $table.playCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get listenMs => $composableBuilder(
    column: $table.listenMs,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DailyStatsTableOrderingComposer
    extends Composer<_$AppDatabase, $DailyStatsTable> {
  $$DailyStatsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get day => $composableBuilder(
    column: $table.day,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get songId => $composableBuilder(
    column: $table.songId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get platform => $composableBuilder(
    column: $table.platform,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get playCount => $composableBuilder(
    column: $table.playCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get listenMs => $composableBuilder(
    column: $table.listenMs,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DailyStatsTableAnnotationComposer
    extends Composer<_$AppDatabase, $DailyStatsTable> {
  $$DailyStatsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get day =>
      $composableBuilder(column: $table.day, builder: (column) => column);

  GeneratedColumn<String> get songId =>
      $composableBuilder(column: $table.songId, builder: (column) => column);

  GeneratedColumn<String> get platform =>
      $composableBuilder(column: $table.platform, builder: (column) => column);

  GeneratedColumn<int> get playCount =>
      $composableBuilder(column: $table.playCount, builder: (column) => column);

  GeneratedColumn<int> get listenMs =>
      $composableBuilder(column: $table.listenMs, builder: (column) => column);
}

class $$DailyStatsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $DailyStatsTable,
          DailyStat,
          $$DailyStatsTableFilterComposer,
          $$DailyStatsTableOrderingComposer,
          $$DailyStatsTableAnnotationComposer,
          $$DailyStatsTableCreateCompanionBuilder,
          $$DailyStatsTableUpdateCompanionBuilder,
          (
            DailyStat,
            BaseReferences<_$AppDatabase, $DailyStatsTable, DailyStat>,
          ),
          DailyStat,
          PrefetchHooks Function()
        > {
  $$DailyStatsTableTableManager(_$AppDatabase db, $DailyStatsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DailyStatsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DailyStatsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DailyStatsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> day = const Value.absent(),
                Value<String> songId = const Value.absent(),
                Value<String> platform = const Value.absent(),
                Value<int> playCount = const Value.absent(),
                Value<int> listenMs = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DailyStatsCompanion(
                day: day,
                songId: songId,
                platform: platform,
                playCount: playCount,
                listenMs: listenMs,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String day,
                required String songId,
                required String platform,
                Value<int> playCount = const Value.absent(),
                Value<int> listenMs = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DailyStatsCompanion.insert(
                day: day,
                songId: songId,
                platform: platform,
                playCount: playCount,
                listenMs: listenMs,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DailyStatsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $DailyStatsTable,
      DailyStat,
      $$DailyStatsTableFilterComposer,
      $$DailyStatsTableOrderingComposer,
      $$DailyStatsTableAnnotationComposer,
      $$DailyStatsTableCreateCompanionBuilder,
      $$DailyStatsTableUpdateCompanionBuilder,
      (DailyStat, BaseReferences<_$AppDatabase, $DailyStatsTable, DailyStat>),
      DailyStat,
      PrefetchHooks Function()
    >;
typedef $$SmartPlaylistSnapshotsTableCreateCompanionBuilder =
    SmartPlaylistSnapshotsCompanion Function({
      required String ruleId,
      required String songKeys,
      required int generatedAt,
      Value<int> rowid,
    });
typedef $$SmartPlaylistSnapshotsTableUpdateCompanionBuilder =
    SmartPlaylistSnapshotsCompanion Function({
      Value<String> ruleId,
      Value<String> songKeys,
      Value<int> generatedAt,
      Value<int> rowid,
    });

class $$SmartPlaylistSnapshotsTableFilterComposer
    extends Composer<_$AppDatabase, $SmartPlaylistSnapshotsTable> {
  $$SmartPlaylistSnapshotsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get ruleId => $composableBuilder(
    column: $table.ruleId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get songKeys => $composableBuilder(
    column: $table.songKeys,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get generatedAt => $composableBuilder(
    column: $table.generatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SmartPlaylistSnapshotsTableOrderingComposer
    extends Composer<_$AppDatabase, $SmartPlaylistSnapshotsTable> {
  $$SmartPlaylistSnapshotsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get ruleId => $composableBuilder(
    column: $table.ruleId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get songKeys => $composableBuilder(
    column: $table.songKeys,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get generatedAt => $composableBuilder(
    column: $table.generatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SmartPlaylistSnapshotsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SmartPlaylistSnapshotsTable> {
  $$SmartPlaylistSnapshotsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get ruleId =>
      $composableBuilder(column: $table.ruleId, builder: (column) => column);

  GeneratedColumn<String> get songKeys =>
      $composableBuilder(column: $table.songKeys, builder: (column) => column);

  GeneratedColumn<int> get generatedAt => $composableBuilder(
    column: $table.generatedAt,
    builder: (column) => column,
  );
}

class $$SmartPlaylistSnapshotsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SmartPlaylistSnapshotsTable,
          SmartPlaylistSnapshot,
          $$SmartPlaylistSnapshotsTableFilterComposer,
          $$SmartPlaylistSnapshotsTableOrderingComposer,
          $$SmartPlaylistSnapshotsTableAnnotationComposer,
          $$SmartPlaylistSnapshotsTableCreateCompanionBuilder,
          $$SmartPlaylistSnapshotsTableUpdateCompanionBuilder,
          (
            SmartPlaylistSnapshot,
            BaseReferences<
              _$AppDatabase,
              $SmartPlaylistSnapshotsTable,
              SmartPlaylistSnapshot
            >,
          ),
          SmartPlaylistSnapshot,
          PrefetchHooks Function()
        > {
  $$SmartPlaylistSnapshotsTableTableManager(
    _$AppDatabase db,
    $SmartPlaylistSnapshotsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SmartPlaylistSnapshotsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$SmartPlaylistSnapshotsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$SmartPlaylistSnapshotsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> ruleId = const Value.absent(),
                Value<String> songKeys = const Value.absent(),
                Value<int> generatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SmartPlaylistSnapshotsCompanion(
                ruleId: ruleId,
                songKeys: songKeys,
                generatedAt: generatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String ruleId,
                required String songKeys,
                required int generatedAt,
                Value<int> rowid = const Value.absent(),
              }) => SmartPlaylistSnapshotsCompanion.insert(
                ruleId: ruleId,
                songKeys: songKeys,
                generatedAt: generatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SmartPlaylistSnapshotsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SmartPlaylistSnapshotsTable,
      SmartPlaylistSnapshot,
      $$SmartPlaylistSnapshotsTableFilterComposer,
      $$SmartPlaylistSnapshotsTableOrderingComposer,
      $$SmartPlaylistSnapshotsTableAnnotationComposer,
      $$SmartPlaylistSnapshotsTableCreateCompanionBuilder,
      $$SmartPlaylistSnapshotsTableUpdateCompanionBuilder,
      (
        SmartPlaylistSnapshot,
        BaseReferences<
          _$AppDatabase,
          $SmartPlaylistSnapshotsTable,
          SmartPlaylistSnapshot
        >,
      ),
      SmartPlaylistSnapshot,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$SongsTableTableManager get songs =>
      $$SongsTableTableManager(_db, _db.songs);
  $$ListeningHistoryTableTableManager get listeningHistory =>
      $$ListeningHistoryTableTableManager(_db, _db.listeningHistory);
  $$UserLikesTableTableManager get userLikes =>
      $$UserLikesTableTableManager(_db, _db.userLikes);
  $$LyricsCacheTableTableManager get lyricsCache =>
      $$LyricsCacheTableTableManager(_db, _db.lyricsCache);
  $$LocalTracksTableTableManager get localTracks =>
      $$LocalTracksTableTableManager(_db, _db.localTracks);
  $$ToplistsCacheTableTableManager get toplistsCache =>
      $$ToplistsCacheTableTableManager(_db, _db.toplistsCache);
  $$PlayEventsTableTableManager get playEvents =>
      $$PlayEventsTableTableManager(_db, _db.playEvents);
  $$DailyStatsTableTableManager get dailyStats =>
      $$DailyStatsTableTableManager(_db, _db.dailyStats);
  $$SmartPlaylistSnapshotsTableTableManager get smartPlaylistSnapshots =>
      $$SmartPlaylistSnapshotsTableTableManager(
        _db,
        _db.smartPlaylistSnapshots,
      );
}
