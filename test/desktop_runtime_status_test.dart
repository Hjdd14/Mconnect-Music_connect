import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/core/desktop/desktop_runtime_status.dart';

/// The 运行状态 card is only as honest as this notifier: every field here is
/// what turns a silent native failure into something the user can read.
void main() {
  late DesktopRuntimeStatusNotifier notifier;

  setUp(() => notifier = DesktopRuntimeStatusNotifier());

  group('initial state', () {
    test('nothing is known before the runner answers', () {
      final state = notifier.state;
      expect(state.trayReady, isNull);
      expect(state.trayError, isNull);
      expect(state.minimizedInsteadOfTray, isFalse);
      expect(state.hotkeysEnabled, isNull);
      expect(state.lastCloseHiddenToTray, isFalse);
      expect(state.lastCloseFellBackToExit, isFalse);
    });
  });

  group('tray', () {
    test('a failed tray icon clears trayReady and keeps the error code', () {
      notifier.setTrayReady(ready: true);
      notifier.setTrayFailed(error: 5);

      expect(notifier.state.trayReady, isFalse);
      expect(notifier.state.trayError, 5);
      // A failure is not a close outcome; the close row keeps its own state.
      expect(notifier.state.lastCloseHiddenToTray, isFalse);
      expect(notifier.state.minimizedInsteadOfTray, isFalse);
    });

    test('a later trayReady is not blocked by the earlier error', () {
      notifier.setTrayFailed(error: 5);
      notifier.setTrayReady(ready: true);

      expect(notifier.state.trayReady, isTrue);
      // The code stays as "the last error the runner reported"; the card only
      // shows it while trayReady is false.
      expect(notifier.state.trayError, 5);
    });
  });

  group('close outcome', () {
    test('minimizing instead of hiding is its own state', () {
      notifier.setMinimizedInstead();

      expect(notifier.state.minimizedInsteadOfTray, isTrue);
      expect(notifier.state.lastCloseHiddenToTray, isFalse);
      expect(notifier.state.lastCloseFellBackToExit, isFalse);
    });

    test('a real hide resets the minimized marker', () {
      notifier.setMinimizedInstead();
      notifier.recordClose(hiddenToTray: true);

      expect(notifier.state.lastCloseHiddenToTray, isTrue);
      expect(notifier.state.lastCloseFellBackToExit, isFalse);
      expect(notifier.state.minimizedInsteadOfTray, isFalse);
    });

    test('an exit is not confused with a hidden window', () {
      notifier.setMinimizedInstead();
      notifier.recordClose(hiddenToTray: false);

      expect(notifier.state.lastCloseHiddenToTray, isFalse);
      expect(notifier.state.lastCloseFellBackToExit, isTrue);
      expect(notifier.state.minimizedInsteadOfTray, isFalse);
    });
  });

  group('queried runtime status', () {
    test('hotkeysEnabled is stored apart from the setHotkeys answer', () {
      // ApplyHotkeys(false) answers true because there was nothing to do; only
      // the queried flag says whether anything is actually registered.
      notifier.setHotkeysEnabled(enabled: false);
      expect(notifier.state.hotkeysEnabled, isFalse);

      notifier.setHotkeysEnabled(enabled: true);
      expect(notifier.state.hotkeysEnabled, isTrue);
    });

    test('smtc availability is a tri-state, never a default', () {
      expect(notifier.state.smtcAvailable, isNull);
      notifier.setSmtcAvailable(available: false);
      expect(notifier.state.smtcAvailable, isFalse);
    });
  });

  group('copyWith', () {
    test('keeps every field it was not given', () {
      notifier.setTrayFailed(error: 7);
      notifier.setMinimizedInstead();
      notifier.setHotkeysEnabled(enabled: true);

      final copy = notifier.state.copyWith(trayReady: false);

      expect(copy.trayError, 7);
      expect(copy.minimizedInsteadOfTray, isTrue);
      expect(copy.hotkeysEnabled, isTrue);
      expect(copy, notifier.state);
    });

    test('equality covers the new fields', () {
      const base = DesktopRuntimeStatus(trayError: 3);
      expect(base, const DesktopRuntimeStatus(trayError: 3));
      expect(base, isNot(const DesktopRuntimeStatus(trayError: 4)));
      expect(base.hashCode, const DesktopRuntimeStatus(trayError: 3).hashCode);
    });
  });

  test('a close that kept the window open is its own state', () {
    final notifier = DesktopRuntimeStatusNotifier();
    addTearDown(notifier.dispose);

    notifier.setTrayUnavailableKeptOpen(error: 5);

    expect(notifier.state.trayKeptWindowOpen, isTrue);
    expect(notifier.state.trayError, 5);
    expect(notifier.state.trayReady, isNull);
    // Keep-window-open is neither hidden nor exited: saying either would be a
    // lie about what the runner did.
    expect(notifier.state.lastCloseHiddenToTray, isFalse);
    expect(notifier.state.lastCloseFellBackToExit, isFalse);

    // A later successful hide clears the alarm.
    notifier.recordClose(hiddenToTray: true);
    expect(notifier.state.trayKeptWindowOpen, isFalse);
    expect(notifier.state.lastCloseHiddenToTray, isTrue);
  });

  test('hiding without a tray icon still records the close as a hide', () {
    final notifier = DesktopRuntimeStatusNotifier();
    addTearDown(notifier.dispose);

    notifier.setHiddenWithoutTray(error: 5);

    // The window really is gone from the taskbar, so this is a hide — but the
    // error code stays visible so the card can say why there is no icon.
    expect(notifier.state.lastCloseHiddenToTray, isTrue);
    expect(notifier.state.lastCloseFellBackToExit, isFalse);
    expect(notifier.state.trayError, 5);
    expect(notifier.state.trayKeptWindowOpen, isFalse);
  });

  test('the integrity level is kept so the card can explain a refused icon', () {
    final notifier = DesktopRuntimeStatusNotifier();
    addTearDown(notifier.dispose);

    expect(notifier.state.integrityLevel, isNull);
    notifier.setIntegrityLevel(level: 0x1000);
    expect(notifier.state.integrityLevel, 0x1000);
    // The status card treats anything at or below low as "the shell will refuse
    // this process", which is exactly what a low-integrity launch does.
    expect(notifier.state.copyWith(integrityLevel: 0x2000).integrityLevel, 0x2000);
  });

  test('elevation is reported so the card can explain a refused tray icon', () {
    final notifier = DesktopRuntimeStatusNotifier();
    addTearDown(notifier.dispose);

    expect(notifier.state.elevated, isNull);
    notifier.setElevated(isElevated: true);
    expect(notifier.state.elevated, isTrue);
  });
}