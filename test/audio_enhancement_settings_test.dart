import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mconnect/features/audio_effects/presentation/providers/audio_effects_provider.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('mconnect_audio_test_');
    Hive.init(tempDir.path);
    await Hive.openBox('settings');
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
      expect(notifier.state.equalizerEnabled, isFalse);
      expect(notifier.state.equalizerPreset, EqualizerPreset.flat);
      expect(notifier.state.equalizerBandGains, List<double>.filled(5, 0));
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

  test('audio enhancement settings persist equalizer choices', () async {
    final notifier = AudioEffectsSettingsNotifier();
    await notifier.ready;

    await notifier.setEqualizerEnabled(true);
    await notifier.setEqualizerPreset(EqualizerPreset.bassBoost);
    await notifier.setEqualizerBandGain(0, 20);
    await notifier.setEqualizerBandGain(4, -20);

    expect(notifier.state.equalizerEnabled, isTrue);
    expect(notifier.state.equalizerPreset, EqualizerPreset.custom);
    expect(notifier.state.equalizerBandGains.first, 12);
    expect(notifier.state.equalizerBandGains.last, -12);

    final restored = AudioEffectsSettingsNotifier();
    await restored.ready;

    expect(restored.state.equalizerEnabled, isTrue);
    expect(restored.state.equalizerPreset, EqualizerPreset.custom);
    expect(restored.state.equalizerBandGains.first, 12);
    expect(restored.state.equalizerBandGains.last, -12);
  });
}
