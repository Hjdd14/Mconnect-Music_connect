import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/features/audio_effects/data/eq_preset_codec.dart';
import 'package:mconnect/features/audio_effects/presentation/providers/audio_effects_provider.dart';
import 'package:mconnect/features/player/data/loudness_normalizer.dart';
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

  // W2-B item b：EQ 预设的 JSON 导入/导出。对外交换格式必须带 schema + version，
  // 且**严格校验**（越界拒绝、不 clamp）——静默夹紧会把别人给的文件变成用户没见过的
  // 曲线，而导入方还以为成功了。
  // W2-B item c：ReplayGain tag → 软件增益。只测**策略与算术**（纯函数）；
  // key→数值 的映射留给调用方那层薄适配（我没能核实 audio_metadata_reader 的键名，
  // 见交付说明的"不确定项"）。
  group('ReplayGain → software gain (W2-B item c)', () {
    test('no usable tag means no normalisation (null, not 0 dB)', () {
      expect(LoudnessNormalizer.gainFor(trackGainDb: null), isNull);
      expect(LoudnessNormalizer.gainFor(trackGainDb: double.nan), isNull);
      expect(LoudnessNormalizer.gainFor(trackGainDb: double.infinity), isNull);
    });

    test('applies the tag value as-is (no sign inversion) inside the range', () {
      expect(LoudnessNormalizer.gainFor(trackGainDb: -6.5), -6.5);
      expect(LoudnessNormalizer.gainFor(trackGainDb: 2.0), 2.0);
    });

    test('clamps boosts and cuts to the policy range', () {
      expect(
        LoudnessNormalizer.gainFor(trackGainDb: 12),
        LoudnessNormalizer.maxBoostDb,
      );
      expect(
        LoudnessNormalizer.gainFor(trackGainDb: -30),
        LoudnessNormalizer.maxCutDb,
      );
    });

    test('peak protection wins over the policy range (never overshoot)', () {
      // peak 1.2 上再 +6dB 会让峰值到 2.4 → 必然削波，所以保护必须赢。
      final gain = LoudnessNormalizer.gainFor(
        trackGainDb: 6,
        trackPeak: 1.2,
      )!;

      expect(gain, lessThan(6));
      expect(
        LoudnessNormalizer.peakAfterGain(1.2, gain),
        lessThanOrEqualTo(1.0),
        reason: '削波保护优先：施加后的峰值不得超过 1.0',
      );
      // 10^(-1/20) / 1.2 → 约 -2.58 dB
      expect(gain, closeTo(-2.58, 0.1));
    });

    test('peak protection does not shrink a safe attenuation', () {
      final gain = LoudnessNormalizer.gainFor(
        trackGainDb: -6,
        trackPeak: 0.5,
      )!;

      expect(gain, -6, reason: '峰值本来就低，削波保护不该把衰减改小');
    });

    test('ignores a non-positive or non-finite peak', () {
      expect(LoudnessNormalizer.gainFor(trackGainDb: 3, trackPeak: 0), 3);
      expect(LoudnessNormalizer.gainFor(trackGainDb: 3, trackPeak: -1), 3);
      expect(
        LoudnessNormalizer.gainFor(trackGainDb: 3, trackPeak: double.nan),
        3,
      );
    });

    test('property: for any peak, the applied gain never clips', () {
      for (var peak = 0.3; peak <= 2.0; peak += 0.1) {
        final gain = LoudnessNormalizer.gainFor(
          trackGainDb: 12,
          trackPeak: peak,
        )!;

        expect(
          LoudnessNormalizer.peakAfterGain(peak, gain),
          lessThanOrEqualTo(1.0),
          reason: 'peak=$peak gain=$gain 时峰值越界（削波保护失效）',
        );
        expect(gain, greaterThanOrEqualTo(LoudnessNormalizer.minGainDb));
      }
    });

    test('parses gain tags with or without the " dB" suffix', () {
      expect(LoudnessNormalizer.parseGainDb('-6.50 dB'), -6.5);
      expect(LoudnessNormalizer.parseGainDb('-6.50'), -6.5);
      expect(LoudnessNormalizer.parseGainDb('  +3.00 dB '), 3.0);
      expect(LoudnessNormalizer.parseGainDb('-1.25DB'), -1.25);
      expect(LoudnessNormalizer.parseGainDb(null), isNull);
      expect(LoudnessNormalizer.parseGainDb(''), isNull);
      expect(LoudnessNormalizer.parseGainDb('dB'), isNull);
      expect(LoudnessNormalizer.parseGainDb('loud'), isNull);
      expect(LoudnessNormalizer.parseGainDb('nan'), isNull);
    });

    test('peak parsing rejects dB-suffixed and non-positive values', () {
      expect(LoudnessNormalizer.parsePeak('0.988553'), 0.988553);
      expect(LoudnessNormalizer.parsePeak(' 1.0 '), 1.0);
      // dB 后缀的峰值说明它不是线性峰值 → 拒绝，而不是按线性解释（10 倍量级错误）
      expect(LoudnessNormalizer.parsePeak('-1.00 dB'), isNull);
      expect(LoudnessNormalizer.parsePeak('0'), isNull);
      expect(LoudnessNormalizer.parsePeak('-0.5'), isNull);
      expect(LoudnessNormalizer.parsePeak(null), isNull);
      expect(LoudnessNormalizer.parsePeak('loud'), isNull);
    });

    test('tag text → normaliser is wired end to end (no sign inversion)', () {
      final gain = LoudnessNormalizer.gainFor(
        trackGainDb: LoudnessNormalizer.parseGainDb('-6.50 dB'),
        trackPeak: LoudnessNormalizer.parsePeak('0.988553'),
      );
      expect(gain, -6.5, reason: '标签要求衰减 → 照做，低峰值不改变结论');

      final boosted = LoudnessNormalizer.gainFor(
        trackGainDb: LoudnessNormalizer.parseGainDb('+3.00 dB'),
        trackPeak: LoudnessNormalizer.parsePeak('0.5'),
      );
      expect(boosted, 3.0, reason: '标签要求提升 → 照做（不得反转符号）');
    });

    test('tag lists: track gain wins over album gain', () {
      expect(
        LoudnessNormalizer.gainFromTags(
          trackGain: const ['-6.50 dB'],
          trackPeak: const ['0.988553'],
          albumGain: const ['-2.00 dB'],
          albumPeak: const ['0.99'],
        ),
        -6.5,
      );
    });

    test('tag lists: falls back to album values, null when nothing usable', () {
      expect(
        LoudnessNormalizer.gainFromTags(albumGain: const ['-3.25 dB']),
        -3.25,
      );
      expect(LoudnessNormalizer.gainFromTags(), isNull);
      expect(LoudnessNormalizer.gainFromTags(trackGain: const []), isNull);
      expect(
        LoudnessNormalizer.gainFromTags(trackGain: const ['', '   ']),
        isNull,
      );
    });

    test('tag lists: repeated tags take the LAST non-empty value', () {
      expect(
        LoudnessNormalizer.gainFromTags(
          trackGain: const ['-2.00 dB', '  ', '-6.50 dB'],
        ),
        -6.5,
        reason: '同一 tag 出现多次时取最后一个非空值，不静默取中间值',
      );
    });

    test('tag lists: an unusable peak only drops clipping protection', () {
      // peak 带 dB 后缀（与"线性峰值"规范不符）→ 被拒 → 只按增益策略走
      expect(
        LoudnessNormalizer.gainFromTags(
          trackGain: const ['+6.00 dB'],
          trackPeak: const ['-1.00 dB'],
        ),
        LoudnessNormalizer.maxBoostDb,
      );

      // 正常线性峰值 → 削波保护生效，结果必须小于策略上限
      final protected = LoudnessNormalizer.gainFromTags(
        trackGain: const ['+6.00 dB'],
        trackPeak: const ['1.2'],
      )!;
      expect(protected, lessThan(LoudnessNormalizer.maxBoostDb));
    });
  });

  group('EQ preset JSON import/export (W2-B item b)', () {
    test('a custom curve round-trips through encode/decode', () {
      final document = EqPresetDocument(
        name: 'my curve',
        bandGains: const [3, -2, 0, 4.5, -12],
        preset: EqualizerPreset.rock,
      );

      final imported = EqPresetDocument.decode(document.encode());

      expect(imported.isSuccess, isTrue);
      expect(imported.error, isNull);
      expect(imported.document!.name, 'my curve');
      expect(imported.document!.bandGains, const [3, -2, 0, 4.5, -12]);
      expect(imported.document!, document);
    });

    test('a built-in preset round-trips (5 bands, name + preset kept)', () {
      final document = EqPresetDocument.fromPreset(EqualizerPreset.rock);

      final imported = EqPresetDocument.decode(document.encode());

      expect(imported.isSuccess, isTrue);
      expect(imported.document!.name, EqualizerPreset.rock.displayName);
      expect(imported.document!.bandGains, EqualizerPreset.rock.bandGains);
      expect(imported.document!.preset, EqualizerPreset.rock);
    });

    test('the payload carries an explicit schema tag and version', () {
      final json =
          jsonDecode(
                EqPresetDocument.fromPreset(EqualizerPreset.vocal).encode(),
              )
              as Map<String, dynamic>;

      expect(json['schema'], EqPresetDocument.schemaTag);
      expect(json['version'], EqPresetDocument.schemaVersion);
    });

    test('rejects a foreign schema tag', () {
      final result = EqPresetDocument.fromJson({
        'schema': 'some.other.app',
        'version': 1,
        'name': 'x',
        'bandGains': const [0, 0, 0, 0, 0],
      });

      expect(result.isSuccess, isFalse);
      expect(result.error, EqPresetError.wrongSchema);
    });

    test('rejects a missing or unknown version', () {
      for (final version in <Object?>[null, 0, 2, '1', 1.0]) {
        final result = EqPresetDocument.fromJson({
          'schema': EqPresetDocument.schemaTag,
          'version': version,
          'name': 'x',
          'bandGains': const [0, 0, 0, 0, 0],
        });

        expect(
          result.error,
          EqPresetError.unsupportedVersion,
          reason: 'version=$version 必须被拒绝（缺版本与不认识合并成同一处置）',
        );
      }
    });

    test('rejects a wrong band count', () {
      for (final gains in <List<double>>[
        const [],
        const [0, 0, 0, 0],
        const [0, 0, 0, 0, 0, 0],
      ]) {
        final result = EqPresetDocument.fromJson({
          'schema': EqPresetDocument.schemaTag,
          'version': 1,
          'name': 'x',
          'bandGains': gains,
        });

        expect(result.error, EqPresetError.wrongBandCount);
      }
    });

    test('rejects out-of-range gains instead of clamping them', () {
      for (final gain in <double>[13, -12.5, 99]) {
        final result = EqPresetDocument.fromJson({
          'schema': EqPresetDocument.schemaTag,
          'version': 1,
          'name': 'x',
          'bandGains': [gain, 0, 0, 0, 0],
        });

        expect(
          result.error,
          EqPresetError.gainOutOfRange,
          reason: '$gain dB 越界必须被拒绝；clamp 成 ±12 会让导入方以为成功了',
        );
        expect(result.document, isNull);
      }

      // 边界值本身合法（±12 允许，只有越界才拒绝）。
      final atEdge = EqPresetDocument.fromJson({
        'schema': EqPresetDocument.schemaTag,
        'version': 1,
        'name': 'x',
        'bandGains': const [12, -12, 0, 0, 0],
      });
      expect(atEdge.isSuccess, isTrue);
      expect(atEdge.document!.bandGains, const [12, -12, 0, 0, 0]);
    });

    test('rejects non-numeric gains, missing gains and empty names', () {
      EqPresetImport build(Object? gains, {Object? name = 'x'}) {
        return EqPresetDocument.fromJson({
          'schema': EqPresetDocument.schemaTag,
          'version': 1,
          'name': name,
          'bandGains': gains,
        });
      }

      expect(build(const ['loud', 0, 0, 0, 0]).error, EqPresetError.nonNumericGain);
      expect(
        build(const [0, 0, 0, 0, double.nan]).error,
        EqPresetError.nonNumericGain,
      );
      expect(build(null).error, EqPresetError.missingGains);
      expect(
        build(const [0, 0, 0, 0, 0], name: '   ').error,
        EqPresetError.missingName,
      );
      expect(
        build(const [0, 0, 0, 0, 0], name: null).error,
        EqPresetError.missingName,
      );
    });

    test('rejects malformed JSON text and non-object payloads', () {
      expect(EqPresetDocument.decode('{not json').error, EqPresetError.notJson);
      expect(EqPresetDocument.decode('').error, EqPresetError.notJson);
      expect(
        EqPresetDocument.fromJson(const <Object?>[1, 2, 3]).error,
        EqPresetError.notAnObject,
      );
      expect(
        EqPresetDocument.fromJson('a string').error,
        EqPresetError.notAnObject,
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
