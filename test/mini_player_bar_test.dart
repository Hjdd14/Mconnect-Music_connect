import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/features/player/data/playback_keep_alive_service.dart';
import 'package:mconnect/features/player/data/playback_notification_service.dart';
import 'package:mconnect/features/player/presentation/providers/player_provider.dart';
import 'package:mconnect/features/player/presentation/screens/player_screen.dart';
import 'package:mconnect/features/player/presentation/widgets/mini_player_bar.dart';
import 'package:mconnect/models/artist.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/song.dart';

import 'support/content_page_fakes.dart';

/// Wave 0-A (item 1)：`PlayerState.error` 有 14 处赋值，但修复前**没有任何 widget
/// 读它** —— 取流失败、恢复失败、换音质失败在用户眼里就是"点了没反应"。
///
/// 本文件同时覆盖两个监听点（mini player 与全屏播放页）以及它们共享的去重：
/// 生产环境里 `/player` 是压在 shell 上的路由，两个 widget **同时存活**，
/// 各自弹一条就会同一个错误弹两次。
///
/// 每个用例用不同的错误文案，避免共享的去重状态在两个用例之间互相吃掉提示。
const _song = Song(
  id: 'wave0a-1',
  platform: PlatformType.netease,
  name: '正在播放的歌',
  artists: [Artist(id: 'a1', name: '歌手')],
);

class _ErrorPlayerNotifier extends PlayerNotifier {
  _ErrorPlayerNotifier()
    : super(
        audioController: IdleAudioController(),
        audioControllerFactory: IdleAudioController.new,
        keepAliveController: const NoopPlaybackKeepAliveController(),
        notificationController: const NoopPlaybackNotificationController(),
        stuckWatchdogInterval: Duration.zero,
      ) {
    state = state.copyWith(
      currentSong: _song,
      playlist: const [_song],
      currentIndex: 0,
    );
  }

  void emitError(String? message) {
    state = state.copyWith(error: () => message);
  }
}

Future<void> _pumpPlayer(
  WidgetTester tester,
  _ErrorPlayerNotifier player, {
  required bool mini,
  required bool screen,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [playerProvider.overrideWith((ref) => player)],
      child: MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              if (screen) const Expanded(child: PlayerScreen()),
              if (mini) const MiniPlayerBar(),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

/// Advances past **one** SnackBar lifetime (entrance 250 ms + 3 s + exit 250 ms
/// ≈ 3.7 s), in small steps.
///
/// Why stepped instead of one `pump(4s)`: `ScaffoldMessenger` creates the
/// `SnackBar.duration` timer only in the build that **follows** the entrance
/// animation reaching `completed` (Flutter `material/scaffold.dart:617-619`).
/// A single `pump(4s)` advances the entrance to completed *at* the 4 s frame, so
/// the 3 s timer only starts there and the bar is still on screen 4.8 s later —
/// which is exactly what the first version of this helper measured (it was not a
/// duplicate announcement).
///
/// Why 5.5 s and not longer: a **second** queued SnackBar only becomes visible
/// after the first expires and would stay until ≈7 s. So "nothing on screen after
/// 5.5 s" is what proves the error was announced exactly once; a helper that
/// waited long enough to drain two bars would pass even with duplicates.
///
/// Not `pumpAndSettle`: `PlayerScreen` keeps a 1 s periodic timer, so settling
/// never terminates.
Future<void> _drainOneSnackBar(WidgetTester tester) async {
  for (var i = 0; i < 55; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('the mini player surfaces a playback error once per occurrence', (
    tester,
  ) async {
    final player = _ErrorPlayerNotifier();
    addTearDown(player.dispose);
    await _pumpPlayer(tester, player, mini: true, screen: false);

    expect(find.text('取流失败甲'), findsNothing);

    player.emitError('取流失败甲');
    await tester.pump();
    expect(find.text('取流失败甲'), findsOneWidget);

    // 同一条错误只弹一条：一次提示的生命周期走完后屏幕上必须已经没有任何提示。
    await _drainOneSnackBar(tester);
    expect(find.text('取流失败甲'), findsNothing);

    // 错误被清除后，同一条错误必须能再次提示（否则用户第二次遇到就再也看不到）。
    player.emitError(null);
    await tester.pump();
    player.emitError('取流失败甲');
    await tester.pump();
    expect(find.text('取流失败甲'), findsOneWidget);

    await _drainOneSnackBar(tester);
    expect(find.text('取流失败甲'), findsNothing);
  });

  testWidgets('the player screen surfaces a playback error', (tester) async {
    final player = _ErrorPlayerNotifier();
    addTearDown(player.dispose);
    await _pumpPlayer(tester, player, mini: false, screen: true);

    expect(find.text('取流失败乙'), findsNothing);

    player.emitError('取流失败乙');
    await tester.pump();
    expect(find.text('取流失败乙'), findsOneWidget);
  });

  testWidgets('both mounted listeners announce an error exactly once', (
    tester,
  ) async {
    final player = _ErrorPlayerNotifier();
    addTearDown(player.dispose);
    await _pumpPlayer(tester, player, mini: true, screen: true);

    player.emitError('取流失败丙');
    await tester.pump();
    expect(find.text('取流失败丙'), findsOneWidget);

    // 只弹一条：等**一条**提示的生命周期（≈3.7s）过去后，屏幕上必须已经空了。
    // 如果两个监听者各弹一条，第二条会在第一条过期后才出现、并一直留到 ≈7s，
    // 于是在这里被抓住。
    await _drainOneSnackBar(tester);
    expect(
      find.text('取流失败丙'),
      findsNothing,
      reason: '两个监听者必须共享"上次已提示的错误"，同一条错误只能弹一次',
    );
  });
}
