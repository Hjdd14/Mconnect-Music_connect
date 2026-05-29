class QqEndpoints {
  QqEndpoints._();

  static const String musicu = 'https://u.y.qq.com/cgi-bin/musicu.fcg';
  static const String lyricBase = 'https://i.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg';
  static const String qrShow = 'https://ssl.ptlogin2.qq.com/ptqrshow';
  static const String qrLogin = 'https://ssl.ptlogin2.qq.com/ptqrlogin';

  // musicu module/method pairs
  static const String moduleUserPlaylist = 'playlist.UserPlayList';
  static const String methodGetUserPlaylist = 'GetUserPlayList';

  static const String modulePlaylistDetail = 'playlist.PlayListPlayDetailService';
  static const String methodGetPlaylistDetail = 'GetPlayListDetail';

  static const String moduleFavRead = 'music.musicasset.SongFavRead';
  static const String methodGetUserFavSongList = 'GetUserFavSongList';

  static const String moduleFavWrite = 'music.musicasset.SongFavWrite';
  static const String methodAddSongFav = 'AddSongFav';
  static const String methodDeleteSongFav = 'DeleteSongFav';

  static const String moduleChartInfo = 'musicToplist.ChartInfo';
  static const String methodGetDailyRecommend = 'GetDailyRecommend';

  static const String moduleVipInfo = 'music.vip.VipInfo';
  static const String methodGetVipInfo = 'GetVipInfo';

  static const String moduleToplist = 'musicToplist.ToplistInfoServer';
  static const String methodGetToplistDetail = 'GetDetail';
}
