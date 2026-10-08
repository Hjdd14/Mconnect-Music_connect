import 'package:flutter/material.dart';
// `SemanticsFlag` is NOT exported by `material.dart` (it lives in
// src/semantics/semantics.dart), and `SemanticsData.hasFlag(SemanticsFlag…)` is
// the only public way to ask "is this node an image?" — `SemanticsData` has no
// `isImage` getter (verified by analyze: `undefined_getter`).
// NOTE: `package:flutter/semantics.dart` is NOT needed any more - the flag is read
// through `SemanticsData.flagsCollection`, which comes from material.dart. The
// deprecated `hasFlag(SemanticsFlag.isImage)` needed it.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/features/album/presentation/pages/album_page.dart';
import 'package:mconnect/features/discovery/presentation/pages/recommendations_page.dart';
import 'package:mconnect/features/discovery/presentation/providers/recommendations_provider.dart';
import 'package:mconnect/models/album.dart';
import 'package:mconnect/models/artist.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/song.dart';

import 'support/content_page_fakes.dart';

/// A cover-less album fixture.
///
/// Deliberately without a `coverUrl`: the cover *slot* carries the label, so the
/// placeholder path is what renders — which keeps `CachedNetworkImage` (and its
/// real HTTP work) out of the widget test entirely. A network fixture would be
/// needed only if the assertion were about pixels, which it is not.
const _coverlessAlbum = Album(id: 'a1', name: '未完成', artistName: '孙燕姿');

const _albumSong = Song(
  id: 's1',
  platform: PlatformType.qq,
  name: '神奇',
  artists: <Artist>[Artist(id: '', name: '孙燕姿')],
);

/// W3-B accessibility: the mechanism, plus the first page that was missing a
/// label.
///
/// **Why a semantics assertion and not just `find.byTooltip`.** `byTooltip`
/// proves the widget has a tooltip; it does not prove the label reaches the
/// semantics tree, which is the thing TalkBack reads. This file asserts the
/// semantics tree itself, with `ensureSemantics()` so it is actually built.
void main() {
  /// Bounded `testWidgets` — a hang is undiagnosable (this repo has already lost
  /// a test to a 10-minute timeout), so a stuck future must fail in 30 s.
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

  widgetTest('每日推荐页的刷新按钮有语义标签，而不是光秃秃的"按钮"', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    // NOT `addTearDown(handle.dispose)`: teardowns run after the framework's
    // end-of-body verification, so the handle is still active when it checks
    // ("A SemanticsHandle was active at the end of the test"). The handle is
    // disposed at the end of this body instead - and only there, or it would be a
    // double dispose.

    // No platforms, so the page does no work: this test is about the app bar's
    // affordance, and a real platform list would drag in network fakes.
    final notifier = RecommendationsNotifier(supportedTypes: const []);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [recommendationsProvider.overrideWith((ref) => notifier)],
        child: const MaterialApp(home: RecommendationsPage()),
      ),
    );
    // Bounded pumps rather than `pumpAndSettle`: the page can show a persistent
    // spinner, and the discipline in this repo is "never let a test depend on
    // every animation finishing".
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(find.byIcon(Icons.refresh), findsOneWidget);
    expect(find.byTooltip('刷新'), findsOneWidget);
    // Two semantic **channels**, and this case exists because they are not the
    // same field:
    //
    // * `IconButton(tooltip:)` publishes into the semantics **tooltip** channel
    //   (`Tooltip` builds `Semantics(tooltip: message)`). The first version of
    //   this case asserted the **label** channel via `find.bySemanticsLabel` and
    //   found 0 widgets while the widget itself was fine — a channel mismatch,
    //   not a broken button.
    // * the page carries `tooltip: '刷新'` (the accessible name an icon-only
    //   button needs). Nothing else was changed: an earlier attempt to ADD a
    //   `Semantics(label:)` wrapper was reverted, because a non-container
    //   `Semantics` merges into the nearest ENCLOSING node - for an AppBar action
    //   that is an app-bar-level ancestor, so it would have labelled the wrong
    //   node (a real defect introduced to make an assertion pass).
    //
    // The assertion below reads the field the tooltip truly writes to (measuring
    // the right channel is the whole point), and proves the text reached the
    // semantics tree rather than only the widget.
    final semantics = tester
        .getSemantics(find.byTooltip('刷新'))
        .getSemanticsData();
    expect(
      semantics.tooltip,
      '刷新',
      reason: 'TalkBack 必须听到"刷新"，否则它只会念"按钮"',
    );

    // Disposed INSIDE the body: the framework verifies at the end of the body,
    // BEFORE `addTearDown` callbacks run, so a teardown-based dispose is too late
    // ("A SemanticsHandle was active at the end of the test").
    handle.dispose();
  });

  widgetTest('专辑封面是"图片 + 角色标签"，且标签里不含专辑名', (tester) async {
    final handle = tester.ensureSemantics();
    // `try`/`finally` (rather than the plain dispose above) so a failing
    // assertion cannot also leak the handle and bury the real failure under
    // "A SemanticsHandle was active".
    try {
      registerFake(
        FakeContentPlatform(
          type: PlatformType.qq,
          album: _coverlessAlbum,
          albumSongs: const <Song>[_albumSong],
        ),
      );

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: AlbumPage(
              platform: PlatformType.qq,
              albumId: 'a1',
              albumName: '未完成',
            ),
          ),
        ),
      );
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      final cover = tester.getSemantics(find.bySemanticsLabel('专辑封面'));
      final coverData = cover.getSemanticsData();
      expect(
        // `hasFlag` is deprecated as of Flutter 3.32 in favour of the flag
        // collection; `flagsCollection.isImage` is the current read.
        coverData.flagsCollection.isImage,
        isTrue,
        reason: '封面是有意义的图，不是装饰',
      );
      expect(coverData.label, '专辑封面');
      expect(
        coverData.label,
        isNot(contains('未完成')),
        reason: '专辑名由相邻文本念出；塞进图片标签会让同一信息念两遍',
      );
    } finally {
      handle.dispose();
    }
  });
}
