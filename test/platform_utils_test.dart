import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/core/platform/platform_utils.dart';

void main() {
  tearDown(() {
    PlatformUtils.setDebugOverride(null);
  });

  test('platform override exposes Windows as desktop', () {
    PlatformUtils.setDebugOverride(AppPlatform.windows);

    expect(PlatformUtils.isWindows, isTrue);
    expect(PlatformUtils.isDesktop, isTrue);
    expect(PlatformUtils.isMobile, isFalse);
  });

  test('platform override exposes Android as mobile', () {
    PlatformUtils.setDebugOverride(AppPlatform.android);

    expect(PlatformUtils.isAndroid, isTrue);
    expect(PlatformUtils.isDesktop, isFalse);
    expect(PlatformUtils.isMobile, isTrue);
  });
}
