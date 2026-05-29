import 'package:flutter/material.dart';
import '../../../../lyrics/models/lyrics_line.dart';

/// Renders a single lyrics line with word-by-word color progression.
/// Used for QRC (QQ) and KRC (Kugou) formats that have per-word timing.
class WordByWordLine extends StatelessWidget {
  final LyricsLine line;
  final Duration currentPosition;
  final bool isCurrentLine;
  final VoidCallback? onTap;

  const WordByWordLine({
    super.key,
    required this.line,
    required this.currentPosition,
    required this.isCurrentLine,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (!isCurrentLine || !line.hasWordTiming) {
      return GestureDetector(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              line.text,
              style: TextStyle(
                fontSize: isCurrentLine ? 20 : 16,
                fontWeight: isCurrentLine ? FontWeight.bold : FontWeight.normal,
                color: isCurrentLine
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.outline,
              ),
              textAlign: TextAlign.center,
            ),
            if (line.hasTranslation) _TranslationText(line: line),
          ],
        ),
      );
    }

    final words = line.words!;
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          RichText(
            textAlign: TextAlign.center,
            text: TextSpan(
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.outline,
              ),
              children: words.map((w) {
                final isPlayed = currentPosition >= w.start + w.duration;
                final isPlaying = currentPosition >= w.start &&
                    currentPosition < w.start + w.duration;
                final color = isPlayed || isPlaying
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.outline;

                return TextSpan(
                  text: w.word,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                  ),
                );
              }).toList(),
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
