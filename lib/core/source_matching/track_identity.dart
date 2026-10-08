import '../../models/song.dart';

/// 跨平台匹配用的曲目标识（Wave 1-A）。
///
/// 与 [Song.dedupeKey] 同源但**更保守**：这里只做"能不能算同一首歌"的归一化，
/// 用于打分，不用于去重落库（那种语义已经由 `dedupeKey` 承担，不能改）。
///
/// 归一化规则（三条，都可单测）：
/// * 括号内容整体丢掉 —— `(Live)`、`【纯音乐】`、`[Remastered 2015]` 这类；
/// * 去掉 `feat/ft/live/remaster/version/explicit/hq/sq/ost` 之类的版本噪声词；
/// * 只保留 `[0-9a-z]` 与 CJK，其余（空白、标点、破折号）全部删除。
class TrackIdentity {
  const TrackIdentity({
    required this.titleKey,
    required this.artistKey,
    required this.duration,
  });

  /// 用歌曲的**主艺人**（`artists.first`）：各平台对"是否把合作艺人列进 artist 名"
  /// 的约定不一致，用全部艺人会让同一录音在主平台与目标平台算出不同 key。
  factory TrackIdentity.fromSong(Song song) {
    return TrackIdentity(
      titleKey: normalizeForMatch(song.name),
      artistKey: song.artists.isEmpty
          ? ''
          : normalizeForMatch(song.artists.first.name),
      duration: song.duration,
    );
  }

  final String titleKey;
  final String artistKey;
  final Duration duration;

  /// `(...)`、`（...）`、`[...]`、`【...】` 整段（含最内层内容）。
  static final RegExp _bracketed = RegExp(
    r'[\(\（\[\【][^\)\）\]\】]*[\)\）\]\】]',
  );

  /// 版本噪声词。词边界按 ASCII 词字符判定，对中文标题无副作用。
  static final RegExp _variantNoise = RegExp(
    r'\b(feat|ft|live|remaster|remastered|version|explicit|hq|sq|ost)\b',
  );

  /// `feat. XXX` / `ft XXX` 之后**整段**是合作艺人名，直接丢掉，否则
  /// "Song feat. Other" 会归一化成 "songother"，永远匹配不上 "song"。
  ///
  /// 已知限制：`Remastered 2011` 这类**带年份**的版本后缀只会去掉词本身，年份会
  /// 留在 key 里（不去掉是因为"1989"这种年份本身就是标题）。这种残差由打分层的
  /// "互为子串给 0.7"兜住。
  static final RegExp _featuredTail = RegExp(r'\b(feat|ft)\.?\s.*$');

  static final RegExp _nonWord = RegExp(r'[^0-9a-z\u4e00-\u9fff]+');

  static String normalizeForMatch(String raw) {
    var value = raw.toLowerCase();
    value = value.replaceAll(_bracketed, ' ');
    value = value.replaceAll(_featuredTail, ' ');
    value = value.replaceAll(_variantNoise, ' ');
    return value.replaceAll(_nonWord, '');
  }
}
