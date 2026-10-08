import 'dart:convert';

import '../presentation/providers/audio_effects_provider.dart';

/// 导入失败的原因（Wave 2-B / item b）。
///
/// 刻意**枚举而不是字符串**：UI 要按原因给不同提示（"这是别的 app 的文件"
/// vs "频段数不对" vs "增益越界"），也便于用例断言"被拒绝且原因正确"。
enum EqPresetError {
  /// 不是合法 JSON。
  notJson,

  /// JSON 顶层不是对象。
  notAnObject,

  /// `schema` 标记不是本 app 的预设格式。
  wrongSchema,

  /// 缺 `version`，或版本号不是本实现认识的那一个（缺失与不认识合并成一条：
  /// 对使用者来说处置方式相同 —— 不能用）。
  unsupportedVersion,

  /// 缺 `name`，或名字为空。
  missingName,

  /// 缺 `bandGains`。
  missingGains,

  /// 频段数不是 [EqPresetDocument.bandCount]。
  wrongBandCount,

  /// 某个增益不是数字（或不是有限值）。
  nonNumericGain,

  /// 某个增益超出 [EqPresetDocument.minGain]..[EqPresetDocument.maxGain]。
  ///
  /// **越界是拒绝、不是 clamp**：静默夹紧会把"别人给的文件"改成一个用户没见过的
  /// 曲线，导入方还以为成功了。
  gainOutOfRange,
}

/// 导入结果：成功带文档，失败带原因；两者互斥。
class EqPresetImport {
  const EqPresetImport.success(EqPresetDocument this.document)
    : error = null;

  const EqPresetImport.failure(this.error) : document = null;

  final EqPresetDocument? document;
  final EqPresetError? error;

  bool get isSuccess => document != null;
}

/// 可导入/导出的 EQ 预设文档（Wave 2-B / item b）。
///
/// 与 `AudioEffectsSettings.toJson()`（Hive 内部存储形状）**故意分开**：那个是私有
/// 存储格式，可以随版本演进；这个是**对外交换格式**，必须带 `schema` + `version`
/// 并严格校验，否则一旦有人贴进来一个畸形 JSON，均衡器就会静默变成别的曲线。
class EqPresetDocument {
  EqPresetDocument({
    required this.name,
    required List<double> bandGains,
    this.preset,
  }) : bandGains = List<double>.unmodifiable(bandGains);

  /// 对外格式标识与版本（item b 的"schema 版本"）。
  static const schemaTag = 'mconnect.eq_preset';
  static const schemaVersion = 1;

  /// 与 [AudioEffectsSettings.equalizerBandGains] 的默认长度一致（5 段）。
  static const bandCount = 5;

  /// 与 `AudioEffectsSettings._clampGain` 的范围一致（±12 dB）。
  static const minGain = -12.0;
  static const maxGain = 12.0;

  final String name;
  final List<double> bandGains;

  /// 若这份文档来自内置预设，记下它（UI 可以显示"摇滚"而不是"自定义"）。
  final EqualizerPreset? preset;

  /// 用内置预设构造（导出入口）。
  factory EqPresetDocument.fromPreset(EqualizerPreset preset) {
    return EqPresetDocument(
      name: preset.displayName,
      bandGains: preset.bandGains,
      preset: preset,
    );
  }

  /// 用当前设置里的自定义曲线构造（导出入口）。
  factory EqPresetDocument.fromSettings(AudioEffectsSettings settings) {
    return EqPresetDocument(
      name: '自定义 EQ',
      bandGains: settings.equalizerBandGains,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'schema': schemaTag,
      'version': schemaVersion,
      'name': name,
      'bandGains': bandGains,
      if (preset != null) 'preset': preset!.name,
    };
  }

  /// 导出为可分享/可落盘的 JSON 文本。
  String encode() => jsonEncode(toJson());

  /// 解析一段 JSON 文本；任何非法/越界输入都返回带原因的失败。
  static EqPresetImport decode(String raw) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return const EqPresetImport.failure(EqPresetError.notJson);
    }
    return fromJson(decoded);
  }

  /// 严格解析（**不做任何 clamp/补默认值**）。
  static EqPresetImport fromJson(Object? value) {
    if (value is! Map) {
      return const EqPresetImport.failure(EqPresetError.notAnObject);
    }

    final schema = value['schema'];
    if (schema != null && schema != schemaTag) {
      return const EqPresetImport.failure(EqPresetError.wrongSchema);
    }

    final version = value['version'];
    if (version is! int || version != schemaVersion) {
      return const EqPresetImport.failure(EqPresetError.unsupportedVersion);
    }

    final name = value['name'];
    if (name is! String || name.trim().isEmpty) {
      return const EqPresetImport.failure(EqPresetError.missingName);
    }

    final rawGains = value['bandGains'];
    if (rawGains is! List) {
      return const EqPresetImport.failure(EqPresetError.missingGains);
    }
    if (rawGains.length != bandCount) {
      return const EqPresetImport.failure(EqPresetError.wrongBandCount);
    }

    final gains = <double>[];
    for (final raw in rawGains) {
      if (raw is! num || !raw.isFinite) {
        return const EqPresetImport.failure(EqPresetError.nonNumericGain);
      }
      final gain = raw.toDouble();
      if (gain < minGain || gain > maxGain) {
        return const EqPresetImport.failure(EqPresetError.gainOutOfRange);
      }
      gains.add(gain);
    }

    final rawPreset = value['preset'];
    final preset = rawPreset is String ? _presetByName(rawPreset) : null;

    return EqPresetImport.success(
      EqPresetDocument(name: name.trim(), bandGains: gains, preset: preset),
    );
  }

  /// 不依赖 `firstOrNull`（那是 `package:collection` 的扩展，本文件不引入新依赖）。
  static EqualizerPreset? _presetByName(String name) {
    for (final candidate in EqualizerPreset.values) {
      if (candidate.name == name) return candidate;
    }
    return null;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! EqPresetDocument) return false;
    if (other.name != name || other.bandGains.length != bandGains.length) {
      return false;
    }
    for (var i = 0; i < bandGains.length; i++) {
      if (other.bandGains[i] != bandGains[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(name, Object.hashAll(bandGains));
}
