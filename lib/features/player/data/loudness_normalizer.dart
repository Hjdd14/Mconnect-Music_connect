import 'dart:math' as math;

/// ReplayGain → 软件增益的**纯函数**（Wave 2-B / item c）。
///
/// ## 为什么输入是"数值"而不是 tag
///
/// `audio_metadata_reader` 实际吐出的 `REPLAYGAIN_*` key 拼写与单位**我没有核实成功**
/// （我的沙箱读不到 pub cache，见交付说明的"不确定项"），所以"key → 数值"的映射留给
/// 调用方那层薄适配，这里只负责**策略与算术**，因此可以完全单测、不依赖任何 IO。
///
/// ## 语义（容易搞反的一条）
///
/// ReplayGain 的 `TRACK_GAIN` 的数值**就是"要施加的调整量"**：`-6.50 dB` 表示把这首歌
/// **调小** 6.5 dB，`+3.00 dB` 表示**调大** 3 dB。所以这里**不做符号反转**，只做区间
/// 限制与削波保护。（把符号反转是常见实现错误：结果会把安静的录音推爆、把响的压死。）
///
/// ## 与 AndroidLoudnessEnhancer 的关系
///
/// 后者在当前代码里只是**EQ 正增益的 headroom 补偿**（见 `player_audio_controller.dart`
/// 的 `androidEqualizerPlanForTest`），**不是**响度归一化。本类与它无关、也不复用它。
class LoudnessNormalizer {
  const LoudnessNormalizer._();

  /// 最多提升多少（dB）。ReplayGain 本身可能要求 +12dB 的提升，但软件增益上的大提升
  /// 会把母带噪声、底噪一起抬起来，所以在"归一化"这个场景里我们只允许小幅提升。
  static const maxBoostDb = 6.0;

  /// 最多衰减多少（dB）。衰减不会引入失真，放宽一些，让响的录音真的能降下来。
  static const maxCutDb = -12.0;

  /// 允许过冲到的峰值上限（dBFS）：留 1dB 余量给解码/重采样/后续 EQ 的过冲。
  static const peakCeilingDb = -1.0;

  /// 绝对下限：只是"别把歌弄成听不见"的兜底，不会把削波保护的结论抬回去
  /// （见 [gainFor] 的注释）。
  static const minGainDb = -24.0;

  /// 最终输出上限（软件的增益不该超过这个量级，超过说明标签异常）。
  static const maxGainDb = 12.0;

  /// 由 ReplayGain 标签算出要施加的软件增益（dB）。
  ///
  /// * 没有可用标签 → 返回 `null`（**不是 0**：调用方必须能区分"没有标签、别动音量"
  ///   与"标签算出 0dB、可以原样播"）；
  /// * [trackGainDb] 先被限制在 [maxCutDb]..[maxBoostDb]；
  /// * 若给了 [trackPeak]（线性峰值，1.0 = 满刻度），则叠加**削波保护**：限制增益使
  ///   `peak * 10^(gain/20)` 不超过 [peakCeilingDb]；削波保护**优先于**上面的区间，
  ///   即"宁可更小也不许过冲"。
  static double? gainFor({double? trackGainDb, double? trackPeak}) {
    if (trackGainDb == null || !trackGainDb.isFinite) return null;

    var gain = trackGainDb.clamp(maxCutDb, maxBoostDb).toDouble();

    final peak = trackPeak;
    if (peak != null && peak.isFinite && peak > 0) {
      final peakLimitDb = _gainToReachPeak(peak);
      if (peakLimitDb < gain) gain = peakLimitDb;
    }

    if (gain < minGainDb) gain = minGainDb;
    if (gain > maxGainDb) gain = maxGainDb;
    return gain;
  }

  /// 施加 [gainDb] 之后，线性峰值会变成多少（用于**用例断言**与真机排查）。
  static double peakAfterGain(double peak, double gainDb) {
    return peak * math.pow(10, gainDb / 20).toDouble();
  }

  /// 解析增益标签的**原始字符串**（Wave 2-B / item c 的取值层）。
  ///
  /// `audio_metadata_reader 1.8.0` 只把 tag 原文交出来、**不做任何换算**（Lead 读包
  /// 核实：FLAC/Vorbis 路径里没有一处 replaceAll/toDouble 碰这些键）。真实文件里两种
  /// 写法都常见 —— `'-6.50 dB'` 与 `'-6.50'` —— 所以这里剥掉**可选的** `dB` 后缀
  /// （大小写不敏感、允许两侧空格）再 parse。解析不出来 → `null`（与 [gainFor] 契约一致）。
  static double? parseGainDb(String? raw) {
    final text = _stripDbSuffix(raw);
    if (text == null) return null;
    final value = double.tryParse(text);
    if (value == null || !value.isFinite) return null;
    return value;
  }

  /// 解析峰值标签的原始字符串。
  ///
  /// ReplayGain 规范里 `_PEAK` 是**线性采样峰值**（如 `0.988553`）。**带 `dB` 后缀的
  /// 峰值一律拒绝**（返回 null）：那说明它不是线性峰值，按线性解释会有 10 倍量级误差
  /// —— 宁可不用这个标签，也不要拿它去做削波保护。
  ///
  /// 注：`linear vs dBFS` 这一点包无法回答（它只存字符串），**待真实文件确认**。
  static double? parsePeak(String? raw) {
    final text = raw?.trim();
    if (text == null || text.isEmpty) return null;
    if (_hasDbSuffix(text)) return null;
    final value = double.tryParse(text);
    if (value == null || !value.isFinite || value <= 0) return null;
    return value;
  }

  static String? _stripDbSuffix(String? raw) {
    final text = raw?.trim();
    if (text == null || text.isEmpty) return null;
    if (!_hasDbSuffix(text)) return text;
    final stripped = text.substring(0, text.length - 2).trim();
    return stripped.isEmpty ? null : stripped;
  }

  static bool _hasDbSuffix(String text) => text.toLowerCase().endsWith('db');

  /// 从**已经取出的** ReplayGain 字符串列表算出软件增益（item c 的适配层）。
  ///
  /// 刻意**只吃字符串列表**、不 `import 'package:audio_metadata_reader/...'`：
  /// "怎么从 `AudioMetadata` 走到 `VorbisMetadata` / `MP3Metadata.customMetadata`"这条
  /// 路由**没有核实过**（Lead 查过 `AudioMetadata` 的字段表，没找到能证明的入口），所以
  /// 不猜。取值由已经 import 该包的取值层（`local_metadata_reader.dart`）把字符串列表
  /// 传进来 —— 分工干净，本函数仍可完全单测。
  ///
  /// 取值策略（集中写在这里，避免每层各有一套）：
  /// * 同一 tag 可能出现多次（上游字段是 `List<String>`）→ **取最后一个非空值**
  ///   （"后写的覆盖先写的"是 TXXX/注释字段的常见语义；不一致时不静默取中间值）；
  /// * **track 优先于 album**：单曲播放用 track gain；album gain 需要"整张专辑"的
  ///   上下文（队列级判断），不属本项范围；
  /// * peak 同理：track peak 优先、album peak 兜底；某个 peak 不可用时**只是不做削波
  ///   保护**，不影响增益本身。
  static double? gainFromTags({
    List<String>? trackGain,
    List<String>? trackPeak,
    List<String>? albumGain,
    List<String>? albumPeak,
  }) {
    final gainText = _lastNonEmpty(trackGain) ?? _lastNonEmpty(albumGain);
    final peakText = _lastNonEmpty(trackPeak) ?? _lastNonEmpty(albumPeak);
    return gainFor(
      trackGainDb: parseGainDb(gainText),
      trackPeak: parsePeak(peakText),
    );
  }

  static String? _lastNonEmpty(List<String>? values) {
    if (values == null || values.isEmpty) return null;
    for (var i = values.length - 1; i >= 0; i--) {
      final candidate = values[i].trim();
      if (candidate.isNotEmpty) return candidate;
    }
    return null;
  }

  /// 让 [peak] 恰好升到 [peakCeilingDb] 所需的增益（通常是负的）。
  static double _gainToReachPeak(double peak) {
    final ceiling = math.pow(10, peakCeilingDb / 20).toDouble();
    return 20 * (math.log(ceiling / peak) / math.ln10);
  }
}
