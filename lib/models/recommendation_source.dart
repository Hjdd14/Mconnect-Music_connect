import 'platform_type.dart';
import 'song.dart';

/// Where a platform's "daily recommendation" actually came from.
///
/// The three platforms differ fundamentally here (all verified against the live
/// services — see `docs/` for the probe log):
///
/// * 网易云 exposes a true personalised daily playlist.
/// * QQ音乐's personalised daily list (「今日私享」) is only visible when logged
///   in, and its anonymous fallback endpoint (`musicToplist.ChartInfo/
///   GetDailyRecommend`) now returns `code 500003`; the usable anonymous
///   substitute is a chart, so the source is reported as [fallbackToplist].
/// * 酷狗's official recommendation endpoints (`/api/v3/recommend/song`,
///   `/api/v3/everyday/recommend`) are refused server-side regardless of
///   signing, so the source is the mobile homepage module
///   ([fallbackHomepage]).
///
/// The UI must surface this, because "酷狗推荐" is not the same promise as
/// "每日推荐".
enum RecommendationKind {
  /// True personalised daily playlist (网易云 `/api/v3/discovery/recommend/songs`).
  personalizedDaily,

  /// Personalised but only readable while logged in (QQ「今日私享」playlist).
  personalPrivate,

  /// Not personalised: a chart used as the recommendation seed (QQ 新歌榜/热歌榜).
  fallbackToplist,

  /// Not personalised: a homepage recommendation module (酷狗 `?json=true`).
  fallbackHomepage,

  /// The platform supports the feature but produced nothing usable right now.
  unavailable,
}

/// User-visible provenance for one platform's recommendation list.
class RecommendationSource {
  final PlatformType platform;
  final RecommendationKind kind;

  /// Short badge label, e.g. `每日推荐` / `今日私享` / `酷狗推荐`.
  final String label;

  /// Optional explanation shown when the list is a fallback, e.g.
  /// `未登录，已回退到新歌榜`.
  final String? note;

  const RecommendationSource({
    required this.platform,
    required this.kind,
    required this.label,
    this.note,
  });

  /// True when the list is a genuine personalised daily recommendation.
  bool get isPersonalized =>
      kind == RecommendationKind.personalizedDaily ||
      kind == RecommendationKind.personalPrivate;
}

/// Combined payload returned by [MusicPlatform.getDailyRecommendation].
///
/// Kept as one object (instead of a separate "last source" getter) so the
/// provider can never observe a source that does not belong to the songs it
/// just received.
class RecommendationResult {
  final List<Song> songs;
  final RecommendationSource? source;

  /// Set when the platform could not produce anything; surfaced per platform.
  final String? error;

  const RecommendationResult({
    this.songs = const [],
    this.source,
    this.error,
  });
}
