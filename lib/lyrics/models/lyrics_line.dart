enum LyricsFormat { lrc, qrc, krc, yrc, unknown }

/// Where a document's text came from, for the "来源" badge.
///
/// Deliberately its own enum instead of `PlatformType`: [lrclib] is a fallback
/// source with no platform at all, and `lib/lyrics/**` must not depend on the
/// app's model layer.
enum LyricsSource {
  netease('网易云音乐'),
  qq('QQ音乐'),
  kugou('酷狗音乐'),
  local('本地音乐'),
  lrclib('LRCLIB'),
  unknown('');

  /// Shown in the badge. Hard-coded like the rest of the player widgets; the
  /// l10n pass (W3-D) owns `lib/l10n/**`, not this.
  final String displayName;

  const LyricsSource(this.displayName);

  bool get isKnown => this != LyricsSource.unknown;
}

class WordTiming {
  final String word;
  final Duration start;
  final Duration duration;

  const WordTiming({
    required this.word,
    required this.start,
    required this.duration,
  });
}

class LyricsLine {
  final Duration timestamp;
  final String text;
  final String? translation;
  final List<WordTiming>? words;

  const LyricsLine({
    required this.timestamp,
    required this.text,
    this.translation,
    this.words,
  });

  bool get hasWordTiming => words != null && words!.isNotEmpty;
  bool get hasTranslation => translation != null && translation!.trim().isNotEmpty;

  LyricsLine withTranslation(String? translation) => LyricsLine(
    timestamp: timestamp,
    text: text,
    translation: translation ?? this.translation,
    words: words,
  );
}

class LyricsDocument {
  final String? title;
  final String? artist;
  final List<LyricsLine> lines;
  final LyricsFormat format;

  /// Which source supplied the text, or [LyricsSource.unknown] for a document
  /// built in code (fakes, tests, an empty placeholder).
  final LyricsSource source;

  const LyricsDocument({
    this.title,
    this.artist,
    this.lines = const [],
    this.format = LyricsFormat.unknown,
    this.source = LyricsSource.unknown,
  });

  factory LyricsDocument.parse(
    String content,
    LyricsFormat format, {
    LyricsSource source = LyricsSource.unknown,
  }) {
    switch (format) {
      case LyricsFormat.lrc:
        return _parseLrc(content, source);
      case LyricsFormat.krc:
        return _parseKrc(content, source);
      case LyricsFormat.qrc:
        return _parseQrc(content, source);
      case LyricsFormat.yrc:
        return _parseYrc(content, source);
      default:
        return _parseLrc(content, source);
    }
  }

  /// True when [content] really yields at least one timed line in [format].
  ///
  /// Format *sniffing* must never trust the presence of a few punctuation marks:
  /// an ordinary LRC that happens to contain `<` and `,` (a smiley, a comma in
  /// the lyrics) used to be routed to the KRC parser, which found no
  /// `[start,duration]` line and blanked the entire song.
  static bool parsesToLines(String content, LyricsFormat format) {
    try {
      return LyricsDocument.parse(content, format).lines.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// The first format in [candidates] that [parsesToLines], else the last one.
  ///
  /// Callers list their format guesses most-specific first and end with
  /// [LyricsFormat.lrc], which needs no markers at all.
  static LyricsFormat sniffFormat(
    String content,
    List<LyricsFormat> candidates, {
    LyricsFormat fallback = LyricsFormat.lrc,
  }) {
    if (candidates.isEmpty) return fallback;
    for (final candidate in candidates) {
      if (parsesToLines(content, candidate)) return candidate;
    }
    return candidates.last;
  }

  /// Parse standard LRC format (NetEase, basic QQ)
  static LyricsDocument _parseLrc(String content, LyricsSource source) {
    final lines = <LyricsLine>[];
    String? title;
    String? artist;

    final timeRegex = RegExp(r'\[(\d{2}):(\d{2})\.(\d{2,3})\]');
    final tagRegex = RegExp(
      r'\[(ti|ar|al|by|offset|length):([^\]]*)\]',
      caseSensitive: false,
    );

    // `[offset:±ms]` shifts the whole timeline and is accepted anywhere in the
    // file — some writers put it in a trailing footer — so it is collected in a
    // first pass instead of while streaming the lines.
    var offsetMs = 0;
    for (final rawLine in content.split('\n')) {
      for (final tagMatch in tagRegex.allMatches(rawLine)) {
        final tag = tagMatch.group(1)?.toLowerCase();
        final value = tagMatch.group(2)?.trim();
        if (tag == 'ti') {
          title = value;
        } else if (tag == 'ar') {
          artist = value;
        } else if (tag == 'offset') {
          // A malformed value keeps the previous offset rather than throwing.
          offsetMs = int.tryParse(value ?? '') ?? offsetMs;
        }
      }
    }

    for (final rawLine in content.split('\n')) {
      final times = timeRegex.allMatches(rawLine).toList();
      if (times.isEmpty) continue;

      // Tags are stripped instead of skipping the line: `[offset:250][00:01.00]词`
      // is a legal single line and used to be dropped whole.
      final text = rawLine
          .replaceAll(timeRegex, '')
          .replaceAll(tagRegex, '')
          .trim();
      if (text.isEmpty) continue;

      for (final match in times) {
        final min = int.parse(match.group(1)!);
        final sec = int.parse(match.group(2)!);
        final msStr = match.group(3)!;
        final ms = msStr.length == 2 ? int.parse(msStr) * 10 : int.parse(msStr);
        final base = Duration(minutes: min, seconds: sec, milliseconds: ms);

        // `[offset:]` may push a timestamp before the start of the track; a
        // negative position is meaningless downstream (line matching, the
        // progress highlight), so it becomes zero.
        final shiftedMs = base.inMilliseconds + offsetMs;
        lines.add(LyricsLine(
          timestamp: Duration(milliseconds: shiftedMs < 0 ? 0 : shiftedMs),
          text: text,
        ));
      }
    }

    final mergedLines = _mergeSameTimestampLines(_stableSortByTimestamp(lines));

    return LyricsDocument(
      title: title,
      artist: artist,
      lines: mergedLines,
      format: LyricsFormat.lrc,
      source: source,
    );
  }

  /// Sorts by timestamp while preserving the file order of equal timestamps.
  ///
  /// `List.sort` gives no stability guarantee: past a few dozen entries Dart's
  /// quicksort is free to swap the two lines that share one timestamp, which
  /// displayed the translation as the main lyric. The original index is carried
  /// along so equal timestamps keep the order the file listed them in.
  static List<LyricsLine> _stableSortByTimestamp(List<LyricsLine> lines) {
    final decorated = [
      for (var index = 0; index < lines.length; index++)
        (index: index, line: lines[index]),
    ];
    decorated.sort((a, b) {
      final byTime = a.line.timestamp.compareTo(b.line.timestamp);
      return byTime != 0 ? byTime : a.index.compareTo(b.index);
    });
    return [for (final entry in decorated) entry.line];
  }

  /// Pairs the lines sharing one timestamp into `(original, translation)`.
  ///
  /// The original is the line the file listed **first** for that timestamp (the
  /// sort above is stable, so "first" means "first in the file"), and the first
  /// *different* text becomes its translation. Every further line with the same
  /// timestamp is kept as its own line: from the third line on, the old code
  /// silently dropped it (a romanisation, a second translation) and, worse, kept
  /// showing the first translation while dropping the new text.
  static List<LyricsLine> _mergeSameTimestampLines(List<LyricsLine> lines) {
    final merged = <LyricsLine>[];
    var index = 0;
    while (index < lines.length) {
      final timestamp = lines[index].timestamp;
      var end = index + 1;
      while (end < lines.length && lines[end].timestamp == timestamp) {
        end++;
      }

      final first = lines[index];
      final seen = <String>{first.text};
      String? translation;
      final extras = <LyricsLine>[];
      for (var i = index + 1; i < end; i++) {
        final candidate = lines[i];
        // A repeated text at the same timestamp is a duplicate line, not a
        // translation of itself.
        if (!seen.add(candidate.text)) continue;
        if (translation == null) {
          translation = candidate.text;
          continue;
        }
        extras.add(candidate);
      }

      merged.add(LyricsLine(
        timestamp: timestamp,
        text: first.text,
        translation: translation,
        words: first.words,
      ));
      merged.addAll(extras);
      index = end;
    }
    return merged;
  }

  /// Parse KRC format (Kugou - decrypted content)
  static LyricsDocument _parseKrc(String content, LyricsSource source) {
    final lines = <LyricsLine>[];
    final lineRegex = RegExp(r'\[(\d+),(\d+)\]');
    final wordRegex = RegExp(r'<(\d+),(\d+),\d+>([^<]+)');

    for (final rawLine in content.split('\n')) {
      final lineMatch = lineRegex.firstMatch(rawLine);
      if (lineMatch == null) continue;

      final timestamp = int.parse(lineMatch.group(1)!);
      final textContent = rawLine.substring(lineMatch.end);

      final words = <WordTiming>[];
      final wordMatches = wordRegex.allMatches(textContent);

      if (wordMatches.isNotEmpty) {
        var currentMs = timestamp;
        for (final wm in wordMatches) {
          final wordDuration = int.parse(wm.group(2)!);
          final word = wm.group(3)!;
          words.add(WordTiming(
            word: word,
            start: Duration(milliseconds: currentMs),
            duration: Duration(milliseconds: wordDuration),
          ));
          currentMs += wordDuration;
        }
      }

      final text = textContent.replaceAll(RegExp(r'<[^>]+>'), '').trim();
      if (text.isEmpty) continue;
      lines.add(LyricsLine(
        timestamp: Duration(milliseconds: timestamp),
        text: text,
        words: words.isNotEmpty ? words : null,
      ));
    }

    final sorted = _stableSortByTimestamp(lines);

    return LyricsDocument(
      lines: sorted,
      format: LyricsFormat.krc,
      source: source,
    );
  }

  /// Parse NetEase's word-by-word `yrc` format.
  ///
  /// Shape, as observed on a real response (see `docs/netease-lyric-shapes.md`):
  ///
  /// ```text
  /// [startMs,durMs](chunkStartMs,chunkDurMs,flags)text
  /// ```
  ///
  /// * the leading `[start,dur]` has **no colons**, so this is not LRC and the
  ///   LRC regex never matches it — routing it to the LRC parser loses the whole
  ///   song silently;
  /// * every `(start,dur,flags)` triple is one chunk **relative to the line
  ///   start**, and a line carries one triple per chunk: that is the word-by-word
  ///   timing;
  /// * the first lines of a real payload are credits (`制作人`, `作词`, …), not the
  ///   first sung line, so nothing here may assume line 0 is the first lyric.
  ///
  /// A missing/empty `yrc` is normal (only 2 of 8 probed tracks had one) — the
  /// caller must always be able to fall back to `lrc`.
  static LyricsDocument _parseYrc(String content, LyricsSource source) {
    final lines = <LyricsLine>[];
    final lineRegex = RegExp(r'^\[(\d+),(\d+)\]');
    final chunkRegex = RegExp(r'\((\d+),(\d+),(\d+)\)([^(]*)');

    for (final rawLine in content.split('\n')) {
      final lineMatch = lineRegex.firstMatch(rawLine);
      if (lineMatch == null) continue;

      final lineStartMs = int.parse(lineMatch.group(1)!);
      final rest = rawLine.substring(lineMatch.end);

      final words = <WordTiming>[];
      final textBuffer = StringBuffer();
      for (final chunk in chunkRegex.allMatches(rest)) {
        final chunkStartMs = int.parse(chunk.group(1)!);
        final chunkDurationMs = int.parse(chunk.group(2)!);
        final chunkText = chunk.group(4)!;
        textBuffer.write(chunkText);
        if (chunkText.isEmpty) continue;
        words.add(
          WordTiming(
            word: chunkText,
            start: Duration(milliseconds: lineStartMs + chunkStartMs),
            duration: Duration(milliseconds: chunkDurationMs),
          ),
        );
      }

      final text = textBuffer.toString().trim();
      if (text.isEmpty) continue;
      lines.add(
        LyricsLine(
          timestamp: Duration(milliseconds: lineStartMs),
          text: text,
          words: words.isNotEmpty ? words : null,
        ),
      );
    }

    return LyricsDocument(
      lines: _stableSortByTimestamp(lines),
      format: LyricsFormat.yrc,
      source: source,
    );
  }

  /// Parse QRC format (QQ Music - decrypted content)
  static LyricsDocument _parseQrc(String content, LyricsSource source) {
    // QRC format is XML-like with word timing
    final lines = <LyricsLine>[];
    final lineRegex = RegExp(r'<L\s+T="(\d+)"\s+D="(\d+)">(.*?)</L>');
    final wordRegex = RegExp(r'<P\s+T="(\d+)"\s+D="(\d+)">(.*?)</P>');

    for (final lineMatch in lineRegex.allMatches(content)) {
      final timestamp = int.parse(lineMatch.group(1)!);
      final text = lineMatch.group(3)!.replaceAll(RegExp(r'<[^>]+>'), '');

      final words = <WordTiming>[];
      final wordContent = lineMatch.group(3)!;

      for (final wm in wordRegex.allMatches(wordContent)) {
        final wordStart = int.parse(wm.group(1)!);
        final wordDuration = int.parse(wm.group(2)!);
        final word = wm.group(3)!;
        words.add(WordTiming(
          word: word,
          start: Duration(milliseconds: timestamp + wordStart),
          duration: Duration(milliseconds: wordDuration),
        ));
      }

      lines.add(LyricsLine(
        timestamp: Duration(milliseconds: timestamp),
        text: text,
        words: words.isNotEmpty ? words : null,
      ));
    }

    final sorted = _stableSortByTimestamp(lines);

    return LyricsDocument(
      lines: sorted,
      format: LyricsFormat.qrc,
      source: source,
    );
  }
}
