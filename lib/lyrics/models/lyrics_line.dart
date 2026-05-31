enum LyricsFormat { lrc, qrc, krc, unknown }

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
  bool get hasTranslation =>
      translation != null && translation!.trim().isNotEmpty;
}

class LyricsDocument {
  final String? title;
  final String? artist;
  final List<LyricsLine> lines;
  final LyricsFormat format;

  const LyricsDocument({
    this.title,
    this.artist,
    this.lines = const [],
    this.format = LyricsFormat.unknown,
  });

  factory LyricsDocument.parse(String content, LyricsFormat format) {
    switch (format) {
      case LyricsFormat.lrc:
        return _parseLrc(content);
      case LyricsFormat.krc:
        return _parseKrc(content);
      case LyricsFormat.qrc:
        return _parseQrc(content);
      default:
        return _parseLrc(content);
    }
  }

  /// Parse standard LRC format (NetEase, basic QQ)
  static LyricsDocument _parseLrc(String content) {
    final lines = <LyricsLine>[];
    String? title;
    String? artist;

    final timeRegex = RegExp(r'\[(\d{2}):(\d{2})\.(\d{2,3})\]');
    final tagRegex = RegExp(r'\[(ti|ar):([^\]]+)\]');

    for (final line in content.split('\n')) {
      final tagMatch = tagRegex.firstMatch(line);
      if (tagMatch != null) {
        final tag = tagMatch.group(1);
        final value = tagMatch.group(2)?.trim();
        if (tag == 'ti') title = value;
        if (tag == 'ar') artist = value;
        continue;
      }

      final times = timeRegex.allMatches(line).toList();
      if (times.isEmpty) continue;

      final text = line.replaceAll(timeRegex, '').trim();
      if (text.isEmpty) continue;

      for (final match in times) {
        final min = int.parse(match.group(1)!);
        final sec = int.parse(match.group(2)!);
        final msStr = match.group(3)!;
        final ms = msStr.length == 2 ? int.parse(msStr) * 10 : int.parse(msStr);

        lines.add(
          LyricsLine(
            timestamp: Duration(minutes: min, seconds: sec, milliseconds: ms),
            text: text,
          ),
        );
      }
    }

    lines.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final mergedLines = _mergeSameTimestampLines(lines);

    return LyricsDocument(
      title: title,
      artist: artist,
      lines: mergedLines,
      format: LyricsFormat.lrc,
    );
  }

  static List<LyricsLine> _mergeSameTimestampLines(List<LyricsLine> lines) {
    final merged = <LyricsLine>[];
    for (final line in lines) {
      if (merged.isEmpty || merged.last.timestamp != line.timestamp) {
        merged.add(line);
        continue;
      }

      final previous = merged.last;
      final knownTexts = {
        previous.text,
        if (previous.translation != null) previous.translation!,
      };
      if (knownTexts.contains(line.text)) continue;
      merged[merged.length - 1] = LyricsLine(
        timestamp: previous.timestamp,
        text: previous.text,
        translation: previous.translation ?? line.text,
        words: previous.words,
      );
    }
    return merged;
  }

  /// Parse KRC format (Kugou - decrypted content)
  static LyricsDocument _parseKrc(String content) {
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
          words.add(
            WordTiming(
              word: word,
              start: Duration(milliseconds: currentMs),
              duration: Duration(milliseconds: wordDuration),
            ),
          );
          currentMs += wordDuration;
        }
      }

      final text = textContent.replaceAll(RegExp(r'<[^>]+>'), '').trim();
      if (text.isEmpty) continue;
      lines.add(
        LyricsLine(
          timestamp: Duration(milliseconds: timestamp),
          text: text,
          words: words.isNotEmpty ? words : null,
        ),
      );
    }

    lines.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    return LyricsDocument(lines: lines, format: LyricsFormat.krc);
  }

  /// Parse QRC format (QQ Music - decrypted content)
  static LyricsDocument _parseQrc(String content) {
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
        words.add(
          WordTiming(
            word: word,
            start: Duration(milliseconds: timestamp + wordStart),
            duration: Duration(milliseconds: wordDuration),
          ),
        );
      }

      lines.add(
        LyricsLine(
          timestamp: Duration(milliseconds: timestamp),
          text: text,
          words: words.isNotEmpty ? words : null,
        ),
      );
    }

    lines.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    return LyricsDocument(lines: lines, format: LyricsFormat.qrc);
  }
}
