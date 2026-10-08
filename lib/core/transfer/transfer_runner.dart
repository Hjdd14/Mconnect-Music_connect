import 'transfer_format.dart';
import 'transfer_report.dart';

/// Matches a document's entries **one at a time**, with bounded retries.
///
/// Three rules come from the platforms rather than from taste:
/// * requests are **serial** — a batch of several hundred lookups fired at once
///   is what gets an account rate-limited (and sometimes suspended);
/// * a transient failure is retried with a **linear backoff**;
/// * when the retries run out the row is reported as [TransferMatchKind.missing]
///   rather than dropped, so the user can see exactly what did not make it.
///
/// The clock is injectable ([sleep]) so a test can assert the backoff schedule
/// without waiting for it.
class TransferMatcher {
  TransferMatcher({
    required this.matcher,
    this.baseBackoff = const Duration(milliseconds: 400),
    this.maxAttempts = 3,
    Future<void> Function(Duration duration)? sleep,
  }) : _sleep = sleep ?? _defaultSleep;

  final PlaylistSourceMatcher matcher;

  /// Delay before the *first* retry. The nth retry waits `baseBackoff * n`.
  final Duration baseBackoff;

  /// Total attempts per row, the first one included. `1` disables retrying.
  final int maxAttempts;

  final Future<void> Function(Duration duration) _sleep;

  static Future<void> _defaultSleep(Duration duration) =>
      Future<void>.delayed(duration);

  /// Resolves every row of [entries], in order.
  ///
  /// [resumeFrom] is a [TransferReport.resumeToken] from an interrupted run:
  /// those rows are reused as-is instead of being asked again, which is what
  /// makes a long import resumable. [onProgress] is called after each row so the
  /// UI can show a counter.
  ///
  /// A row with an exact identity is resolved locally and **never** reaches the
  /// matcher — no request is spent on a song the document already names.
  Future<TransferReport> match({
    required String playlistName,
    required List<TransferEntry> entries,
    Map<int, TransferMatch>? resumeFrom,
    void Function(int done, int total)? onProgress,
  }) async {
    final total = entries.length;
    final matches = <TransferMatch>[];

    for (var index = 0; index < total; index++) {
      final resumed = resumeFrom?[index];
      matches.add(
        resumed ?? await _matchOne(index, entries[index]),
      );
      onProgress?.call(index + 1, total);
    }

    return TransferReport(playlistName: playlistName, matches: matches);
  }

  Future<TransferMatch> _matchOne(int index, TransferEntry entry) async {
    // The document already names the song: no request, no ambiguity.
    final identified = entry.toSong();
    if (identified != null) {
      return TransferMatch(
        entryIndex: index,
        entry: entry,
        kind: TransferMatchKind.exact,
        song: identified,
        reason: '文档已给出平台与 ID',
      );
    }

    final primary = await _ask(entry);
    if (primary == null) {
      // Every attempt threw. Saying so is the whole point of the report: the row
      // is listed as unmatched rather than quietly disappearing.
      return TransferMatch(
        entryIndex: index,
        entry: entry,
        kind: TransferMatchKind.missing,
        reason: '匹配请求失败',
      );
    }

    final direct = _bucket(index, entry, primary);
    if (direct != null) return direct;

    // Nothing under the committed reading. A plain-text / `#EXTINF` line is
    // ambiguous (`歌名 - 歌手` vs `歌手 - 歌名`), so the swapped reading gets one
    // chance before the row is called unmatched.
    final alternate = entry.alternate;
    if (alternate != null) {
      final swapped = await _ask(alternate);
      if (swapped != null) {
        final match = _bucket(index, entry, swapped);
        if (match != null) return match;
      }
    }

    return TransferMatch(
      entryIndex: index,
      entry: entry,
      kind: TransferMatchKind.missing,
      reason: '未找到可播放版本',
    );
  }

  /// Asks the matcher for [query], retrying with a linear backoff.
  ///
  /// Returns the candidates, or null when every attempt threw. An empty list is
  /// a *successful* "nothing matched" and must not be confused with the null
  /// case — one is "no such song", the other is "the platform is failing".
  Future<List<SourceMatchCandidate>?> _ask(TransferEntry query) async {
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        return await matcher.candidatesFor(query);
      } catch (_) {
        // A failed attempt is not a verdict; back off and try again, unless
        // this was the last one.
        if (attempt < maxAttempts) {
          await _sleep(baseBackoff * attempt);
        }
      }
    }
    return null;
  }

  /// Files one row under one of the three buckets.
  ///
  /// [entry] is always the row as the document wrote it, even when [candidates]
  /// came from its swapped reading — the report quotes the user's own line.
  /// Returns null when there is nothing to file (no candidates at all).
  TransferMatch? _bucket(
    int index,
    TransferEntry entry,
    List<SourceMatchCandidate> candidates,
  ) {
    if (candidates.isEmpty) return null;

    final confident = <SourceMatchCandidate>[
      for (final candidate in candidates)
        if (candidate.confident) candidate,
    ];
    if (confident.isNotEmpty) {
      return TransferMatch(
        entryIndex: index,
        entry: entry,
        kind: TransferMatchKind.exact,
        song: confident.first.song,
        candidates: candidates,
        reason: '高置信匹配',
      );
    }

    return TransferMatch(
      entryIndex: index,
      entry: entry,
      kind: TransferMatchKind.needsConfirmation,
      song: candidates.first.song,
      candidates: candidates,
      reason: '存在候选但置信不足',
    );
  }
}
