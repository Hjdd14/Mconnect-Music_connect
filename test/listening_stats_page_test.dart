import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/features/stats/presentation/pages/listening_stats_page.dart';
import 'package:mconnect/features/stats/presentation/providers/listening_stats_provider.dart';
import 'package:mconnect/models/artist.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/song.dart';

/// W3-B: the page-level three states for 听歌统计.
///
/// The page migrated onto `AsyncStateView` with no assertion that could tell —
/// dropping the retry, or letting the spinner replace the error, left every test
/// green (`test/listening_stats_provider_test.dart` is provider-level and belongs
/// to another task, and is deliberately not touched here).
void main() {
  const song = Song(
    id: 's1',
    platform: PlatformType.netease,
    name: '夜曲',
    artists: <Artist>[Artist(id: '', name: '周杰伦')],
  );

  /// Bounded `testWidgets` — a hang is undiagnosable, so a never-completing
  /// future must fail in 30 s rather than eat the runner's 10-minute default.
  void widgetTest(
    String description,
    Future<void> Function(WidgetTester) body,
  ) {
    testWidgets(
      description,
      body,
      timeout: const Timeout(Duration(seconds: 30)),
    );
  }

  Widget wrap(ListeningStatsNotifier notifier) {
    return ProviderScope(
      overrides: [
        listeningStatsProvider.overrideWith((ref) => notifier),
        // The page watches this one too, and the real implementation reads the
        // drift database. A widget test must override it: real I/O never completes
        // inside `testWidgets`' fake-async zone, and a future that never completes
        // is exactly how a suite ends up hanging.
        listeningStatsReportProvider.overrideWith(
          (ref) async => const ListeningStatsReport(
            artists: <ListeningStatsDimension>[],
            albums: <ListeningStatsDimension>[],
            platforms: <ListeningStatsDimension>[],
            days: <ListeningStatsDay>[],
            hours: <ListeningStatsHourBucket>[],
          ),
        ),
      ],
      child: const MaterialApp(home: ListeningStatsPage()),
    );
  }

  widgetTest('loading is the shared spinner, with no retry', (tester) async {
    final pending = Completer<ListeningStatsState>();
    final notifier = ListeningStatsNotifier(
      _PendingStatsRepository(pending),
      // The legacy Hive import is a migration concern, not this state's.
      importLegacySnapshot: false,
    );

    await tester.pumpWidget(wrap(notifier));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      find.text('重试'),
      findsNothing,
      reason: '加载中不是失败，不能给重试',
    );

    // Let the load finish so nothing is left pending into teardown.
    pending.complete(const ListeningStatsState());
    await tester.pump();
  });

  widgetTest('a failed load is an error state whose retry really reloads', (
    tester,
  ) async {
    final repository = _FailingStatsRepository();
    final notifier = ListeningStatsNotifier(
      repository,
      importLegacySnapshot: false,
    );

    await tester.pumpWidget(wrap(notifier));
    await tester.pumpAndSettle();

    expect(
      find.text('听歌统计加载失败'),
      findsOneWidget,
      reason: 'provider 的固定文案（listening_stats_provider.dart:114）',
    );
    expect(find.widgetWithText(ElevatedButton, '重试'), findsOneWidget);
    expect(repository.loads, 1);

    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();

    expect(
      repository.loads,
      2,
      reason: '点重试必须真的再读一次，而不是只把错误清掉',
    );
  });

  widgetTest('no records is a section-level empty state, not an error', (
    tester,
  ) async {
    final notifier = ListeningStatsNotifier(
      MemoryListeningStatsRepository(),
      importLegacySnapshot: false,
    );

    await tester.pumpWidget(wrap(notifier));
    await tester.pumpAndSettle();

    expect(find.text('还没有统计记录'), findsOneWidget);
    // The page itself has content (the four summary tiles), so this is an empty
    // *section*: it must not offer a retry, which would imply a failure.
    expect(find.text('重试'), findsNothing);
    expect(find.text('播放次数'), findsOneWidget);
  });

  widgetTest('a recorded play renders its row instead of the empty state', (
    tester,
  ) async {
    final repository = MemoryListeningStatsRepository();
    await repository.recordSongStarted(song);
    await repository.addListenedDuration(song, const Duration(minutes: 3));
    final notifier = ListeningStatsNotifier(
      repository,
      importLegacySnapshot: false,
    );

    await tester.pumpWidget(wrap(notifier));
    await tester.pumpAndSettle();

    expect(find.text('夜曲'), findsOneWidget);
    expect(find.text('还没有统计记录'), findsNothing);
  });
}

/// A repository whose `load()` never completes, to hold the loading state.
class _PendingStatsRepository extends MemoryListeningStatsRepository {
  _PendingStatsRepository(this.pending);

  final Completer<ListeningStatsState> pending;

  @override
  Future<ListeningStatsState> load() => pending.future;
}

/// A repository whose every read fails.
class _FailingStatsRepository extends MemoryListeningStatsRepository {
  int loads = 0;

  @override
  Future<ListeningStatsState> load() async {
    loads++;
    throw Exception('stats db down');
  }
}
