import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/core/database/app_database.dart';
import 'package:mconnect/features/library/presentation/providers/likes_provider.dart';
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

  test('toggleLike adds and removes only the local like record', () async {
    final notifier = LikesNotifier(db.likesDao, db.songsDao);
    final song = _song('toggle-me');

    final added = await notifier.toggleLike(song);

    expect(added, isTrue);
    expect(await db.likesDao.isLiked(song.id, song.platform.name), isTrue);
    expect(await db.songsDao.getSong(song.id, song.platform.name), isNotNull);

    final removed = await notifier.toggleLike(song);

    expect(removed, isFalse);
    expect(await db.likesDao.isLiked(song.id, song.platform.name), isFalse);
    expect(await db.songsDao.getSong(song.id, song.platform.name), isNotNull);
  });
}

Song _song(String id) {
  return Song(
    id: id,
    platform: PlatformType.netease,
    name: 'song $id',
    artists: const [Artist(id: 'artist', name: 'artist')],
  );
}
