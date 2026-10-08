import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/song.dart';
import '../constants/app_constants.dart';
import 'share_links.dart';

/// Seam over the system share sheet.
///
/// `SharePlus` is a singleton over a platform channel, so it cannot be exercised
/// in a widget test (it would try to open a real share sheet). Everything above
/// this interface is testable with a fake channel; [SharePlusChannel] is the
/// only place that touches the plugin.
abstract class ShareChannel {
  /// Opens the system share sheet for [text].
  ///
  /// [origin] is required by iPadOS (`sharePositionOrigin`); on other platforms
  /// it is ignored. Callers pass the tapped widget's rect when they have one.
  Future<void> shareText(String text, {String? subject, Rect? origin});

  /// Opens the system share sheet for local [paths] (a generated PNG, a log file).
  ///
  /// [text] is the optional body sent alongside the files — the lyrics card uses
  /// it for the "歌名 - 歌手" line so a share target that drops attachments still
  /// shows something useful.
  Future<void> shareFiles(
    List<String> paths, {
    String? subject,
    String? text,
    Rect? origin,
  });
}

class SharePlusChannel implements ShareChannel {
  const SharePlusChannel();

  @override
  Future<void> shareText(String text, {String? subject, Rect? origin}) async {
    await SharePlus.instance.share(
      ShareParams(text: text, subject: subject, sharePositionOrigin: origin),
    );
  }

  @override
  Future<void> shareFiles(
    List<String> paths, {
    String? subject,
    String? text,
    Rect? origin,
  }) async {
    if (paths.isEmpty) return;
    await SharePlus.instance.share(
      ShareParams(
        files: [for (final path in paths) XFile(path)],
        subject: subject,
        text: text,
        sharePositionOrigin: origin,
      ),
    );
  }
}

/// Composes and sends the app's shareable payloads.
class ShareService {
  const ShareService(this._channel);

  final ShareChannel _channel;

  /// "歌名 - 歌手\n<mconnect://song…>"
  Future<void> shareSong(Song song, {Rect? origin}) {
    return _channel.shareText(
      buildSongShareText(song),
      subject: song.name,
      origin: origin,
    );
  }

  /// "歌单名（N 首）\n来自 Mconnect\n<mconnect://playlist…>"
  Future<void> sharePlaylist({
    required String name,
    required int songCount,
    required String link,
    Rect? origin,
  }) {
    return _channel.shareText(
      buildPlaylistShareText(name: name, songCount: songCount, link: link),
      subject: name,
      origin: origin,
    );
  }

  /// Shares an exported playlist *document* (m3u8 / `歌名 - 歌手` text / JSON).
  ///
  /// Distinct from [sharePlaylist] on purpose: that one sends the
  /// `mconnect://playlist` link, which only this app can import, while these
  /// three are the formats a third-party player, server or mover can read.
  /// [formatLabel] goes into the subject so the receiving app can say what it
  /// received.
  ///
  /// The payload is plain text: a `.m3u8` is a text file, so saving it under that
  /// extension is the user's step. Sharing it as an attachment is [shareFiles]'
  /// job (used by the lyrics card), and this method deliberately stays text-only
  /// so the text payloads above it keep working unchanged.
  Future<void> sharePlaylistExport({
    required String name,
    required String content,
    required String formatLabel,
    Rect? origin,
  }) {
    return _channel.shareText(
      content,
      subject: '${playlistDisplayName(name)}（$formatLabel）',
      origin: origin,
    );
  }

  /// Shares generated **local files**, e.g. the lyrics card PNG.
  ///
  /// [paths] must already exist on disk — this layer does no file I/O. The caller
  /// owns writing (and later cleaning up) the temporary file; see
  /// `lib/lyrics/lyrics_share_card.dart`.
  Future<void> shareFiles(
    List<String> paths, {
    String? subject,
    String? text,
    Rect? origin,
  }) {
    return _channel.shareFiles(
      paths,
      subject: subject,
      text: text,
      origin: origin,
    );
  }
}

/// `未命名歌单` when [name] is blank.
///
/// Shared by [buildPlaylistShareText] and [ShareService.sharePlaylistExport] so
/// the two cannot disagree about what an unnamed playlist is called.
String playlistDisplayName(String name) {
  final trimmed = name.trim();
  return trimmed.isEmpty ? '未命名歌单' : trimmed;
}

/// Text shared for a single song. Kept as a free function so the exact payload
/// is unit-testable without any channel.
String buildSongShareText(Song song) {
  return '${song.name} - ${song.artistNames}\n${ShareLinks.songLink(song)}';
}

/// Text shared for a playlist. [link] comes from
/// `MyPlaylistsNotifier.exportPlaylistLink` (or a platform share URL).
String buildPlaylistShareText({
  required String name,
  required int songCount,
  required String link,
}) {
  return '${playlistDisplayName(name)}（$songCount 首）\n'
      '来自 ${AppConstants.appName}\n$link';
}

final shareServiceProvider = Provider<ShareService>((ref) {
  return const ShareService(SharePlusChannel());
});
