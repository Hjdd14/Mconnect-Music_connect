import 'dart:async';

import 'package:flutter/services.dart';

import '../diagnostics/diagnostics_service.dart';
import '../share/deep_link_service.dart';

/// SMTC / tray playback status. The wire words are fixed by
/// `docs/desktop-lyrics-protocol.md` section 4.3.
enum DesktopPlaybackStatus { playing, paused, stopped }

/// One event pushed by the Windows runner.
///
/// Deliberately untyped beyond the name: the payload shapes live in the
/// protocol doc (`smtcControl{action, positionMs?}`, `trayCommand{action}`,
/// `windowStateChanged{...}`), and a field the native side has not shipped yet
/// must not crash Dart. Accessors are null-safe by construction.
class DesktopIntegrationEvent {
  const DesktopIntegrationEvent(this.name, this.arguments);

  /// Event name, one of [DesktopIntegrationService.eventNames].
  final String name;

  final Map<String, Object?> arguments;

  Object? operator [](String key) => arguments[key];

  @override
  String toString() => 'DesktopIntegrationEvent($name, $arguments)';
}

/// Dart half of `com.mconnect.mconnect/desktop_integration`.
///
/// The Windows runner owns the native side (SMTC, tray icon, window state, single
/// instance, disk, hotkeys, sleep). This class exists so the rest of the app can
/// speak to it through one object that **never throws**: every method answers a
/// `bool`, a `String?`, an `int?` or a `Map?` and records a one-shot diagnostic
/// instead.
///
/// That contract is the point, not a convenience. On a build where the native
/// handler is absent (a Linux dev run, an older runner binary, a unit test) the
/// channel answers `MissingPluginException`; a `Future` that throws there would
/// turn every play/pause into an unhandled async error in the player page.
class DesktopIntegrationService {
  DesktopIntegrationService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName) {
    _channel.setMethodCallHandler(_handleEvent);
  }

  static const String channelName = 'com.mconnect.mconnect/desktop_integration';

  /// The single instance the app talks to.
  static final DesktopIntegrationService instance = DesktopIntegrationService();

  /// Event names the protocol defines. Anything else is a runner that is ahead
  /// of this Dart build, and is dropped rather than guessed at.
  static const Set<String> eventNames = {
    'smtcControl',
    'trayCommand',
    'uriReceived',
    'windowCloseRequested',
    'windowStateChanged',
    'trayReady',
    'smtcUnavailable',
    // The runner now says what its close path actually did, so the settings
    // page can show whether 关闭到托盘 really hid the window or fell back to a
    // real exit because no tray icon existed.
    'hiddenToTray',
    'closeFellBackToExit',
    // The tray icon never made it into the notification area, and the close
    // path answered by minimizing instead of hiding (or quitting).
    'trayFailed',
    'minimizedInsteadOfTray',
    // The tray icon is missing, so the close was swallowed and the window was
    // deliberately left on screen, plus the shell's answer to where an accepted
    // icon landed (diagnostic: an icon can exist inside the overflow flyout).
    'trayUnavailableKeptOpen',
    'hiddenWithoutTray',
    'trayIconPlaced',
  };

  final MethodChannel _channel;
  final StreamController<DesktopIntegrationEvent> _events =
      StreamController<DesktopIntegrationEvent>.broadcast();

  /// Methods already reported as unavailable, so a missing native side costs one
  /// log line rather than one per playback tick (setTimeline runs ~1 Hz).
  final Set<String> _reportedUnavailable = <String>{};

  Stream<DesktopIntegrationEvent> get events => _events.stream;

  Future<bool> initialize() => _invokeBool('initialize');

  Future<bool> setMediaMetadata({
    String? title,
    String? artist,
    String? album,
    String? coverUrl,
    int? durationMs,
  }) {
    return _invokeBool('setMediaMetadata', {
      'title': ?title,
      'artist': ?artist,
      'album': ?album,
      'coverUrl': ?coverUrl,
      'durationMs': ?durationMs,
    });
  }

  Future<bool> setPlaybackState(DesktopPlaybackStatus status) {
    return _invokeBool('setPlaybackState', {'status': status.name});
  }

  Future<bool> setTimeline({
    required int positionMs,
    required int durationMs,
    bool seeking = false,
  }) {
    return _invokeBool('setTimeline', {
      'positionMs': positionMs,
      'durationMs': durationMs,
      'seeking': seeking,
    });
  }

  Future<bool> setTrayState({
    required bool playing,
    required bool hasSong,
    required bool floatingLyrics,
    required bool taskbarLyrics,
    required bool liked,
    String? title,
    String? artist,
  }) {
    return _invokeBool('setTrayState', {
      'playing': playing,
      'hasSong': hasSong,
      'floatingLyrics': floatingLyrics,
      'taskbarLyrics': taskbarLyrics,
      'liked': liked,
      'title': ?title,
      'artist': ?artist,
    });
  }

  /// `setCloseBehavior` (protocol section 4.3).
  ///
  /// [minimizeToTray] is the "关闭到托盘" setting: the runner hides the window
  /// instead of quitting. [firstRunHint] asks it to explain the tray icon the
  /// first time that happens, which is what stops the window from simply
  /// "disappearing" for a new user.
  Future<bool> setCloseBehavior({
    required bool minimizeToTray,
    required bool firstRunHint,
    required bool rememberWindowState,
  }) {
    return _invokeBool('setCloseBehavior', {
      'minimizeToTray': minimizeToTray,
      'firstRunHint': firstRunHint,
      // The runner owns the save points (WM_EXITSIZEMOVE and the close path),
      // so the setting has to travel with the close behaviour rather than
      // staying a Dart-only preference that the native side keeps ignoring.
      'rememberWindowState': rememberWindowState,
    });
  }

  /// Global hotkeys. Collisions and registration failures are the runner's
  /// business: Dart only ships the two chords the user typed.
  Future<bool> setHotkeys({
    required bool enabled,
    required String lyricsToggle,
    required String playPause,
  }) {
    return _invokeBool('setHotkeys', {
      'enabled': enabled,
      'lyricsToggle': lyricsToggle,
      'playPause': playPause,
    });
  }

  /// Keeps the machine awake while a song plays.
  ///
  /// The protocol passes a **bare bool** here (not a map), so the argument is
  /// the bool itself; a runner that expects an envelope would fail the call and
  /// answer false, which is why the shape is pinned by a test.
  Future<bool> setPreventSleep(bool enabled) =>
      _invokeBool('setPreventSleep', enabled);

  /// The window geometry the runner remembered, or `null` when it has none
  /// (fresh install, or no native handler at all).
  ///
  /// `null` means "unknown", never "default rectangle": the caller must not
  /// restore a window to a guessed position.
  Future<Map<String, Object?>?> getWindowState() async {
    final result = await _invoke('getWindowState');
    if (result is! Map) return null;
    return <String, Object?>{
      for (final entry in result.entries) entry.key.toString(): entry.value,
    };
  }

  /// What the runner knows about itself right now, or `null` when it cannot
  /// answer (no native handler at all).
  ///
  /// The status card used to be fed exclusively by pushed events, so a tray
  /// icon the shell never accepted - the one failure that emits nothing -
  /// left it saying "尚未收到运行器答复" forever. This is the pull half.
  ///
  /// Keys: `trayAdded` (bool), `trayError` (int, 0 = none),
  /// `smtcAvailable` (bool), `hotkeysEnabled` (bool). Callers read them
  /// defensively; a field a newer runner adds must not break this build.
  Future<Map<String, Object?>?> getRuntimeStatus() async {
    final result = await _invoke('getRuntimeStatus');
    if (result is! Map) return null;
    return <String, Object?>{
      for (final entry in result.entries) entry.key.toString(): entry.value,
    };
  }

  /// Asks the runner to persist its window geometry.
  ///
  /// [state] is optional because the protocol's `saveWindowState` takes no
  /// parameters: the process that owns the window knows its live rectangle
  /// better than a snapshot taken a frame earlier. Passing a map is the
  /// round-trip half of [getWindowState] for callers that keep their own copy.
  Future<bool> saveWindowState([Map<String, Object?>? state]) =>
      _invokeBool('saveWindowState', state);

  /// Forgets the remembered geometry so the next launch uses the defaults.
  Future<bool> resetWindowState() => _invokeBool('resetWindowState');

  /// The `mconnect://` link a cold start was launched with, or `null`.
  ///
  /// One-shot by contract: the runner clears its copy on read, so a second call
  /// answers null instead of replaying a navigation the user already saw.
  Future<String?> takeInitialUri() async {
    final result = await _invoke('takeInitialUri');
    if (result is! String) return null;
    final trimmed = result.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// The Windows accent colour as `0xAARRGGBB`, or `null` when the runner
  /// cannot read it. `null` means "keep the theme seed", never "black".
  Future<int?> getAccentColor() async {
    final result = await _invoke('getAccentColor');
    if (result is int) return result;
    if (result is double) return result.round();
    return null;
  }

  /// Bytes available on the volume holding [path], or `null` when the native
  /// side cannot say (no handler, a path that does not exist, an unmounted
  /// drive). `null` means unknown — never "plenty of room".
  Future<int?> freeSpaceBytes(String path) async {
    final result = await _invoke('freeSpaceBytes', path);
    if (result is int) return result;
    if (result is double) return result.round();
    return null;
  }

  Future<void> dispose() async {
    if (_events.isClosed) return;
    _channel.setMethodCallHandler(null);
    await _events.close();
  }

  /// One place for the never-throw contract: every outbound call goes through
  /// here, so a new method cannot forget the `MissingPluginException` branch or
  /// the one-shot diagnostic (a 1 Hz caller would otherwise flood the log).
  Future<Object?> _invoke(String method, [Object? arguments]) async {
    try {
      return await _channel.invokeMethod<Object?>(method, arguments);
    } on MissingPluginException {
      _reportUnavailable(method);
      return null;
    } on PlatformException catch (error) {
      _reportFailure(method, error);
      return null;
    } on Object catch (error, stack) {
      DiagnosticsService.instance.recordError('desktop.$method', error, stack);
      return null;
    }
  }

  Future<bool> _invokeBool(String method, [Object? arguments]) async {
    return await _invoke(method, arguments) == true;
  }

  Future<void> _handleEvent(MethodCall call) async {
    if (!eventNames.contains(call.method)) {
      return;
    }
    final arguments = call.arguments;
    if (arguments is! Map) {
      // A payload this build cannot read must not take the event stream down.
      return;
    }
    if (_events.isClosed) return;
    _events.add(
      DesktopIntegrationEvent(call.method, {
        for (final entry in arguments.entries)
          entry.key.toString(): entry.value,
      }),
    );
  }

  void _reportUnavailable(String method) {
    if (!_reportedUnavailable.add(method)) return;
    DiagnosticsService.instance.record(
      'desktop',
      'desktop_integration_unavailable',
      data: {'method': method},
    );
  }

  void _reportFailure(String method, PlatformException error) {
    if (!_reportedUnavailable.add('$method:${error.code}')) return;
    DiagnosticsService.instance.record(
      'desktop',
      'desktop_integration_failed',
      data: {'method': method, 'code': error.code, 'message': error.message},
    );
  }
}

/// Bridges the runner's deep links into the app's existing inbound-link path.
///
/// Windows does not go through `app_links`: the runner owns the `mconnect://`
/// launch argument, the second-instance hand-off and the `uriReceived` event.
/// Rather than teach every caller about a second link source, this adapter
/// implements the same [LinkSource] seam `app_links` does, so
/// [DeepLinkService] keeps parsing, classifying and navigating exactly as it
/// does on Android — the desktop path differs only in where the URI comes from.
///
/// [fallback] is what keeps a Windows build usable against a runner binary that
/// predates this channel: with no native URI the platform source still answers.
class DesktopLinkSource implements LinkSource {
  DesktopLinkSource({
    required this.desktop,
    this.fallback = const AppLinksSource(),
  });

  final DesktopIntegrationService desktop;

  /// Consulted when the runner has no link to offer.
  final LinkSource fallback;

  @override
  Future<Uri?> initialLink() async {
    final raw = await desktop.takeInitialUri();
    final uri = raw == null ? null : Uri.tryParse(raw);
    if (uri != null && uri.hasScheme) return uri;
    return fallback.initialLink();
  }

  @override
  Stream<Uri> links() {
    final controller = StreamController<Uri>();
    final subscriptions = <StreamSubscription<Uri>>[];
    controller.onListen = () {
      for (final source in <Stream<Uri>>[fallback.links(), _desktopLinks()]) {
        subscriptions.add(
          source.listen(
            (uri) {
              if (!controller.isClosed) controller.add(uri);
            },
            // A dead platform stream (no plugin, a runner restarted underneath
            // us) must not surface as an unhandled async error.
            onError: (Object _) {},
          ),
        );
      }
    };
    controller.onCancel = () async {
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
      subscriptions.clear();
    };
    return controller.stream;
  }

  Stream<Uri> _desktopLinks() {
    return desktop.events
        .where((event) => event.name == 'uriReceived')
        .map((event) => Uri.tryParse(event['uri']?.toString() ?? ''))
        .where((uri) => uri != null && uri.hasScheme)
        .cast<Uri>();
  }
}