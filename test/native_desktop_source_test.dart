import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Source-level guards for the Windows runner's desktop integration.
///
/// Closing the window, remembering its geometry and the tray fallback all live
/// in C++ that flutter test cannot execute, so the contract is asserted against
/// the sources: the message has to be answered before Flutter's lifecycle
/// manager can route it, hiding is only allowed when a tray icon really exists,
/// and a disabled "remember window state" must not write to disk on the way out.
String _source(String path) {
  final file = File(path);
  expect(file.existsSync(), isTrue, reason: '$path is missing');
  return file.readAsStringSync();
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
  group('close to tray', () {
    test('answers WM_CLOSE before the Flutter lifecycle round trip', () {
      final source = _source('windows/runner/flutter_window.cpp');
      final handler = _section(
        source,
        'LRESULT FlutterWindow::MessageHandler',
        'Win32Window::MessageHandler(hwnd, message, wparam, lparam)',
      );

      expect(handler, contains('WM_CLOSE'));
      final close = handler.indexOf('desktop_integration_channel_->HandleCloseRequest()');
      final lifecycle = handler.indexOf('HandleTopLevelWindowProc');
      expect(close, greaterThan(-1), reason: 'WM_CLOSE must be answered here');
      expect(lifecycle, greaterThan(-1));
      // Flutter 3.47 answers the first WM_CLOSE with a System.requestAppExit
      // round trip that never reaches the tray, so the integration channel has
      // to see the message first.
      expect(
        close,
        lessThan(lifecycle),
        reason: 'WM_CLOSE must be handled before HandleTopLevelWindowProc',
      );
    });

    test('only hides when the tray icon really exists', () {
      final source = _source(
        'windows/runner/desktop/desktop_integration_channel.cpp',
      );
      final request = _section(
        source,
        'bool DesktopIntegrationChannel::HandleCloseRequest',
        'bool DesktopIntegrationChannel::ApplyHotkeys',
      );

      expect(request, contains('tray_icon_added_'));
      expect(request, contains('minimize_to_tray_'));
      expect(request, contains('force_quit_'));
      // The protocol keeps its existing event and adds one for each outcome.
      expect(request, contains('"windowCloseRequested"'));
      expect(request, contains('"closeFellBackToExit"'));
      expect(request, contains('"hiddenToTray"'));
      expect(request, contains('SW_HIDE'));
    });

    test('the tray icon load never answers nullptr', () {
      final source = _source(
        'windows/runner/desktop/desktop_integration_channel.cpp',
      );
      final loader = _section(
        source,
        'HICON LoadTrayIcon()',
        'DesktopIntegrationChannel::DesktopIntegrationChannel(',
      );

      // 小托盘图标 → 默认尺寸 → 模块图标 → 系统图标，任一级成功即用。
      expect(loader, contains('LoadImageW'));
      expect(loader, contains('SM_CXSMICON'));
      expect(loader, contains('IDI_APP_ICON'));
      expect(loader, contains('IDI_APPLICATION'));
      expect(loader, contains('LoadIconW(nullptr'));
      expect(
        loader,
        isNot(contains('return nullptr')),
        reason: 'a null icon is exactly what leaves the app with no tray at all',
      );
    });

    test('AddTrayIcon follows the documented version-4 sequence', () {
      final source = _source(
        'windows/runner/desktop/desktop_integration_channel.cpp',
      );
      final add = _section(
        source,
        'bool DesktopIntegrationChannel::AddTrayIcon',
        'void DesktopIntegrationChannel::RemoveTrayIcon',
      );

      // NIF_SHOWTIP is only legal for the version-4 callback, so the add itself
      // must use the plain flag set; the version and the tooltip flag come after.
      final firstAdd = add.indexOf('Shell_NotifyIconW(NIM_ADD');
      final setVersion = add.indexOf('Shell_NotifyIconW(NIM_SETVERSION');
      expect(firstAdd, greaterThan(-1));
      expect(setVersion, greaterThan(firstAdd));
      expect(add, contains('icon.uFlags = base_flags;'));
      expect(add, contains('NIF_SHOWTIP'));
      // A refused host window is rebuilt once instead of being retried forever.
      expect(add, contains('DestroyWindow(tray_host_)'));
      expect(add, contains('ERROR_ACCESS_DENIED'));
      // Second strategy: register by GUID, which does not depend on the window
      // slot the shell just refused.
      expect(add, contains('NIF_GUID'));
      expect(add, contains('tray_guid_mode_ = true;'));
      expect(add, contains('tray_error_'));
      expect(add, contains('"trayFailed"'));
      expect(add, contains('"stage"'));
      expect(add, contains('"error"'));
    });

    test('getRuntimeStatus answers what a pushed event never said', () {
      final source = _source(
        'windows/runner/desktop/desktop_integration_channel.cpp',
      );
      final header = _source(
        'windows/runner/desktop/desktop_integration_channel.h',
      );
      final status = _section(
        source,
        'if (method == "getRuntimeStatus")',
        'if (method == "freeSpaceBytes")',
      );

      expect(status, contains('"trayAdded"'));
      expect(status, contains('"trayError"'));
      expect(status, contains('"smtcAvailable"'));
      expect(status, contains('"hotkeysEnabled"'));
      // The registered list is the truth; ApplyHotkeys(false) answers true
      // without registering anything.
      expect(status, contains('hotkeys_.empty()'));

      expect(header, contains('int tray_error_ = 0;'));
    });

    test('does not persist geometry when remembering is off', () {
      final source = _source(
        'windows/runner/desktop/desktop_integration_channel.cpp',
      );
      final header = _source(
        'windows/runner/desktop/desktop_integration_channel.h',
      );

      expect(header, contains('bool remember_window_state_ = true;'));

      final save = _section(
        source,
        'bool DesktopIntegrationChannel::SaveWindowStateNow',
        'void DesktopIntegrationChannel::HandleForwardedPayload',
      );
      expect(save, contains('remember_window_state_'));

      // The idle save timer after a drag/resize is the other place that writes.
      final idle = _section(source, 'case WM_EXITSIZEMOVE:', 'case WM_COPYDATA:');
      expect(idle, contains('remember_window_state_'));
      expect(idle, contains('SetTimer'));
    });

    test('a missing tray icon still hides the window, and stays recoverable', () {
      final source = _source(
        'windows/runner/desktop/desktop_integration_channel.cpp',
      );
      final request = _section(
        source,
        'bool DesktopIntegrationChannel::HandleCloseRequest',
        'bool DesktopIntegrationChannel::ApplyHotkeys',
      );

      // 1.6.2 answered "no tray icon" with SW_MINIMIZE, which the user read as
      // "it was not minimized to the tray". The X button must not leave the app
      // in the taskbar, so hide it — the window is still recoverable because a
      // second launch forwards its command line and calls ShowMainWindow().
      expect(request, contains('"hiddenWithoutTray"'));
      expect(request, contains('ShowWindow(window_, SW_HIDE)'));
      expect(request, isNot(contains('SW_MINIMIZE')));
      expect(request, contains('tray_unavailable_ = true;'));

      final kept = request.indexOf('"hiddenWithoutTray"');
      expect(kept, greaterThan(-1));
      final fallback = request.substring(kept);
      expect(fallback, contains('return true'));
      expect(
        fallback,
        isNot(contains('return false')),
        reason: 'the hidden fallback must not let the app exit',
      );
      // Recoverability is the whole reason hiding is safe here.
      final single = _source('windows/runner/desktop/desktop_integration_channel.cpp');
      final forwarded = _section(
        single,
        'void DesktopIntegrationChannel::HandleForwardedPayload',
        'bool DesktopIntegrationChannel::HandleWindowMessage',
      );
      expect(forwarded, contains('ShowMainWindow()'));
      // The reason travels with the event so the status card can print it.
      expect(request, contains('tray_error_'));
    });

    test('the tray icon is owned by a dedicated host window', () {
      final source = _source(
        'windows/runner/desktop/desktop_integration_channel.cpp',
      );
      final header = _source(
        'windows/runner/desktop/desktop_integration_channel.h',
      );
      final host = _section(
        source,
        'bool DesktopIntegrationChannel::EnsureTrayHost',
        'bool DesktopIntegrationChannel::AddTrayIcon',
      );

      // The Flutter window was refused by the shell (NIM_ADD failed for three
      // flag sets while an ordinary window succeeded), so the icon gets its own.
      expect(source, contains('MCONNECT_TRAY_HOST'));
      expect(host, contains('CreateWindowExW'));
      expect(header, contains('HWND tray_host_ = nullptr;'));

      final add = _section(
        source,
        'bool DesktopIntegrationChannel::AddTrayIcon',
        'void DesktopIntegrationChannel::RemoveTrayIcon',
      );
      expect(add, contains('EnsureTrayHost()'));
      expect(add, contains('icon.hWnd = host;'));
      // Per-process icon id + a delete before the add: a run killed with the
      // task manager leaves the shell answering ERROR_ALREADY_EXISTS (183) for
      // the old slot, which is what the status card reported.
      expect(add, contains('tray_icon_id_ = GetCurrentProcessId();'));
      expect(add, contains('Shell_NotifyIconW(NIM_DELETE, &icon);'));
      expect(add, contains('ERROR_ALREADY_EXISTS'));
      expect(add, contains('Shell_NotifyIconW(NIM_MODIFY, &icon)'));
      // Where the shell put the icon is reported; an icon in the overflow can
      // refuse to answer, so this never gates the "added" decision.
      expect(add, contains('Shell_NotifyIconGetRect'));
      expect(add, contains('"trayIconPlaced"'));
      expect(add, contains('tray_retry_delay_ms_ = 1000;'));
    });

    test('a refused tray retries with backoff instead of giving up', () {
      final source = _source(
        'windows/runner/desktop/desktop_integration_channel.cpp',
      );

      expect(source, contains('kTrayRetryMaxDelayMs = 30000'));
      final timer = _section(
        source,
        'if (wparam == kTrayRetryTimerId)',
        '*result = 0;',
      );
      expect(timer, contains('tray_retry_delay_ms_ * 2'));
      expect(timer, contains('std::min'));
      expect(
        timer,
        isNot(contains('kTrayRetryLimit')),
        reason: 'giving up after ten tries is what left no tray icon at all',
      );

      // Elevation is a real reason the shell refuses an icon; report it.
      expect(source, contains('IsUserAnAdmin'));
      expect(source, contains('"elevated"'));
    });
    test('reads rememberWindowState and re-arms the tray hint', () {
      final source = _source(
        'windows/runner/desktop/desktop_integration_channel.cpp',
      );
      final behavior = _section(
        source,
        'if (method == "setCloseBehavior")',
        'if (method == "setHotkeys")',
      );

      expect(behavior, contains('"rememberWindowState"'));
      expect(behavior, contains('"minimizeToTray"'));
      expect(behavior, contains('"firstRunHint"'));
      // Turning close-to-tray back on should explain the tray icon again.
      expect(behavior, contains('hint_armed_'));
    });
  });
}