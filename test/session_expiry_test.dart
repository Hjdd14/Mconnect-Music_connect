import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/app.dart';
import 'package:mconnect/features/auth/presentation/providers/auth_provider.dart';
import 'package:mconnect/models/platform_type.dart';

/// task-5: the user-visible half of session expiry.
///
/// Wave 1 shipped `handleSessionExpired` with tests but no production caller and
/// no way for the user to learn that the app had logged them out. These tests pin
/// the signal (state) and the notice (UI).
void main() {
  group('AuthState expiry signal', () {
    test('handleSessionExpired clears the user and raises the notice', () async {
      final notifier = AuthNotifier();
      await notifier.handleSessionExpired(PlatformType.netease);

      expect(notifier.state.isLoggedIn(PlatformType.netease), isFalse);
      expect(notifier.state.expiredPlatform, PlatformType.netease);
      expect(notifier.state.expiryNoticeId, 1);
    });

    test('a repeated expiry is a new event, not a silent repeat', () async {
      final notifier = AuthNotifier();
      await notifier.handleSessionExpired(PlatformType.qq);
      await notifier.handleSessionExpired(PlatformType.qq);

      expect(notifier.state.expiryNoticeId, 2);
      expect(notifier.state.expiredPlatform, PlatformType.qq);
    });

    test('the notice is cleared without touching the logged-out state', () async {
      final notifier = AuthNotifier();
      await notifier.handleSessionExpired(PlatformType.kugou);

      notifier.clearExpiryNotice();

      expect(notifier.state.expiredPlatform, isNull);
      expect(notifier.state.expiryNoticeId, 1, reason: 'the event counter stays');
      expect(notifier.state.isLoggedIn(PlatformType.kugou), isFalse);
    });

    test('clearing an already-clear notice is a no-op', () async {
      final notifier = AuthNotifier();
      notifier.clearExpiryNotice();
      expect(notifier.state.expiredPlatform, isNull);
      expect(notifier.state.expiryNoticeId, 0);
    });

    test('an ordinary login state carries no expiry signal', () {
      const state = AuthState();
      expect(state.expiredPlatform, isNull);
      expect(state.expiryNoticeId, 0);
    });
  });

  group('the notice itself', () {
    testWidgets('shows the platform, the message and a working 「去登录」 action', (
      tester,
    ) async {
      final key = GlobalKey<ScaffoldMessengerState>();
      var navigated = 0;

      await tester.pumpWidget(
        MaterialApp(
          scaffoldMessengerKey: key,
          home: const Scaffold(body: SizedBox.shrink()),
        ),
      );

      showSessionExpiredNotice(
        messenger: key.currentState!,
        platform: PlatformType.netease,
        onGoToLogin: () => navigated++,
      );
      // Let the entrance animation finish: tapping a snackbar action on the
      // first frame hits nothing.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.textContaining('登录已过期'), findsOneWidget);
      expect(find.textContaining('网易云音乐'), findsOneWidget);
      expect(find.text('去登录'), findsOneWidget);

      await tester.tap(find.text('去登录'));
      await tester.pumpAndSettle();
      expect(navigated, 1);
    });

    testWidgets('a second expiry replaces the first notice', (tester) async {
      final key = GlobalKey<ScaffoldMessengerState>();

      await tester.pumpWidget(
        MaterialApp(
          scaffoldMessengerKey: key,
          home: const Scaffold(body: SizedBox.shrink()),
        ),
      );

      showSessionExpiredNotice(
        messenger: key.currentState!,
        platform: PlatformType.netease,
        onGoToLogin: () {},
      );
      await tester.pump();
      showSessionExpiredNotice(
        messenger: key.currentState!,
        platform: PlatformType.qq,
        onGoToLogin: () {},
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('QQ 音乐'), findsOneWidget);
      expect(find.textContaining('网易云音乐'), findsNothing);
    });
  });
}
