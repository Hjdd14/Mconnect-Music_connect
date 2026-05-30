import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mconnect/features/audio_effects/presentation/providers/audio_effects_provider.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('mconnect_audio_test_');
    Hive.init(tempDir.path);
  });

  tearDown(() async {
    await Hive.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test(
    'audio enhancement settings default to safe disabled behavior',
    () async {
      final notifier = AudioEffectsSettingsNotifier();
      await notifier.ready;

      expect(notifier.state.fadeEnabled, isFalse);
      expect(notifier.state.fadeDuration, const Duration(milliseconds: 800));
      expect(notifier.state.sleepTimerDuration, const Duration(minutes: 30));
    },
  );

  test(
    'audio enhancement settings persist fade and sleep timer choices',
    () async {
      final notifier = AudioEffectsSettingsNotifier();
      await notifier.ready;

      await notifier.setFadeEnabled(true);
      await notifier.setFadeDuration(const Duration(milliseconds: 1200));
      await notifier.setSleepTimerDuration(const Duration(minutes: 45));

      final restored = AudioEffectsSettingsNotifier();
      await restored.ready;

      expect(restored.state.fadeEnabled, isTrue);
      expect(restored.state.fadeDuration, const Duration(milliseconds: 1200));
      expect(restored.state.sleepTimerDuration, const Duration(minutes: 45));
    },
  );
}
