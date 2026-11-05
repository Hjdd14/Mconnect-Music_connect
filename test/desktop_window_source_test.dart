import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Regression guards for the Windows window-sizing order.
///
/// The first frame of the desktop build used to appear, then a 700 ms timer
/// resized the HWND and the FlutterView. On 175% DPI that left the window black
/// while the Dart isolate kept running. These source-level assertions pin the
/// fix: sizing happens inside Win32Window::Create before OnCreate creates the
/// FlutterViewController, and the post-first-frame timer stays gone.
void main() {
  test('sizes the window before FlutterViewController is created', () {
    final source = File('windows/runner/win32_window.cpp').readAsStringSync();

    final resize = source.indexOf('SetWindowPos(window, nullptr');
    final onCreate = source.indexOf('return OnCreate();');
    expect(resize, greaterThan(0));
    expect(onCreate, greaterThan(0));
    expect(
      resize,
      lessThan(onCreate),
      reason: 'SetWindowPos must run before OnCreate creates the view',
    );
    expect(source, contains('GetDpiForWindow(window)'));
    expect(source, contains('GetMonitorInfo'));
    expect(source, contains('SetMinimumSize'));
  });

  test('desktop routes slide over an opaque backing, never cross-fade', () {
    final source = File('lib/core/router/app_router.dart').readAsStringSync();

    expect(source, contains('_DesktopRouteBacking'));
    expect(source, contains("Key('desktop-route-opaque-backing')"));
    expect(
      source,
      contains('surfaceContainerLow.withValues(alpha: 1.0)'),
      reason: 'the route floor must be fully opaque',
    );
    expect(source, contains('SizedBox.expand'));
    expect(
      source,
      contains('ClipRRect'),
      reason: 'the rectangular Scaffold floor must be clipped to the plate',
    );
    expect(source, contains('return SlideTransition'));
    expect(
      source,
      isNot(contains('return FadeTransition')),
      reason: 'a cross-fade lets the outgoing page show through',
    );
  });

  test('does not resize the engine surface after the first frame', () {
    final source = File('windows/runner/flutter_window.cpp').readAsStringSync();

    expect(source, contains('SetNextFrameCallback'));
    expect(source, isNot(contains('ResizeToWorkArea')));
    expect(source, isNot(contains('SetTimer(GetHandle(), 1')));
    expect(source, isNot(contains('WM_TIMER')));
  });
}
