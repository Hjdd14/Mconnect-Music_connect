class KugouEndpoints {
  KugouEndpoints._();

  // NOTE (v1.4.1): several endpoints below are plain HTTP because their host has
  // **no usable TLS** — `mobilecdn.kugou.com`, `mobilecdnbj.kugou.com` and
  // `login.user.kugou.com` answer 443 with `CERTIFICATE_VERIFY_FAILED: Hostname
  // mismatch` (probe: scripts/test_kugou_tls_probe.dart). Those hosts are why
  // `network_security_config.xml` still needs a `kugou.com` cleartext entry;
  // endpoints whose host *does* serve TLS have been moved to HTTPS (songInfo,
  // songPrivateUrl, lyrics/krcs). See docs/kugou-cleartext-probe.md.
  static const String searchBase =
      'http://mobilecdn.kugou.com/api/v3/search/song';
  static const String playlistSearch =
      'https://complexsearch.kugou.com/v1/search/special';

  /// Playback metadata (`cmd=playInfo`) — the response carries the playable CDN
  /// URL. HTTPS is verified working (probe 2026-10-06, `status:1`), and this is
  /// the endpoint whose cleartext response an on-path attacker could rewrite
  /// into an arbitrary audio URL that the download manager would then persist,
  /// so it is deliberately **not** on the cleartext allowlist any more.
  static const String songInfo = 'https://m.kugou.com/app/i/getSongInfo.php';
  static const String songPlaybackUrl = 'https://gateway.kugou.com/v5/url';

  /// VIP / 私密取流 (`v6/priv_url`).
  ///
  /// Moved to HTTPS in v1.4.1 (task-17 §4b): the response carries a **private
  /// stream URL**, so a cleartext response rewritten on-path would be persisted
  /// by the download manager — the same risk class as [songInfo]. Probe
  /// (`scripts/test_kugou_tls_probe.dart`, 2026-10-06): `tracker.kugou.com`
  /// completes TLS with a valid certificate (`HTTP 200`).
  static const String songPrivateUrl = 'https://tracker.kugou.com/v6/priv_url';
  static const String lyricsSearch = 'https://lyrics.kugou.com/search';
  static const String lyricsSearchByHash = 'https://krcs.kugou.com/search';
  static const String lyricsDownload = 'https://lyrics.kugou.com/download';
  static const String rankList = 'http://mobilecdn.kugou.com/api/v3/rank/list';

  /// Legacy 官方每日推荐 endpoint.
  ///
  /// Still reachable (probed 2026-10-06: the server answers the WAF page
  /// `Access Deny ! No Actions !` with HTTP 200 for five different signing
  /// variants), and deliberately kept as the *first* attempt so the fallback in
  /// `KugouPlatform.getDailyRecommendation` is exercised rather than dead code.
  /// [homepage] is the source that actually produces songs.
  static const String recommend =
      'http://mobilecdn.kugou.com/api/v3/recommend/song';

  /// Mobile homepage module (`?json=true`). `data` holds 10 recommended songs;
  /// `special.list.info[].songs` adds more. This replaces [recommend].
  static const String homepage = 'http://m.kugou.com/?json=true';

  /// Artist / album content endpoints (all plain JSON, probed live).
  static const String singerInfo =
      'http://mobilecdnbj.kugou.com/api/v3/singer/info';
  static const String singerSongs =
      'http://mobilecdnbj.kugou.com/api/v3/singer/song';

  /// NOTE: `/api/v3/singer/albumlist` is dead (`Access Deny ! No Actions !`);
  /// the live path is `/api/v3/singer/album` (no `list` suffix).
  static const String singerAlbums =
      'http://mobilecdn.kugou.com/api/v3/singer/album';
  static const String albumInfo =
      'http://mobilecdn.kugou.com/api/v3/album/info';
  static const String albumSongs =
      'http://mobilecdn.kugou.com/api/v3/album/song';

  // Auth (HTTPS required)
  static const String qrCodeGet =
      'https://passport.kugou.com/api/v3/login/qrcode/get';
  static const String qrCodeCheck =
      'https://passport.kugou.com/api/v3/login/qrcode/check';
  static const String qrKey = 'https://login-user.kugou.com/v2/qrcode';
  static const String qrCheckNew =
      'https://login-user.kugou.com/v2/get_userinfo_qrcode';
  static const String userInfo = 'https://wwwapi.kugou.com/uc/userinfo';

  /// Page the QR code points at. Kept here (was an inline literal in
  /// `kugou_api.dart`) so every URL lives in one file.
  static const String qrLoginPage =
      'https://h5.kugou.com/apps/loginQRCode/html/index.html';

  /// Phone + SMS-code login. **Unreachable from the UI since v1.4.1** — Kugou is
  /// QR-login only (`KugouPlatform.supportsPhoneLogin == false`), and this
  /// constant is kept solely so the retired API method still compiles.
  ///
  /// Do not wire it back up without first fixing the transport: this host has
  /// **no usable TLS** (probe 2026-10-06: `CERTIFICATE_VERIFY_FAILED: Hostname
  /// mismatch`), so the phone number and the SMS code would travel in cleartext.
  static const String sendMobileCode =
      'http://login.user.kugou.com/v7/send_mobile_code';

  // Library (HTTP for CDN, HTTPS for API)
  static const String userCollection =
      'https://wwwapi.kugou.com/uc/collection/song/list';
  static const String userPlaylist =
      'https://gateway.kugou.com/v7/get_all_list';
  static const String playlistDetail =
      'http://mobilecdnbj.kugou.com/api/v5/special/detail';
  static const String playlistSongs =
      'http://mobilecdnbj.kugou.com/api/v5/special/song';
  static const String userPlaylistSongs =
      'https://gateway.kugou.com/v4/get_list_all_file';
  /// Collect / uncollect a song. **Cleartext with the session token in the
  /// query string** — accepted residual risk, not an oversight:
  /// `mobilecdn.kugou.com` has no usable TLS (probe 2026-10-06:
  /// `CERTIFICATE_VERIFY_FAILED: Hostname mismatch`), so the only alternatives
  /// are "leave the like button broken" or "accept that an on-path attacker can
  /// read the token and forge a like". The token is the user's own and the
  /// action is reversible, so the feature is kept and the risk documented; see
  /// `docs/kugou-cleartext-probe.md`.
  static const String songCollect =
      'http://mobilecdn.kugou.com/api/v5/song/collect';
  static const String songUncollect =
      'http://mobilecdn.kugou.com/api/v5/song/uncollect';
  static const String rankSong = 'http://mobilecdn.kugou.com/api/v3/rank/song';
  static const String loginIndex =
      'http://mobilecdn.kugou.com/api/v2/login/index';

  /// VIP status. Same cleartext + token-in-query caveat as [songCollect]; this
  /// one is read-only.
  static const String vipInfoApi = 'http://mobilecdn.kugou.com/api/v2/user/vip';
  static const String playlistAdd =
      'https://gateway.kugou.com/cloudlist.service/v5/add_list';

  /// Shared H5 cloud playlists (`t1.kugou.com` short links resolve here).
  static const String sharedPlaylistSongs =
      'https://pubsongscdn.kugou.com/v2/get_other_list_file';

  /// HTTP `Referer` the shared-playlist endpoint requires.
  static const String sharedPlaylistReferer = 'https://activity.kugou.com/';
}
