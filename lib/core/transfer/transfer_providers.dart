import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../source_matching/source_match_cache.dart';
import '../source_matching/source_match_service.dart';
import 'source_match_adapter.dart';
import 'transfer_report.dart';
import 'transfer_runner.dart';

/// A store the import path never uses.
///
/// [SourceMatchService] is borrowed here for its **scoring only**: the import
/// flow never calls `resolve*` (an imported row has no song to resolve a URL for
/// — that is exactly why it needs matching), so no URL is ever written and this
/// cache is never read. Implementing the empty store instead of reaching for
/// `DriftSourceMatchCacheStore` also keeps the import path off the database.
class _UnusedSourceMatchCacheStore implements SourceMatchCacheStore {
  const _UnusedSourceMatchCacheStore();

  @override
  Future<SourceMatchEntry?> get(
    String songKey,
    String targetPlatform, {
    required DateTime now,
  }) async => null;

  @override
  Future<void> put(SourceMatchEntry entry) async {}

  @override
  Future<int> purgeExpired({required DateTime now}) async => 0;
}

/// W1-A's service, held only for its scorer and threshold.
///
/// Private on purpose: `lib/core/source_matching/` should own the app-wide
/// instance (and would cache resolved URLs). This one exists so the transfer flow
/// can call [`scoreCandidate`] and read [`scoreThreshold`] instead of restating
/// the 0.5×title / 0.3×artist / 0.2×duration formula and the 0.8 threshold — the
/// single-source-of-truth rule this project keeps paying for when it is broken.
final _sourceMatchScoringProvider = Provider<SourceMatchService>(
  (ref) => SourceMatchService(cache: const _UnusedSourceMatchCacheStore()),
);

/// The matcher the transfer flow uses.
///
/// It is a **thin adapter** over W1-A's `SourceMatchService`:
/// * the score is `service.scoreCandidate` (their function, not a copy);
/// * the threshold is `service.scoreThreshold` (their field, not a restated 0.8);
/// * the normalisation is `TrackIdentity.normalizeForMatch` (their rules);
/// * the query shape is the same bare-title search their own `_searchWithRetry`
///   issues.
///
/// What is *not* theirs, and cannot be, is the platform iteration: their public
/// entry points (`resolve` / `resolveDetailed`) both require an already-identified
/// `Song` (platform + id known) and return a URL, whereas an imported row has
/// neither and needs a `Song` back. See `SourceMatchCandidateFinder` for the exact
/// boundary.
final playlistSourceMatcherProvider = Provider<PlaylistSourceMatcher>((ref) {
  final service = ref.watch(_sourceMatchScoringProvider);
  return SourceMatchCandidateFinder(
    score: service.scoreCandidate,
    confidentAt: service.scoreThreshold,
  );
});

/// Sequential, retrying matcher built on [playlistSourceMatcherProvider].
///
/// This is where the import flow's **serial + backoff** lives, deliberately once:
/// W1-A's service has its own for the URL path, and a second per-platform retry
/// inside the adapter would nest two backoffs around the same request.
final transferMatcherProvider = Provider<TransferMatcher>(
  (ref) => TransferMatcher(matcher: ref.watch(playlistSourceMatcherProvider)),
);

/// A share payload that is a *transfer document* (m3u8 / JSON / `歌名 - 歌手`
/// lines) rather than a link.
///
/// `InboundLinkHandler` can only return a route name, and the import page lives
/// in a different part of the tree, so the text is parked here for the page to
/// pick up — and clear — when it mounts. It is a one-shot slot by design: a
/// value that is read twice would re-import the same document.
final pendingPlaylistTransferProvider = StateProvider<String?>((ref) => null);
