import 'dart:async';

import 'package:app_links/app_links.dart';

import '../../features/library/presentation/providers/my_playlists_provider.dart';
import '../../models/song.dart';
import '../transfer/playlist_codec.dart';
import 'share_links.dart';

/// Source of inbound links: platform deep links (`ACTION_VIEW`) and the Android
/// `ShareIntentHandler` forward of an `ACTION_SEND` payload.
///
/// `AppLinks` is a singleton factory over a platform channel, so this seam is
/// what makes [DeepLinkService] testable without a device.
abstract class LinkSource {
  /// The link that cold-started the app, if any.
  Future<Uri?> initialLink();

  /// Links delivered while the app is running.
  Stream<Uri> links();
}

class AppLinksSource implements LinkSource {
  const AppLinksSource();

  @override
  Future<Uri?> initialLink() => AppLinks().getInitialLink();

  @override
  Stream<Uri> links() => AppLinks().uriLinkStream;
}

/// What the app must do about an inbound link.
sealed class InboundLinkOutcome {
  const InboundLinkOutcome();
}

/// Play [song] and show the player.
class PlaySongOutcome extends InboundLinkOutcome {
  const PlaySongOutcome(this.song);

  final Song song;
}

/// Navigate to [location]; [message], when set, is a user-visible result.
class NavigateOutcome extends InboundLinkOutcome {
  const NavigateOutcome(this.location, {this.message});

  final String location;
  final String? message;
}

/// Executes an inbound link.
///
/// Takes the notifier instead of a `Ref`/`WidgetRef` so it can be driven in a
/// unit test with a real [MyPlaylistsNotifier] over a temporary directory.
class InboundLinkHandler {
  const InboundLinkHandler({required this.playlists, this.onTransferText});

  final MyPlaylistsNotifier playlists;

  /// Called with the raw payload when an inbound share carries a playlist
  /// *document* (m3u8 / our own JSON / `歌名 - 歌手` lines) rather than a link.
  ///
  /// Needed because such a payload has no URL for [ShareLinks.classify] to find:
  /// without this the shared playlist would be discarded silently, which is the
  /// one outcome a transfer feature must never have. The wiring hands it to
  /// `pendingPlaylistTransferProvider`, which the import page consumes.
  final void Function(String text)? onTransferText;

  /// Returns null for text that carries no link we understand (the caller stays
  /// where it is) — an unrecognised share must never move the user somewhere
  /// surprising.
  Future<InboundLinkOutcome?> handle(String rawText) async {
    final target = ShareLinks.classify(rawText);
    switch (target) {
      case null:
        final payload = transferPayloadOf(rawText);
        if (payload == null) return null;
        onTransferText?.call(payload);
        return const NavigateOutcome(ShareLinks.importPlaylistLocation);
      case SongLinkTarget(song: final song):
        return PlaySongOutcome(song);
      case LocalPlaylistLinkTarget(link: final link):
        return _importLocalPlaylist(link);
      case PlatformPlaylistLinkTarget():
        // Platform share URLs are parsed by the import page (it knows the
        // 网易云/QQ/酷狗 formats); the user only has to confirm.
        return const NavigateOutcome(ShareLinks.importPlaylistLocation);
    }
  }

  /// The shared payload when it is an importable playlist document, else null.
  ///
  /// An `ACTION_SEND` payload reaches Dart wrapped in `mconnect://share?text=…`
  /// (see `ShareIntentHandler`), so one level is unwrapped before judging; prose
  /// that merely happens to contain a newline is rejected by
  /// [looksLikePlaylistTransfer].
  static String? transferPayloadOf(String rawText) {
    final trimmed = rawText.trim();
    if (trimmed.isEmpty) return null;
    final uri = Uri.tryParse(trimmed);
    final unwrapped = uri == null ? null : ShareLinks.unwrapBridgeText(uri);
    final candidate = unwrapped ?? trimmed;
    return looksLikePlaylistTransfer(candidate) ? candidate : null;
  }

  Future<InboundLinkOutcome> _importLocalPlaylist(String link) async {
    try {
      final playlist = await playlists.importShareLink(link);
      if (playlist == null) {
        return const NavigateOutcome(
          ShareLinks.importPlaylistLocation,
          message: '无法识别该 Mconnect 歌单链接',
        );
      }
      return NavigateOutcome(
        ShareLinks.importPlaylistLocation,
        message: '已导入歌单「${playlist.name}」',
      );
    } catch (e) {
      // A storage failure must not crash the app on launch; tell the user and
      // put them on the page where they can retry by pasting the link.
      return NavigateOutcome(
        ShareLinks.importPlaylistLocation,
        message: '导入歌单失败：$e',
      );
    }
  }
}

/// Subscribes to inbound links and forwards each outcome to [onOutcome].
class DeepLinkService {
  DeepLinkService({
    required this.source,
    required this.handler,
    required this.onOutcome,
  });

  final LinkSource source;
  final InboundLinkHandler handler;
  final void Function(InboundLinkOutcome outcome) onOutcome;

  StreamSubscription<Uri>? _subscription;
  String? _initialLink;
  bool _started = false;

  bool get isRunning => _subscription != null;

  /// Starts listening. Safe to call twice (a second call is a no-op).
  Future<void> start() async {
    if (_started) return;
    _started = true;

    // Read the cold-start link first: `app_links` can deliver the same intent
    // through both [LinkSource.initialLink] and the stream, and handling it
    // twice would import a shared playlist twice. The guard is armed only
    // *after* the link was handled — arming it first would make [_handle]
    // discard the very link we are about to process.
    final initial = await source.initialLink();
    if (initial != null) {
      await _handle(initial);
      _initialLink = initial.toString();
    }

    _subscription = source.links().listen(
      (uri) => unawaited(_handle(uri)),
      onError: (Object _) {},
    );
  }

  Future<void> _handle(Uri uri) async {
    final raw = uri.toString();
    if (raw == _initialLink) {
      // Already handled as the cold-start link; consume the replay once.
      _initialLink = null;
      return;
    }
    try {
      final outcome = await handler.handle(raw);
      if (outcome != null) onOutcome(outcome);
    } catch (_) {
      // A malformed link must never take the app down.
    }
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
    _started = false;
    _initialLink = null;
  }
}
