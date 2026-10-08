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

  /// 让 [peak] 恰好升到 [peakCeilingDb] 所需的增益（通常是负的）。
  static double _gainToReachPeak(double peak) {
    final ceiling = math.pow(10, peakCeilingDb / 20).toDouble();
    return 20 * (math.log(ceiling / peak) / math.ln10);
  }
}
