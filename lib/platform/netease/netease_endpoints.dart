class NeteaseEndpoints {
  NeteaseEndpoints._();

  // 无加密 API 端点 (GET/POST, 响应是明文 JSON)
  static const String search = '/api/cloudsearch/pc';
  static const String songUrl = '/api/song/enhance/player/url/v1';
  static const String lyric = '/api/song/lyric';
  static const String userInfo = '/api/nuser/account/get';
  static const String userPlaylist = '/api/user/playlist';
  static const String playlistDetail = '/api/v6/playlist/detail';
  static const String recommendSongs = '/api/v3/discovery/recommend/songs';
  static const String recommendResource =
      '/api/v1/discovery/recommend/resource';
  static const String like = '/api/radio/like';
  static const String qrKey = '/api/login/qrcode/unikey';
  static const String qrCheck = '/api/login/qrcode/client/login';
  static const String anonymousToken = '/api/register/anonimous';
}
