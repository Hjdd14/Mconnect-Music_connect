// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint

// --- Songs Table ---

class $SongsTable extends Songs with TableInfo<$SongsTable, SongRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SongsTable(this.attachedDatabase, [this._alias]);

  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id', aliasedName, false,
    type: DriftSqlType.string, requiredDuringInsert: true,
  );
  static const VerificationMeta _platformMeta = const VerificationMeta('platform');
  @override
  late final GeneratedColumn<String> platform = GeneratedColumn<String>(
    'platform', aliasedName, false,
    type: DriftSqlType.string, requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name', aliasedName, false,
    type: DriftSqlType.string, requiredDuringInsert: true,
  );
  static const VerificationMeta _artistsMeta = const VerificationMeta('artists');
  @override
  late final GeneratedColumn<String> artists = GeneratedColumn<String>(
    'artists', aliasedName, false,
    type: DriftSqlType.string, requiredDuringInsert: true,
  );
  static const VerificationMeta _albumNameMeta = const VerificationMeta('albumName');
  @override
  late final GeneratedColumn<String> albumName = GeneratedColumn<String>(
    'album_name', aliasedName, true,
    type: DriftSqlType.string, requiredDuringInsert: false,
  );
  static const VerificationMeta _albumCoverMeta = const VerificationMeta('albumCover');
  @override
  late final GeneratedColumn<String> albumCover = GeneratedColumn<String>(
    'album_cover', aliasedName, true,
    type: DriftSqlType.string, requiredDuringInsert: false,
  );
  static const VerificationMeta _durationMsMeta = const VerificationMeta('durationMs');
  @override
  late final GeneratedColumn<int> durationMs = GeneratedColumn<int>(
    'duration_ms', aliasedName, false,
    type: DriftSqlType.int, requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _fingerprintMeta = const VerificationMeta('fingerprint');
  @override
  late final GeneratedColumn<String> fingerprint = GeneratedColumn<String>(
    'fingerprint', aliasedName, false,
    type: DriftSqlType.string, requiredDuringInsert: true,
  );

  @override
  List<GeneratedColumn> get $columns =>
      [id, platform, name, artists, albumName, albumCover, durationMs, fingerprint];
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
      context.handle(_platformMeta, platform.isAcceptableOrUnknown(data['platform']!, _platformMeta));
    } else if (isInserting) {
      context.missing(_platformMeta);
    }
    if (data.containsKey('name')) {
      context.handle(_nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('artists')) {
      context.handle(_artistsMeta, artists.isAcceptableOrUnknown(data['artists']!, _artistsMeta));
    } else if (isInserting) {
      context.missing(_artistsMeta);
    }
    if (data.containsKey('album_name')) {
      context.handle(_albumNameMeta, albumName.isAcceptableOrUnknown(data['album_name']!, _albumNameMeta));
    }
    if (data.containsKey('album_cover')) {
      context.handle(_albumCoverMeta, albumCover.isAcceptableOrUnknown(data['album_cover']!, _albumCoverMeta));
    }
    if (data.containsKey('duration_ms')) {
      context.handle(_durationMsMeta, durationMs.isAcceptableOrUnknown(data['duration_ms']!, _durationMsMeta));
    }
    if (data.containsKey('fingerprint')) {
      context.handle(_fingerprintMeta, fingerprint.isAcceptableOrUnknown(data['fingerprint']!, _fingerprintMeta));
    } else if (isInserting) {
      context.missing(_fingerprintMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id, platform};
  @override
  SongRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SongRecord(
      id: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      platform: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}platform'])!,
      name: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      artists: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}artists'])!,
      albumName: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}album_name']),
      albumCover: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}album_cover']),
      durationMs: attachedDatabase.typeMapping.read(DriftSqlType.int, data['${effectivePrefix}duration_ms'])!,
      fingerprint: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}fingerprint'])!,
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

  const SongRecord({
    required this.id,
    required this.platform,
    required this.name,
    required this.artists,
    this.albumName,
    this.albumCover,
    required this.durationMs,
    required this.fingerprint,
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
    return map;
  }

  SongsCompanion toCompanion(bool nullToAbsent) {
    return SongsCompanion(
      id: Value(id),
      platform: Value(platform),
      name: Value(name),
      artists: Value(artists),
      albumName: albumName == null && nullToAbsent ? const Value.absent() : Value(albumName),
      albumCover: albumCover == null && nullToAbsent ? const Value.absent() : Value(albumCover),
      durationMs: Value(durationMs),
      fingerprint: Value(fingerprint),
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
      albumName: serializer.fromJson<String?>(json['album_name']),
      albumCover: serializer.fromJson<String?>(json['album_cover']),
      durationMs: serializer.fromJson<int>(json['duration_ms']),
      fingerprint: serializer.fromJson<String>(json['fingerprint']),
    );
  }

  factory SongRecord.fromJsonString(
    String encodedJson, {
    ValueSerializer? serializer,
  }) =>
      SongRecord.fromJson(
        DataClass.parseJson(encodedJson) as Map<String, dynamic>,
        serializer: serializer,
      );

  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'platform': serializer.toJson<String>(platform),
      'name': serializer.toJson<String>(name),
      'artists': serializer.toJson<String>(artists),
      'album_name': serializer.toJson<String?>(albumName),
      'album_cover': serializer.toJson<String?>(albumCover),
      'duration_ms': serializer.toJson<int>(durationMs),
      'fingerprint': serializer.toJson<String>(fingerprint),
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
  }) =>
      SongRecord(
        id: id ?? this.id,
        platform: platform ?? this.platform,
        name: name ?? this.name,
        artists: artists ?? this.artists,
        albumName: albumName.present ? albumName.value : this.albumName,
        albumCover: albumCover.present ? albumCover.value : this.albumCover,
        durationMs: durationMs ?? this.durationMs,
        fingerprint: fingerprint ?? this.fingerprint,
      );

  SongRecord copyWithCompanion(SongsCompanion data) {
    return SongRecord(
      id: data.id.present ? data.id.value : this.id,
      platform: data.platform.present ? data.platform.value : this.platform,
      name: data.name.present ? data.name.value : this.name,
      artists: data.artists.present ? data.artists.value : this.artists,
      albumName: data.albumName.present ? data.albumName.value : this.albumName,
      albumCover: data.albumCover.present ? data.albumCover.value : this.albumCover,
      durationMs: data.durationMs.present ? data.durationMs.value : this.durationMs,
      fingerprint: data.fingerprint.present ? data.fingerprint.value : this.fingerprint,
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
          ..write('fingerprint: $fingerprint')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, platform, name, artists, albumName, albumCover, durationMs, fingerprint);
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
          other.fingerprint == this.fingerprint);
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

  const SongsCompanion({
    this.id = const Value.absent(),
    this.platform = const Value.absent(),
    this.name = const Value.absent(),
    this.artists = const Value.absent(),
    this.albumName = const Value.absent(),
    this.albumCover = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.fingerprint = const Value.absent(),
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
  })  : id = Value(id),
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
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) map['id'] = Variable<String>(id.value);
    if (platform.present) map['platform'] = Variable<String>(platform.value);
    if (name.present) map['name'] = Variable<String>(name.value);
    if (artists.present) map['artists'] = Variable<String>(artists.value);
    if (albumName.present) map['album_name'] = Variable<String>(albumName.value);
    if (albumCover.present) map['album_cover'] = Variable<String>(albumCover.value);
    if (durationMs.present) map['duration_ms'] = Variable<int>(durationMs.value);
    if (fingerprint.present) map['fingerprint'] = Variable<String>(fingerprint.value);
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
          ..write('fingerprint: $fingerprint')
          ..write(')'))
        .toString();
  }
}

// --- ListeningHistory Table ---

class $ListeningHistoryTable extends ListeningHistory
    with TableInfo<$ListeningHistoryTable, ListeningHistoryEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ListeningHistoryTable(this.attachedDatabase, [this._alias]);

  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id', aliasedName, false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'),
  );
  static const VerificationMeta _songIdMeta = const VerificationMeta('songId');
  @override
  late final GeneratedColumn<String> songId = GeneratedColumn<String>(
    'song_id', aliasedName, false,
    type: DriftSqlType.string, requiredDuringInsert: true,
  );
  static const VerificationMeta _platformMeta = const VerificationMeta('platform');
  @override
  late final GeneratedColumn<String> platform = GeneratedColumn<String>(
    'platform', aliasedName, false,
    type: DriftSqlType.string, requiredDuringInsert: true,
  );
  static const VerificationMeta _listenedAtMeta = const VerificationMeta('listenedAt');
  @override
  late final GeneratedColumn<int> listenedAt = GeneratedColumn<int>(
    'listened_at', aliasedName, false,
    type: DriftSqlType.int, requiredDuringInsert: true,
  );
  static const VerificationMeta _durationListenedMeta = const VerificationMeta('durationListened');
  @override
  late final GeneratedColumn<int> durationListened = GeneratedColumn<int>(
    'duration_listened', aliasedName, false,
    type: DriftSqlType.int, requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );

  @override
  List<GeneratedColumn> get $columns => [id, songId, platform, listenedAt, durationListened];
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
      context.handle(_songIdMeta, songId.isAcceptableOrUnknown(data['song_id']!, _songIdMeta));
    } else if (isInserting) {
      context.missing(_songIdMeta);
    }
    if (data.containsKey('platform')) {
      context.handle(_platformMeta, platform.isAcceptableOrUnknown(data['platform']!, _platformMeta));
    } else if (isInserting) {
      context.missing(_platformMeta);
    }
    if (data.containsKey('listened_at')) {
      context.handle(_listenedAtMeta, listenedAt.isAcceptableOrUnknown(data['listened_at']!, _listenedAtMeta));
    } else if (isInserting) {
      context.missing(_listenedAtMeta);
    }
    if (data.containsKey('duration_listened')) {
      context.handle(_durationListenedMeta, durationListened.isAcceptableOrUnknown(data['duration_listened']!, _durationListenedMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [{songId, platform, listenedAt}];

  @override
  ListeningHistoryEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ListeningHistoryEntry(
      id: attachedDatabase.typeMapping.read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      songId: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}song_id'])!,
      platform: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}platform'])!,
      listenedAt: attachedDatabase.typeMapping.read(DriftSqlType.int, data['${effectivePrefix}listened_at'])!,
      durationListened: attachedDatabase.typeMapping.read(DriftSqlType.int, data['${effectivePrefix}duration_listened'])!,
    );
  }

  @override
  $ListeningHistoryTable createAlias(String alias) {
    return $ListeningHistoryTable(attachedDatabase, alias);
  }
}

class ListeningHistoryEntry extends DataClass implements Insertable<ListeningHistoryEntry> {
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
      songId: serializer.fromJson<String>(json['song_id']),
      platform: serializer.fromJson<String>(json['platform']),
      listenedAt: serializer.fromJson<int>(json['listened_at']),
      durationListened: serializer.fromJson<int>(json['duration_listened']),
    );
  }

  factory ListeningHistoryEntry.fromJsonString(
    String encodedJson, {
    ValueSerializer? serializer,
  }) =>
      ListeningHistoryEntry.fromJson(
        DataClass.parseJson(encodedJson) as Map<String, dynamic>,
        serializer: serializer,
      );

  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'song_id': serializer.toJson<String>(songId),
      'platform': serializer.toJson<String>(platform),
      'listened_at': serializer.toJson<int>(listenedAt),
      'duration_listened': serializer.toJson<int>(durationListened),
    };
  }

  ListeningHistoryEntry copyWith({
    int? id,
    String? songId,
    String? platform,
    int? listenedAt,
    int? durationListened,
  }) =>
      ListeningHistoryEntry(
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
      listenedAt: data.listenedAt.present ? data.listenedAt.value : this.listenedAt,
      durationListened: data.durationListened.present ? data.durationListened.value : this.durationListened,
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
  int get hashCode => Object.hash(id, songId, platform, listenedAt, durationListened);
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
  })  : songId = Value(songId),
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
    if (id.present) map['id'] = Variable<int>(id.value);
    if (songId.present) map['song_id'] = Variable<String>(songId.value);
    if (platform.present) map['platform'] = Variable<String>(platform.value);
    if (listenedAt.present) map['listened_at'] = Variable<int>(listenedAt.value);
    if (durationListened.present) map['duration_listened'] = Variable<int>(durationListened.value);
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

// --- UserLikes Table ---

class $UserLikesTable extends UserLikes
    with TableInfo<$UserLikesTable, UserLike> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $UserLikesTable(this.attachedDatabase, [this._alias]);

  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id', aliasedName, false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'),
  );
  static const VerificationMeta _songIdMeta = const VerificationMeta('songId');
  @override
  late final GeneratedColumn<String> songId = GeneratedColumn<String>(
    'song_id', aliasedName, false,
    type: DriftSqlType.string, requiredDuringInsert: true,
  );
  static const VerificationMeta _platformMeta = const VerificationMeta('platform');
  @override
  late final GeneratedColumn<String> platform = GeneratedColumn<String>(
    'platform', aliasedName, false,
    type: DriftSqlType.string, requiredDuringInsert: true,
  );
  static const VerificationMeta _addedAtMeta = const VerificationMeta('addedAt');
  @override
  late final GeneratedColumn<int> addedAt = GeneratedColumn<int>(
    'added_at', aliasedName, false,
    type: DriftSqlType.int, requiredDuringInsert: true,
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
      context.handle(_songIdMeta, songId.isAcceptableOrUnknown(data['song_id']!, _songIdMeta));
    } else if (isInserting) {
      context.missing(_songIdMeta);
    }
    if (data.containsKey('platform')) {
      context.handle(_platformMeta, platform.isAcceptableOrUnknown(data['platform']!, _platformMeta));
    } else if (isInserting) {
      context.missing(_platformMeta);
    }
    if (data.containsKey('added_at')) {
      context.handle(_addedAtMeta, addedAt.isAcceptableOrUnknown(data['added_at']!, _addedAtMeta));
    } else if (isInserting) {
      context.missing(_addedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [{songId, platform}];

  @override
  UserLike map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return UserLike(
      id: attachedDatabase.typeMapping.read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      songId: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}song_id'])!,
      platform: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}platform'])!,
      addedAt: attachedDatabase.typeMapping.read(DriftSqlType.int, data['${effectivePrefix}added_at'])!,
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
      songId: serializer.fromJson<String>(json['song_id']),
      platform: serializer.fromJson<String>(json['platform']),
      addedAt: serializer.fromJson<int>(json['added_at']),
    );
  }

  factory UserLike.fromJsonString(
    String encodedJson, {
    ValueSerializer? serializer,
  }) =>
      UserLike.fromJson(
        DataClass.parseJson(encodedJson) as Map<String, dynamic>,
        serializer: serializer,
      );

  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'song_id': serializer.toJson<String>(songId),
      'platform': serializer.toJson<String>(platform),
      'added_at': serializer.toJson<int>(addedAt),
    };
  }

  UserLike copyWith({int? id, String? songId, String? platform, int? addedAt}) =>
      UserLike(
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
  })  : songId = Value(songId),
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
    if (id.present) map['id'] = Variable<int>(id.value);
    if (songId.present) map['song_id'] = Variable<String>(songId.value);
    if (platform.present) map['platform'] = Variable<String>(platform.value);
    if (addedAt.present) map['added_at'] = Variable<int>(addedAt.value);
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

// --- LyricsCache Table ---

class $LyricsCacheTable extends LyricsCache
    with TableInfo<$LyricsCacheTable, LyricsCacheEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LyricsCacheTable(this.attachedDatabase, [this._alias]);

  static const VerificationMeta _songIdMeta = const VerificationMeta('songId');
  @override
  late final GeneratedColumn<String> songId = GeneratedColumn<String>(
    'song_id', aliasedName, false,
    type: DriftSqlType.string, requiredDuringInsert: true,
  );
  static const VerificationMeta _platformMeta = const VerificationMeta('platform');
  @override
  late final GeneratedColumn<String> platform = GeneratedColumn<String>(
    'platform', aliasedName, false,
    type: DriftSqlType.string, requiredDuringInsert: true,
  );
  static const VerificationMeta _contentMeta = const VerificationMeta('content');
  @override
  late final GeneratedColumn<String> content = GeneratedColumn<String>(
    'content', aliasedName, false,
    type: DriftSqlType.string, requiredDuringInsert: true,
  );
  static const VerificationMeta _formatMeta = const VerificationMeta('format');
  @override
  late final GeneratedColumn<String> format = GeneratedColumn<String>(
    'format', aliasedName, false,
    type: DriftSqlType.string, requiredDuringInsert: true,
  );
  static const VerificationMeta _syncedAtMeta = const VerificationMeta('syncedAt');
  @override
  late final GeneratedColumn<int> syncedAt = GeneratedColumn<int>(
    'synced_at', aliasedName, false,
    type: DriftSqlType.int, requiredDuringInsert: true,
  );

  @override
  List<GeneratedColumn> get $columns => [songId, platform, content, format, syncedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'lyrics_cache';

  @override
  VerificationContext validateIntegrity(
    Insertable<LyricsCacheEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('song_id')) {
      context.handle(_songIdMeta, songId.isAcceptableOrUnknown(data['song_id']!, _songIdMeta));
    } else if (isInserting) {
      context.missing(_songIdMeta);
    }
    if (data.containsKey('platform')) {
      context.handle(_platformMeta, platform.isAcceptableOrUnknown(data['platform']!, _platformMeta));
    } else if (isInserting) {
      context.missing(_platformMeta);
    }
    if (data.containsKey('content')) {
      context.handle(_contentMeta, content.isAcceptableOrUnknown(data['content']!, _contentMeta));
    } else if (isInserting) {
      context.missing(_contentMeta);
    }
    if (data.containsKey('format')) {
      context.handle(_formatMeta, format.isAcceptableOrUnknown(data['format']!, _formatMeta));
    } else if (isInserting) {
      context.missing(_formatMeta);
    }
    if (data.containsKey('synced_at')) {
      context.handle(_syncedAtMeta, syncedAt.isAcceptableOrUnknown(data['synced_at']!, _syncedAtMeta));
    } else if (isInserting) {
      context.missing(_syncedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {songId, platform};

  @override
  LyricsCacheEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LyricsCacheEntry(
      songId: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}song_id'])!,
      platform: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}platform'])!,
      content: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}content'])!,
      format: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}format'])!,
      syncedAt: attachedDatabase.typeMapping.read(DriftSqlType.int, data['${effectivePrefix}synced_at'])!,
    );
  }

  @override
  $LyricsCacheTable createAlias(String alias) {
    return $LyricsCacheTable(attachedDatabase, alias);
  }
}

class LyricsCacheEntry extends DataClass implements Insertable<LyricsCacheEntry> {
  final String songId;
  final String platform;
  final String content;
  final String format;
  final int syncedAt;

  const LyricsCacheEntry({
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

  factory LyricsCacheEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LyricsCacheEntry(
      songId: serializer.fromJson<String>(json['song_id']),
      platform: serializer.fromJson<String>(json['platform']),
      content: serializer.fromJson<String>(json['content']),
      format: serializer.fromJson<String>(json['format']),
      syncedAt: serializer.fromJson<int>(json['synced_at']),
    );
  }

  factory LyricsCacheEntry.fromJsonString(
    String encodedJson, {
    ValueSerializer? serializer,
  }) =>
      LyricsCacheEntry.fromJson(
        DataClass.parseJson(encodedJson) as Map<String, dynamic>,
        serializer: serializer,
      );

  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'song_id': serializer.toJson<String>(songId),
      'platform': serializer.toJson<String>(platform),
      'content': serializer.toJson<String>(content),
      'format': serializer.toJson<String>(format),
      'synced_at': serializer.toJson<int>(syncedAt),
    };
  }

  LyricsCacheEntry copyWith({
    String? songId,
    String? platform,
    String? content,
    String? format,
    int? syncedAt,
  }) =>
      LyricsCacheEntry(
        songId: songId ?? this.songId,
        platform: platform ?? this.platform,
        content: content ?? this.content,
        format: format ?? this.format,
        syncedAt: syncedAt ?? this.syncedAt,
      );

  LyricsCacheEntry copyWithCompanion(LyricsCacheCompanion data) {
    return LyricsCacheEntry(
      songId: data.songId.present ? data.songId.value : this.songId,
      platform: data.platform.present ? data.platform.value : this.platform,
      content: data.content.present ? data.content.value : this.content,
      format: data.format.present ? data.format.value : this.format,
      syncedAt: data.syncedAt.present ? data.syncedAt.value : this.syncedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LyricsCacheEntry(')
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
      (other is LyricsCacheEntry &&
          other.songId == this.songId &&
          other.platform == this.platform &&
          other.content == this.content &&
          other.format == this.format &&
          other.syncedAt == this.syncedAt);
}

class LyricsCacheCompanion extends UpdateCompanion<LyricsCacheEntry> {
  final Value<String> songId;
  final Value<String> platform;
  final Value<String> content;
  final Value<String> format;
  final Value<int> syncedAt;

  const LyricsCacheCompanion({
    this.songId = const Value.absent(),
    this.platform = const Value.absent(),
    this.content = const Value.absent(),
    this.format = const Value.absent(),
    this.syncedAt = const Value.absent(),
  });

  LyricsCacheCompanion.insert({
    required String songId,
    required String platform,
    required String content,
    required String format,
    required int syncedAt,
  })  : songId = Value(songId),
        platform = Value(platform),
        content = Value(content),
        format = Value(format),
        syncedAt = Value(syncedAt);

  static Insertable<LyricsCacheEntry> custom({
    Expression<String>? songId,
    Expression<String>? platform,
    Expression<String>? content,
    Expression<String>? format,
    Expression<int>? syncedAt,
  }) {
    return RawValuesInsertable({
      if (songId != null) 'song_id': songId,
      if (platform != null) 'platform': platform,
      if (content != null) 'content': content,
      if (format != null) 'format': format,
      if (syncedAt != null) 'synced_at': syncedAt,
    });
  }

  LyricsCacheCompanion copyWith({
    Value<String>? songId,
    Value<String>? platform,
    Value<String>? content,
    Value<String>? format,
    Value<int>? syncedAt,
  }) {
    return LyricsCacheCompanion(
      songId: songId ?? this.songId,
      platform: platform ?? this.platform,
      content: content ?? this.content,
      format: format ?? this.format,
      syncedAt: syncedAt ?? this.syncedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (songId.present) map['song_id'] = Variable<String>(songId.value);
    if (platform.present) map['platform'] = Variable<String>(platform.value);
    if (content.present) map['content'] = Variable<String>(content.value);
    if (format.present) map['format'] = Variable<String>(format.value);
    if (syncedAt.present) map['synced_at'] = Variable<int>(syncedAt.value);
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LyricsCacheCompanion(')
          ..write('songId: $songId, ')
          ..write('platform: $platform, ')
          ..write('content: $content, ')
          ..write('format: $format, ')
          ..write('syncedAt: $syncedAt')
          ..write(')'))
        .toString();
  }
}

// --- Playlists Table ---

class $PlaylistsTable extends Playlists
    with TableInfo<$PlaylistsTable, Playlist> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PlaylistsTable(this.attachedDatabase, [this._alias]);

  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id', aliasedName, false,
    type: DriftSqlType.string, requiredDuringInsert: true,
  );
  static const VerificationMeta _platformMeta = const VerificationMeta('platform');
  @override
  late final GeneratedColumn<String> platform = GeneratedColumn<String>(
    'platform', aliasedName, false,
    type: DriftSqlType.string, requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name', aliasedName, false,
    type: DriftSqlType.string, requiredDuringInsert: true,
  );
  static const VerificationMeta _songCountMeta = const VerificationMeta('songCount');
  @override
  late final GeneratedColumn<int> songCount = GeneratedColumn<int>(
    'song_count', aliasedName, false,
    type: DriftSqlType.int, requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _syncedAtMeta = const VerificationMeta('syncedAt');
  @override
  late final GeneratedColumn<int> syncedAt = GeneratedColumn<int>(
    'synced_at', aliasedName, true,
    type: DriftSqlType.int, requiredDuringInsert: false,
  );

  @override
  List<GeneratedColumn> get $columns => [id, platform, name, songCount, syncedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'playlists';

  @override
  VerificationContext validateIntegrity(
    Insertable<Playlist> instance, {
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
      context.handle(_platformMeta, platform.isAcceptableOrUnknown(data['platform']!, _platformMeta));
    } else if (isInserting) {
      context.missing(_platformMeta);
    }
    if (data.containsKey('name')) {
      context.handle(_nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('song_count')) {
      context.handle(_songCountMeta, songCount.isAcceptableOrUnknown(data['song_count']!, _songCountMeta));
    }
    if (data.containsKey('synced_at')) {
      context.handle(_syncedAtMeta, syncedAt.isAcceptableOrUnknown(data['synced_at']!, _syncedAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id, platform};

  @override
  Playlist map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Playlist(
      id: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      platform: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}platform'])!,
      name: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      songCount: attachedDatabase.typeMapping.read(DriftSqlType.int, data['${effectivePrefix}song_count'])!,
      syncedAt: attachedDatabase.typeMapping.read(DriftSqlType.int, data['${effectivePrefix}synced_at']),
    );
  }

  @override
  $PlaylistsTable createAlias(String alias) {
    return $PlaylistsTable(attachedDatabase, alias);
  }
}

class Playlist extends DataClass implements Insertable<Playlist> {
  final String id;
  final String platform;
  final String name;
  final int songCount;
  final int? syncedAt;

  const Playlist({
    required this.id,
    required this.platform,
    required this.name,
    required this.songCount,
    this.syncedAt,
  });

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['platform'] = Variable<String>(platform);
    map['name'] = Variable<String>(name);
    map['song_count'] = Variable<int>(songCount);
    if (!nullToAbsent || syncedAt != null) {
      map['synced_at'] = Variable<int>(syncedAt);
    }
    return map;
  }

  PlaylistsCompanion toCompanion(bool nullToAbsent) {
    return PlaylistsCompanion(
      id: Value(id),
      platform: Value(platform),
      name: Value(name),
      songCount: Value(songCount),
      syncedAt: syncedAt == null && nullToAbsent ? const Value.absent() : Value(syncedAt),
    );
  }

  factory Playlist.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Playlist(
      id: serializer.fromJson<String>(json['id']),
      platform: serializer.fromJson<String>(json['platform']),
      name: serializer.fromJson<String>(json['name']),
      songCount: serializer.fromJson<int>(json['song_count']),
      syncedAt: serializer.fromJson<int?>(json['synced_at']),
    );
  }

  factory Playlist.fromJsonString(
    String encodedJson, {
    ValueSerializer? serializer,
  }) =>
      Playlist.fromJson(
        DataClass.parseJson(encodedJson) as Map<String, dynamic>,
        serializer: serializer,
      );

  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'platform': serializer.toJson<String>(platform),
      'name': serializer.toJson<String>(name),
      'song_count': serializer.toJson<int>(songCount),
      'synced_at': serializer.toJson<int?>(syncedAt),
    };
  }

  Playlist copyWith({
    String? id,
    String? platform,
    String? name,
    int? songCount,
    Value<int?> syncedAt = const Value.absent(),
  }) =>
      Playlist(
        id: id ?? this.id,
        platform: platform ?? this.platform,
        name: name ?? this.name,
        songCount: songCount ?? this.songCount,
        syncedAt: syncedAt.present ? syncedAt.value : this.syncedAt,
      );

  Playlist copyWithCompanion(PlaylistsCompanion data) {
    return Playlist(
      id: data.id.present ? data.id.value : this.id,
      platform: data.platform.present ? data.platform.value : this.platform,
      name: data.name.present ? data.name.value : this.name,
      songCount: data.songCount.present ? data.songCount.value : this.songCount,
      syncedAt: data.syncedAt.present ? data.syncedAt.value : this.syncedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Playlist(')
          ..write('id: $id, ')
          ..write('platform: $platform, ')
          ..write('name: $name, ')
          ..write('songCount: $songCount, ')
          ..write('syncedAt: $syncedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, platform, name, songCount, syncedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Playlist &&
          other.id == this.id &&
          other.platform == this.platform &&
          other.name == this.name &&
          other.songCount == this.songCount &&
          other.syncedAt == this.syncedAt);
}

class PlaylistsCompanion extends UpdateCompanion<Playlist> {
  final Value<String> id;
  final Value<String> platform;
  final Value<String> name;
  final Value<int> songCount;
  final Value<int?> syncedAt;

  const PlaylistsCompanion({
    this.id = const Value.absent(),
    this.platform = const Value.absent(),
    this.name = const Value.absent(),
    this.songCount = const Value.absent(),
    this.syncedAt = const Value.absent(),
  });

  PlaylistsCompanion.insert({
    required String id,
    required String platform,
    required String name,
    this.songCount = const Value.absent(),
    this.syncedAt = const Value.absent(),
  })  : id = Value(id),
        platform = Value(platform),
        name = Value(name);

  static Insertable<Playlist> custom({
    Expression<String>? id,
    Expression<String>? platform,
    Expression<String>? name,
    Expression<int>? songCount,
    Expression<int>? syncedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (platform != null) 'platform': platform,
      if (name != null) 'name': name,
      if (songCount != null) 'song_count': songCount,
      if (syncedAt != null) 'synced_at': syncedAt,
    });
  }

  PlaylistsCompanion copyWith({
    Value<String>? id,
    Value<String>? platform,
    Value<String>? name,
    Value<int>? songCount,
    Value<int?>? syncedAt,
  }) {
    return PlaylistsCompanion(
      id: id ?? this.id,
      platform: platform ?? this.platform,
      name: name ?? this.name,
      songCount: songCount ?? this.songCount,
      syncedAt: syncedAt ?? this.syncedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) map['id'] = Variable<String>(id.value);
    if (platform.present) map['platform'] = Variable<String>(platform.value);
    if (name.present) map['name'] = Variable<String>(name.value);
    if (songCount.present) map['song_count'] = Variable<int>(songCount.value);
    if (syncedAt.present) map['synced_at'] = Variable<int>(syncedAt.value);
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PlaylistsCompanion(')
          ..write('id: $id, ')
          ..write('platform: $platform, ')
          ..write('name: $name, ')
          ..write('songCount: $songCount, ')
          ..write('syncedAt: $syncedAt')
          ..write(')'))
        .toString();
  }
}

// --- DAO Mixins ---

mixin _$SongsDaoMixin on DatabaseAccessor<AppDatabase> {
  $SongsTable get songs => attachedDatabase.songs;
  $ListeningHistoryTable get listeningHistory => attachedDatabase.listeningHistory;
  $UserLikesTable get userLikes => attachedDatabase.userLikes;
  $LyricsCacheTable get lyricsCache => attachedDatabase.lyricsCache;
  $PlaylistsTable get playlists => attachedDatabase.playlists;
}

mixin _$HistoryDaoMixin on DatabaseAccessor<AppDatabase> {
  $SongsTable get songs => attachedDatabase.songs;
  $ListeningHistoryTable get listeningHistory => attachedDatabase.listeningHistory;
}

mixin _$LikesDaoMixin on DatabaseAccessor<AppDatabase> {
  $SongsTable get songs => attachedDatabase.songs;
  $UserLikesTable get userLikes => attachedDatabase.userLikes;
}

mixin _$LyricsCacheDaoMixin on DatabaseAccessor<AppDatabase> {
  $LyricsCacheTable get lyricsCache => attachedDatabase.lyricsCache;
}

// --- Database Class ---

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);

  late final $SongsTable songs = $SongsTable(this);
  late final $ListeningHistoryTable listeningHistory = $ListeningHistoryTable(this);
  late final $UserLikesTable userLikes = $UserLikesTable(this);
  late final $LyricsCacheTable lyricsCache = $LyricsCacheTable(this);
  late final $PlaylistsTable playlists = $PlaylistsTable(this);

  late final SongsDao songsDao = SongsDao(this as AppDatabase);
  late final HistoryDao historyDao = HistoryDao(this as AppDatabase);
  late final LikesDao likesDao = LikesDao(this as AppDatabase);
  late final LyricsCacheDao lyricsCacheDao = LyricsCacheDao(this as AppDatabase);

  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();

  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
        songs,
        listeningHistory,
        userLikes,
        lyricsCache,
        playlists,
      ];
}
