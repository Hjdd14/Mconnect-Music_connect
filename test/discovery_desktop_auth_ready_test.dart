import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/features/auth/presentation/providers/auth_provider.dart';
import 'package:mconnect/features/discovery/presentation/desktop/discovery_desktop_page.dart';
import 'package:mconnect/features/discovery/presentation/providers/playlist_recommendations_provider.dart';
import 'package:mconnect/features/new_songs/presentation/providers/new_songs_provider.dart';
import 'package:mconnect/features/toplist/presentation/providers/toplists_provider.dart';
import 'package:mconnect/models/artist.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/song.dart';
import 'package:mconnect/models/user.dart';

/// 冷启动竞态：`App.initState` 里 `authProvider.init()` 是"发了不等"，而它要读
/// 安全存储、再对每个平台打一次 `getUserInfo()`。桌面发现页的 post-frame 加载
/// 会先跑，此时每个平台都还是"未登录"，于是页面停在"还没有每日推荐"，只能靠
/// 右上角刷新救回来（手机端早就监听登录态了，桌面版漏了这一段）。
void main() {
  testWidgets('waits for the session restore instead of showing "not logged in"', (
    tester,
  ) async {
    final auth = _FakeAuth()..apply(const AuthState(restoring: true));
    final recommendations = _RecordingRecommendations();
    final toplists = _FakeToplists();
    final newSongs = _FakeNewSongs();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authProvider.overrideWith((ref) => auth),
          playlistRecommendationsProvider.overrideWith((ref) => recommendations),
          toplistsProvider.overrideWith((ref) => toplists),
          newSongsProvider.overrideWith((ref) => newSongs),
        ],
        child: const MaterialApp(
          home: Scaffold(body: DiscoveryDesktopPage()),
        ),
      ),
    );
    await tester.pump();

    // While the restore runs: a spinner, and no request fired at all.
    expect(recommendations.loads, 0);
    expect(
      find.byKey(const ValueKey('discovery-recommendations-loading')),
      findsOneWidget,
    );
    expect(find.text('还没有每日推荐'), findsNothing);

    // Restore finishes with one logged-in platform.
    auth.apply(
      AuthState(
        restoring: false,
        loggedUsers: {PlatformType.netease: _user(PlatformType.netease)},
      ),
    );
    await tester.pump();

    // The page loaded by itself, no 刷新 tap needed.
    expect(recommendations.loads, 1);
    expect(
      find.byKey(const ValueKey('discovery-recommendations-loading')),
      findsNothing,
    );
    expect(find.text('Weightless'), findsOneWidget);
    expect(find.text('还没有每日推荐'), findsNothing);
  });

  testWidgets('does not reload when the login set has not changed', (
    tester,
  ) async {
    final auth = _FakeAuth()
      ..apply(
        AuthState(
          loggedUsers: {PlatformType.netease: _user(PlatformType.netease)},
        ),
      );
    final recommendations = _RecordingRecommendations();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authProvider.overrideWith((ref) => auth),
          playlistRecommendationsProvider.overrideWith((ref) => recommendations),
          toplistsProvider.overrideWith((ref) => _FakeToplists()),
          newSongsProvider.overrideWith((ref) => _FakeNewSongs()),
        ],
        child: const MaterialApp(
          home: Scaffold(body: DiscoveryDesktopPage()),
        ),
      ),
    );
    await tester.pump();
    expect(recommendations.loads, 1);

    // An unrelated auth emission (e.g. a profile refresh) must not refetch.
    auth.apply(
      AuthState(
        loggedUsers: {PlatformType.netease: _user(PlatformType.netease)},
        expiryNoticeId: 7,
      ),
    );
    await tester.pump();
    expect(recommendations.loads, 1);

    // A real login change does refetch.
    auth.apply(
      AuthState(
        loggedUsers: {
          PlatformType.netease: _user(PlatformType.netease),
          PlatformType.qq: _user(PlatformType.qq),
        },
      ),
    );
    await tester.pump();
    expect(recommendations.loads, 2);
  });

  testWidgets('a logged-out start still explains itself once the restore ends', (
    tester,
  ) async {
    final auth = _FakeAuth()..apply(const AuthState(restoring: true));
    final recommendations = _RecordingRecommendations(seed: null);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authProvider.overrideWith((ref) => auth),
          playlistRecommendationsProvider.overrideWith((ref) => recommendations),
          toplistsProvider.overrideWith((ref) => _FakeToplists()),
          newSongsProvider.overrideWith((ref) => _FakeNewSongs()),
        ],
        child: const MaterialApp(
          home: Scaffold(body: DiscoveryDesktopPage()),
        ),
      ),
    );
    await tester.pump();
    expect(recommendations.loads, 0);

    auth.apply(const AuthState());
    await tester.pump();
    await tester.pump();

    expect(recommendations.loads, 1);
    expect(find.text('还没有每日推荐'), findsOneWidget);
  });
}

User _user(PlatformType platform) =>
    User(id: 'u-${platform.name}', nickname: '测试', platform: platform);

Song _song() => Song(
  id: 'n-1',
  platform: PlatformType.netease,
  name: 'Weightless',
  artists: const <Artist>[Artist(id: 'a-1', name: 'Hwavey')],
  duration: const Duration(minutes: 3),
);

/// `state` is protected, so the test mutates it from a subclass.
class _FakeAuth extends AuthNotifier {
  void apply(AuthState next) => state = next;
}

class _RecordingRecommendations extends PlaylistRecommendationsNotifier {
  _RecordingRecommendations({this.seed = const _Seed()})
    : super(supportedTypes: const <PlatformType>[]);

  final _Seed? seed;
  int loads = 0;

  @override
  Future<void> loadRecommendations() async {
    loads++;
    state = PlaylistRecommendationsState(
      songsByPlatform: seed == null
          ? const {}
          : {PlatformType.netease: [_song()]},
    );
  }
}

class _Seed {
  const _Seed();
}

class _FakeToplists extends ToplistsNotifier {
  _FakeToplists() : super(supportedTypes: const <PlatformType>[]);
}

class _FakeNewSongs extends NewSongsNotifier {
  _FakeNewSongs() : super(supportedTypes: const <PlatformType>[]);
}
