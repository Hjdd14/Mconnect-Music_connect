import '../../models/song.dart';
import '../../platform/base/music_platform.dart';
import '../../platform/base/platform_registry.dart';
import '../source_matching/track_identity.dart';
import 'transfer_format.dart';
import 'transfer_report.dart';

/// W1-A's scoring function, taken as a tear-off from `SourceMatchService`
/// (`service.scoreCandidate`).
///
/// Taking the *function* keeps **one** implementation of the matching score in
/// the codebase instead of a second copy here — the drift this project has paid
/// for repeatedly — and keeps this file independently testable: a test injects
/// its own scorer and exercises the ordering / bucketing / request discipline
/// without standing up a service, a cache or a platform registry.
typedef SourceMatchScorer =
    double Function(TrackIdentity identity, Song candidate);

/// Finds candidate songs for an imported row, then ranks them with
/// [SourceMatchScorer].
///
/// **Division of labour.** W1-A's `SourceMatchService` owns *"are these the same
/// song?"*: the `TrackIdentity` normalisation, the 0.5×title / 0.3×artist /
/// 0.2×duration score, the ±3s duration veto, and the threshold. All three are
/// used here as-is (`TrackIdentity.normalizeForMatch`, the injected [score], the
/// injected [confidentAt]).
///
/// What this class owns is the part W1-A's public surface cannot express: their
/// `resolve` / `resolveDetailed` both require an **already-identified** `Song`
/// (platform + id known) and return a *URL*, while an imported row has neither id
/// nor platform and needs a `Song` back. So this class only iterates the
/// logged-in platforms, asks each for a few results by title (the same bare-title
/// query `SourceMatchService._searchWithRetry` issues), and hands them to W1-A's
/// scorer. No score, threshold, normalisation rule or duration tolerance is
/// restated here.
///
/// Requests are **serial**. A few hundred rows each fanning out to three
/// platforms at once is what gets an account rate-limited. Per-row retry and
/// backoff belong to `TransferMatcher`, so this class deliberately adds no retry
/// of its own — one backoff implementation, not two.
class SourceMatchCandidateFinder implements PlaylistSourceMatcher {
  SourceMatchCandidateFinder({
    required this.score,
    required this.confidentAt,
    List<MusicPlatform> Function()? platforms,
    this.searchLimit = 10,
    this.maxCandidates = 5,
  }) : _platforms = platforms ?? (() => PlatformRegistry.all);

  /// W1-A's scorer, passed as a tear-off (`service.scoreCandidate`).
  final SourceMatchScorer score;

  /// Score at or above which a candidate is imported without asking.
  ///
  /// Required rather than defaulted so it cannot drift from W1-A's
  /// `SourceMatchService.scoreThreshold` (0.8, the same number its own
  /// `resolveDetailed` compares against): the wiring site passes that field.
  final double confidentAt;

  final List<MusicPlatform> Function() _platforms;

  /// How many results to ask each platform for — the same budget
  /// `SourceMatchService.searchLimit` uses.
  final int searchLimit;

  /// Cap on the candidates handed to the report. Only the best one drives the
  /// import; the rest exist so the user can pick another, and a long tail would
  /// only make the report unreadable.
  final int maxCandidates;

  @override
  Future<List<SourceMatchCandidate>> candidatesFor(TransferEntry entry) async {
    final title = entry.title.trim();
    if (title.isEmpty) return const <SourceMatchCandidate>[];

    // Built from the row rather than from a `Song`, because an unmatched row has
    // no `Song` yet. `TrackIdentity.normalizeForMatch` is W1-A's own
    // normaliser, so both sides of the comparison go through the same rules.
    final identity = TrackIdentity(
      titleKey: TrackIdentity.normalizeForMatch(title),
      artistKey: entry.artists.isEmpty
          ? ''
          : TrackIdentity.normalizeForMatch(entry.artists.first),
      duration: entry.duration,
    );

    final scored = <SourceMatchCandidate>[];
    for (final platform in _platforms()) {
      // A platform the user is not signed in to cannot serve the song; asking
      // only burns a request and can surface a session error.
      if (!platform.isLoggedIn) continue;
      try {
        // Same query shape `SourceMatchService._searchWithRetry` uses: the
        // title, not title+artist — platforms rank better on the bare title.
        final results = await platform.search(title, limit: searchLimit);
        for (final candidate in results) {
          final value = score(identity, candidate);
          // 0 is W1-A's "not the same recording" verdict (e.g. the duration veto
          // fired), which is a rejection rather than a weak candidate.
          if (value <= 0) continue;
          scored.add(
            SourceMatchCandidate(
              song: candidate,
              confident: value >= confidentAt,
              score: value,
            ),
          );
        }
      } catch (_) {
        // One platform refusing to answer must not lose the row: the remaining
        // platforms still get their turn, and a row that matches nothing is
        // reported rather than dropped.
      }
    }

    scored.sort((a, b) => (b.score ?? 0).compareTo(a.score ?? 0));
    return scored.length > maxCandidates
        ? scored.sublist(0, maxCandidates)
        : scored;
  }
}
