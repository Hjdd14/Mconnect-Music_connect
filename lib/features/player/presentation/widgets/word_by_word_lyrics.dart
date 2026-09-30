import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../../../lyrics/lyrics_progress.dart';
import '../../../../lyrics/models/lyrics_line.dart';

/// Renders one lyric line with the already-played characters in [playedColor]
/// and the rest in [baseColor].
///
/// Character spans (rather than a gradient mask) are used deliberately: when a
/// line wraps onto several rows, a single horizontal gradient colours every row
/// at once, while spans follow the text in reading order — the first row fills
/// up, then the next one.
///
/// Font size/weight are inherited from the surrounding `DefaultTextStyle` (the
/// in-app list animates them), so only colors are set here.
class PlayedLyricsText extends StatelessWidget {
  final String text;
  final int playedCharacters;
  final ValueListenable<int>? progressListenable;
  final Color playedColor;
  final Color baseColor;
  final Key? primaryKey;
  final TextAlign textAlign;

  const PlayedLyricsText({
    super.key,
    required this.text,
    required this.playedCharacters,
    required this.playedColor,
    required this.baseColor,
    this.progressListenable,
    this.primaryKey,
    this.textAlign = TextAlign.center,
  });

  @override
  Widget build(BuildContext context) {
    final listenable = progressListenable;
    if (listenable == null) {
      return _build(playedCharacters);
    }
    return ValueListenableBuilder<int>(
      valueListenable: listenable,
      builder: (context, value, _) => _build(value),
    );
  }

  Widget _build(int played) {
    final count = played.clamp(0, text.length);
    if (count <= 0) {
      return Text(
        text,
        key: primaryKey,
        textAlign: textAlign,
        style: TextStyle(color: baseColor),
      );
    }
    if (count >= text.length) {
      return Text(
        text,
        key: primaryKey,
        textAlign: textAlign,
        style: TextStyle(color: playedColor),
      );
    }
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: text.substring(0, count),
            style: TextStyle(color: playedColor),
          ),
          TextSpan(
            text: text.substring(count),
            style: TextStyle(color: baseColor),
          ),
        ],
      ),
      key: primaryKey,
      textAlign: textAlign,
    );
  }
}

/// Renders a single lyrics line with word-by-word color progression.
/// Used for QRC (QQ) and KRC (Kugou) formats that have per-word timing; the
/// played prefix comes from the shared progress helper so the in-app lyrics and
/// the floating overlay agree on where the sweep is.
class WordByWordLine extends StatelessWidget {
  final LyricsLine line;
  final Duration currentPosition;
  final bool isCurrentLine;
  final Key? primaryKey;
  final VoidCallback? onTap;

  /// Pre-computed played character count. When omitted it is derived from
  /// [currentPosition] for the current line.
  final int? playedCharacters;

  /// Per-frame played character count; null when not animating.
  final ValueListenable<int>? progressListenable;

  const WordByWordLine({
    super.key,
    required this.line,
    required this.currentPosition,
    required this.isCurrentLine,
    this.primaryKey,
    this.onTap,
    this.playedCharacters,
    this.progressListenable,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    if (!isCurrentLine) {
      return GestureDetector(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              line.text,
              key: line.text.trim().isNotEmpty ? primaryKey : null,
              style: TextStyle(fontSize: 16, color: colors.outline),
              textAlign: TextAlign.center,
            ),
            if (line.hasTranslation) _TranslationText(line: line),
          ],
        ),
      );
    }

    final played =
        playedCharacters ?? playedCharacterCount(line, currentPosition);
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DefaultTextStyle(
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            child: PlayedLyricsText(
              text: line.text,
              playedCharacters: played,
              progressListenable: progressListenable,
              playedColor: colors.primary,
              baseColor: colors.onSurface,
              primaryKey: line.text.trim().isNotEmpty ? primaryKey : null,
            ),
          ),
          if (line.hasTranslation) _TranslationText(line: line),
        ],
      ),
    );
  }
}

class _TranslationText extends StatelessWidget {
  final LyricsLine line;

  const _TranslationText({required this.line});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        line.translation!,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 13,
          color: Theme.of(context).colorScheme.outline,
          height: 1.4,
        ),
      ),
    );
  }
}
