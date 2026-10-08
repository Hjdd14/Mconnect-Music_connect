import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/core/database/app_database.dart';
import 'package:mconnect/features/library/presentation/pages/likes_page.dart';
import 'package:mconnect/features/library/presentation/providers/likes_provider.dart';
import 'package:mconnect/features/player/presentation/providers/player_provider.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/song.dart';

import 'support/content_page_fakes.dart';

/// In-memory stand-in for the liked-songs notifier.
///
/// **Why not the real `LikesNotifier`:** a `testWidgets` body runs in a
/// fake-async zone, so awaiting drift's real database IO there never finishes
/// (the run stalls instead of failing — this already cost the team one stalled
/// run holding the native-asset lock). The database behaviour of
/// `toggleLike` is covered by `test/likes_provider_test.dart` with a real
/// in-memory database; here only the UI→notifier chain is under test.
class _StubLikes extends LikesNotifier {
  _StubLikes(AppDatabase db, {List<Song> initial = const []})
    : _songs = [...initial],
      _db = db,
      super(db.likesDao, db.songsDao) {
    // The super constructor kicks off `loadLikes()`; the override is a no-op, so
    // seeding the state here is what the page sees.
    state = LikesState(songs: List<Song>.from(_songs));
  }

  final List<Song> _songs;
  // Kept only to satisfy the DAO arguments; never queried by the overrides.
  // ignore: unused_field
  final AppDatabase _db;

  /// Songs the app asked to toggle, in order — lets a test assert the menu acted
  /// on the row it was opened from.
  final toggledSongs = <Song>[];

  /// How many times the page asked for a (re)load — the three-state tests need
  /// this to prove the retry button is wired to `loadLikes`.
  int loadCalls = 0;

  /// Puts the page into an arbitrary state (loading / error / filtered empty).
  ///
  /// A method rather than a direct `state = …` from the test body: `state` is
  /// `@protected`, so only the subclass may write it.
  void seedState(LikesState next) => state = next;

  @override
  Future<void> loadLikes() async {
    loadCalls++;
  }

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

/// 我喜欢：long-press → the shared song menu.
///
/// The gesture already exists on the other song lists (playlist detail, 榜单,
/// 搜索…), so it has to mean the same thing here. These tests drive the whole
/// chain and assert a real outcome (the notifier's state and the rebuilt list),
/// not merely that the menu appeared.
void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  // The provider's notifier is disposed by Riverpod; only the unused database
  // handle is ours to close.
  tearDown(() async {
    await db.close();
  });

  Future<void> pumpPage(
    WidgetTester tester,
    LikesNotifier likes, {
    PlayerNotifier? player,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          likesProvider.overrideWith((ref) => likes),
          if (player != null) playerProvider.overrideWith((ref) => player),
        ],
        child: const MaterialApp(home: LikesPage()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('长按 → 菜单 → 取消喜欢：歌曲移出我喜欢，列表回到空态', (tester) async {
    final liked = song('n1', PlatformType.netease, name: '晴天', artist: '周杰伦');
    final likes = _StubLikes(db, initial: [liked]);

    await pumpPage(tester, likes);
    expect(find.text('我喜欢 (1)'), findsOneWidget);
    expect(find.text('晴天'), findsOneWidget);

    await tester.longPress(find.text('晴天'));
    await tester.pumpAndSettle();

    // The row is a liked song, so the menu must offer the unlike direction —
    // that is the `isLiked: true` wiring under test.
    expect(find.text('取消喜欢'), findsOneWidget);

    await tester.tap(find.text('取消喜欢'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(likes.toggledSongs.single.id, 'n1');
    expect(likes.state.songs, isEmpty, reason: '菜单动作必须真的改状态');
    expect(find.text('还没有喜欢的歌曲'), findsOneWidget, reason: '列表要跟着状态重建');
    expect(find.text('我喜欢 (0)'), findsOneWidget);

    // Drain the success snackbar's timer before the test ends.
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('长按 → 喜欢方向正确显示：已喜欢的行显示「取消喜欢」而不是「喜欢」', (tester) async {
    final likes = _StubLikes(
      db,
      initial: [song('n1', PlatformType.netease, name: '晴天')],
    );

    await pumpPage(tester, likes);
    await tester.longPress(find.text('晴天'));
    await tester.pumpAndSettle();

    expect(find.text('取消喜欢'), findsOneWidget);
    expect(find.text('喜欢'), findsNothing);

    // Close without choosing anything: nothing may change.
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(likes.toggledSongs, isEmpty);
    expect(likes.state.songs, hasLength(1));
  });

  testWidgets('长按 → 菜单 → 下一首播放：插到当前曲目之后', (tester) async {
    final platform = registerFake(
      FakeContentPlatform(type: PlatformType.netease),
    );
    final likes = _StubLikes(
      db,
      initial: [song('n1', PlatformType.netease, name: '晴天')],
    );

    final player = PlayerNotifier(
      audioController: IdleAudioController(),
      platformResolver: (_) => platform,
    );
    await player.playSong(song('current', PlatformType.netease, name: '正在播放'));

    await pumpPage(tester, likes, player: player);

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

  /// 三态契约（W0-E）：这一页的内联三态换成了共享的 `AsyncStateView`。
  ///
  /// The three assertions here are the ones that were impossible before the
  /// migration: a *skeleton* (not a spinner) while loading, and a retry that is
  /// an `ElevatedButton` wired back to `loadLikes`.
  group('我喜欢 · 三态契约（W0-E）', () {
    Future<void> pumpRaw(WidgetTester tester, LikesNotifier likes) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [likesProvider.overrideWith((ref) => likes)],
          child: const MaterialApp(home: LikesPage()),
        ),
      );
      // Deliberately `pump`, never `pumpAndSettle`: the skeleton's `Shimmer` is
      // an infinite animation, so settling would time out.
      await tester.pump();
    }

    testWidgets('加载中 → 共享骨架屏；没有转圈，也没有重试', (tester) async {
      final likes = _StubLikes(db)
        ..seedState(const LikesState(isLoading: true));

      await pumpRaw(tester, likes);

      expect(
        find.byKey(const Key('async-skeleton-list')),
        findsOneWidget,
        reason: '高频列表的 loading 态必须是骨架屏',
      );
      expect(
        find.byType(CircularProgressIndicator),
        findsNothing,
        reason: '三态统一后这一页不再有自己的转圈实现',
      );
      expect(find.text('重试'), findsNothing);
    });

    testWidgets('加载失败 → 统一错误态：重试是 ElevatedButton，且真的重新加载', (tester) async {
      final likes = _StubLikes(db)
        ..seedState(const LikesState(error: '加载喜欢列表失败'));
      final loadCallsBefore = likes.loadCalls;

      await pumpRaw(tester, likes);

      expect(find.text('加载失败'), findsOneWidget);
      expect(find.text('加载喜欢列表失败'), findsOneWidget);
      expect(
        find.widgetWithText(ElevatedButton, '重试'),
        findsOneWidget,
        reason: 'AsyncStateView 规则 1：重试永远是 ElevatedButton',
      );
      expect(find.widgetWithText(TextButton, '重试'), findsNothing);

      await tester.tap(find.text('重试'));
      await tester.pump();

      expect(
        likes.loadCalls,
        loadCallsBefore + 1,
        reason: '重试必须接回 provider 的 loadLikes',
      );
    });
  });
}
