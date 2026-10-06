import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/core/utils/snackbar_helper.dart';

/// The helper is the single place that decides toast colour/duration; these
/// tests pin the contract the 30+ converted call sites now depend on.
void main() {
  testWidgets('an error toast uses the theme error colour and the error duration', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showErrorSnackBar(context, '保存失败'),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('go'));
    await tester.pump();

    final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
    expect(snackBar.duration, const Duration(seconds: 3));
    expect(snackBar.behavior, SnackBarBehavior.floating);
    expect(find.text('保存失败'), findsOneWidget);
  });

  testWidgets('a success toast has no error colour and the short duration', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showSuccessSnackBar(context, '已保存'),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('go'));
    await tester.pump();

    final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
    expect(snackBar.duration, const Duration(seconds: 2));
    expect(snackBar.behavior, SnackBarBehavior.floating);
    expect(snackBar.backgroundColor, isNull);
  });

  testWidgets('an explicit duration overrides the default', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showSuccessSnackBar(
                  context,
                  '已开始下载',
                  duration: const Duration(seconds: 4),
                ),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('go'));
    await tester.pump();

    expect(
      tester.widget<SnackBar>(find.byType(SnackBar)).duration,
      const Duration(seconds: 4),
    );
  });

  testWidgets('an action is forwarded and tappable', (tester) async {
    var tapped = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showInfoSnackBar(
                  context,
                  '登录已过期，请重新登录',
                  action: SnackBarAction(
                    label: '去登录',
                    onPressed: () => tapped++,
                  ),
                ),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('go'));
    await tester.pump();
    // The snackbar needs its entrance animation before its action is hittable.
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('去登录'), findsOneWidget);

    await tester.tap(find.text('去登录'));
    await tester.pumpAndSettle();
    expect(tapped, 1);
  });

  testWidgets('a toast with no ScaffoldMessenger ancestor is dropped, not thrown', (
    tester,
  ) async {
    // Deliberately *no* MaterialApp: it installs a ScaffoldMessenger, which is
    // exactly what this test needs to be missing.
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Builder(builder: (context) => const SizedBox.shrink()),
      ),
    );

    // No messenger: the old code would have thrown here, turning a courtesy
    // message into a crash.
    final context = tester.element(find.byType(SizedBox).first);
    expect(() => showErrorSnackBar(context, 'boom'), returnsNormally);
  });
}
