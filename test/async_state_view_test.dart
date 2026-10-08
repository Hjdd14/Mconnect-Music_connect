import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/core/widgets/async_state_view.dart';

/// The shared three-state view is a *contract*: every page migrates onto it, so
/// its three rules are asserted here rather than re-checked per page.
///
/// 1. retry is an `ElevatedButton` (never a `TextButton`);
/// 2. body copy uses `onSurfaceVariant`, never `outline`;
/// 3. `error` always offers a way out, `empty` never pretends to be an error.
void main() {
  Future<void> pump(WidgetTester tester, Widget view) => tester.pumpWidget(
    MaterialApp(home: Scaffold(body: view)),
  );

  testWidgets('loading shows a spinner and no retry affordance', (tester) async {
    await pump(tester, const AsyncStateView.loading());

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('重试'), findsNothing);
  });

  testWidgets('loading with a title keeps the label under the spinner', (
    tester,
  ) async {
    await pump(tester, const AsyncStateView.loading(title: '正在加载'));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('正在加载'), findsOneWidget);
  });

  testWidgets('loading with skeleton renders fixed rows and no spinner', (
    tester,
  ) async {
    await pump(tester, const AsyncStateView.loading(skeleton: true));

    final list = tester.widget<ListView>(
      find.byKey(const Key('async-skeleton-list')),
    );
    expect(list.semanticChildCount ?? list.childrenDelegate.estimatedChildCount,
        AsyncStateView.skeletonRows);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('error shows the reason and retry is an ElevatedButton that fires', (
    tester,
  ) async {
    var retried = 0;
    await pump(
      tester,
      AsyncStateView.error(
        title: '加载失败',
        message: '网络连接超时',
        onRetry: () => retried++,
      ),
    );

    expect(find.text('加载失败'), findsOneWidget);
    expect(find.text('网络连接超时'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);

    // Rule 1: the retry control must be an ElevatedButton, and it must be the
    // only button on screen.
    expect(
      find.widgetWithText(ElevatedButton, '重试'),
      findsOneWidget,
    );
    expect(find.byType(TextButton), findsNothing);

    await tester.tap(find.text('重试'));
    await tester.pump();
    expect(retried, 1);
  });

  testWidgets('body copy uses onSurfaceVariant, not outline', (tester) async {
    await pump(
      tester,
      AsyncStateView.error(title: '加载失败', onRetry: () {}),
    );

    final context = tester.element(find.text('加载失败'));
    final scheme = Theme.of(context).colorScheme;
    final style = tester.widget<Text>(find.text('加载失败')).style;

    // Rule 2. `outline` is a border colour; the audit found it used as body copy
    // on ~10 pages.
    expect(style?.color, scheme.onSurfaceVariant);
    expect(style?.color, isNot(scheme.outline));
  });

  testWidgets('empty shows guidance and offers no retry', (tester) async {
    await pump(
      tester,
      const AsyncStateView.empty(
        title: '还没有喜欢的歌曲',
        message: '在播放器中点击爱心添加',
        icon: Icons.favorite_border,
      ),
    );

    expect(find.text('还没有喜欢的歌曲'), findsOneWidget);
    expect(find.text('在播放器中点击爱心添加'), findsOneWidget);
    expect(find.byIcon(Icons.favorite_border), findsOneWidget);
    // Rule 3: an empty list is not a failure, so there is nothing to retry.
    expect(find.text('重试'), findsNothing);
    expect(find.byType(ElevatedButton), findsNothing);
  });

  testWidgets('sliver wrapper keeps the state inside a fill-remaining sliver', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            slivers: [
              const SliverAsyncStateView(
                child: AsyncStateView.empty(title: '还没有榜单数据'),
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.byType(SliverFillRemaining), findsOneWidget);
    expect(find.text('还没有榜单数据'), findsOneWidget);
  });

  testWidgets('sliver wrapper applies inside-padding around the state', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            slivers: [
              const SliverAsyncStateView(
                padding: EdgeInsets.only(bottom: 88),
                child: AsyncStateView.empty(title: '还没有榜单数据'),
              ),
            ],
          ),
        ),
      ),
    );

    final padding = tester.widget<Padding>(find.byType(Padding).first);
    expect(padding.padding, const EdgeInsets.only(bottom: 88));
    expect(find.text('还没有榜单数据'), findsOneWidget);
  });
}
