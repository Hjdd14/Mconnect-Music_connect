import '../../models/song.dart';
import 'json_codec.dart';
import 'm3u8_codec.dart';
import 'text_codec.dart';

/// One way a user can take a playlist out of the app.
///
/// The list is deliberately short and non-technical: `link` and `qr` hand over
/// something only this app can read, while the other three are the formats a
/// third-party player, server or cross-service mover can read.
enum PlaylistExportChoice {
  /// The `mconnect://playlist?data=…` link (via `ShareService.sharePlaylist`).
  link,

  /// `.m3u8` — what Navidrome, Namida, VLC and foobar2000 read.
  m3u8,

  /// One `歌名 - 歌手` per line — what cross-service movers accept.
  text,

  /// This app's own JSON, carrying `platform` + `id` so it re-imports exactly.
  json,

  /// The same link as [link], drawn as a QR code for another phone to scan.
  qr;

  /// What the export sheet calls this choice.
  String get label => switch (this) {
    PlaylistExportChoice.link => '分享链接',
    PlaylistExportChoice.m3u8 => 'M3U8 播放列表',
    PlaylistExportChoice.text => '纯文本（歌名 - 歌手）',
    PlaylistExportChoice.json => 'Mconnect JSON',
    PlaylistExportChoice.qr => '二维码分享',
  };

  /// True for the choices whose payload is the songs themselves; the other two
  /// carry only the share link, so the page does not have to fetch the tracks
  /// for them.
  bool get carriesSongs => switch (this) {
    PlaylistExportChoice.m3u8 ||
    PlaylistExportChoice.text ||
    PlaylistExportChoice.json => true,
    PlaylistExportChoice.link || PlaylistExportChoice.qr => false,
  };

  /// True for the one choice that renders instead of sharing.
  bool get isRendered => this == PlaylistExportChoice.qr;
}

/// Builds the payload one [PlaylistExportChoice] produces.
///
/// Pure and codec-only on purpose: "is the exported m3u8 well-formed?" belongs in
/// a unit test over the codecs, not in a widget test over a share sheet. The page
/// only decides *which* choice was tapped.
abstract final class PlaylistExport {
  static String contentFor(
    PlaylistExportChoice choice, {
    required String name,
    required List<Song> songs,
    required String link,
  }) => switch (choice) {
    PlaylistExportChoice.m3u8 => M3u8Codec.encode(name: name, songs: songs),
    PlaylistExportChoice.text => PlaylistTextCodec.encode(songs: songs),
    PlaylistExportChoice.json =>
      PlaylistJsonCodec.encode(name: name, songs: songs),
    // The two link-based choices carry the link itself; `qr` only renders it.
    PlaylistExportChoice.link ||
    PlaylistExportChoice.qr => link,
  };
}
