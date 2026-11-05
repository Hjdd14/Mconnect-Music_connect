import 'package:flutter/foundation.dart';

import 'lyrics_animation_catalog.dart';

/// One render frame shared by every overlay surface
/// (docs/desktop-lyrics-protocol.md, section 2.1).
///
/// This is the desktop replacement for the old merged payload: the Android
/// overlay keeps receiving its legacy map (see [FloatingLyricsPayload]) while
/// Windows consumes frames, so both windows paint the same line at the same
/// highlight position.
@immutable
class LyricsOverlayFrame {
  const LyricsOverlayFrame({
    required this.text,
    this.translation,
    this.nextText = '',
    this.nextTranslation,
    this.lineIndex = -1,
    this.progress = 0,
    this.highlightProgress = 0,
    this.highlightRate = 0,
    this.wordSegments,
    this.isPlaying = false,
    this.hasSong = false,
    this.revision = 0,
    this.songTitle,
    this.artistName,
    this.albumName,
    this.coverUrl,
  });

  /// Frame with no lyric text. The native side treats it as "nothing to draw".
  static const LyricsOverlayFrame empty = LyricsOverlayFrame(text: '');

  /// The protocol caps the optional segment table at 32 entries.
  static const int maxWordSegments = 32;

  final String text;
  final String? translation;
  final String nextText;
  final String? nextTranslation;

  /// Index of [text] inside the lyrics document. A jump (seek) is visible to
  /// the native side as a delta of more than one, which is what tells it to
  /// snap instead of animate.
  final int lineIndex;

  /// Whole-song playback progress 0..1 (reserved for future rendering).
  final double progress;

  /// Already-sung fraction of [text], 0..1.
  final double highlightProgress;

  /// Progress per millisecond, used to keep the sweep smooth between frames.
  final double highlightRate;

  /// Ascending cumulative boundaries 0..1 for word-timed lyrics (QRC/KRC/YRC).
  final List<double>? wordSegments;

  final bool isPlaying;
  final bool hasSong;

  /// Increasing frame counter; the native side drops older frames.
  final int revision;

  final String? songTitle;
  final String? artistName;
  final String? albumName;
  final String? coverUrl;

  LyricsOverlayFrame copyWith({
    String? text,
    String? translation,
    String? nextText,
    String? nextTranslation,
    int? lineIndex,
    double? progress,
    double? highlightProgress,
    double? highlightRate,
    List<double>? wordSegments,
    bool? isPlaying,
    bool? hasSong,
    int? revision,
    String? songTitle,
    String? artistName,
    String? albumName,
    String? coverUrl,
  }) {
    return LyricsOverlayFrame(
      text: text ?? this.text,
      translation: translation ?? this.translation,
      nextText: nextText ?? this.nextText,
      nextTranslation: nextTranslation ?? this.nextTranslation,
      lineIndex: lineIndex ?? this.lineIndex,
      progress: progress ?? this.progress,
      highlightProgress: highlightProgress ?? this.highlightProgress,
      highlightRate: highlightRate ?? this.highlightRate,
      wordSegments: wordSegments ?? this.wordSegments,
      isPlaying: isPlaying ?? this.isPlaying,
      hasSong: hasSong ?? this.hasSong,
      revision: revision ?? this.revision,
      songTitle: songTitle ?? this.songTitle,
      artistName: artistName ?? this.artistName,
      albumName: albumName ?? this.albumName,
      coverUrl: coverUrl ?? this.coverUrl,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'text': text,
      'translation': translation,
      'nextText': nextText,
      'nextTranslation': nextTranslation,
      'lineIndex': lineIndex,
      'progress': progress.clamp(0.0, 1.0),
      'highlightProgress': highlightProgress.clamp(0.0, 1.0),
      'highlightRate': highlightRate < 0 ? 0.0 : highlightRate,
      'wordSegments': normalizeWordSegments(wordSegments),
      'isPlaying': isPlaying,
      'hasSong': hasSong,
      'revision': revision,
      'songTitle': songTitle,
      'artistName': artistName,
      'albumName': albumName,
      'coverUrl': coverUrl,
    };
  }

  /// Sends the frame to a sink whose surface only understands a subset of the
  /// fields (the Android legacy map). Kept next to [toJson] so the two shapes
  /// cannot drift apart silently.
  Map<String, Object?> toJsonFor(LyricsSurface surface) {
    final json = toJson();
    if (surface == LyricsSurface.taskbar) {
      // The taskbar strip has no room for the next line and never paints the
      // cover; dropping them keeps the 200 ms update small.
      json.remove('nextTranslation');
    }
    return json;
  }

  /// Clamps, drops non-ascending entries and truncates to 32 values.
  ///
  /// Returns null for an empty result: an absent table tells the native side
  /// "sweep evenly" instead of "sweep in zero steps".
  static List<double>? normalizeWordSegments(Iterable<double>? segments) {
    if (segments == null) return null;
    final normalized = <double>[];
    var previous = -1.0;
    for (final raw in segments) {
      final value = raw.clamp(0.0, 1.0).toDouble();
      if (value < previous) continue;
      normalized.add(value);
      previous = value;
      if (normalized.length == maxWordSegments) break;
    }
    return normalized.isEmpty ? null : List<double>.unmodifiable(normalized);
  }
}
