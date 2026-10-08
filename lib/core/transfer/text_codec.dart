import '../../models/song.dart';
import 'transfer_format.dart';

/// The `歌名 - 歌手` plain-text format.
///
/// This is the exchange format cross-service movers accept, so the encoder is
/// deliberately lossy: one line per song, no ids, no metadata. Import is
/// therefore always a *matching* problem, never a lookup — see
/// [TransferEntry.alternateTitle] for the ambiguity that creates.
abstract final class PlaylistTextCodec {
  /// Separator between title and artist, and between the two readings of an
  /// ambiguous line. Aliases [transferSeparator] so callers have one name for it.
  static const String separator = transferSeparator;

  /// One `歌名 - 歌手` per line; a song with no artist is just its title.
  static String encode({required List<Song> songs}) {
    final lines = <String>[];
    for (final song in songs) {
      final title = song.name.trim();
      // A song with no title has nothing to write and nothing to match on.
      if (title.isEmpty) continue;
      final artists = song.artistNames.trim();
      lines.add(
        artists.isEmpty ? title : '$title$transferSeparator$artists',
      );
    }
    return lines.join('\n');
  }

  /// Parses one `歌名 - 歌手` (or `歌手 - 歌名`) per line.
  ///
  /// Blank lines and `#` comment lines are skipped, and so is any line carrying
  /// a URL — an m3u8 that reached us as text would otherwise turn its own entry
  /// locators into song titles. A line with no separator is taken at face value:
  /// a title with no artist. A line with a separator is split on the **first**
  /// occurrence and recorded with the swapped reading in
  /// [TransferEntry.alternateTitle].
  ///
  /// Returns null when [text] yields no usable line.
  static TransferDocument? decode(String text, {String name = '导入歌单'}) {
    final entries = <TransferEntry>[];
    for (final raw in text.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      if (line.contains('://')) continue;

      final entry = TransferEntry.fromDisplayLine(line, sourceLine: line);
      if (entry.title.isEmpty) continue;
      entries.add(entry);
    }

    if (entries.isEmpty) return null;
    return TransferDocument(
      name: name,
      entries: entries,
      format: PlaylistTransferFormat.text,
    );
  }
}
