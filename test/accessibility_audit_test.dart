import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/features/discovery/presentation/pages/recommendations_page.dart';
import 'package:mconnect/features/discovery/presentation/providers/recommendations_provider.dart';

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
}
