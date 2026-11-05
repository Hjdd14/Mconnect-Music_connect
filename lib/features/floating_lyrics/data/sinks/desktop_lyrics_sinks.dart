import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/diagnostics/diagnostics_service.dart';
import '../../../../core/lyrics/lyrics_animation_catalog.dart';
import '../../../../core/lyrics/lyrics_overlay_config.dart';
import '../../../../core/lyrics/lyrics_overlay_frame.dart';
import '../../../../core/lyrics/lyrics_overlay_sink.dart';
import '../../../../core/platform/platform_utils.dart';

/// Shared plumbing of the two Windows overlays.
///
/// Both channels answer with the protocol's "false means the native side could
/// not do it" contract; a missing implementation (Android, an older Windows
/// build) is not an error, so it degrades to false instead of throwing into the
/// sync loop (docs/desktop-lyrics-protocol.md, section 6).
abstract class DesktopLyricsSink extends LyricsOverlaySink {
  DesktopLyricsSink({
    required String channelName,
    MethodChannel? channel,
    DiagnosticsService? diagnostics,
  }) : _channel = channel ?? MethodChannel(channelName),
       _diagnostics = diagnostics ?? DiagnosticsService.instance;

  final MethodChannel _channel;
  final DiagnosticsService _diagnostics;

  /// The channel this sink drives.
  ///
  /// Protected because the taskbar strip also *receives* calls: it is the only
  /// surface whose native side pushes geometry/state events, and a sink that
  /// wants them has to register a call handler on its own channel.
  @protected
  MethodChannel get channel => _channel;

  @override
  bool get supportsPreview => true;

  /// Frame + style. The floating window keeps accepting style on update: that
  /// is the pre-rewrite behaviour the native window still relies on during the
  /// transition, and unknown frame keys are ignored by the new renderer.
  Map<String, Object?> frameArguments(
    LyricsOverlayFrame frame,
    LyricsOverlayConfig config,
  ) {
    return <String, Object?>{...frame.toJsonFor(surface), ...config.toJson()};
  }

  Future<bool> invokeBool(String method, [Object? arguments]) async {
    return await invoke<Object?>(method, arguments) == true;
  }

  Future<T?> invoke<T>(String method, [Object? arguments]) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on MissingPluginException {
      return null;
    } on PlatformException catch (error, stack) {
      _diagnostics.recordError('desktop_lyrics.$method', error, stack);
      return null;
    }
  }

  @override
  Future<bool> configure(LyricsOverlayConfig config) {
    return invokeBool('configure', config.toJson());
  }

  @override
  Future<bool> show(LyricsOverlayFrame frame, LyricsOverlayConfig config) {
    return invokeBool('show', frameArguments(frame, config));
  }

  @override
  Future<bool> update(LyricsOverlayFrame frame, LyricsOverlayConfig config) {
    return invokeBool('update', frameArguments(frame, config));
  }

  @override
  Future<bool> hide() => invokeBool('hide');

  @override
  Future<bool> preview(LyricsPreviewRequest request) {
    return invokeBool('preview', request.toJson());
  }

  @override
  Future<List<LyricsMonitorInfo>> getMonitors() async {
    final result = await invoke<List<dynamic>>('getMonitors');
    if (result == null) return const <LyricsMonitorInfo>[];
    return <LyricsMonitorInfo>[
      for (final item in result)
        if (item is Map) LyricsMonitorInfo.fromJson(item),
    ];
  }
}

/// Windows floating lyrics window (com.mconnect.mconnect/floating_lyrics).
///
/// Same channel and same legacy methods as the Android overlay, plus the new
/// desktop ones. The frame it sends is a superset of the old payload, so a
/// native build from before the rewrite keeps rendering.
class WindowsFloatingLyricsSink extends DesktopLyricsSink {
  WindowsFloatingLyricsSink({super.channel, super.diagnostics})
    : super(channelName: LyricsChannels.floating);

  @override
  LyricsSurface get surface => LyricsSurface.floating;

  @override
  bool get requiresOverlayPermission => true;

  @override
  Future<bool> ensureAvailable() async {
    return await invokeBool('canDrawOverlays');
  }

  @override
  Future<bool> openOverlaySettings() => invokeBool('openOverlaySettings');

  @override
  Future<bool> resetPosition() => invokeBool('resetPosition');

  @override
  Future<bool> setInteractive(bool interactive) {
    return invokeBool('setInteractive', interactive);
  }
}

/// Windows taskbar lyrics strip (com.mconnect.mconnect/taskbar_lyrics).
///
/// Frames carry no style: the strip is configured once through configure(), and
/// its updates are the hottest path on the app (every ~200 ms while playing).
class WindowsTaskbarLyricsSink extends DesktopLyricsSink {
  WindowsTaskbarLyricsSink({super.channel, super.diagnostics})
    : super(channelName: LyricsChannels.taskbar) {
    // The strip reports its own geometry and state; a MethodChannel without a
    // call handler simply drops them. Registering here is what turns
    // geometryChanged / taskbarStateChanged / positionChanged / closedByUser
    // into something Dart can react to.
    channel.setMethodCallHandler(_handleNativeCall);
  }

  /// Events the strip's native side emits (docs/desktop-lyrics-protocol.md 4.2).
  static const Set<String> nativeEventNames = <String>{
    'geometryChanged',
    'taskbarStateChanged',
    'positionChanged',
    'taskbarPlacement',
    'dragOffset',
    'geometrySelfTestFailed',
    'closedByUser',
    'ready',
  };

  final StreamController<TaskbarLyricsEvent> _events =
      StreamController<TaskbarLyricsEvent>.broadcast();

  /// Everything the native strip reports, with its raw argument map.
  Stream<TaskbarLyricsEvent> get eventStream => _events.stream;

  Future<void> _handleNativeCall(MethodCall call) async {
    if (!nativeEventNames.contains(call.method)) return;
    final arguments = call.arguments;
    _events.add(
      TaskbarLyricsEvent(
        call.method,
        arguments is Map ? arguments : const <Object?, Object?>{},
      ),
    );
  }

  @override
  Future<void> dispose() async {
    channel.setMethodCallHandler(null);
    await _events.close();
    await super.dispose();
  }

  @override
  LyricsSurface get surface => LyricsSurface.taskbar;

  @override
  Map<String, Object?> frameArguments(
    LyricsOverlayFrame frame,
    LyricsOverlayConfig config,
  ) {
    return frame.toJsonFor(LyricsSurface.taskbar);
  }

  @override
  Future<bool> refreshGeometry() => invokeBool('refreshGeometry');

  @override
  Future<List<LyricsTaskbarInfo>> getTaskbarInfo() async {
    final result = await invoke<List<dynamic>>('getTaskbarInfo');
    if (result == null) return const <LyricsTaskbarInfo>[];
    return <LyricsTaskbarInfo>[
      for (final item in result)
        if (item is Map) LyricsTaskbarInfo.fromJson(item),
    ];
  }
}

/// One event pushed by the native taskbar strip.
///
/// A small value object instead of a raw [MethodCall]: the status notifier and
/// the diagnostics panel read the same handful of fields, and the typed getters
/// keep the `Object?`-shaped channel arguments out of their code.
@immutable
class TaskbarLyricsEvent {
  const TaskbarLyricsEvent(
    this.name, [
    this.payload = const <Object?, Object?>{},
  ]);

  /// Native method name, one of [WindowsTaskbarLyricsSink.nativeEventNames].
  final String name;

  /// Raw argument map; empty for the argument-less events (geometryChanged,
  /// closedByUser).
  final Map<Object?, Object?> payload;

  bool? get autoHide => _bool('autoHide');

  bool? get spaceInsufficient => _bool('spaceInsufficient');

  /// Only sent by newer native builds; older ones leave the strip's own
  /// geometry probe to answer whether the taskbar exists.
  bool? get found => _bool('found');

  String? get edge {
    final value = payload['edge'];
    return value is String ? value : null;
  }

  double? get offsetX => _double('offsetX');

  double? get width => _double('width');

  double? get height => _double('height');

  String? get reason {
    final value = payload['reason'];
    return value is String ? value : null;
  }

  double? get left => _double('left');

  double? get top => _double('top');

  bool? get visible => _bool('visible');

  bool? _bool(String key) {
    final value = payload[key];
    return value is bool ? value : null;
  }

  double? _double(String key) {
    final value = payload[key];
    return value is num ? value.toDouble() : null;
  }

  @override
  String toString() => 'TaskbarLyricsEvent($name, $payload)';
}

/// The sinks this build can drive, created once and shared.
///
/// Two consumers need the same instances: the sync controller (which pushes
/// frames) and the taskbar status notifier (which asks for geometry and
/// listens to the strip's events). Building them twice would open two event
/// streams and register two call handlers on one channel, so the instances live
/// here and the provider owns their disposal.
///
/// An empty list means use the legacy Android sink, which is what the sync
/// controller falls back to on every non-Windows platform.
final desktopLyricsSinksProvider = Provider<List<LyricsOverlaySink>>((ref) {
  if (!PlatformUtils.isWindows) return const <LyricsOverlaySink>[];
  final sinks = <LyricsOverlaySink>[
    WindowsFloatingLyricsSink(),
    WindowsTaskbarLyricsSink(),
  ];
  ref.onDispose(() {
    for (final sink in sinks) {
      unawaited(sink.dispose());
    }
  });
  return List<LyricsOverlaySink>.unmodifiable(sinks);
});
