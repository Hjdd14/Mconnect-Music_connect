import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/core/theme/app_background.dart';
import 'package:mconnect/core/theme/app_background_provider.dart';

/// The background layers must not `stat` the picture on every rebuild.
///
/// `File(path).existsSync()` used to run inside `build` of every glass surface:
/// `SecondaryGlassSurface` wraps every secondary route, so one navigation
/// evaluated it twice (outgoing + incoming page) and the player route evaluated
/// it on every frame of its transition. On Android those stats hit FUSE-mounted
/// external storage and block the UI thread.
class _TestBackgroundNotifier extends AppBackgroundSettingsNotifier {
  _TestBackgroundNotifier(AppBackgroundSettings settings) {
    state = settings;
  }
}

void main() {
  const imagePath = 'C:/mconnect-test/background-that-does-not-exist.jpg';
  const settings = AppBackgroundSettings(imagePath: imagePath);

  Future<int> pumpAndRebuild(WidgetTester tester, {required int rebuilds}) async {
    var probeCalls = 0;
    bool probe(String path) {
      probeCalls++;
      return false;
    }

    Widget tree(int generation) => ProviderScope(
      overrides: [
        appBackgroundSettingsProvider.overrideWith(
          (ref) => _TestBackgroundNotifier(settings),
        ),
        fileExistsProbeProvider.overrideWithValue(probe),
      ],
      child: MaterialApp(
        home: SecondaryGlassSurface(child: Text('page $generation')),
      ),
    );

    await tester.pumpWidget(tree(0));
    for (var i = 1; i <= rebuilds; i++) {
      await tester.pumpWidget(tree(i));
    }
    return probeCalls;
  }

  testWidgets('背景路径不变时，反复 rebuild 只 stat 一次', (tester) async {
    final calls = await pumpAndRebuild(tester, rebuilds: 10);

    expect(calls, 1, reason: '设置没变就不该重新 stat：11 次 build 只能有 1 次探测');
  });

  test('ProviderScope 不同（新的一次构建）时才重新探测', () async {
    var calls = 0;
    bool probe(String path) {
      calls++;
      return false;
    }

    final container = ProviderContainer(
      overrides: [
        appBackgroundSettingsProvider.overrideWith(
          (ref) => _TestBackgroundNotifier(settings),
        ),
        fileExistsProbeProvider.overrideWithValue(probe),
      ],
    );
    addTearDown(container.dispose);

    expect(container.read(backgroundImageExistsProvider(imagePath)), isFalse);
    expect(container.read(backgroundImageExistsProvider(imagePath)), isFalse);
    expect(calls, 1);

    // A different picture is a different cache key, so it is probed on its own.
    expect(
      container.read(backgroundImageExistsProvider('C:/other.jpg')),
      isFalse,
    );
    expect(calls, 2);
  });
}
