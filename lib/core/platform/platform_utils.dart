import 'dart:io';

import 'package:flutter/foundation.dart';

enum AppPlatform { android, ios, windows, macos, linux, other }

class PlatformUtils {
  static AppPlatform? _debugOverride;

  static AppPlatform get current => _debugOverride ?? _detect();

  static bool get isAndroid => current == AppPlatform.android;
  static bool get isIos => current == AppPlatform.ios;
  static bool get isWindows => current == AppPlatform.windows;
  static bool get isMacos => current == AppPlatform.macos;
  static bool get isLinux => current == AppPlatform.linux;

  static bool get isDesktop => isWindows || isMacos || isLinux;

  static bool get isMobile => isAndroid || isIos;

  @visibleForTesting
  static void setDebugOverride(AppPlatform? platform) {
    _debugOverride = platform;
  }

  static AppPlatform _detect() {
    if (Platform.isAndroid) return AppPlatform.android;
    if (Platform.isIOS) return AppPlatform.ios;
    if (Platform.isWindows) return AppPlatform.windows;
    if (Platform.isMacOS) return AppPlatform.macos;
    if (Platform.isLinux) return AppPlatform.linux;
    return AppPlatform.other;
  }
}
