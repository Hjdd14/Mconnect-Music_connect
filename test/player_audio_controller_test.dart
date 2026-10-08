import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/features/player/data/player_audio_controller.dart';

void main() {
  // W2-B (a)：Windows 的均衡器走 libmpv 的 `af` 滤镜，只有 `NativePlayer` 支持；
  // 其它实现下以前是**静默 no-op**（用户以为均衡器坏了却毫无线索）。本波只加诊断、
  // 不修后端，所以这里用**源码级断言**锁定"那条分支确实记了诊断、且空 filter 不刷"：
  // 行为级用例需要构造一个"非 NativePlayer"的 media_kit Player，那会在单测里初始化
  // libmpv；真实渲染效果列入【需真机】。
  group('Windows equalizer quiet-failure diagnostic', () {
    test('records windows_equalizer_unsupported in the non-NativePlayer branch', () {
      final source = File(
        'lib/features/player/data/media_kit_windows_audio_controller.dart',
      ).readAsStringSync();

      expect(
        source,
        contains('windows_equalizer_unsupported'),
        reason: '静默失效必须留下诊断，否则真机上无法复盘',
      );
      expect(
        source,
        contains('filter.trim().isEmpty'),
        reason: '关闭 EQ 的空 filter 不该刷诊断',
      );

      // 锚点必须**唯一**：该文件 :29 是接口声明 `setAudioFilter(String filter);`，
      // :370 才是实现（结尾是 `async {`）。用不带 async 的锚会切出接口那一小段，
      // 于是下面 nativeBranch == -1（上一版就是这样红的）。
      // 所以：① 锚在实现独有的 async 形态上；② 切片后立刻断言"这确实是实现体"。
      final methodStart = source.indexOf('setAudioFilter(String filter) async');
      expect(
        methodStart,
        greaterThan(-1),
        reason: '找不到 setAudioFilter 的实现（锚点必须带 async，接口声明以 ; 结尾）',
      );
      final methodEnd = source.indexOf('Future<void>', methodStart + 1);
      expect(
        methodEnd,
        greaterThan(methodStart),
        reason: '取不到方法结束位置（片段里出现了别的 Future<void>？）',
      );
      final method = source.substring(methodStart, methodEnd);
      expect(
        method,
        contains('setProperty'),
        reason: '切出来的不是实现体（锚点命中了接口声明？）',
      );

      final nativeBranch = method.indexOf("setProperty('af', filter)");
      final diagnostic = method.indexOf('windows_equalizer_unsupported');
      expect(nativeBranch, greaterThan(-1), reason: 'NativePlayer 分支不见了');
      expect(diagnostic, greaterThan(-1), reason: '静默失效的诊断不见了');
      expect(
        diagnostic,
        greaterThan(nativeBranch),
        reason: '诊断必须在 setProperty 之后（即只服务非 NativePlayer 分支）',
      );
    });
  });

  group('Android equalizer safety gain conversion', () {
    test('converts bass preset to safe EQ with loudness compensation', () {
      final plan = JustAudioController.androidEqualizerPlanForTest(
        enabled: true,
        bandGains: const [6, 4, 1, 0, 0],
        bandCount: 5,
        minDecibels: -12,
        maxDecibels: 12,
      );

      expect(plan.equalizerEnabled, isTrue);
      expect(plan.bandGains, orderedEquals([0, -2, -5, -6, -6]));
      expect(plan.bandGains.every((gain) => gain <= 0), isTrue);
      expect(plan.loudnessEnabled, isTrue);
      expect(plan.loudnessGain, 6);
    });

    test('adds preset loudness compensation without positive EQ band gain', () {
      final vocalPlan = JustAudioController.androidEqualizerPlanForTest(
        enabled: true,
        bandGains: const [-2, 0, 5, 3, 1],
        bandCount: 5,
        minDecibels: -12,
        maxDecibels: 12,
      );
      final rockPlan = JustAudioController.androidEqualizerPlanForTest(
        enabled: true,
        bandGains: const [4, 2, 0, 3, 5],
        bandCount: 5,
        minDecibels: -12,
        maxDecibels: 12,
      );

      expect(vocalPlan.equalizerEnabled, isTrue);
      expect(vocalPlan.bandGains, orderedEquals([-7, -5, 0, -2, -4]));
      expect(vocalPlan.bandGains.every((gain) => gain <= 0), isTrue);
      expect(vocalPlan.loudnessEnabled, isTrue);
      expect(vocalPlan.loudnessGain, 5);

      expect(rockPlan.equalizerEnabled, isTrue);
      expect(rockPlan.bandGains, orderedEquals([-1, -3, -5, -2, 0]));
      expect(rockPlan.bandGains.every((gain) => gain <= 0), isTrue);
      expect(rockPlan.loudnessEnabled, isTrue);
      expect(rockPlan.loudnessGain, 5);
    });

    test('compensates a subtle one band boost without positive EQ gain', () {
      final plan = JustAudioController.androidEqualizerPlanForTest(
        enabled: true,
        bandGains: const [1, 0, 0, 0, 0],
        bandCount: 5,
        minDecibels: -12,
        maxDecibels: 12,
      );

      expect(plan.equalizerEnabled, isTrue);
      expect(plan.bandGains, orderedEquals([0, -1, -1, -1, -1]));
      expect(plan.bandGains.every((gain) => gain <= 0), isTrue);
      expect(plan.loudnessEnabled, isTrue);
      expect(plan.loudnessGain, 1);
    });

    test('caps loudness compensation for extreme custom boosts', () {
      final plan = JustAudioController.androidEqualizerPlanForTest(
        enabled: true,
        bandGains: const [12, 0, 0, 0, 0],
        bandCount: 5,
        minDecibels: -12,
        maxDecibels: 12,
      );

      expect(plan.equalizerEnabled, isTrue);
      expect(plan.bandGains, orderedEquals([0, -12, -12, -12, -12]));
      expect(plan.bandGains.every((gain) => gain <= 0), isTrue);
      expect(plan.loudnessEnabled, isTrue);
      expect(plan.loudnessGain, 6);
    });

    test('does not use loudness for negative-only or flat curves', () {
      final negativePlan = JustAudioController.androidEqualizerPlanForTest(
        enabled: true,
        bandGains: const [0, -3, -1],
        bandCount: 5,
        minDecibels: -12,
        maxDecibels: 12,
      );
      final flatPlan = JustAudioController.androidEqualizerPlanForTest(
        enabled: true,
        bandGains: const [0, 0, 0, 0, 0],
        bandCount: 5,
        minDecibels: -12,
        maxDecibels: 12,
      );

      expect(negativePlan.equalizerEnabled, isTrue);
      expect(negativePlan.bandGains, orderedEquals([0, -3, -1, 0, 0]));
      expect(negativePlan.loudnessEnabled, isFalse);
      expect(negativePlan.loudnessGain, 0);
      expect(flatPlan.equalizerEnabled, isFalse);
      expect(flatPlan.bandGains, orderedEquals([0, 0, 0, 0, 0]));
      expect(flatPlan.loudnessEnabled, isFalse);
      expect(flatPlan.loudnessGain, 0);
    });

    test('clamps unsupported settings before applying safety headroom', () {
      final plan = JustAudioController.androidEqualizerPlanForTest(
        enabled: true,
        bandGains: const [12, -20, 2],
        bandCount: 3,
        minDecibels: -12,
        maxDecibels: 3,
      );

      expect(plan.equalizerEnabled, isTrue);
      expect(plan.bandGains, orderedEquals([0, -12, -1]));
      expect(plan.bandGains.every((gain) => gain >= -12 && gain <= 0), isTrue);
      expect(plan.loudnessEnabled, isTrue);
      expect(plan.loudnessGain, 3);
    });

    test('treats device bands beyond saved settings as 0 dB participants', () {
      final plan = JustAudioController.androidEqualizerPlanForTest(
        enabled: true,
        bandGains: const [6, 4],
        bandCount: 4,
        minDecibels: -12,
        maxDecibels: 12,
      );

      expect(plan.equalizerEnabled, isTrue);
      expect(plan.bandGains, orderedEquals([0, -2, -6, -6]));
      expect(plan.loudnessEnabled, isTrue);
      expect(plan.loudnessGain, 6);
    });

    test(
      'falls back to disabled EQ and loudness when the device cannot attenuate',
      () {
        final plan = JustAudioController.androidEqualizerPlanForTest(
          enabled: true,
          bandGains: const [6, 4, 0],
          bandCount: 3,
          minDecibels: 0,
          maxDecibels: 12,
        );

        expect(plan.equalizerEnabled, isFalse);
        expect(plan.bandGains, orderedEquals([0, 0, 0]));
        expect(plan.loudnessEnabled, isFalse);
        expect(plan.loudnessGain, 0);
      },
    );

    test('keeps the equalizer disabled when settings are disabled', () {
      final plan = JustAudioController.androidEqualizerPlanForTest(
        enabled: false,
        bandGains: const [6, 4, 1],
        bandCount: 3,
        minDecibels: -12,
        maxDecibels: 12,
      );

      expect(plan.equalizerEnabled, isFalse);
      expect(plan.bandGains, orderedEquals([0, 0, 0]));
      expect(plan.loudnessEnabled, isFalse);
      expect(plan.loudnessGain, 0);
    });

    test(
      'disables loudness before applying EQ, then enables compensation last',
      () async {
        final events = <String>[];

        await JustAudioController.applyAndroidEqualizerPlanForTest(
          enabled: true,
          bandGains: const [6, 4, 1, 0, 0],
          bandCount: 5,
          minDecibels: -12,
          maxDecibels: 12,
          setEnabled: (value) async => events.add('enabled:$value'),
          setBandGain: (index, gain) async =>
              events.add('gain:$index:${gain.round()}'),
          setLoudnessEnabled: (value) async =>
              events.add('loudnessEnabled:$value'),
          setLoudnessGain: (gain) async =>
              events.add('loudnessGain:${gain.round()}'),
        );

        expect(events, [
          'loudnessEnabled:false',
          'loudnessGain:0',
          'gain:0:0',
          'gain:1:-2',
          'gain:2:-5',
          'gain:3:-6',
          'gain:4:-6',
          'enabled:true',
          'loudnessGain:6',
          'loudnessEnabled:true',
        ]);
      },
    );

    test(
      'disables Android EQ and loudness without rewriting bands for a flat plan',
      () async {
        final events = <String>[];

        await JustAudioController.applyAndroidEqualizerPlanForTest(
          enabled: true,
          bandGains: const [0, 0, 0],
          bandCount: 3,
          minDecibels: -12,
          maxDecibels: 12,
          setEnabled: (value) async => events.add('enabled:$value'),
          setBandGain: (index, gain) async =>
              events.add('gain:$index:${gain.round()}'),
          setLoudnessEnabled: (value) async =>
              events.add('loudnessEnabled:$value'),
          setLoudnessGain: (gain) async =>
              events.add('loudnessGain:${gain.round()}'),
        );

        expect(events, [
          'loudnessEnabled:false',
          'loudnessGain:0',
          'enabled:false',
        ]);
      },
    );

    test(
      'stops clearing loudness when a newer EQ apply supersedes the plan',
      () async {
        final events = <String>[];
        var current = true;

        await JustAudioController.applyAndroidEqualizerPlanForTest(
          enabled: true,
          bandGains: const [6, 4, 1, 0, 0],
          bandCount: 5,
          minDecibels: -12,
          maxDecibels: 12,
          shouldContinue: () => current,
          setEnabled: (value) async => events.add('enabled:$value'),
          setBandGain: (index, gain) async =>
              events.add('gain:$index:${gain.round()}'),
          setLoudnessEnabled: (value) async {
            events.add('loudnessEnabled:$value');
            current = false;
          },
          setLoudnessGain: (gain) async =>
              events.add('loudnessGain:${gain.round()}'),
        );

        expect(events, ['loudnessEnabled:false']);
      },
    );

    test('keeps safe EQ applied when loudness compensation fails', () async {
      final events = <String>[];

      await JustAudioController.applyAndroidEqualizerPlanForTest(
        enabled: true,
        bandGains: const [6, 4, 1, 0, 0],
        bandCount: 5,
        minDecibels: -12,
        maxDecibels: 12,
        setEnabled: (value) async => events.add('enabled:$value'),
        setBandGain: (index, gain) async =>
            events.add('gain:$index:${gain.round()}'),
        setLoudnessEnabled: (value) async {
          events.add('loudnessEnabled:$value');
          if (value) {
            throw StateError('unsupported loudness');
          }
        },
        setLoudnessGain: (gain) async =>
            events.add('loudnessGain:${gain.round()}'),
      );

      expect(events, [
        'loudnessEnabled:false',
        'loudnessGain:0',
        'gain:0:0',
        'gain:1:-2',
        'gain:2:-5',
        'gain:3:-6',
        'gain:4:-6',
        'enabled:true',
        'loudnessGain:6',
        'loudnessEnabled:true',
      ]);
    });
  });
}
