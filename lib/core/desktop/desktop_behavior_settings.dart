import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'desktop_integration_service.dart';

/// The app's single Hive box for settings (opened by `main.dart` before the
/// first frame) and this batch's slice of it.
const String desktopBehaviorBoxName = 'settings';
const String desktopBehaviorSettingsKey = 'desktop_behavior_settings';

/// Desktop-only behaviour settings (Windows today).
///
/// This is the **intent** the settings page edits; the Windows runner owns the
/// behaviour itself (tray icon, window geometry, hotkey registration, power
/// requests). [applyTo] is the one place that translates intent into
/// `desktop_integration` calls, so the page never talks to the channel.
///
/// Defaults lean the way a desktop music player is expected to behave — close
/// to tray, remember the window — except for the two that take something from
/// the rest of the system: global hotkeys stay **off** until asked for (a global
/// chord is a system-wide grab) and sleep prevention stays **off** until asked
/// for (it changes how the machine behaves when the lid or the timer fires).
@immutable
class DesktopBehaviorSettings {
  const DesktopBehaviorSettings({
    this.closeToTray = true,
    this.firstRunHint = true,
    this.hotkeysEnabled = false,
    this.toggleLyricsHotkey = defaultToggleLyricsHotkey,
    this.playPauseHotkey = defaultPlayPauseHotkey,
    this.preventSleepWhilePlaying = false,
    this.rememberWindowState = true,
  });

  static const String defaultToggleLyricsHotkey = 'Ctrl+Alt+L';
  static const String defaultPlayPauseHotkey = 'Ctrl+Alt+Space';

  /// Longest accepted hotkey string.
  ///
  /// A chord is a handful of tokens; anything past this is a paste accident and
  /// would be rejected by the runner anyway, so it is trimmed here instead of
  /// being shipped and failing registration silently.
  static const int maxHotkeyLength = 64;

  /// Hide the window to the tray instead of quitting on close.
  final bool closeToTray;

  /// Ask the runner to explain the tray icon the first time the window hides.
  final bool firstRunHint;

  /// Whether the two global chords below are registered at all.
  final bool hotkeysEnabled;

  /// Global chord that toggles the desktop lyrics window.
  final String toggleLyricsHotkey;

  /// Global chord that toggles play/pause.
  final String playPauseHotkey;

  /// Keep the machine awake while a song is playing (and only then).
  final bool preventSleepWhilePlaying;

  /// Restore the last window position/size on the next launch, and save it on
  /// close.
  final bool rememberWindowState;

  DesktopBehaviorSettings copyWith({
    bool? closeToTray,
    bool? firstRunHint,
    bool? hotkeysEnabled,
    String? toggleLyricsHotkey,
    String? playPauseHotkey,
    bool? preventSleepWhilePlaying,
    bool? rememberWindowState,
  }) {
    return DesktopBehaviorSettings(
      closeToTray: closeToTray ?? this.closeToTray,
      firstRunHint: firstRunHint ?? this.firstRunHint,
      hotkeysEnabled: hotkeysEnabled ?? this.hotkeysEnabled,
      toggleLyricsHotkey: toggleLyricsHotkey ?? this.toggleLyricsHotkey,
      playPauseHotkey: playPauseHotkey ?? this.playPauseHotkey,
      preventSleepWhilePlaying:
          preventSleepWhilePlaying ?? this.preventSleepWhilePlaying,
      rememberWindowState: rememberWindowState ?? this.rememberWindowState,
    );
  }

  /// True only while the feature is on **and** something is actually playing:
  /// a paused player must not keep a workstation awake.
  bool shouldPreventSleep({required bool isPlaying}) {
    return preventSleepWhilePlaying && isPlaying;
  }

  Map<String, dynamic> toJson() {
    return {
      'closeToTray': closeToTray,
      'firstRunHint': firstRunHint,
      'hotkeysEnabled': hotkeysEnabled,
      'toggleLyricsHotkey': toggleLyricsHotkey,
      'playPauseHotkey': playPauseHotkey,
      'preventSleepWhilePlaying': preventSleepWhilePlaying,
      'rememberWindowState': rememberWindowState,
    };
  }

  /// Tolerant by construction: a missing key, a wrong type or a Hive value from
  /// a future build falls back to the default instead of throwing during
  /// startup (the box is read before the first frame).
  factory DesktopBehaviorSettings.fromJson(dynamic value) {
    if (value is! Map) return const DesktopBehaviorSettings();
    const defaults = DesktopBehaviorSettings();
    return DesktopBehaviorSettings(
      closeToTray: _readBool(value['closeToTray'], defaults.closeToTray),
      firstRunHint: _readBool(value['firstRunHint'], defaults.firstRunHint),
      hotkeysEnabled: _readBool(
        value['hotkeysEnabled'],
        defaults.hotkeysEnabled,
      ),
      // Only a String is a hotkey: a number or a map means the stored value
      // came from somewhere this build does not understand, and shipping its
      // toString() would register a nonsense chord.
      toggleLyricsHotkey: normalizeHotkey(
        _readString(value['toggleLyricsHotkey']),
        fallback: defaultToggleLyricsHotkey,
      ),
      playPauseHotkey: normalizeHotkey(
        _readString(value['playPauseHotkey']),
        fallback: defaultPlayPauseHotkey,
      ),
      preventSleepWhilePlaying: _readBool(
        value['preventSleepWhilePlaying'],
        defaults.preventSleepWhilePlaying,
      ),
      rememberWindowState: _readBool(
        value['rememberWindowState'],
        defaults.rememberWindowState,
      ),
    );
  }

  /// Pushes the settings into the runner.
  ///
  /// [isPlaying] is what makes sleep prevention a **state** rather than a
  /// switch: the same settings object produces a different `setPreventSleep`
  /// depending on whether the player is running. Every call is awaited so the
  /// three reach the channel in a deterministic order (a test asserts it), and
  /// none of them can throw (see [DesktopIntegrationService]).
  Future<DesktopBehaviorApplyResult> applyTo(
    DesktopIntegrationService service, {
    required bool isPlaying,
  }) async {
    await service.setCloseBehavior(
      minimizeToTray: closeToTray,
      firstRunHint: firstRunHint,
      rememberWindowState: rememberWindowState,
    );
    final hotkeysRegistered = await service.setHotkeys(
      enabled: hotkeysEnabled,
      lyricsToggle: toggleLyricsHotkey,
      playPause: playPauseHotkey,
    );
    await service.setPreventSleep(shouldPreventSleep(isPlaying: isPlaying));
    return DesktopBehaviorApplyResult(hotkeysRegistered: hotkeysRegistered);
  }

  /// Trims and collapses a user-typed chord.
  ///
  /// Blank input falls back rather than shipping an empty accelerator (which
  /// the runner would either ignore or register as a bare modifier). The result
  /// is capped at [maxHotkeyLength].
  static String normalizeHotkey(String? value, {required String fallback}) {
    final collapsed = (value ?? '').trim().replaceAll(RegExp(r'\s+'), ' ');
    if (collapsed.isEmpty) return fallback;
    if (collapsed.length <= maxHotkeyLength) return collapsed;
    return collapsed.substring(0, maxHotkeyLength);
  }

  static String? _readString(Object? value) => value is String ? value : null;

  static bool _readBool(Object? value, bool fallback) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      if (normalized == 'true' || normalized == '1') return true;
      if (normalized == 'false' || normalized == '0') return false;
    }
    return fallback;
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is DesktopBehaviorSettings &&
            other.closeToTray == closeToTray &&
            other.firstRunHint == firstRunHint &&
            other.hotkeysEnabled == hotkeysEnabled &&
            other.toggleLyricsHotkey == toggleLyricsHotkey &&
            other.playPauseHotkey == playPauseHotkey &&
            other.preventSleepWhilePlaying == preventSleepWhilePlaying &&
            other.rememberWindowState == rememberWindowState;
  }

  @override
  int get hashCode => Object.hash(
    closeToTray,
    firstRunHint,
    hotkeysEnabled,
    toggleLyricsHotkey,
    playPauseHotkey,
    preventSleepWhilePlaying,
    rememberWindowState,
  );

  @override
  String toString() {
    return 'DesktopBehaviorSettings(closeToTray: $closeToTray, '
        'firstRunHint: $firstRunHint, hotkeysEnabled: $hotkeysEnabled, '
        'toggleLyricsHotkey: $toggleLyricsHotkey, '
        'playPauseHotkey: $playPauseHotkey, '
        'preventSleepWhilePlaying: $preventSleepWhilePlaying, '
        'rememberWindowState: $rememberWindowState)';
  }
}

/// What the runner answered while a settings push was applied.
///
/// Only the hotkey registration has a user-visible failure mode (another
/// application owns the chord), so that is the one answer callers act on; the
/// settings page renders it in its 运行状态 card instead of letting the failure
/// disappear into an unawaited future.
@immutable
class DesktopBehaviorApplyResult {
  const DesktopBehaviorApplyResult({required this.hotkeysRegistered});

  final bool hotkeysRegistered;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DesktopBehaviorApplyResult &&
          other.hotkeysRegistered == hotkeysRegistered;

  @override
  int get hashCode => hotkeysRegistered.hashCode;
}

/// Read/write seam for [DesktopBehaviorSettings].
///
/// Shape and reason are the same as `AudioEffectsSettingsStore`: the production
/// store writes Hive, while a widget test overrides the provider with
/// [MemoryDesktopBehaviorSettingsStore]. Without the seam, a switch tap fires a
/// real Hive write from a UI callback, and the file-level `tearDown`'s
/// `Hive.close()` then waits for a continuation that only runs inside
/// `FakeAsync` — a three-second hang per test (see
/// `test/settings_persistence_test.dart`).
///
/// "It really persists" is covered separately by a plain `test()` over the Hive
/// store, so a memory-only implementation can never make the widget test green
/// while the real app forgets the setting.
abstract class DesktopBehaviorSettingsStore {
  /// `null` means "never saved", i.e. use the constructor defaults.
  Object? read();

  Future<void> write(Map<String, dynamic> json);
}

class HiveDesktopBehaviorSettingsStore implements DesktopBehaviorSettingsStore {
  const HiveDesktopBehaviorSettingsStore();

  @override
  Object? read() {
    try {
      return Hive.box(desktopBehaviorBoxName).get(desktopBehaviorSettingsKey);
    } catch (e, s) {
      debugPrint('DesktopBehaviorSettingsStore read failed: $e');
      debugPrint('$s');
      return null;
    }
  }

  @override
  Future<void> write(Map<String, dynamic> json) async {
    try {
      final box = await Hive.openBox(desktopBehaviorBoxName);
      await box.put(desktopBehaviorSettingsKey, json);
    } catch (e, s) {
      debugPrint('DesktopBehaviorSettingsStore write failed: $e');
      debugPrint('$s');
    }
  }
}

/// Test double: never touches Hive, records every write request.
class MemoryDesktopBehaviorSettingsStore
    implements DesktopBehaviorSettingsStore {
  MemoryDesktopBehaviorSettingsStore([this._value]);

  Object? _value;

  /// The JSON currently "on disk" (`null` = never written).
  Object? get value => _value;

  /// Every write, in order — assert on these to prove a tap asked for a save.
  final List<Map<String, dynamic>> writes = <Map<String, dynamic>>[];

  @override
  Object? read() => _value;

  @override
  Future<void> write(Map<String, dynamic> json) async {
    _value = json;
    writes.add(json);
  }
}

/// Injection point: Hive in production, memory in widget tests.
final desktopBehaviorSettingsStoreProvider =
    Provider<DesktopBehaviorSettingsStore>(
      (ref) => const HiveDesktopBehaviorSettingsStore(),
    );

/// The channel the settings are pushed into.
///
/// A provider rather than a direct `DesktopIntegrationService.instance` read so
/// a test can point the page at a mocked channel.
final desktopIntegrationServiceProvider = Provider<DesktopIntegrationService>(
  (ref) => DesktopIntegrationService.instance,
);

final desktopBehaviorSettingsProvider =
    StateNotifierProvider<
      DesktopBehaviorSettingsNotifier,
      DesktopBehaviorSettings
    >((ref) {
      return DesktopBehaviorSettingsNotifier(
        ref.read(desktopBehaviorSettingsStoreProvider),
      );
    });

class DesktopBehaviorSettingsNotifier
    extends StateNotifier<DesktopBehaviorSettings> {
  DesktopBehaviorSettingsNotifier([DesktopBehaviorSettingsStore? store])
    : _store = store ?? const HiveDesktopBehaviorSettingsStore(),
      super(const DesktopBehaviorSettings()) {
    _load();
  }

  final DesktopBehaviorSettingsStore _store;

  void _load() {
    try {
      final raw = _store.read();
      if (!mounted) return;
      state = DesktopBehaviorSettings.fromJson(raw);
    } catch (e, s) {
      debugPrint('DesktopBehaviorSettingsNotifier load failed: $e');
      debugPrint('$s');
    }
  }

  Future<void> setCloseToTray(bool value) =>
      _save(state.copyWith(closeToTray: value));

  Future<void> setFirstRunHint(bool value) =>
      _save(state.copyWith(firstRunHint: value));

  Future<void> setHotkeysEnabled(bool value) =>
      _save(state.copyWith(hotkeysEnabled: value));

  /// Blank or whitespace-only input keeps this setting's default chord instead
  /// of persisting an accelerator the runner cannot parse.
  Future<void> setToggleLyricsHotkey(String value) {
    return _save(
      state.copyWith(
        toggleLyricsHotkey: DesktopBehaviorSettings.normalizeHotkey(
          value,
          fallback: DesktopBehaviorSettings.defaultToggleLyricsHotkey,
        ),
      ),
    );
  }

  Future<void> setPlayPauseHotkey(String value) {
    return _save(
      state.copyWith(
        playPauseHotkey: DesktopBehaviorSettings.normalizeHotkey(
          value,
          fallback: DesktopBehaviorSettings.defaultPlayPauseHotkey,
        ),
      ),
    );
  }

  Future<void> setPreventSleepWhilePlaying(bool value) =>
      _save(state.copyWith(preventSleepWhilePlaying: value));

  Future<void> setRememberWindowState(bool value) =>
      _save(state.copyWith(rememberWindowState: value));

  Future<void> _save(DesktopBehaviorSettings settings) async {
    state = settings;
    // The store swallows its own I/O failures: a failed save must not throw
    // from a switch callback, and the in-memory state is still correct for
    // this session.
    await _store.write(settings.toJson());
  }
}
