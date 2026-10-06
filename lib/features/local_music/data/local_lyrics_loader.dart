import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;

import '../../../lyrics/models/lyrics_line.dart';

/// A lyric file that was successfully decoded into a format the existing
/// lyrics pipeline understands.
class LocalLyricsPayload {
  final String content;
  final LyricsFormat format;

  const LocalLyricsPayload({required this.content, required this.format});

  String get formatName => format.name;
}

/// Reads the sidecar lyric file that sits next to a local audio file.
///
/// Formats:
/// * `.lrc` / `.txt` — stored verbatim (the existing LRC parser handles both
///   timed and untimed text);
/// * `.krc` — Kugou ships it **encrypted**, so it is decrypted first
///   (base64 → drop the 4-byte header → XOR with the 16-byte key → zlib
///   inflate → UTF-8). This mirrors `kugou_api.dart:516` `_decryptKrc`; the
///   copy is deliberate, `lib/platform/kugou/**` belongs to another
///   workstream and exposing that private method would be a cross-workstream
///   edit;
/// * `.qrc` — QQ desktop writes it as plain `<L T=… D=…>` XML.
///
/// A `.krc`/`.qrc` that cannot be decoded is **rejected** (returns `null`)
/// instead of being stored as ciphertext: the old scanner read every lyric file
/// with `readText()` and handed the bytes to the LRC parser, which is why
/// encrypted KRC showed up as a single garbage line — or, worse, printed base64.
class LocalLyricsLoader {
  static const supportedExtensions = {'.lrc', '.krc', '.qrc', '.txt'};

  /// The 16-byte KRC XOR key, identical to the Kugou client implementation.
  static const List<int> krcKey = [
    0x40, 0x47, 0x61, 0x77, 0x5e, 0x32, 0x74, 0x47,
    0x51, 0x36, 0x31, 0x2d, 0xce, 0xd2, 0x6e, 0x69,
  ];

  /// Loads [lyricsPath], or returns `null` when the file is missing, empty or
  /// could not be decoded into non-empty timed lines.
  Future<LocalLyricsPayload?> load(String lyricsPath) async {
    final extension = p.extension(lyricsPath).toLowerCase();
    if (!supportedExtensions.contains(extension)) return null;

    String raw;
    try {
      raw = await File(lyricsPath).readAsString();
    } catch (_) {
      return null;
    }
    return decode(raw, extension);
  }

  /// Decodes raw lyric text by extension.
  ///
  /// Split out from [load] because the Android path cannot read a `content://`
  /// URI with `dart:io`: `MainActivity` reads the sidecar file and hands the
  /// text over, and this is where it gets decrypted/validated.
  static LocalLyricsPayload? decode(String raw, String extension) {
    final normalized = extension.toLowerCase();
    if (!supportedExtensions.contains(normalized)) return null;
    if (raw.trim().isEmpty) return null;
    switch (normalized) {
      case '.krc':
        final decrypted = decryptKrc(raw);
        if (decrypted == null) return null;
        return _accept(decrypted, LyricsFormat.krc);
      case '.qrc':
        if (!_looksLikeQrc(raw)) return null;
        return _accept(raw, LyricsFormat.qrc);
      default:
        // `.lrc` / `.txt`: kept verbatim, exactly as before. These are also the
        // only formats allowed to be untimed plain text.
        return LocalLyricsPayload(content: raw, format: LyricsFormat.lrc);
    }
  }

  /// True when [content] parses into at least one timed line for [format].
  ///
  /// This is what stops a mis-named `.lrc`-holding-junk (or a decrypted
  /// payload that turned out to be something else) from being persisted as
  /// "lyrics": nothing parseable means nothing stored.
  static bool parsesToLines(String content, LyricsFormat format) {
    try {
      return LyricsDocument.parse(content, format).lines.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static LocalLyricsPayload? _accept(String content, LyricsFormat format) {
    if (!parsesToLines(content, format)) return null;
    return LocalLyricsPayload(content: content, format: format);
  }

  static bool _looksLikeQrc(String raw) =>
      raw.contains('<L ') && raw.contains('</L>');

  /// Decrypts a KRC payload. Returns `null` on any malformed input.
  ///
  /// Visible for testing: the test encrypts a fixture with the inverse
  /// transform, so a change to either the key or the byte order fails loudly
  /// instead of silently producing garbage lyrics.
  static String? decryptKrc(String raw) {
    try {
      final data = base64.decode(raw.trim());
      if (data.length <= 4) return null;

      // The first 4 bytes are a header (the KRC key length); the body is XORed
      // with the 16-byte key and then zlib-compressed.
      final body = data.sublist(4);
      final decrypted = List<int>.generate(
        body.length,
        (i) => body[i] ^ krcKey[i % krcKey.length],
        growable: false,
      );
      final inflated = zlib.decode(decrypted);
      if (inflated.isEmpty) return null;
      final text = utf8.decode(inflated, allowMalformed: true);
      return text.trim().isEmpty ? null : text;
    } catch (_) {
      return null;
    }
  }

  /// Inverse of [decryptKrc], used by the tests (and by nothing else).
  @visibleForTesting
  static String encryptKrcForTest(String plainText, {int header = 4}) {
    final compressed = zlib.encode(utf8.encode(plainText));
    final xored = List<int>.generate(
      compressed.length,
      (i) => compressed[i] ^ krcKey[i % krcKey.length],
      growable: false,
    );
    return base64.encode([...List<int>.filled(header, 0), ...xored]);
  }
}
