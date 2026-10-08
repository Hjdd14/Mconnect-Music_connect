import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../models/album.dart';
import '../../models/artist.dart';
import '../../models/platform_type.dart';
import '../../models/song.dart';

/// The three interchange formats a playlist can leave and re-enter the app in.
///
/// All three are **text**: export produces a string (which the share sheet or
/// the clipboard carries) and import parses a string. None of them references an
/// external audio source — a transfer document only ever describes songs the
/// user already has in their own playlists, which is the compliance boundary
/// this feature is built inside.
enum PlaylistTransferFormat {
  /// `.m3u8` — what Navidrome, Namida, VLC and foobar2000 read.
  m3u8,

  /// One `歌名 - 歌手` per line — the lowest common denominator several
  /// cross-service movers accept as input.
  text,

  /// This app's own JSON, carrying `platform` + `id` so a round trip is exact.
  json;

  /// File extension a saved export should use.
  String get extension => switch (this) {
    PlaylistTransferFormat.m3u8 => 'm3u8',
    PlaylistTransferFormat.text => 'txt',
    PlaylistTransferFormat.json => 'json',
  };

  /// User-facing name, used by the export sheet.
  String get label => switch (this) {
    PlaylistTransferFormat.m3u8 => 'M3U8 播放列表',
    PlaylistTransferFormat.text => '纯文本（歌名 - 歌手）',
    PlaylistTransferFormat.json => 'Mconnect JSON',
  };
}

/// Separator between the title and the artist in every transfer format.
///
/// One constant for m3u8's `#EXTINF` display text and the plain-text rows: both
/// formats carry the same `歌名 - 歌手` convention and both inherit the same
/// ambiguity, so they must not be able to drift apart on it.
const String transferSeparator = ' - ';

/// The two readings of one `A - B` display line.
@immutable
class DisplaySplit {
  const DisplaySplit({
    required this.title,
    this.artists = const <String>[],
    this.alternateTitle,
    this.alternateArtists = const <String>[],
  });

  final String title;
  final List<String> artists;

  /// The swapped reading, present only when the line had a separator.
  final String? alternateTitle;
  final List<String> alternateArtists;

  bool get hasAlternate => alternateTitle != null;
}

/// Splits a `A - B` display line into the reading this app commits to
/// (`歌名 - 歌手`, its own export order) plus the swapped one.
///
/// `A - B` is genuinely ambiguous — third-party movers export `歌名 - 歌手` while
/// a hand-written list is just as often `歌手 - 歌名`, and nothing in the line
/// says which. Rather than guess once and be wrong half the time, the committed
/// reading is tried first and the swapped reading is kept for the matcher to
/// fall back on (see `TransferMatcher`).
///
/// A line with no separator, or one whose separator is at an edge, is taken at
/// face value with no alternate reading.
DisplaySplit splitDisplayLine(String display) {
  final text = display.trim();
  if (text.isEmpty) return const DisplaySplit(title: '');
  final index = text.indexOf(transferSeparator);
  if (index <= 0) return DisplaySplit(title: text);

  final left = text.substring(0, index).trim();
  final right = text.substring(index + transferSeparator.length).trim();
  if (left.isEmpty || right.isEmpty) return DisplaySplit(title: text);

  return DisplaySplit(
    title: left,
    artists: <String>[right],
    alternateTitle: right,
    alternateArtists: <String>[left],
  );
}

/// Best-effort song title from a bare [locator] line.
///
/// An m3u8 entry whose locator has no preceding `#EXTINF` still has to become a
/// row — dropping it would be the silent data loss this feature exists to
/// prevent — so the file name stands in for the title.
String? titleFromLocator(String locator) {
  final withoutQuery = locator.split('?').first;
  final segments = withoutQuery.split(RegExp(r'[/\\]'));
  var last = segments.isEmpty ? withoutQuery : segments.last;
  if (last.isEmpty) return null;
  final dot = last.lastIndexOf('.');
  if (dot > 0) last = last.substring(0, dot);
  final trimmed = last.trim();
  return trimmed.isEmpty ? null : trimmed;
}

/// One row of a transfer document, before it has been matched to a playable song.
///
/// The three codecs all normalise into this shape, so the matcher and the report
/// never have to know which format the row came from.
@immutable
class TransferEntry {
  const TransferEntry({
    required this.title,
    this.artists = const <String>[],
    this.duration = Duration.zero,
    this.platform,
    this.id,
    this.locator,
    this.sourceLine,
    this.albumName,
    this.albumCover,
    this.alternateTitle,
    this.alternateArtists = const <String>[],
  });

  /// Song title. A blank line is skipped by the codecs rather than turned into
  /// an entry, so this is non-empty for anything that came out of a parser.
  final String title;

  /// Artist names, in the order the document listed them.
  final List<String> artists;

  /// Zero when the document did not carry a length.
  final Duration duration;

  /// Set only when the source carried an exact platform + id (our own JSON, or
  /// an `mconnect://song` locator inside an m3u8). Such a row needs no matching.
  final PlatformType? platform;

  /// Platform-native song id; meaningful only together with [platform].
  final String? id;

  /// The raw locator line (URL or filesystem path), kept so a report can hand
  /// the original back to the user when nothing matched.
  final String? locator;

  /// The line this entry was parsed from, quoted verbatim in reports.
  final String? sourceLine;

  /// Album name / cover, when the source carried them.
  ///
  /// Only this app's own JSON does, and it stores exactly the two fields the
  /// `mconnect://playlist?data=…` share link stores, so a JSON export
  /// round-trips a playlist without losing its artwork. m3u8 and the
  /// `歌名 - 歌手` text format leave both null.
  final String? albumName;
  final String? albumCover;

  /// The other reading of an ambiguous line.
  ///
  /// `A - B` in a plain-text list is genuinely ambiguous: third-party movers
  /// export `歌名 - 歌手` while a hand-written list is just as often
  /// `歌手 - 歌名`, and nothing in the line tells the two apart. The codec
  /// commits to `歌名 - 歌手` (the app's own export order) and records the
  /// swapped reading here; the matcher runner tries the alternate only when the
  /// primary reading resolves nothing.
  final String? alternateTitle;

  /// Artists under the [alternateTitle] reading.
  final List<String> alternateArtists;

  /// Builds a row from a `A - B` display line (an m3u8 `#EXTINF` payload or a
  /// plain-text row), carrying both readings via [splitDisplayLine].
  factory TransferEntry.fromDisplayLine(
    String display, {
    Duration duration = Duration.zero,
    PlatformType? platform,
    String? id,
    String? locator,
    String? sourceLine,
  }) {
    final split = splitDisplayLine(display);
    return TransferEntry(
      title: split.title,
      artists: split.artists,
      duration: duration,
      platform: platform,
      id: id,
      locator: locator,
      sourceLine: sourceLine,
      alternateTitle: split.alternateTitle,
      alternateArtists: split.alternateArtists,
    );
  }

  bool get hasExactIdentity =>
      platform != null && id != null && id!.trim().isNotEmpty;

  /// True when this row has a second reading worth trying.
  bool get hasAlternate => alternateTitle != null;

  String get artistNames => artists.join(', ');

  /// `歌名 - 歌手`, or just the title when no artist is known.
  String get display => artists.isEmpty || artistNames.trim().isEmpty
      ? title
      : '$title - $artistNames';

  /// The same row under its other reading, or null when there is none.
  TransferEntry? get alternate => alternateTitle == null
      ? null
      : TransferEntry(
          title: alternateTitle!,
          artists: alternateArtists,
          duration: duration,
          locator: locator,
          sourceLine: sourceLine,
          albumName: albumName,
          albumCover: albumCover,
        );

  /// The song this row already identifies, or null when it must be matched.
  Song? toSong() {
    if (!hasExactIdentity) return null;
    return Song(
      id: id!,
      platform: platform!,
      name: title,
      artists: artists.isEmpty
          ? const <Artist>[Artist(id: '', name: '未知歌手')]
          : artists
                .map((name) => Artist(id: '', name: name))
                .toList(growable: false),
      album: albumName == null
          ? null
          : Album(id: '', name: albumName!, coverUrl: albumCover),
      duration: duration,
      coverUrl: albumCover,
    );
  }
}

/// A parsed transfer document: what a string said, before any matching.
@immutable
class TransferDocument {
  const TransferDocument({
    required this.name,
    required this.entries,
    required this.format,
  });

  final String name;
  final List<TransferEntry> entries;
  final PlaylistTransferFormat format;

  bool get isEmpty => entries.isEmpty;
  int get length => entries.length;
}

/// Largest payload a QR code should carry for a phone camera to read reliably.
///
/// A version-40 QR at medium error correction technically holds roughly 2.3 kB,
/// but that is a controlled-lighting upper bound. On a phone screen at arm's
/// length, scanning starts to fail in practice well before it — and the playlist
/// share link is base64url JSON of every song, so it outgrows any budget fast.
const int maxQrPayloadBytes = 1200;

/// Whether [payload] fits in a scannable QR code.
bool isQrShareable(String payload, {int maxBytes = maxQrPayloadBytes}) {
  final trimmed = payload.trim();
  if (trimmed.isEmpty) return false;
  return utf8.encode(trimmed).length <= maxBytes;
}

/// What the QR code should carry for a playlist share [link].
///
/// Returns null when the link is too large to scan, which is the normal case for
/// a long playlist: the caller must then offer the text share instead of drawing
/// a QR code that no camera can read.
String? qrPayloadForPlaylistLink(
  String link, {
  int maxBytes = maxQrPayloadBytes,
}) {
  final trimmed = link.trim();
  return isQrShareable(trimmed, maxBytes: maxBytes) ? trimmed : null;
}
