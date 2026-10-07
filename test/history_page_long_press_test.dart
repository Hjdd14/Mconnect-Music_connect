import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/core/database/app_database.dart';
import 'package:mconnect/features/library/presentation/pages/history_page.dart';
import 'package:mconnect/features/library/presentation/providers/history_provider.dart';
import 'package:mconnect/features/library/presentation/providers/likes_provider.dart';
import 'package:mconnect/features/player/presentation/providers/player_provider.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/song.dart';

import 'support/content_page_fakes.dart';

/// In-memory stand-in for the history notifier.
///
/// A `testWidgets` body cannot await drift's real database IO (fake-async zone →
/// the run stalls instead of failing), so the history list is seeded directly
/// and `recordListen`/`clearHistory` are answered in memory. The real DAO
/// behaviour is covered by the plain-`test()` provider tests.
class _StubHistory extends HistoryNotifier {
  _StubHistory(AppDatabase db, {List<HistoryEntry> initial = const []})
    : _db = db,
      super(db.historyDao, db.songsDao) {
    state = HistoryState(entries: List<HistoryEntry>.from(initial));
  }

  // Kept only to satisfy the DAO arguments; never queried by the overrides.
  // ignore: unused_field
  final AppDatabase _db;

  @override
  Future<void> loadHistory() async {}

  @override
  Future<void> recordListen(Song song, {int durationMs = 0}) async {
    state = state.copyWith(
      entries: [
        HistoryEntry(song: song, listenedAt: DateTime.now()),
        ...state.entries,
      ],
    );
  }

  @override
  Future<void> clearHistory() async {
    state = const HistoryState();
  }
}

/// Same shape as the likes-page stub: the history page reads 我喜欢 to label the
/// menu entry, and the assertion is about that state, not about a database.
class _StubLikes extends LikesNotifier {
  _StubLikes(AppDatabase db, {List<Song> initial = const []})
    : _songs = [...initial],
      _db = db,
      super(db.likesDao, db.songsDao) {
    state = LikesState(songs: List<Song>.from(_songs));
  }

  final List<Song> _songs;
  // ignore: unused_field
  final AppDatabase _db;

  final toggledSongs = <Song>[];

  @override
  Future<void> loadLikes() async {}

  @override
  Future<bool> isLiked(String songId, PlatformType platform) async {
    return _songs.any((s) => s.id == songId && s.platform == platform);
  }

  @override
  Future<bool> toggleLike(Song song) async {
    toggledSongs.add(song);
    final index = _songs.indexWhere(
      (s) => s.id == song.id && s.platform == song.platform,
    );
    if (index >= 0) {
      _songs.removeAt(index);
      state = state.copyWith(songs: List<Song>.from(_songs));
      return false;
    }
    _songs.insert(0, song);
    state = state.copyWith(songs: List<Song>.from(_songs));
    return true;
  }
}

/// 听歌历史：long-press → the shared song menu (it used to be missing here, so
/// the same gesture behaved differently from every other song list).
void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> pumpPage(
    WidgetTester tester, {
    required HistoryNotifier history,
    required LikesNotifier likes,
    PlayerNotifier? player,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          historyProvider.overrideWith((ref) => history),
          likesProvider.overrideWith((ref) => likes),
          if (player != null) playerProvider.overrideWith((ref) => player),
        ],
        child: const MaterialApp(home: HistoryPage()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('长按 → 菜单 → 喜欢：写入我喜欢，再次长按改显示「取消喜欢」', (tester) async {
    final played = song('n1', PlatformType.netease, name: '晴天', artist: '周杰伦');
    final history = _StubHistory(
      db,
      initial: [HistoryEntry(song: played, listenedAt: DateTime.now())],
    );
    final likes = _StubLikes(db);

    await pumpPage(tester, history: history, likes: likes);
    expect(find.text('听歌历史 (1)'), findsOneWidget);
    expect(find.text('晴天'), findsOneWidget);

    // Not liked yet → the menu must offer the like direction (this is the
    // `likesProvider` lookup the page gained).
    await tester.longPress(find.text('晴天'));
    await tester.pumpAndSettle();
    expect(find.text('喜欢'), findsOneWidget);
    expect(find.text('取消喜欢'), findsNothing);

    await tester.tap(find.text('喜欢'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(likes.toggledSongs.single.id, 'n1');
    expect(
      likes.state.songs.map((s) => s.id).toList(),
      ['n1'],
      reason: '菜单动作必须真的改喜欢状态',
    );

    // …and the page now reads that state back.
    await tester.longPress(find.text('晴天'));
    await tester.pumpAndSettle();
    expect(find.text('取消喜欢'), findsOneWidget);
    expect(find.text('喜欢'), findsNothing);

    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('长按 → 菜单 → 下一首播放：插到当前曲目之后', (tester) async {
    final platform = registerFake(
      FakeContentPlatform(type: PlatformType.netease),
    );
    final played = song('n1', PlatformType.netease, name: '晴天');
    final history = _StubHistory(
      db,
      initial: [HistoryEntry(song: played, listenedAt: DateTime.now())],
    );
    final likes = _StubLikes(db);

    final player = PlayerNotifier(
      audioController: IdleAudioController(),
      platformResolver: (_) => platform,
    );
    await player.playSong(song('current', PlatformType.netease, name: '正在播放'));

    await pumpPage(tester,
        history: history, likes: likes, player: player);

    await tester.longPress(find.text('晴天'));
    await tester.pumpAndSettle();
    expect(find.text('下一首播放'), findsOneWidget);

    await tester.tap(find.text('下一首播放'));
    await tester.pump();

    expect(player.state.playlist.map((s) => s.name).toList(), [
      '正在播放',
      '晴天',
    ]);
    expect(
      player.state.playlist[player.state.currentIndex + 1].name,
      '晴天',
      reason: '「下一首播放」必须在当前曲目之后，而不是队尾',
    );

    await tester.pump(const Duration(seconds: 5));
  });
}
