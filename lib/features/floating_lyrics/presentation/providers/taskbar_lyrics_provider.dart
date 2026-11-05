import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../../../core/lyrics/lyrics_animation_catalog.dart';
import '../../../../core/lyrics/lyrics_overlay_config.dart';
import '../../../../core/lyrics/lyrics_overlay_sink.dart';
import '../../data/floating_lyrics_models.dart';
import '../../data/sinks/desktop_lyrics_sinks.dart';

const _settingsBoxName = 'settings';
const _taskbarLyricsKey = 'taskbar_lyrics_settings';

/// Persisted taskbar lyrics style (docs/desktop-lyrics-protocol.md 2.3).
///
/// A separate notifier from [floatingLyricsProvider] because the two windows
/// carry different defaults and must be switchable independently.
final taskbarLyricsProvider =
    StateNotifierProvider<TaskbarLyricsNotifier, TaskbarLyricsSettings>((ref) {
      return TaskbarLyricsNotifier();
    });

class TaskbarLyricsNotifier extends StateNotifier<TaskbarLyricsSettings> {
  Future<void> ready = Future.value();

  TaskbarLyricsNotifier() : super(const TaskbarLyricsSettings()) {
    _load();
  }

  void _load() {
    try {
      final box = Hive.box(_settingsBoxName);
      final raw = box.get(_taskbarLyricsKey);
      if (!mounted || raw is! Map) return;
      state = TaskbarLyricsSettings.fromJson(raw);
    } catch (e, s) {
      debugPrint('TaskbarLyricsNotifier load failed: $e');
      debugPrint('$s');
    }
  }

  /// Applies [change] through one write path so every setter persists.
  Future<void> apply(
    TaskbarLyricsSettings Function(TaskbarLyricsSettings current) change,
  ) {
    return _save(change(state));
  }

  Future<void> setEnabled(bool enabled) =>
      apply((s) => s.copyWith(enabled: enabled));

  Future<void> setMonitorDeviceName(String value) =>
      apply((s) => s.copyWith(monitorDeviceName: value));

  Future<void> setAnchor(LyricsTaskbarAnchor value) =>
      apply((s) => s.copyWith(anchor: value));

  Future<void> setOffsetX(double value) => apply(
    (s) => s.copyWith(offsetX: TaskbarLyricsSettings.clampOffsetX(value)),
  );

  Future<void> setWidth(double value) =>
      apply((s) => s.copyWith(width: TaskbarLyricsSettings.clampWidth(value)));

  Future<void> setHeight(double value) => apply(
    (s) => s.copyWith(height: TaskbarLyricsSettings.clampHeight(value)),
  );

  Future<void> setFontSize(double value) => apply(
    (s) => s.copyWith(fontSize: TaskbarLyricsSettings.clampFontSize(value)),
  );

  Future<void> setFontFamily(String value) =>
      apply((s) => s.copyWith(fontFamily: value));

  Future<void> setFontWeight(int value) => apply(
    (s) => s.copyWith(fontWeight: TaskbarLyricsSettings.clampFontWeight(value)),
  );

  Future<void> setTextColor(Color color) =>
      apply((s) => s.copyWith(textColor: color));

  Future<void> setHighlightColor(Color color) =>
      apply((s) => s.copyWith(highlightColor: color));

  Future<void> setBackgroundMode(LyricsBackgroundMode value) =>
      apply((s) => s.copyWith(backgroundMode: value));

  Future<void> setBackgroundColor(Color color) =>
      apply((s) => s.copyWith(backgroundColor: color));

  Future<void> setBackgroundOpacity(double value) => apply(
    (s) => s.copyWith(
      backgroundOpacity: TaskbarLyricsSettings.clampBackgroundOpacity(value),
    ),
  );

  Future<void> setLineMode(LyricsLineMode value) =>
      apply((s) => s.copyWith(lineMode: value));

  Future<void> setTranslationLayout(LyricsTranslationLayout value) =>
      apply((s) => s.copyWith(translationLayout: value));

  Future<void> setLineAnimation(LyricsLineTransition value) =>
      apply((s) => s.copyWith(lineAnimation: value));

  Future<void> setAnimationDurationMs(int value) => apply(
    (s) => s.copyWith(
      animationDurationMs: TaskbarLyricsSettings.clampAnimationDurationMs(
        value,
      ),
    ),
  );

  Future<void> setEasing(LyricsEasing value) =>
      apply((s) => s.copyWith(easing: value));

  Future<void> setWindowAnimation(LyricsWindowTransition value) =>
      apply((s) => s.copyWith(windowAnimation: value));

  Future<void> setClickThrough(bool value) =>
      apply((s) => s.copyWith(clickThrough: value));

  Future<void> setFollowAutoHide(bool value) =>
      apply((s) => s.copyWith(followAutoHide: value));

  Future<void> setHideInFullscreen(bool value) =>
      apply((s) => s.copyWith(hideInFullscreen: value));

  Future<void> setMarquee(bool value) =>
      apply((s) => s.copyWith(marquee: value));

  Future<void> setEdgePadding(double value) => apply(
    (s) =>
        s.copyWith(edgePadding: TaskbarLyricsSettings.clampEdgePadding(value)),
  );

  Future<void> setCornerRadius(double value) => apply(
    (s) => s.copyWith(
      cornerRadius: TaskbarLyricsSettings.clampCornerRadius(value),
    ),
  );

  Future<void> setDebugGeometry(bool value) =>
      apply((s) => s.copyWith(debugGeometry: value));

  Future<void> setReduceMotion(bool value) =>
      apply((s) => s.copyWith(reduceMotion: value));

  Future<void> _save(TaskbarLyricsSettings settings) async {
    state = settings;
    try {
      final box = await Hive.openBox(_settingsBoxName);
      await box.put(_taskbarLyricsKey, settings.toJson());
    } catch (e, s) {
      debugPrint('TaskbarLyricsNotifier save failed: $e');
      debugPrint('$s');
    }
  }
}

/// What the native taskbar strip last reported (docs/desktop-lyrics-protocol.md
/// section 4.2).
///
/// Nothing here is persisted: it is the view of the current desktop session,
/// used by the lyrics studio's status bar to explain why the strip is where it
/// is (or is not).
@immutable
class TaskbarLyricsStatus {
  const TaskbarLyricsStatus({
    this.monitors = const <LyricsMonitorInfo>[],
    this.taskbars = const <LyricsTaskbarInfo>[],
    this.spaceInsufficient = false,
    this.edge = 'bottom',
    this.found = false,
    this.autoHide = false,
    this.offsetX,
    this.width,
    this.placement,
    this.lastError,
  });

  /// Monitors the floating overlay channel reports; the taskbar channel has no
  /// getMonitors of its own (protocol section 4.2).
  final List<LyricsMonitorInfo> monitors;

  final List<LyricsTaskbarInfo> taskbars;

  /// The strip did not fit the free taskbar area and sits against its inner
  /// edge instead.
  final bool spaceInsufficient;

  /// Dock edge of the first taskbar: bottom / top / left / right.
  final String edge;

  final bool found;
  final bool autoHide;

  /// Strip origin the native side reported after a drag.
  final double? offsetX;

  /// Strip width the native side reported after a resize.
  final double? width;

  /// Live rectangle of the strip in physical pixels, as the native window just
  /// placed it. The studio shows it so a slider drag has a visible answer even
  /// when the strip itself is hard to see on a busy taskbar.
  final Rect? placement;

  final String? lastError;

  static const Object _unset = Object();

  TaskbarLyricsStatus copyWith({
    List<LyricsMonitorInfo>? monitors,
    List<LyricsTaskbarInfo>? taskbars,
    bool? spaceInsufficient,
    String? edge,
    bool? found,
    bool? autoHide,
    Object? offsetX = _unset,
    Object? width = _unset,
    Object? placement = _unset,
    Object? lastError = _unset,
  }) {
    return TaskbarLyricsStatus(
      monitors: monitors ?? this.monitors,
      taskbars: taskbars ?? this.taskbars,
      spaceInsufficient: spaceInsufficient ?? this.spaceInsufficient,
      edge: edge ?? this.edge,
      found: found ?? this.found,
      autoHide: autoHide ?? this.autoHide,
      offsetX: identical(offsetX, _unset) ? this.offsetX : offsetX as double?,
      width: identical(width, _unset) ? this.width : width as double?,
      placement: identical(placement, _unset)
          ? this.placement
          : placement as Rect?,
      lastError: identical(lastError, _unset)
          ? this.lastError
          : lastError as String?,
    );
  }
}

/// Keeps [TaskbarLyricsStatus] current.
///
/// The strip's channel used to be write-only on the Dart side: every native
/// geometryChanged / taskbarStateChanged / positionChanged / closedByUser was
/// dropped on the floor, and nothing ever asked for the taskbar geometry.
class TaskbarLyricsStatusNotifier extends StateNotifier<TaskbarLyricsStatus> {
  TaskbarLyricsStatusNotifier({
    this.sinks = const <LyricsOverlaySink>[],
    this.onDragOffset,
    TaskbarLyricsStatus initial = const TaskbarLyricsStatus(),
  }) : super(initial);

  /// Commits a dragged offset into the persisted style.
  ///
  /// A drag reports continuously, so the notifier debounces before writing: the
  /// strip must not fight a per-frame Hive write while the user moves it, and
  /// the placement must survive the next geometry refresh.
  final void Function(double offsetX)? onDragOffset;

  Timer? _offsetCommit;

  /// The sinks to probe; `desktopLyricsSinksProvider` supplies them in the app,
  /// tests pass their own.
  final List<LyricsOverlaySink> sinks;
  StreamSubscription<TaskbarLyricsEvent>? _events;

  /// Listens to the strip's native events. A second call replaces the first.
  void attach(Stream<TaskbarLyricsEvent> stream) {
    unawaited(_events?.cancel());
    _events = stream.listen(_onEvent);
  }

  /// Re-reads the taskbar geometry and the monitor list from the native side.
  Future<void> refresh() async {
    LyricsOverlaySink? floating;
    LyricsOverlaySink? taskbar;
    for (final sink in sinks) {
      switch (sink.surface) {
        case LyricsSurface.floating:
          floating ??= sink;
          break;
        case LyricsSurface.taskbar:
          taskbar ??= sink;
          break;
      }
    }

    try {
      final monitors = floating == null
          ? const <LyricsMonitorInfo>[]
          : await floating.getMonitors();
      if (taskbar == null) {
        if (!mounted) return;
        state = state.copyWith(
          monitors: monitors,
          taskbars: const <LyricsTaskbarInfo>[],
          found: false,
          lastError: null,
        );
        return;
      }
      await taskbar.refreshGeometry();
      final taskbars = await taskbar.getTaskbarInfo();
      if (!mounted) return;
      final first = taskbars.isEmpty ? null : taskbars.first;
      state = state.copyWith(
        monitors: monitors,
        taskbars: taskbars,
        found: taskbars.isNotEmpty,
        edge: first?.edge ?? state.edge,
        autoHide: first?.autoHide ?? state.autoHide,
        spaceInsufficient: state.spaceInsufficient,
        lastError: null,
      );
    } catch (error, stack) {
      debugPrint('TaskbarLyricsStatusNotifier refresh failed: $error');
      debugPrint('$stack');
      if (!mounted) return;
      state = state.copyWith(lastError: error.toString());
    }
  }

  void _onEvent(TaskbarLyricsEvent event) {
    if (!mounted) return;
    switch (event.name) {
      case 'geometryChanged':
        // The strip re-probed its taskbar: it exists (the probe reported it)
        // and the next state event carries the new edge.
        state = state.copyWith(found: true);
        break;
      case 'taskbarStateChanged':
        state = state.copyWith(
          found: event.found ?? true,
          autoHide: event.autoHide ?? state.autoHide,
          edge: event.edge ?? state.edge,
          spaceInsufficient: event.spaceInsufficient ?? state.spaceInsufficient,
        );
        break;
      case 'positionChanged':
        state = state.copyWith(offsetX: event.offsetX, width: event.width);
        break;
      case 'taskbarPlacement':
        final left = event.left;
        final top = event.top;
        final width = event.width;
        final height = event.height;
        if (event.visible == false) {
          state = state.copyWith(placement: null);
          break;
        }
        if (left != null && top != null && width != null && height != null) {
          state = state.copyWith(
            placement: Rect.fromLTWH(left, top, width, height),
          );
        }
        break;
      case 'dragOffset':
        final offsetX = event.offsetX;
        if (offsetX == null) break;
        state = state.copyWith(offsetX: offsetX, width: event.width);
        _offsetCommit?.cancel();
        _offsetCommit = Timer(const Duration(milliseconds: 180), () {
          onDragOffset?.call(offsetX);
        });
        break;
      case 'geometrySelfTestFailed':
        // The native geometry self-test runs in Release too now. A failure is
        // exactly the "the sliders do nothing" class of bug, so surface it.
        state = state.copyWith(
          lastError: '几何自检失败：${event.reason ?? "未知"}',
        );
        break;
      case 'closedByUser':
        // The strip hid itself; the geometry it reported is still the truth.
        break;
    }
  }

  @override
  void dispose() {
    _offsetCommit?.cancel();
    _offsetCommit = null;
    unawaited(_events?.cancel());
    _events = null;
    super.dispose();
  }
}

/// Live taskbar geometry/state, kept current by the strip's own events.
final taskbarLyricsStatusProvider =
    StateNotifierProvider<TaskbarLyricsStatusNotifier, TaskbarLyricsStatus>((
      ref,
    ) {
      final sinks = ref.watch(desktopLyricsSinksProvider);
      final notifier = TaskbarLyricsStatusNotifier(
        sinks: sinks,
        onDragOffset: (offsetX) =>
            ref.read(taskbarLyricsProvider.notifier).setOffsetX(offsetX),
      );
      for (final sink in sinks) {
        if (sink is WindowsTaskbarLyricsSink) {
          notifier.attach(sink.eventStream);
        }
      }
      // One probe on first use, so the studio shows the real state instead of
      // "not found" until the user presses 重新探测.
      unawaited(notifier.refresh());
      return notifier;
    });
