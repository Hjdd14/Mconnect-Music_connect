import 'package:flutter/foundation.dart';

import '../../models/song.dart';
import 'transfer_format.dart';

/// How a transfer row resolved.
enum TransferMatchKind {
  /// Identified (or matched confidently): imported without asking.
  exact,

  /// Resolved, but not confidently. The user confirms.
  needsConfirmation,

  /// Nothing matched. Reported with the original line, never silently dropped.
  missing,
}

/// One possible song for an entry, with the matcher's own confidence.
@immutable
class SourceMatchCandidate {
  const SourceMatchCandidate({
    required this.song,
    required this.confident,
    this.score,
  });

  final Song song;

  /// True when the matcher is sure enough to import without asking. A single
  /// high-confidence candidate becomes [TransferMatchKind.exact]; anything less
  /// becomes [TransferMatchKind.needsConfirmation].
  final bool confident;

  /// The matcher's raw score (0..1) when it has one. Kept so the report can show
  /// "匹配度 87%" and so candidates can be ordered best-first; a matcher that
  /// does not score leaves it null.
  final double? score;
}

/// The minimal seam onto W1-A's `SourceMatchService`.
///
/// This file declares **only what the transfer flow needs** — the matching
/// algorithm itself lives in W1-A, and writing a second one here is precisely
/// the duplicated-logic debt this project has paid for repeatedly. Until W1-A
/// lands, [NoSourceMatcher] is wired in: it resolves nothing, so unmatched rows
/// surface as [TransferMatchKind.missing] instead of disappearing.
abstract class PlaylistSourceMatcher {
  /// Candidates for [entry], best first. Empty means "nothing found".
  Future<List<SourceMatchCandidate>> candidatesFor(TransferEntry entry);
}

/// The stand-in used until W1-A's service is wired in.
///
/// Deliberately resolves nothing rather than guessing: a wrong automatic match
/// silently puts the wrong song in the user's playlist, which is worse than an
/// honest "could not match".
class NoSourceMatcher implements PlaylistSourceMatcher {
  const NoSourceMatcher();

  @override
  Future<List<SourceMatchCandidate>> candidatesFor(TransferEntry entry) async =>
      const <SourceMatchCandidate>[];
}

/// What happened to one row of the document.
@immutable
class TransferMatch {
  const TransferMatch({
    required this.entryIndex,
    required this.entry,
    required this.kind,
    this.song,
    this.candidates = const <SourceMatchCandidate>[],
    this.reason,
  });

  /// Position in the source document. Used as the resume key and as the
  /// draft's selection key, so it must stay stable across a resumed run.
  final int entryIndex;

  final TransferEntry entry;
  final TransferMatchKind kind;

  /// The song to import: always set for [TransferMatchKind.exact], and set to
  /// the best candidate for [TransferMatchKind.needsConfirmation]. Null only for
  /// [TransferMatchKind.missing].
  final Song? song;

  /// Every candidate the matcher offered, for a "pick another" affordance.
  final List<SourceMatchCandidate> candidates;

  /// Why this row ended up here — shown to the user, and the only trace of a
  /// failed lookup that is not a dropped song.
  final String? reason;

  bool get isMissing => kind == TransferMatchKind.missing;
}

/// The three-bucket result of matching a whole document.
@immutable
class TransferReport {
  const TransferReport({required this.playlistName, required this.matches});

  final String playlistName;
  final List<TransferMatch> matches;

  List<TransferMatch> get exact => _of(TransferMatchKind.exact);
  List<TransferMatch> get needsConfirmation =>
      _of(TransferMatchKind.needsConfirmation);
  List<TransferMatch> get missing => _of(TransferMatchKind.missing);

  int get exactCount => exact.length;
  int get needsConfirmationCount => needsConfirmation.length;
  int get missingCount => missing.length;
  int get total => matches.length;

  bool get isEmpty => matches.isEmpty;

  /// True when every row resolved, i.e. there is nothing to warn the user about.
  bool get isLossless => missingCount == 0;

  /// The rows that can be written with no further questions.
  List<Song> get autoSongs => <Song>[
    for (final match in exact)
      if (match.song != null) match.song!,
  ];

  /// Matches keyed by their position in the source document.
  ///
  /// Hand this back to `TransferMatcher.match(resumeFrom: …)` to continue an
  /// interrupted run instead of asking every platform from the beginning again.
  Map<int, TransferMatch> resumeToken() => <int, TransferMatch>{
    for (final match in matches) match.entryIndex: match,
  };

  List<TransferMatch> _of(TransferMatchKind kind) => <TransferMatch>[
    for (final match in matches)
      if (match.kind == kind) match,
  ];
}

/// What the user has agreed to import out of a [TransferReport].
///
/// Kept separate from the report because the report is the *machine's* answer
/// and this is the *user's*: the UI flips rows here and nothing re-runs matching.
class TransferDraft {
  TransferDraft(this.report);

  final TransferReport report;

  final Set<int> _acceptedIndices = <int>{};

  /// Whether a 待确认 row has been accepted by the user.
  bool isAccepted(TransferMatch match) =>
      _acceptedIndices.contains(match.entryIndex);

  int get acceptedCount => _acceptedIndices.length;

  /// Accepts or un-accepts a 待确认 row. Rows in the other two buckets are not
  /// selectable: 可入 is always imported and 无 has nothing to import.
  void toggle(TransferMatch match) {
    if (match.kind != TransferMatchKind.needsConfirmation) return;
    if (!_acceptedIndices.remove(match.entryIndex)) {
      _acceptedIndices.add(match.entryIndex);
    }
  }

  /// Accepts every 待确认 row that actually has a candidate.
  void acceptAllNeedsConfirmation() {
    for (final match in report.needsConfirmation) {
      if (match.song != null) _acceptedIndices.add(match.entryIndex);
    }
  }

  void clearAccepted() => _acceptedIndices.clear();

  /// Everything the user is importing, in **document order**: every 可入 row
  /// plus the 待确认 rows they accepted. 无 rows contribute nothing but stay in
  /// the report so the UI can still list what was skipped.
  List<Song> get songsToImport {
    final songs = <Song>[];
    for (final match in report.matches) {
      final song = match.song;
      if (song == null) continue;
      final include = switch (match.kind) {
        TransferMatchKind.exact => true,
        TransferMatchKind.needsConfirmation => isAccepted(match),
        TransferMatchKind.missing => false,
      };
      if (include) songs.add(song);
    }
    return songs;
  }
}
