import '../../models/artist.dart';
import '../../models/platform_type.dart';
import '../../models/song.dart';

/// The `mconnect://` scheme and every link the app emits or accepts.
///
/// Three hosts exist, and they must not be confused:
/// * **`playlist`** — `mconnect://playlist?data=<base64url(json)>`, encoded by
///   `MyPlaylistsRepository.encodeShareLink`. It carries the whole playlist, so
///   importing it needs no network and no account. The encoding lives there and
///   is *not* redefined here; this file only recognises it.
/// * **`song`** — `mconnect://song?platform=&id=&name=&artist=`, defined here.
///   It carries enough metadata to start playback without a lookup, because no
///   platform in this app exposes a "song by id" endpoint.
/// * **`share`** — `mconnect://share?text=<urlencoded>`, not a user-facing link:
///   it is the bridge the Android `ShareIntentHandler` activity uses to hand an
///   inbound `ACTION_SEND` payload to Dart (`app_links` only delivers
///   `ACTION_VIEW`, so someone has to convert one into the other natively).
class ShareLinks {
  ShareLinks._();

  static const String scheme = 'mconnect';
  static const String songHost = 'song';
  static const String playlistHost = 'playlist';
  static const String bridgeHost = 'share';

  /// Query parameter carrying the forwarded payload on [bridgeHost] links.
  static const String bridgeTextParam = 'text';

  static const String _songIdParam = 'id';
  static const String _songPlatformParam = 'platform';
  static const String _songNameParam = 'name';
  static const String _songArtistParam = 'artist';

  /// Builds the canonical share link for [song].
  static String songLink(Song song) {
    return Uri(
      scheme: scheme,
      host: songHost,
      queryParameters: <String, String>{
        _songPlatformParam: song.platform.name,
        _songIdParam: song.id,
        if (song.name.isNotEmpty) _songNameParam: song.name,
        if (song.artistNames.isNotEmpty) _songArtistParam: song.artistNames,
      },
    ).toString();
  }

  /// Rebuilds a [Song] from a link produced by [songLink], or null when the
  /// link is not ours / is malformed.
  ///
  /// `PlatformType.local` links are rejected: a local file is identified by a
  /// `content://` path on *this* device, so the link would be useless (and
  /// misleading) on the receiver's.
  static Song? parseSongLink(String raw) {
    final uri = _tryUri(raw);
    if (uri == null || uri.scheme != scheme || uri.host != songHost) {
      return null;
    }
    final id = uri.queryParameters[_songIdParam];
    if (id == null || id.isEmpty) return null;
    final platformName = uri.queryParameters[_songPlatformParam];
    if (platformName == null || platformName.isEmpty) return null;

    final PlatformType platform;
    try {
      platform = PlatformType.parse(platformName);
    } catch (_) {
      return null;
    }
    if (platform == PlatformType.local) return null;

    final name = uri.queryParameters[_songNameParam];
    final artist = uri.queryParameters[_songArtistParam];
    return Song(
      id: id,
      platform: platform,
      name: (name == null || name.isEmpty) ? '未知歌曲' : name,
      artists: _artistsFrom(artist),
    );
  }

  /// True for a playlist link this app can import offline (see [playlistHost]).
  static bool isLocalPlaylistLink(String raw) {
    final uri = _tryUri(raw);
    return uri != null && uri.scheme == scheme && uri.host == playlistHost;
  }

  /// Builds the bridge link an `ACTION_SEND` payload travels in.
  static String bridgeLink(String sharedText) {
    return Uri(
      scheme: scheme,
      host: bridgeHost,
      queryParameters: <String, String>{bridgeTextParam: sharedText},
    ).toString();
  }

  /// Unwraps the payload of a [bridgeLink], or null when [uri] is not one.
  static String? unwrapBridgeText(Uri uri) {
    if (uri.scheme != scheme || uri.host != bridgeHost) return null;
    final text = uri.queryParameters[bridgeTextParam];
    return (text == null || text.trim().isEmpty) ? null : text;
  }

  /// Pulls the first shareable link out of arbitrary shared text.
  ///
  /// `ACTION_SEND` payloads are usually prose with a link in the middle
  /// ("这首歌不错 https://… 分享自 XX"), and Chinese sentence punctuation is
  /// routinely glued to the URL, so trailing punctuation is trimmed.
  static String? extractLink(String rawText) {
    final trimmed = rawText.trim();
    if (trimmed.isEmpty) return null;
    final match = _linkPattern.firstMatch(trimmed);
    if (match == null) return null;
    final link = _trimTrailingPunctuation(match.group(0)!);
    return link.isEmpty ? null : link;
  }

  /// Classifies any inbound text (deep link URL or shared prose) into a target.
  static ShareLinkTarget? classify(String rawText) => _classify(rawText, 0);

  static ShareLinkTarget? _classify(String rawText, int depth) {
    // The whole payload may be the bridge link the Android ShareIntentHandler
    // forwarded...
    final direct = _tryUri(rawText);
    final forwarded = direct == null ? null : unwrapBridgeText(direct);
    if (forwarded != null && depth < 2) return _classify(forwarded, depth + 1);

    final link = extractLink(rawText);
    if (link == null) return null;

    // ...or it may be embedded in prose that was shared with it.
    final linkUri = _tryUri(link);
    final nested = linkUri == null ? null : unwrapBridgeText(linkUri);
    if (nested != null && depth < 2) return _classify(nested, depth + 1);

    final song = parseSongLink(link);
    if (song != null) return SongLinkTarget(link, song);
    if (isLocalPlaylistLink(link)) return LocalPlaylistLinkTarget(link);

    final uri = _tryUri(link);
    if (uri == null) return null;
    if (uri.scheme == 'http' || uri.scheme == 'https') {
      return PlatformPlaylistLinkTarget(link);
    }
    return null;
  }

  /// Route for the imported local playlist, so the user lands on the result
  /// instead of an empty "paste a link" form.
  static String localPlaylistLocation(String playlistId, String name) {
    return Uri(
      path: '/playlist/${PlatformType.local.name}/$playlistId',
      queryParameters: <String, String>{if (name.isNotEmpty) 'name': name},
    ).toString();
  }

  /// `'/import-playlist'`: where a link we cannot resolve locally is handed to
  /// the import page (it knows how to parse 网易云/QQ/酷狗 share URLs).
  static const String importPlaylistLocation = '/import-playlist';

  /// `'/player'`: where a resolved song link lands.
  static const String playerLocation = '/player';

  static final RegExp _linkPattern = RegExp(
    r'(?:https?|mconnect)://[^\s\u4e00-\u9fff]+',
    caseSensitive: false,
  );

  static const String _trailingPunctuation = '.,;:!?、。，；：！）》】」』\'"“”';

  static String _trimTrailingPunctuation(String value) {
    var end = value.length;
    while (end > 0 && _trailingPunctuation.contains(value[end - 1])) {
      end--;
    }
    return value.substring(0, end);
  }

  static Uri? _tryUri(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;
    final uri = Uri.tryParse(text);
    if (uri == null || uri.scheme.isEmpty) return null;
    return uri;
  }

  static List<Artist> _artistsFrom(String? names) {
    if (names == null || names.trim().isEmpty) {
      return const <Artist>[Artist(id: '', name: '未知歌手')];
    }
    return names
        .split(',')
        .map((name) => name.trim())
        .where((name) => name.isNotEmpty)
        .map((name) => Artist(id: '', name: name))
        .toList(growable: false);
  }
}

/// What an inbound link turned out to be.
sealed class ShareLinkTarget {
  const ShareLinkTarget(this.link);

  /// The raw link that was recognised (never the surrounding prose).
  final String link;
}

class SongLinkTarget extends ShareLinkTarget {
  const SongLinkTarget(super.link, this.song);

  final Song song;
}

/// `mconnect://playlist?data=…` — importable with no network.
class LocalPlaylistLinkTarget extends ShareLinkTarget {
  const LocalPlaylistLinkTarget(super.link);
}

/// Any other http(s) link: presumed to be a platform playlist share URL. The
/// import page decides whether it can actually parse it.
class PlatformPlaylistLinkTarget extends ShareLinkTarget {
  const PlatformPlaylistLinkTarget(super.link);
}
