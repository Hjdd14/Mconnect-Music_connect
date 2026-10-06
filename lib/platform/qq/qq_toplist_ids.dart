/// QQ Music chart ids (`topId`), verified against the live `GetAll` catalogue
/// and the legacy `fcg_v8_toplist_cp` endpoint on 2026-10-06.
///
/// Why this class exists: the pre-v1.4.0 adapter hardcoded `topId=4` with the
/// comment "热歌榜", but `4` is 巅峰榜·流行指数 and the real 热歌榜 is `26`
/// (300 tracks). The user-visible symptom was "QQ 热歌榜没有入口" — the app was
/// showing the wrong chart and could not reach the right one at all.
class QqToplistIds {
  QqToplistIds._();

  /// 巅峰榜·热歌 — 300 tracks, daily. **This is 热歌榜.**
  static const int hot = 26;

  /// 巅峰榜·新歌 — used as the anonymous substitute for the personalised
  /// daily recommendation.
  static const int newSongs = 27;

  /// 飙升榜.
  static const int soaring = 62;

  /// 巅峰榜·流行指数 (what the old code wrongly labelled 热歌榜).
  static const int popularIndex = 4;

  /// 巅峰榜·听歌识曲榜.
  static const int audioRecognition = 67;

  /// 巅峰榜·MV榜.
  static const int mv = 201;

  /// 地区榜·内地榜.
  static const int mainland = 5;

  /// 特色榜·说唱榜.
  static const int rap = 58;

  /// 全球榜·美国公告牌榜.
  static const int billboard = 108;

  /// Human-readable names for the ids above, used in fallback provenance.
  static const String hotName = '热歌榜';
  static const String newSongsName = '新歌榜';

  /// Largest page the legacy chart endpoint actually serves.
  ///
  /// Verified live: `song_num=100` and `song_num=300` both return **50**
  /// tracks, while `song_begin=100&song_num=5` returns ranks 101-105. So the
  /// 300-track 热歌榜 must be paged 50 at a time.
  static const int pageSize = 50;

  /// Chart groups the catalogue endpoint reports, in display order.
  static const List<String> groupOrder = ['巅峰榜', '地区榜', '特色榜', '全球榜'];
}
