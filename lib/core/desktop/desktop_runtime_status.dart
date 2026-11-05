import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Live state of the Windows runner features the 桌面行为 switches control.
///
/// The switches are only half of the contract: `setCloseBehavior` can succeed
/// while the *tray icon* failed to appear, and a global hotkey can be rejected
/// because another application already owns the chord. Those failures used to
/// be invisible (the `setHotkeys` answer was discarded), which is exactly how
/// a user ends up clicking 关闭到托盘 and watching the window vanish into a
/// tray they cannot see. Every field here is nullable on purpose: `null` means
/// "the runner never said", which is not the same as "failed".
@immutable
class DesktopRuntimeStatus {
  const DesktopRuntimeStatus({
    this.trayReady,
    this.trayError,
    this.hotkeysRegistered,
    this.hotkeysEnabled,
    this.smtcAvailable,
    this.lastCloseHiddenToTray = false,
    this.lastCloseFellBackToExit = false,
    this.minimizedInsteadOfTray = false,
    this.trayKeptWindowOpen = false,
    this.elevated,
    this.integrityLevel,
  });

  /// `true` once the runner added its notification-area icon.
  final bool? trayReady;

  /// `GetLastError()` from the `NIM_ADD` that failed, `0` meaning "no error".
  ///
  /// This is the number the status card prints: "尚未收到运行器答复" was the old
  /// answer to a tray icon that never appeared, and it told the user nothing.
  final int? trayError;

  /// Result of the last `setHotkeys` call; `false` means a chord conflict.
  final bool? hotkeysRegistered;

  /// Whether the runner really holds registrations, as answered by
  /// `getRuntimeStatus`.
  ///
  /// Deliberately separate from [hotkeysRegistered]: `ApplyHotkeys(false)`
  /// answers `true` because there was nothing to register, so the call's answer
  /// alone reports a false positive whenever the feature is switched off.
  final bool? hotkeysEnabled;

  /// `false` once the runner reported `smtcUnavailable`.
  final bool? smtcAvailable;

  /// The most recent close was swallowed and the window is in the tray.
  final bool lastCloseHiddenToTray;

  /// The most recent close fell back to a real exit (no tray icon).
  final bool lastCloseFellBackToExit;

  /// The most recent close was swallowed, but the window went to the taskbar
  /// instead of the tray because the icon was missing.
  ///
  /// Older runners used this for the minimize fallback; current ones keep the
  /// window open instead and set [trayKeptWindowOpen].
  final bool minimizedInsteadOfTray;

  /// The most recent close left the window exactly where it was because the
  /// tray icon is missing. Hiding into a tray that does not exist is how the
  /// app gets lost, so this is the honest answer.
  final bool trayKeptWindowOpen;

  /// Whether the process runs elevated (`IsUserAnAdmin`). An elevated process
  /// can be refused a tray icon by an unelevated Explorer.
  final bool? elevated;

  /// Windows integrity RID of the runner process (`0x1000` low, `0x2000`
  /// medium, `0x3000` high). A low-integrity process cannot talk to the
  /// Explorer taskbar, so `Shell_NotifyIcon` fails with access denied.
  final int? integrityLevel;

  DesktopRuntimeStatus copyWith({
    bool? trayReady,
    int? trayError,
    bool? hotkeysRegistered,
    bool? hotkeysEnabled,
    bool? smtcAvailable,
    bool? lastCloseHiddenToTray,
    bool? lastCloseFellBackToExit,
    bool? minimizedInsteadOfTray,
    bool? trayKeptWindowOpen,
    bool? elevated,
    int? integrityLevel,
  }) {
    return DesktopRuntimeStatus(
      trayReady: trayReady ?? this.trayReady,
      trayError: trayError ?? this.trayError,
      hotkeysRegistered: hotkeysRegistered ?? this.hotkeysRegistered,
      hotkeysEnabled: hotkeysEnabled ?? this.hotkeysEnabled,
      smtcAvailable: smtcAvailable ?? this.smtcAvailable,
      lastCloseHiddenToTray:
          lastCloseHiddenToTray ?? this.lastCloseHiddenToTray,
      lastCloseFellBackToExit:
          lastCloseFellBackToExit ?? this.lastCloseFellBackToExit,
      minimizedInsteadOfTray:
          minimizedInsteadOfTray ?? this.minimizedInsteadOfTray,
      trayKeptWindowOpen: trayKeptWindowOpen ?? this.trayKeptWindowOpen,
      elevated: elevated ?? this.elevated,
      integrityLevel: integrityLevel ?? this.integrityLevel,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is DesktopRuntimeStatus &&
            other.trayReady == trayReady &&
            other.trayError == trayError &&
            other.hotkeysRegistered == hotkeysRegistered &&
            other.hotkeysEnabled == hotkeysEnabled &&
            other.smtcAvailable == smtcAvailable &&
            other.lastCloseHiddenToTray == lastCloseHiddenToTray &&
            other.lastCloseFellBackToExit == lastCloseFellBackToExit &&
            other.minimizedInsteadOfTray == minimizedInsteadOfTray &&
            other.trayKeptWindowOpen == trayKeptWindowOpen &&
            other.elevated == elevated &&
            other.integrityLevel == integrityLevel;
  }

  @override
  int get hashCode => Object.hash(
    trayReady,
    trayError,
    hotkeysRegistered,
    hotkeysEnabled,
    smtcAvailable,
    lastCloseHiddenToTray,
    lastCloseFellBackToExit,
    minimizedInsteadOfTray,
    trayKeptWindowOpen,
    elevated,
    integrityLevel,
  );
}

class DesktopRuntimeStatusNotifier
    extends StateNotifier<DesktopRuntimeStatus> {
  DesktopRuntimeStatusNotifier() : super(const DesktopRuntimeStatus());

  void setTrayReady({required bool ready}) {
    state = state.copyWith(trayReady: ready);
  }

  void setHotkeysRegistered({required bool registered}) {
    state = state.copyWith(hotkeysRegistered: registered);
  }

  void setSmtcAvailable({required bool available}) {
    state = state.copyWith(smtcAvailable: available);
  }

  /// The runner could not add its tray icon; [error] is its `GetLastError()`
  /// (or a generic failure code when the shell set none).
  void setTrayFailed({required int error}) {
    state = state.copyWith(trayReady: false, trayError: error);
  }

  /// Whether the runner really holds hotkey registrations.
  void setHotkeysEnabled({required bool enabled}) {
    state = state.copyWith(hotkeysEnabled: enabled);
  }

  /// The close was swallowed, but the window went to the taskbar because no
  /// tray icon existed. Neither "hidden" nor "exited".
  void setMinimizedInstead() {
    state = state.copyWith(
      minimizedInsteadOfTray: true,
      lastCloseHiddenToTray: false,
      lastCloseFellBackToExit: false,
    );
  }

  /// The runner refused to hide because the tray icon is missing: the window
  /// is still open, and [error] is the reason it can print.
  void setTrayUnavailableKeptOpen({required int error}) {
    state = state.copyWith(
      trayError: error,
      trayKeptWindowOpen: true,
      minimizedInsteadOfTray: false,
      lastCloseHiddenToTray: false,
      lastCloseFellBackToExit: false,
    );
  }

  /// The close hid the window even though no tray icon exists. The window is
  /// still recoverable by launching the app again (single-instance hand-off);
  /// [error] is why the icon never appeared.
  void setHiddenWithoutTray({required int error}) {
    state = state.copyWith(
      trayError: error,
      lastCloseHiddenToTray: true,
      lastCloseFellBackToExit: false,
      trayKeptWindowOpen: false,
      minimizedInsteadOfTray: false,
    );
  }

  void setIntegrityLevel({required int level}) {
    state = state.copyWith(integrityLevel: level);
  }

  void setElevated({required bool isElevated}) {
    state = state.copyWith(elevated: isElevated);
  }

  void recordClose({required bool hiddenToTray}) {
    state = state.copyWith(
      lastCloseHiddenToTray: hiddenToTray,
      lastCloseFellBackToExit: !hiddenToTray,
      minimizedInsteadOfTray: false,
      trayKeptWindowOpen: false,
    );
  }
}

final desktopRuntimeStatusProvider =
    StateNotifierProvider<DesktopRuntimeStatusNotifier, DesktopRuntimeStatus>(
      (ref) => DesktopRuntimeStatusNotifier(),
    );