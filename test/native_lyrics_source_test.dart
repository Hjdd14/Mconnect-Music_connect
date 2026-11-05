import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Source-level guards for the Windows native lyrics stack.
///
/// The native renderer cannot run in flutter test, so the contract it must
/// satisfy - per-pixel alpha through UpdateLayeredWindow, Direct2D/DirectWrite
/// drawing with a GDI+ fallback, the taskbar geometry probes, the channel
/// method names from docs/desktop-lyrics-protocol.md and the CMake wiring - is
/// asserted against the C++ sources themselves. Every assertion below maps to a
/// behaviour that has a visible failure mode in the running app, so a refactor
/// that drops one of them is caught here instead of on a user's desktop.
String _source(String path) {
  final file = File(path);
  expect(file.existsSync(), isTrue, reason: '$path is missing');
  return file.readAsStringSync();
}

List<String> _sourcesIn(String directory) {
  final dir = Directory(directory);
  expect(dir.existsSync(), isTrue, reason: '$directory is missing');
  return dir
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.cpp') || file.path.endsWith('.h'))
      .map((file) => file.path)
      .toList()
    ..sort();
}

/// The text between [start] and the first [end] after it, so an assertion can
/// name one function instead of grepping the whole file.
String _section(String source, String start, String end) {
  final begin = source.indexOf(start);
  expect(begin, greaterThan(-1), reason: 'missing "$start"');
  final finish = source.indexOf(end, begin);
  expect(finish, greaterThan(begin), reason: 'missing "$end" after "$start"');
  return source.substring(begin, finish);
}

void main() {
  group('layered window presentation', () {
    test('presents a 32bpp DIB with UpdateLayeredWindow and no colour key', () {
      final source = _source('windows/runner/lyrics/lyrics_renderer.cpp');

      expect(source, contains('CreateDIBSection'));
      expect(source, contains('BI_RGB'));
      expect(source, contains('UpdateLayeredWindow'));
      expect(source, contains('ULW_ALPHA'));
      expect(source, contains('AC_SRC_ALPHA'));
      expect(source, contains('AC_SRC_OVER'));

      // A colour key punches holes through anti-aliased glyph edges and cannot
      // express the translucent rounded background, so it must not come back.
      for (final path in _sourcesIn('windows/runner')) {
        final text = File(path).readAsStringSync();
        expect(text, isNot(contains('LWA_COLORKEY')), reason: path);
        expect(
          text,
          isNot(contains('SetLayeredWindowAttributes')),
          reason: path,
        );
      }
    });

    test('keeps the Direct2D/DirectWrite backend and defaults to GDI+', () {
      final source = _source('windows/runner/lyrics/lyrics_renderer.cpp');

      // The D2D scene/draw code is kept for a future backend switch, but the
      // stable path on this Windows/Flutter combination is GDI+ (the D2D
      // initialiser used to crash while the window was still being created).
      expect(source, contains('CreateDCRenderTarget'));
      expect(source, contains('ID2D1DCRenderTarget'));
      expect(source, contains('IDWriteTextLayout'));
      expect(source, contains('CreateTextLayout'));
      expect(source, contains('D2D1_TEXT_ANTIALIAS_MODE_GRAYSCALE'));
      expect(source, contains('kind_ = RendererKind::kGdiPlus'));
      expect(source, contains('InitializeGdiPlus'));
    });

    test('falls back to per-pixel GDI+ instead of showing nothing', () {
      final source = _source('windows/runner/lyrics/lyrics_renderer.cpp');

      expect(source, contains('GdiplusStartup'));
      expect(source, contains('PixelFormat32bppPARGB'));
      expect(source, contains('RendererKind::kGdiPlus'));
      expect(source, contains('fallback_reason'));
    });
  });

  group('lyrics types and animation catalog', () {
    test('mirrors every transition and easing name from the protocol', () {
      final types = _source('windows/runner/lyrics/lyrics_types.h');
      const lineTransitions = [
        'none',
        'fade',
        'fadeThrough',
        'slideLeft',
        'slideRight',
        'slideUp',
        'slideDown',
        'pushLeft',
        'pushRight',
        'scaleIn',
        'scaleOut',
        'wipeLeft',
        'wipeRight',
        'flipX',
        'flipY',
        'dropBounce',
        'springUp',
        'glowSoft',
        'random',
      ];
      for (final name in lineTransitions) {
        expect(types, contains('"$name"'), reason: 'line transition $name');
      }
      const windowTransitions = [
        'slideFromTop',
        'slideFromBottom',
        'slideFromLeft',
        'slideFromRight',
        'pop',
      ];
      for (final name in windowTransitions) {
        expect(types, contains('"$name"'), reason: 'window transition $name');
      }
      const easings = ['linear', 'easeOut', 'easeInOut', 'overshoot'];
      for (final name in easings) {
        expect(types, contains('"$name"'), reason: 'easing $name');
      }
      expect(types, contains('ParseLineTransition'));
      expect(types, contains('ParseWindowTransition'));
      expect(types, contains('ParseEasing'));
      expect(types, contains('kLineTransitionCount'));
      expect(types, contains('kWindowTransitionCount'));
    });

    test('implements easing, line frames and reduce motion', () {
      final source = _source('windows/runner/lyrics/lyrics_animation.cpp');

      expect(source, contains('ApplyEasing'));
      expect(source, contains('ComputeLineTransition'));
      expect(source, contains('ComputeWindowTransition'));
      expect(source, contains('ResolveRandomTransition'));
      expect(source, contains('reduce_motion'));
      expect(source, contains('kOvershoot'));
      expect(source, contains('alpha'));
    });
  });

  group('floating lyrics window', () {
    test('keeps the Dart-facing class API the channel depends on', () {
      final header = _source('windows/runner/lyrics/floating_lyrics_window.h');

      expect(header, contains('class FloatingLyricsWindow'));
      expect(header, contains('bool Show('));
      expect(header, contains('bool Update('));
      expect(header, contains('void Hide();'));
      expect(
        header,
        contains(
          'void SetEventCallback(std::function<void(const std::string&)> callback);',
        ),
      );
      expect(header, contains('bool IsLocked()'));
      expect(header, contains('int GetWidth()'));
      expect(header, contains('bool Configure('));
      expect(header, contains('bool Preview('));
      expect(header, contains('void SetInteractive('));
      expect(header, contains('void ResetPosition('));
    });

    test('reports the events the Dart service already listens to', () {
      final source = _source(
        'windows/runner/lyrics/floating_lyrics_window.cpp',
      );

      for (final event in [
        'closedByUser',
        'lockChanged',
        'windowResized',
        'styleChanged',
        'controlRequested',
        'positionChanged',
        'moveEnded',
        'ready',
      ]) {
        expect(source, contains(event), reason: 'event $event');
      }
      // The renderer fallback is reported by the layered window base, which owns
      // the renderer and knows when it had to demote to GDI+.
      expect(
        _source('windows/runner/lyrics/lyrics_window_base.cpp'),
        contains('rendererFallback'),
      );
      // The window consumes the per-word segment table and the sweep rate the
      // protocol added, not just the legacy 0..1 progress.
      expect(source, contains('highlight_rate'));
      expect(source, contains('word_segments'));
    });

    test('base window handles layered hit testing, drag, resize and DPI', () {
      final source = _source('windows/runner/lyrics/lyrics_window_base.cpp');

      expect(source, contains('WS_EX_LAYERED'));
      expect(source, contains('WS_EX_TOOLWINDOW'));
      expect(source, contains('WS_EX_NOACTIVATE'));
      expect(source, contains('WM_NCHITTEST'));
      expect(source, contains('HTTRANSPARENT'));
      expect(source, contains('WM_DPICHANGED'));
      expect(source, contains('GetDpiForWindow'));
      expect(source, contains('SetTimer'));
      expect(source, contains('WM_EXITSIZEMOVE'));
      expect(source, contains('TrackMouseEvent'));
      expect(source, contains('EnumDisplayMonitors'));
    });
  });

  group('taskbar lyrics', () {
    test('geometry probes the real taskbar and computes a free rect', () {
      final source = _source('windows/runner/lyrics/taskbar_geometry.cpp');

      for (final probe in [
        'Shell_TrayWnd',
        'Shell_SecondaryTrayWnd',
        'TrayNotifyWnd',
        'ReBarWindow32',
        'MSTaskListWClass',
        'MonitorFromWindow',
        'SHAppBarMessage',
        'ABM_GETSTATE',
        'ABS_AUTOHIDE',
      ]) {
        expect(source, contains(probe), reason: probe);
      }
      expect(source, contains('ComputeTaskbarGeometry'));
      expect(source, contains('free_rect'));
      expect(source, contains('anchor'));
      expect(source, contains('offset_x'));
      expect(source, contains('space_insufficient'));
    });

    test('taskbar window listens for taskbar and display changes', () {
      final source = _source('windows/runner/lyrics/taskbar_lyrics_window.cpp');

      expect(source, contains('TaskbarCreated'));
      expect(source, contains('WM_SETTINGCHANGE'));
      expect(source, contains('WM_DISPLAYCHANGE'));
      expect(source, contains('SetWinEventHook'));
      expect(source, contains('EVENT_OBJECT_LOCATIONCHANGE'));
      expect(source, contains('spaceInsufficient'));
      expect(source, contains('geometryChanged'));
    });

    test('supports stacked, inline and hidden translation layouts', () {
      final types = _source('windows/runner/lyrics/lyrics_types.h');
      final args = _source('windows/runner/lyrics/lyrics_channel_args.h');
      final renderer = _source('windows/runner/lyrics/lyrics_renderer.cpp');

      expect(types, contains('TranslationLayout'));
      expect(types, contains('ParseTranslationLayout'));
      expect(types, contains('"inline"'));
      expect(types, contains('"hidden"'));
      expect(args, contains('"translationLayout"'));
      expect(renderer, contains('TranslationLayout::kInline'));
      expect(renderer, contains('TranslationLayout::kHidden'));
    });

    test('taskbar channel exposes the protocol surface', () {
      final source = _source('windows/runner/taskbar_lyrics_channel.cpp');

      expect(source, contains('com.mconnect.mconnect/taskbar_lyrics'));
      for (final method in [
        'configure',
        'show',
        'update',
        'hide',
        'preview',
        'refreshGeometry',
        'getTaskbarInfo',
      ]) {
        expect(source, contains('"$method"'), reason: method);
      }
      expect(source, contains('taskbarStateChanged'));
    });
  });

  group('channel wiring', () {
    test('floating lyrics channel keeps legacy methods and adds new ones', () {
      final source = _source('windows/runner/floating_lyrics_channel.cpp');

      expect(source, contains('com.mconnect.mconnect/floating_lyrics'));
      for (final method in [
        'canDrawOverlays',
        'openOverlaySettings',
        'show',
        'update',
        'hide',
        'configure',
        'preview',
        'resetPosition',
        'getMonitors',
        'setInteractive',
      ]) {
        expect(source, contains('"$method"'), reason: method);
      }
      for (final key in ['textColor', 'highlightColor', 'backgroundColor']) {
        expect(source, contains('"$key"'), reason: key);
      }
      // The frame and style keys are parsed in the shared reader; a dropped key
      // there silently blanks the overlay, so it is asserted as a set.
      final readers = _source('windows/runner/lyrics/lyrics_channel_args.h');
      for (final key in [
        'text',
        'translation',
        'nextText',
        'highlightProgress',
        'highlightRate',
        'wordSegments',
        'isLocked',
        'lineAnimation',
        'windowAnimation',
      ]) {
        expect(readers, contains('"$key"'), reason: key);
      }
      // Guarded by test/floating_lyrics_service_test.dart as well: colours are
      // unsigned, never rejected for having the high bit set.
      expect(source, contains('std::uint32_t'));
      expect(source, contains('static_cast<std::uint32_t>'));
      expect(source, isNot(contains('if (argb < 0)')));
    });

    test('both channels are registered from one place', () {
      final header = _source('windows/runner/floating_lyrics_channel.h');

      expect(header, contains('taskbar_lyrics_channel.h'));
      expect(header, contains('TaskbarLyricsChannel'));
    });
  });

  group('build wiring', () {
    test('CMake compiles the new sources and links the required libraries', () {
      final source = _source('windows/runner/CMakeLists.txt');

      for (final file in [
        'lyrics/lyrics_animation.cpp',
        'lyrics/lyrics_renderer.cpp',
        'lyrics/lyrics_window_base.cpp',
        'lyrics/floating_lyrics_window.cpp',
        'lyrics/taskbar_geometry.cpp',
        'lyrics/taskbar_lyrics_window.cpp',
        'taskbar_lyrics_channel.cpp',
      ]) {
        expect(source, contains(file), reason: file);
      }
      for (final lib in [
        'd2d1',
        'dwrite',
        'dwmapi',
        'shell32',
        'shlwapi',
        'ole32',
        'oleaut32',
        'uuid',
        'windowsapp',
        'gdi32',
        'user32',
        'gdiplus',
      ]) {
        expect(source, contains('$lib.lib'), reason: lib);
      }
      // The parity team adds these; the runner must keep a marked slot for them.
      expect(source, contains('MConnect parity channels'));
    });
  });

  group('taskbar placement stays inside the taskbar', () {
    test('never centres the strip on the monitor', () {
      final source = _source('windows/runner/lyrics/taskbar_geometry.cpp');
      final header = _source('windows/runner/lyrics/taskbar_geometry.h');

      // The old fallback laid the strip out across the whole monitor, so an
      // empty free band parked it in the middle of the screen. Nothing may
      // measure the monitor to place the strip again.
      expect(source, isNot(contains('monitor_width - fallback_width')));
      expect(source, isNot(contains('monitor_height - fallback_height')));
      expect(source, isNot(contains('above_taskbar')));

      // Placement says whether the strip has a home at all instead of
      // inventing one somewhere else.
      expect(header, contains('bool visible = false;'));
      expect(source, contains('placement.visible = false'));
      expect(source, contains('placement.visible = true'));
    });

    test('falls back to the whole taskbar band instead of collapsing it', () {
      final source = _source('windows/runner/lyrics/taskbar_geometry.cpp');
      final header = _source('windows/runner/lyrics/taskbar_geometry.h');

      // Win11's task list often spans the whole bar, which trimmed the band to
      // zero width and triggered the screen-centred fallback.
      expect(header, contains('trimmed_insufficient'));
      expect(source, contains('geometry.trimmed_insufficient = true;'));
      expect(source, contains('geometry.free_rect = input.taskbar;'));
      // ...while the degradation is still reported to Dart.
      expect(source, contains('geometry.space_insufficient = true;'));
    });

    test('handles vertical taskbars along the bar, not the monitor', () {
      final source = _source('windows/runner/lyrics/taskbar_geometry.cpp');
      final placement = _section(
        source,
        'TaskbarLyricsPlacement PlaceTaskbarLyrics',
        'bool ProbeTaskbar',
      );

      expect(placement, contains('TaskbarEdge::kLeft'));
      expect(placement, contains('TaskbarEdge::kRight'));
      // A left/right strip is as wide as the bar is thick, minus the padding.
      expect(placement, contains('thickness - edge_padding * 2'));
      expect(placement, contains('space_insufficient'));
    });

    test('window hides instead of keeping the create-time rectangle', () {
      final source = _source('windows/runner/lyrics/taskbar_lyrics_window.cpp');
      final placement = _section(
        source,
        'void TaskbarLyricsWindow::ApplyPlacement',
        'void TaskbarLyricsWindow::UpdateVisibilityForState',
      );

      expect(placement, contains('!placement.visible'));
      expect(placement, contains('last_placement_ = RECT{}'));
      expect(placement, contains('LyricsWindowBase::Hide();'));
      // The window must not be shown again on the next frame while there is
      // still no rectangle to show it at.
      expect(source, contains('placement_valid_'));
    });

    test('plays the entrance once and the exit at all', () {
      final source = _source('windows/runner/lyrics/taskbar_lyrics_window.cpp');

      expect(source, contains('window_animator_.Start(false'));
      expect(source, contains('closing_'));
      final entrance = source.indexOf('window_animator_.Start(true, now)');
      expect(entrance, greaterThan(-1));
      final guard = source.lastIndexOf('if (!visible())', entrance);
      expect(
        guard,
        greaterThan(-1),
        reason: 'the entrance must not restart on every frame',
      );
      expect(entrance - guard, lessThan(200));
    });

    test('reads the taskbar opacity and reduce-motion keys Dart sends', () {
      final args = _source('windows/runner/lyrics/lyrics_channel_args.h');
      final types = _source('windows/runner/lyrics/lyrics_types.h');
      final window = _source('windows/runner/lyrics/taskbar_lyrics_window.cpp');

      final taskbar = _section(
        args,
        'inline TaskbarLyricsStyle ReadTaskbarStyle',
        '}  // namespace lyrics',
      );
      // Dart sends backgroundOpacity (lib/core/lyrics/lyrics_overlay_config
      // .dart); the old "opacity" key is only the compatibility fallback.
      expect(taskbar, contains('"backgroundOpacity"'));
      expect(taskbar, contains('"opacity"'));
      expect(taskbar, contains('"reduceMotion"'));

      final style = _section(
        types,
        'struct TaskbarLyricsStyle',
        'struct MonitorInfo',
      );
      expect(style, contains('bool reduce_motion = false;'));
      expect(window, contains('result.reduce_motion = style.reduce_motion;'));
      expect(window, isNot(contains('result.reduce_motion = false;')));
    });
  });

  group('drag and resize feedback', () {
    test('suspends programmatic layout while the user moves the window', () {
      final header = _source('windows/runner/lyrics/lyrics_window_base.h');
      final base = _source('windows/runner/lyrics/lyrics_window_base.cpp');
      final floating = _source(
        'windows/runner/lyrics/floating_lyrics_window.cpp',
      );
      final taskbar = _source('windows/runner/lyrics/taskbar_lyrics_window.cpp');

      expect(header, contains('bool resizing_ = false;'));
      expect(base, contains('WM_ENTERSIZEMOVE'));
      expect(base, contains('resizing_ = true;'));
      expect(base, contains('resizing_ = false;'));

      final layout = _section(
        floating,
        'void FloatingLyricsWindow::ApplyLayout',
        'const lyrics::MonitorInfo monitor = ResolveMonitor();',
      );
      expect(layout, contains('if (dragging_ || resizing_) return;'));

      final placement = _section(
        taskbar,
        'void TaskbarLyricsWindow::ApplyPlacement',
        'const double scale = dpi_scale();',
      );
      expect(placement, contains('if (dragging_ || resizing_) return;'));
    });

    test('reports the size the user dragged to', () {
      final floating = _source(
        'windows/runner/lyrics/floating_lyrics_window.cpp',
      );
      final settled = _section(
        floating,
        'void FloatingLyricsWindow::OnSizeSettled',
        'void FloatingLyricsWindow::OnDpiChanged',
      );
      expect(settled, contains('Emit("windowResized"'));
      expect(settled, contains('"width"'));
      expect(settled, contains('"height"'));
    });

    test('a full-width bottom bar is a bottom bar, not a left bar', () {
      final source = _source('windows/runner/lyrics/taskbar_geometry.cpp');
      final edge = _section(
        source,
        'TaskbarEdge EdgeFromRect',
        'int ClampValue',
      );

      // The old order asked "touches the left edge?" before it ever considered
      // the bottom, so every default Windows bar (rect starts at x=0) was read
      // as a LEFT bar: the width slider did nothing and the anchor moved
      // nothing. Decide by span instead.
      expect(edge, isNot(contains('taskbar.left <= monitor.left')));
      expect(edge, contains('monitor_width'));
      expect(edge, contains('bar_width * 10 >= monitor_width * 9'));
      expect(edge, contains('bar_height * 10 >= monitor_height * 9'));
      expect(edge, contains('top_gap'));
      expect(edge, contains('bottom_gap'));

      // And the self-test pins the exact rectangle from the bug report.
      expect(
        source,
        contains('a full-width bar at the bottom is a bottom bar'),
      );
      expect(source, contains('a full-height bar on the right is a right bar'));
      expect(
        source,
        contains('an inset bottom bar must still be a bottom bar'),
      );
    });

    test('the geometry self-test runs in Release and reports failures', () {
      final source = _source('windows/runner/lyrics/taskbar_lyrics_window.cpp');

      // A wrong edge is invisible in Release except as "the sliders do
      // nothing", which is exactly how long this bug survived.
      expect(source, contains('RunTaskbarGeometrySelfTest'));
      expect(source, contains('geometrySelfTestFailed'));
      expect(source, isNot(contains('#ifndef NDEBUG\n  // The geometry math is pure')));
    });

    test('the strip can be dragged and keeps its new offset', () {
      final source = _source('windows/runner/lyrics/taskbar_lyrics_window.cpp');
      final header = _source('windows/runner/lyrics/taskbar_lyrics_window.h');

      // Dragging used to be disabled outright, which is why the strip felt
      // glued to the taskbar no matter what the offset slider said.
      expect(source, contains('draggable_ = true;'));
      expect(header, contains('void OnDragFinished() override;'));
      final drag = _section(
        source,
        'void TaskbarLyricsWindow::OnDragFinished',
        'void TaskbarLyricsWindow::ApplyPlacement',
      );
      expect(drag, contains('Emit("dragOffset"'));
      expect(drag, contains('"offsetX"'));
      // The local style must move before the Dart round trip, or the next
      // frame re-places the strip at the old offset and it snaps back.
      expect(drag, contains('style_.offset_x = offset;'));
    });

    test('the strip is owned by the taskbar so it cannot be painted over', () {
      final source = _source('windows/runner/lyrics/taskbar_lyrics_window.cpp');

      expect(source, contains('void TaskbarLyricsWindow::AdoptTaskbarOwner()'));
      expect(source, contains('GWLP_HWNDPARENT'));
      expect(source, contains('FindWindowW(L"Shell_TrayWnd"'));
      // Both windows are topmost; Explorer re-raises its own, so topmost is
      // re-asserted on every placement as a second line of defence.
      final placement = _section(
        source,
        'void TaskbarLyricsWindow::ApplyPlacement',
        'void TaskbarLyricsWindow::UpdateVisibilityForState',
      );
      expect(placement, contains('SetWindowPos(hwnd(), HWND_TOPMOST'));
      expect(placement, contains('EmitPlacement(rect, true);'));
    });

    test('the strip reports its live rectangle and honours debug geometry', () {
      final source = _source('windows/runner/lyrics/taskbar_lyrics_window.cpp');

      final emit = _section(
        source,
        'void TaskbarLyricsWindow::EmitPlacement',
        'void TaskbarLyricsWindow::OnDragFinished',
      );
      expect(emit, contains('Emit("taskbarPlacement"'));
      expect(emit, contains('"left"'));
      expect(emit, contains('"width"'));
      expect(emit, contains('"visible"'));

      final scene = _section(
        source,
        'bool TaskbarLyricsWindow::BuildScene',
        'void TaskbarLyricsWindow::OnFrameTick',
      );
      expect(scene, contains('style_.debug_geometry'));
      expect(scene, contains('BackgroundMode::kSolid'));
    });
  });
}