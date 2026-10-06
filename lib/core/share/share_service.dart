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
}

class SharePlusChannel implements ShareChannel {
  const SharePlusChannel();

  @override
  Future<void> shareText(String text, {String? subject, Rect? origin}) async {
    await SharePlus.instance.share(
      ShareParams(text: text, subject: subject, sharePositionOrigin: origin),
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
  final title = name.trim().isEmpty ? '未命名歌单' : name.trim();
  return '$title（$songCount 首）\n来自 ${AppConstants.appName}\n$link';
}

final shareServiceProvider = Provider<ShareService>((ref) {
  return const ShareService(SharePlusChannel());
});
