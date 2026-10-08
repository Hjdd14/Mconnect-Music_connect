import 'json_codec.dart';
import 'm3u8_codec.dart';
import 'text_codec.dart';
import 'transfer_format.dart';

/// The one entry point the import page uses: work out what [text] is and parse
/// it, or return null when nothing recognises it.
///
/// Detection is by **structure, not by file name** — the import page receives
/// pasted text and share payloads, neither of which carries an extension. The
/// order matters:
///
/// 1. an `#EXTM3U`/`#EXTINF` header wins outright, because a plain-text reader
///    would happily turn every directive into a bogus song title;
/// 2. our own JSON is recognised by its `format` tag, so a foreign `.json` is
///    rejected instead of parsed into an empty playlist;
/// 3. anything else is treated as `歌名 - 歌手` lines.
///
/// Returns null when the text is blank or yields no entry at all.
TransferDocument? decodePlaylistTransfer(String text, {String name = '导入歌单'}) {
  final m3u8 = M3u8Codec.decode(text);
  if (m3u8 != null && !m3u8.isEmpty) return m3u8;

  final json = PlaylistJsonCodec.decode(text);
  if (json != null && !json.isEmpty) return json;

  final plain = PlaylistTextCodec.decode(text, name: name);
  if (plain != null && !plain.isEmpty) return plain;

  return null;
}

/// True for text this app could plausibly import, without parsing it fully.
///
/// Used by the deep-link handler to decide whether a shared payload is worth
/// routing to the import page at all — a share that carries nothing importable
/// must not move the user somewhere surprising.
bool looksLikePlaylistTransfer(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return false;
  if (trimmed.contains(M3u8Codec.header)) return true;
  if (trimmed.contains(PlaylistJsonCodec.formatTag)) return true;
  // A plain list needs at least two non-empty lines to be worth treating as a
  // playlist rather than as prose that happens to have a newline.
  final lines = trimmed
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty && !line.startsWith('#'))
      .take(2)
      .length;
  return lines >= 2;
}
