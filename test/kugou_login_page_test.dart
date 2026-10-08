import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/features/auth/presentation/pages/login_page.dart';
import 'package:mconnect/features/auth/presentation/providers/auth_provider.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/platform/base/music_platform.dart';

/// v1.4.1 (task-17 §4a): Kugou is QR-code login only.
///
/// The phone form was *removed*, not hidden behind a `false` flag — otherwise
/// its controllers and handlers would become unused private members and
/// `flutter analyze` would no longer be clean. These tests pin the user-visible
/// half of that: no phone/verification inputs, no "使用手机号登录" toggle, while
/// the QR flow (including the 酷狗概念版 variant selector) keeps working.
void main() {
  testWidgets('kugou login page shows the QR flow and no phone form', (
    tester,
  ) async {
    final notifier = _FakeAuthNotifier();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authProvider.overrideWith((ref) => notifier)],
        child: const MaterialApp(
          home: LoginPage(platform: PlatformType.kugou),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // No way to reach phone login.
    expect(find.text('使用手机号登录'), findsNothing);
    expect(find.text('收起手机号登录'), findsNothing);
    expect(find.text('手机号'), findsNothing);
    expect(find.text('验证码'), findsNothing);
    expect(find.text('获取验证码'), findsNothing);
    expect(find.byType(TextField), findsNothing);

    // The QR path is intact.
    expect(find.text('请使用手机扫描二维码登录'), findsOneWidget);
    expect(find.text('酷狗概念版'), findsOneWidget);
    expect(find.text('酷狗音乐'), findsWidgets);
    expect(notifier.qrVariants, ['lite']);
  });

  testWidgets('switching the kugou variant re-requests the QR code', (
    tester,
  ) async {
    final notifier = _FakeAuthNotifier();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authProvider.overrideWith((ref) => notifier)],
        child: const MaterialApp(
          home: LoginPage(platform: PlatformType.kugou),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('酷狗音乐').first);
    await tester.pumpAndSettle();

    expect(notifier.qrVariants, ['lite', 'android']);
    // The variant selector is not a login-method switcher.
    expect(find.text('使用手机号登录'), findsNothing);
  });

  testWidgets('netease login page also offers no phone form', (tester) async {
    final notifier = _FakeAuthNotifier();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authProvider.overrideWith((ref) => notifier)],
        child: const MaterialApp(
          home: LoginPage(platform: PlatformType.netease),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNothing);
    expect(find.text('获取验证码'), findsNothing);
    expect(find.text('请使用手机扫描二维码登录'), findsOneWidget);
    expect(notifier.qrVariants, [null]);
  });
  // The login page migrated onto the shared `AsyncStateView` (loading / error +
  // retry) with no assertion that could tell: removing the retry, or letting the
  // spinner replace the error, left every test green.
  testWidgets('fetching the QR code shows the shared loading state', (
    tester,
  ) async {
    final pending = Completer<QrLoginResult>();
    final notifier = _FakeAuthNotifier(qrPending: pending);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [authProvider.overrideWith((ref) => notifier)],
        child: const MaterialApp(
          home: LoginPage(platform: PlatformType.kugou),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      find.text('重试'),
      findsNothing,
      reason: '加载中不是失败，不能给重试',
    );

    // Let the request finish so no future is left hanging into teardown.
    pending.complete(
      const QrLoginResult(key: 'key-1', qrUrl: 'https://example.test/qr'),
    );
    await tester.pumpAndSettle();
  });

  testWidgets('a failed QR fetch is an error state whose retry re-requests', (
    tester,
  ) async {
    final notifier = _FakeAuthNotifier(qrError: Exception('qr endpoint down'));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [authProvider.overrideWith((ref) => notifier)],
        child: const MaterialApp(
          home: LoginPage(platform: PlatformType.kugou),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('qr endpoint down'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, '重试'), findsOneWidget);
    expect(notifier.qrVariants, hasLength(1));

    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();

    expect(
      notifier.qrVariants,
      hasLength(2),
      reason: '点重试必须真的再要一次二维码，而不是只把错误清掉',
    );
  });
}

class _FakeAuthNotifier extends AuthNotifier {
  _FakeAuthNotifier({this.qrError, this.qrPending});

  /// Thrown by the QR request, for the error-state cases.
  final Object? qrError;

  /// When set, the QR request never completes, for the loading-state case.
  final Completer<QrLoginResult>? qrPending;

  final qrVariants = <String?>[];

  @override
  Future<QrLoginResult> getQrCodeWithVariant(
    PlatformType platform, {
    String? authVariant,
  }) async {
    qrVariants.add(authVariant);
    final failure = qrError;
    if (failure != null) throw failure;
    final pending = qrPending;
    if (pending != null) return pending.future;
    return const QrLoginResult(
      key: 'key-1',
      qrUrl: 'https://example.test/qr',
    );
  }

  @override
  Stream<QrLoginStatus> pollQrStatus(
    PlatformType platform,
    String key, {
    String? authVariant,
  }) async* {
    yield QrLoginStatus.waiting;
  }
}
