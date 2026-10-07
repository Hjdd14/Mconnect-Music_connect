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
}

class _FakeAuthNotifier extends AuthNotifier {
  final qrVariants = <String?>[];

  @override
  Future<QrLoginResult> getQrCodeWithVariant(
    PlatformType platform, {
    String? authVariant,
  }) async {
    qrVariants.add(authVariant);
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
