import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/core/transfer/playlist_codec.dart';
import 'package:mconnect/core/transfer/transfer_format.dart';
import 'package:mconnect/core/transfer/transfer_providers.dart';
import 'package:mconnect/core/transfer/transfer_report.dart';
import 'package:mconnect/core/transfer/transfer_runner.dart';
import 'package:mconnect/features/library/data/my_playlists_repository.dart';
import 'package:mconnect/features/library/presentation/pages/import_playlist_page.dart';
import 'package:mconnect/features/library/presentation/providers/my_playlists_provider.dart';
import 'package:mconnect/models/artist.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/playlist.dart';
import 'package:mconnect/models/song.dart';

/// A hang is undiagnosable: bound every widget test so a never-completing future
/// fails in 30 s instead of eating the runner's 10-minute default.
const _timeout = Timeout(Duration(seconds: 30));

/// W1-C increment 2: the matching report the import page renders.
///
/// The hard requirement this file pins down is that **未匹配 rows are shown**:
/// an import that silently drops what it could not resolve is the failure mode
/// the report exists to prevent.

/// Three rows, one per bucket, once the matcher below has answered.
const _threeBucketText = '可入的歌 - 歌手1\n待确认的歌 - 歌手2\n没有的歌 - 歌手3';

const _matchedExact = Song(
  id: 'm1',
  platform: PlatformType.netease,
  name: '可入的歌',
  artists: <Artist>[Artist(id: '', name: '歌手1')],
);

const _matchedWeak = Song(
  id: 'm2',
  platform: PlatformType.qq,
  name: '待确认的歌',
  artists: <Artist>[Artist(id: '', name: '歌手2')],
);

void main() {
  late _FakeMyPlaylistsRepository repository;

  setUp(() {
    repository = _FakeMyPlaylistsRepository();
  });

  // Runs before any widget test on purpose: it pins down which layer is wrong
  // when a bucket assertion fails below. If this passes, the parse and the
  // bucketing are right and the fault is in the page; if it fails, the page was
  // never the problem.
  test('解析 + 匹配：三行各落一桶', () async {
    final document = decodePlaylistTransfer(_threeBucketText);

    expect(document, isNotNull);
    expect(
      document!.entries.map((entry) => entry.title).toList(),
      <String>['可入的歌', '待确认的歌', '没有的歌'],
    );

    final report = await TransferMatcher(matcher: _ThreeBucketMatcher()).match(
      playlistName: document.name,
      entries: document.entries,
    );

    expect(report.exactCount, 1);
    expect(report.needsConfirmationCount, 1);
    expect(report.missingCount, 1);
    expect(report.missing.single.entry.title, '没有的歌');
    expect(report.missing.single.reason, '未找到可播放版本');
  });

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          myPlaylistsProvider.overrideWith(
            (ref) => MyPlaylistsNotifier(repository: repository),
          ),
          playlistSourceMatcherProvider.overrideWithValue(
            _ThreeBucketMatcher(),
          ),
        ],
        child: const MaterialApp(home: ImportPlaylistPage()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> parse(WidgetTester tester, String input) async {
    await tester.enterText(find.byType(TextField), input);
    await tester.tap(find.text('解析'));
    await tester.pumpAndSettle();
  }

  /// Bounded `testWidgets`: a never-completing future must fail in 30 s rather
  /// than eat the runner's 10-minute default and block the whole suite.
  void widgetTest(
    String description,
    Future<void> Function(WidgetTester) body,
  ) {
    testWidgets(description, body, timeout: _timeout);
  }

  widgetTest('粘贴文本后三桶同屏：可入 / 待确认 / 未匹配', (tester) async {
    await pumpPage(tester);
    await parse(tester, _threeBucketText);

    expect(find.text('可入 (1)'), findsOneWidget);
    expect(find.text('待确认 (1)'), findsOneWidget);
    expect(find.text('未匹配 (1)'), findsOneWidget);

    // 三类各自的那一行都在列表里。
    expect(find.text('可入的歌 - 歌手1'), findsOneWidget);
    expect(find.text('待确认的歌 - 歌手2'), findsOneWidget);
    expect(find.text('没有的歌 - 歌手3'), findsOneWidget);
  });

  widgetTest('未匹配的行展示原始行与原因，不被丢弃', (tester) async {
    await pumpPage(tester);
    await parse(tester, _threeBucketText);

    expect(find.text('没有的歌 - 歌手3'), findsOneWidget);
    expect(find.text('未找到可播放版本'), findsOneWidget);
  });

  widgetTest('待确认行可勾选与取消，待导入数量跟着变', (tester) async {
    await pumpPage(tester);
    await parse(tester, _threeBucketText);

    // 默认只导入「可入」的那一首。
    expect(find.text('将导入 1 首'), findsOneWidget);

    await tester.ensureVisible(find.text('待确认的歌 - 歌手2'));
    await tester.tap(find.text('待确认的歌 - 歌手2'));
    await tester.pumpAndSettle();
    expect(find.text('将导入 2 首'), findsOneWidget);

    await tester.ensureVisible(find.text('待确认的歌 - 歌手2'));
    await tester.tap(find.text('待确认的歌 - 歌手2'));
    await tester.pumpAndSettle();
    expect(find.text('将导入 1 首'), findsOneWidget);
  });

  widgetTest('未匹配行不可勾选（没有可导入的目标）', (tester) async {
    await pumpPage(tester);
    await parse(tester, _threeBucketText);

    await tester.ensureVisible(find.text('没有的歌 - 歌手3'));
    await tester.tap(find.text('没有的歌 - 歌手3'));
    await tester.pumpAndSettle();

    expect(find.text('将导入 1 首'), findsOneWidget);
  });

  widgetTest('保存把「可入 + 已勾选的待确认」写进我的歌单，顺序按文档', (tester) async {
    await pumpPage(tester);
    await parse(tester, _threeBucketText);

    await tester.ensureVisible(find.text('待确认的歌 - 歌手2'));
    await tester.tap(find.text('待确认的歌 - 歌手2'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('保存到我的歌单'));
    await tester.pumpAndSettle();

    expect(repository.imported, hasLength(1));
    expect(repository.imported.single.name, '导入歌单');
    expect(
      repository.imported.single.songs.map((song) => song.name).toList(),
      <String>['可入的歌', '待确认的歌'],
    );
  });

  widgetTest('深链投递的文本在页面打开后被自动解析', (tester) async {
    await pumpPage(tester);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ImportPlaylistPage)),
    );
    // What `deep_link_wiring` does when Android forwards an `ACTION_SEND`
    // payload that turned out to be a playlist document.
    container.read(pendingPlaylistTransferProvider.notifier).state =
        _threeBucketText;

    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('可入 (1)'), findsOneWidget);
    expect(
      container.read(pendingPlaylistTransferProvider),
      isNull,
      reason: '一次性槽位必须被消费掉，否则每次重建都会重新导入',
    );
  });
}

/// Answers `可入的歌` confidently, `待确认的歌` weakly, and `没有的歌` with
/// **nothing at all** — i.e. exactly one row per bucket.
///
/// The third case is spelled out rather than left to `default` because the point
/// of the bucket it feeds is the distinction: 未匹配 means *no candidate was
/// found*, not "a candidate scored low" (that is 待确认).
class _ThreeBucketMatcher implements PlaylistSourceMatcher {
  @override
  Future<List<SourceMatchCandidate>> candidatesFor(TransferEntry entry) async {
    switch (entry.title) {
      case '可入的歌':
        return const <SourceMatchCandidate>[
          SourceMatchCandidate(song: _matchedExact, confident: true),
        ];
      case '待确认的歌':
        return const <SourceMatchCandidate>[
          SourceMatchCandidate(song: _matchedWeak, confident: false),
        ];
      case '没有的歌':
        // Also covers the swapped reading ('歌手3'), which the runner tries
        // after the committed one finds nothing.
        return const <SourceMatchCandidate>[];
      default:
        return const <SourceMatchCandidate>[];
    }
  }
}

class _FakeMyPlaylistsRepository extends MyPlaylistsRepository {
  final List<({String name, List<Song> songs})> imported =
      <({String name, List<Song> songs})>[];

  @override
  Future<List<Playlist>> getPlaylists() async => const <Playlist>[];

  @override
  Future<Playlist> importPlaylist({
    required String name,
    required List<Song> songs,
  }) async {
    imported.add((name: name, songs: songs));
    return Playlist(
      id: 'imported_1',
      name: name,
      platform: PlatformType.local,
      songCount: songs.length,
      editable: true,
    );
  }
}
