import 'package:flutter/foundation.dart';

import 'lyrics_line.dart';

/// One platform's raw lyric tracks for a song, **kept separate per format**.
///
/// They are deliberately not pre-concatenated: `lrc`, `translation` and `romaji`
/// are ordinary LRC, while `yrc` is NetEase's word-by-word format — a different
/// *format*, not a richer LRC. Concatenating them would hand a `yrc` line to the
/// LRC parser, which silently ignores it (the leading `[start,dur]` has no
/// colons). See `docs/netease-lyric-shapes.md` for the observed shapes.
@immutable
class LyricsBundle {
  /// The plain, line-timed lyrics.
  final String? lrc;

  /// The translation track (`tlyric`), line-timed, same timestamps as [lrc].
  final String? translation;

  /// NetEase word-by-word lyrics (`yrc`), or null when the song has none — which
  /// is the common case (2 of 8 probed tracks had one).
  final String? yrc;

  /// QQ word-timed lyrics (`qrc`), or null when the server sent an encrypted or
  /// unrecognised body — see `QqPlatform.getLyricsBundle`.
  final String? qrc;

  /// Romanisation (`romalrc` / `yromalrc`), line-timed LRC.
  final String? romaji;

  const LyricsBundle({
    this.lrc,
    this.translation,
    this.yrc,
    this.qrc,
    this.romaji,
  });

  bool get isEmpty =>
      _isBlank(lrc) &&
      _isBlank(translation) &&
      _isBlank(yrc) &&
      _isBlank(qrc) &&
      _isBlank(romaji);

  static bool _isBlank(String? value) => value == null || value.trim().isEmpty;
}

/// The track that becomes the displayed text: word-by-word first, `lrc` second.
///
/// The yrc candidate must actually **parse** before it wins: `yrc` availability
/// is per song, and a payload that is present but unusable must fall back to a
/// usable `lrc` instead of rendering "暂无歌词". Returns null when the bundle
/// carries no usable text at all.
({String content, LyricsFormat format})? mainLyricsTrack(LyricsBundle bundle) {
  final yrc = bundle.yrc;
  if (yrc != null &&
      yrc.trim().isNotEmpty &&
      LyricsDocument.parsesToLines(yrc, LyricsFormat.yrc)) {
    return (content: yrc, format: LyricsFormat.yrc);
  }
  final qrc = bundle.qrc;
  if (qrc != null &&
      qrc.trim().isNotEmpty &&
      LyricsDocument.parsesToLines(qrc, LyricsFormat.qrc)) {
    return (content: qrc, format: LyricsFormat.qrc);
  }
  final lrc = bundle.lrc;
  if (lrc != null && lrc.trim().isNotEmpty) {
    // The field is *named* `lrc`, but a single-payload platform hands whatever it
    // has through the default `getLyricsBundle` — for Kugou that is often
    // encrypted-then-decrypted KRC, whose `[start,duration]` lines an LRC parser
    // cannot see. Keep the marker sniffing here, validated by parsing, or the
    // whole song goes back to "暂无歌词" (the W0-B bug).
    return (
      content: lrc,
      format: LyricsDocument.sniffFormat(lrc, const [
        LyricsFormat.qrc,
        LyricsFormat.krc,
        LyricsFormat.lrc,
      ]),
    );
  }
  return null;
}

/// The displayable document for [bundle].
///
/// Translations are merged by **exact timestamp** rather than by concatenating
/// the two tracks and letting the LRC parser pair same-timestamp lines: that
/// trick cannot work for `yrc`, whose timestamps are not LRC timestamps.
LyricsDocument buildLyricsDocument(
  LyricsBundle bundle, {
  LyricsSource source = LyricsSource.unknown,
}) {
  final track = mainLyricsTrack(bundle);
  if (track == null) return LyricsDocument(source: source);

  final document = LyricsDocument.parse(
    track.content,
    track.format,
    source: source,
  );
  if (document.lines.isEmpty) return document;

  final translation = bundle.translation;
  if (translation == null || translation.trim().isEmpty) return document;
  return _withTranslations(
    document,
    LyricsDocument.parse(translation, LyricsFormat.lrc),
  );
}

LyricsDocument _withTranslations(
  LyricsDocument document,
  LyricsDocument translations,
) {
  final byTimestamp = <Duration, String>{};
  for (final line in translations.lines) {
    final text = line.text.trim();
    if (text.isEmpty) continue;
    byTimestamp.putIfAbsent(line.timestamp, () => text);
  }
  if (byTimestamp.isEmpty) return document;

  return LyricsDocument(
    title: document.title,
    artist: document.artist,
    format: document.format,
    source: document.source,
    lines: [
      for (final line in document.lines)
        line.hasTranslation
            ? line
            : line.withTranslation(byTimestamp[line.timestamp]),
    ],
  );
}
