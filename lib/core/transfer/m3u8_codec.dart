import 'package:flutter/foundation.dart';

import '../../models/song.dart';
import '../share/share_links.dart';
import 'transfer_format.dart';

/// How an m3u8 export renders the locator line of each entry.
@immutable
class M3u8ExportOptions {
  const M3u8ExportOptions({this.pathFor});

  /// When set, each entry line is a filesystem path instead of the default
  /// `mconnect://song…` locator — for handing the file to a server (Navidrome)
  /// or a player that resolves paths against its own music root. The caller owns
  /// any prefix it wants, e.g.
  /// `M3u8ExportOptions(pathFor: (s) => '$root/${s.artistNames} - ${s.name}.mp3')`.
  ///
  /// Note that a path locator is **export-only**: nothing in the app can turn a
  /// path back into a song, so such a file re-imports as unmatched rows (which
  /// the report then shows) unless the songs are also identified another way.
  final String Function(Song song)? pathFor;
}

/// Extended M3U (`#EXTM3U`) encode/decode.
///
/// The default locator is an `mconnect://song…` share link rather than a path:
/// it is the only locator this app can turn back into a concrete song with no
/// network and no ambiguity, which is what makes export → import a real round
/// trip. The `#EXTINF` row is still written in full so a third-party player (or
/// a human) can read the file.
abstract final class M3u8Codec {
  /// The first line of every extended M3U.
  static const String header = '#EXTM3U';

  /// `#PLAYLIST:<name>` — the directive most players understand as the title.
  static const String playlistTag = '#PLAYLIST:';

  /// `#EXTINF:` — per-entry duration + display title.
  static const String infoTag = '#EXTINF:';

  /// Encodes [songs] as an extended M3U with [name] as the playlist title.
  static String encode({
    required String name,
    required List<Song> songs,
    M3u8ExportOptions options = const M3u8ExportOptions(),
  }) {
    final buffer = StringBuffer()
      ..writeln(header)
      ..writeln('$playlistTag${_cleanName(name)}');
    for (final song in songs) {
      final title = song.name.trim();
      // A song with no title has nothing to write and nothing to match on.
      if (title.isEmpty) continue;
      final artists = song.artistNames.trim();
      final display = artists.isEmpty
          ? title
          : '$title$transferSeparator$artists';
      buffer.writeln('$infoTag${song.duration.inSeconds},$display');
      buffer.writeln(_locatorFor(song, options));
    }
    return buffer.toString();
  }

  /// The locator line: the caller's path when it supplied one, otherwise this
  /// app's own `mconnect://song` link (the only locator that round-trips).
  static String _locatorFor(Song song, M3u8ExportOptions options) {
    final path = options.pathFor?.call(song).trim();
    if (path != null && path.isNotEmpty) return path;
    return ShareLinks.songLink(song);
  }

  static String _cleanName(String name) {
    final trimmed = name.trim();
    return trimmed.isEmpty ? '未命名歌单' : trimmed;
  }

  /// Parses [text] as extended M3U.
  ///
  /// Returns null only when the text is not an m3u8 at all — neither an
  /// `#EXTM3U` header nor a single `#EXTINF` row. An m3u8 with zero entries (an
  /// empty export) therefore decodes to an **empty document**, not to null, so
  /// the caller can tell "an empty playlist" apart from "not my format" by
  /// checking [TransferDocument.isEmpty].
  ///
  /// Never drops a row: a locator line with no preceding `#EXTINF` still becomes
  /// an entry, named after the file itself.
  static TransferDocument? decode(String text) {
    var hasHeader = false;
    var hasInfo = false;
    var name = '导入歌单';
    final entries = <TransferEntry>[];

    String? pendingTitle;
    List<String> pendingArtists = const <String>[];
    String? pendingAlternateTitle;
    List<String> pendingAlternateArtists = const <String>[];
    var pendingDuration = Duration.zero;

    void clearPending() {
      pendingTitle = null;
      pendingArtists = const <String>[];
      pendingAlternateTitle = null;
      pendingAlternateArtists = const <String>[];
      pendingDuration = Duration.zero;
    }

    for (final raw in text.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;

      if (line.startsWith(header)) {
        hasHeader = true;
        continue;
      }
      if (line.startsWith(playlistTag)) {
        final parsed = line.substring(playlistTag.length).trim();
        if (parsed.isNotEmpty) name = parsed;
        continue;
      }
      if (line.startsWith(infoTag)) {
        hasInfo = true;
        final payload = line.substring(infoTag.length);
        final comma = payload.indexOf(',');
        final secondsText = comma == -1 ? payload : payload.substring(0, comma);
        final display = comma == -1 ? '' : payload.substring(comma + 1);
        // `#EXTINF:-1` is the standard "length unknown" marker, not -1 seconds.
        final seconds = int.tryParse(secondsText.trim()) ?? -1;
        pendingDuration = seconds > 0
            ? Duration(seconds: seconds)
            : Duration.zero;

        final split = splitDisplayLine(display);
        pendingTitle = split.title.isEmpty ? null : split.title;
        pendingArtists = split.artists;
        pendingAlternateTitle = split.alternateTitle;
        pendingAlternateArtists = split.alternateArtists;
        continue;
      }
      if (line.startsWith('#')) continue;

      // A locator line closes whatever `#EXTINF` preceded it.
      final resolved = ShareLinks.parseSongLink(line);
      final title = pendingTitle ?? titleFromLocator(line);
      if (title == null || title.isEmpty) {
        clearPending();
        continue;
      }
      entries.add(
        TransferEntry(
          title: title,
          artists: pendingArtists,
          duration: pendingDuration,
          platform: resolved?.platform,
          id: resolved?.id,
          locator: line,
          sourceLine: line,
          alternateTitle: pendingAlternateTitle,
          alternateArtists: pendingAlternateArtists,
        ),
      );
      clearPending();
    }

    if (!hasHeader && !hasInfo) return null;
    return TransferDocument(
      name: name,
      entries: entries,
      format: PlaylistTransferFormat.m3u8,
    );
  }
}
