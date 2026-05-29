class KugouEndpoints {
  KugouEndpoints._();

  // CDN endpoints (HTTP to avoid SSL certificate issues)
  static const String searchBase =
      'http://mobilecdn.kugou.com/api/v3/search/song';
  static const String playlistSearch =
      'https://complexsearch.kugou.com/v1/search/special';
  static const String songInfo = 'http://m.kugou.com/app/i/getSongInfo.php';
  static const String songPlaybackUrl = 'https://gateway.kugou.com/v5/url';
  static const String songPrivateUrl = 'http://tracker.kugou.com/v6/priv_url';
  static const String lyricsSearch = 'http://lyrics.kugou.com/search';
  static const String lyricsSearchByHash = 'http://krcs.kugou.com/search';
  static const String lyricsDownload = 'http://lyrics.kugou.com/download';
  static const String rankList = 'http://mobilecdn.kugou.com/api/v3/rank/list';
  static const String recommend =
      'http://mobilecdn.kugou.com/api/v3/recommend/song';

  // Auth (HTTPS required)
  static const String qrCodeGet =
      'https://passport.kugou.com/api/v3/login/qrcode/get';
  static const String qrCodeCheck =
      'https://passport.kugou.com/api/v3/login/qrcode/check';
  static const String qrKey = 'https://login-user.kugou.com/v2/qrcode';
  static const String qrCheckNew =
      'https://login-user.kugou.com/v2/get_userinfo_qrcode';
  static const String userInfo = 'https://wwwapi.kugou.com/uc/userinfo';
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
  static const String songCollect =
      'http://mobilecdn.kugou.com/api/v5/song/collect';
  static const String songUncollect =
      'http://mobilecdn.kugou.com/api/v5/song/uncollect';
  static const String rankSong = 'http://mobilecdn.kugou.com/api/v3/rank/song';
  static const String loginIndex =
      'http://mobilecdn.kugou.com/api/v2/login/index';
  static const String vipInfoApi = 'http://mobilecdn.kugou.com/api/v2/user/vip';
  static const String playlistAdd =
      'https://gateway.kugou.com/cloudlist.service/v5/add_list';
}
