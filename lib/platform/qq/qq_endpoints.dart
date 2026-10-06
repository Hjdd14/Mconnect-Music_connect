/// Every QQ Music URL and musicu `module`/`method` pair the adapter uses.
///
/// Keeping them here (instead of inline in `qq_api.dart`) is what makes the
/// endpoints auditable: the 2026-10 probe that fixed the 热歌榜 defect
/// (`topid=26`, not `4`) is recorded next to the URLs it verified.
class QqEndpoints {
  QqEndpoints._();

  static const String musicu = 'https://u.y.qq.com/cgi-bin/musicu.fcg';
  static const String lyricBase =
      'https://i.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg';
  static const String qrShow = 'https://ssl.ptlogin2.qq.com/ptqrshow';
  static const String qrLogin = 'https://ssl.ptlogin2.qq.com/ptqrlogin';

  /// Legacy chart detail. Verified live: returns the chart definition plus
  /// `cur_count`/`old_count` (rank movement) for every song, needs no cookie,
  /// and answers over HTTPS. Caps a single page at 50 tracks, so callers page
  /// with [songBegin].
  static const String toplistCp =
      'https://c.y.qq.com/v8/fcg-bin/fcg_v8_toplist_cp.fcg';

  /// Legacy artist profile (`getSingerInfo`, `singerBrief`, `total_*`,
  /// `getSongInfo[]`). Verified live over HTTPS.
  static const String singerDetail =
      'https://c.y.qq.com/v8/fcg-bin/fcg_v8_singer_detail_cp.fcg';

  /// Legacy album detail (`data.list[]` = the album's tracks). Verified live.
  static const String albumInfo =
      'https://c.y.qq.com/v8/fcg-bin/fcg_v8_album_info_cp.fcg';

  static const String searchPlaylist =
      'https://c.y.qq.com/soso/fcgi-bin/client_music_search_songlist';
  static const String profileHomepage =
      'https://c.y.qq.com/rsc/fcgi-bin/fcg_get_profile_homepage.fcg';
  static const String userCreatedDiss =
      'https://c.y.qq.com/rsc/fcgi-bin/fcg_user_created_diss';
  static const String legacyPlaylistDetail =
      'https://c.y.qq.com/qzone/fcg-bin/fcg_ucc_getcdinfo_byids_cp.fcg';
  static const String addSongToDir =
      'https://c.y.qq.com/splcloud/fcgi-bin/fcg_music_add2songdir.fcg';
  static const String createPlaylist =
      'https://c.y.qq.com/splcloud/fcgi-bin/create_playlist.fcg';
  static const String collectPlaylist =
      'https://c.y.qq.com/folder/fcgi-bin/fcg_qm_order_diss.fcg';

  /// PC page that carries the logged-in 「今日私享」 playlist id. Verified
  /// anonymously 2026-10: 8269 bytes and no 今日私享 marker, i.e. the
  /// personalised daily list is only visible to a signed-in cookie.
  static const String dailyPrivatePage =
      'https://c.y.qq.com/node/musicmac/v6/index.html';

  /// OAuth endpoints used by the QR login handshake.
  static const String graphShow = 'https://graph.qq.com/oauth2.0/show';
  static const String graphAuthorize =
      'https://graph.qq.com/oauth2.0/authorize';
  static const String graphLoginJump =
      'https://graph.qq.com/oauth2.0/login_jump';
  static const String oauthRedirectUri =
      'https://y.qq.com/portal/wx_redirect.html?login_type=1';

  /// Cover URL templates (QQ serves covers by `mid`).
  static const String songCover =
      'https://y.qq.com/music/photo_new/T002R300x300M000';
  static const String artistCover =
      'https://y.gtimg.cn/music/photo_new/T001R300x300M000';

  // --- musicu module/method pairs ------------------------------------------

  static const String moduleUserPlaylist = 'playlist.UserPlayList';
  static const String methodGetUserPlaylist = 'GetUserPlayList';

  static const String modulePlaylistDetail =
      'playlist.PlayListPlayDetailService';
  static const String methodGetPlaylistDetail = 'GetPlayListDetail';

  static const String moduleFavRead = 'music.musicasset.SongFavRead';
  static const String methodGetUserFavSongList = 'GetUserFavSongList';

  static const String moduleFavWrite = 'music.musicasset.SongFavWrite';
  static const String methodAddSongFav = 'AddSongFav';
  static const String methodDeleteSongFav = 'DeleteSongFav';

  static const String moduleVipInfo = 'music.vip.VipInfo';
  static const String methodGetVipInfo = 'GetVipInfo';

  static const String moduleToplist = 'musicToplist.ToplistInfoServer';
  static const String methodGetToplistDetail = 'GetDetail';
  static const String methodGetToplistCatalogue = 'GetAll';

  /// Artist profile with the canonical avatar (`basic_info.singer_pmid`).
  static const String moduleSinger = 'music.musichallSinger.SingerInfoInter';
  static const String methodGetSingerDetail = 'GetSingerDetail';

  /// Artist album list. `music.musichallAlbum.AlbumListInter` answers
  /// `code 500003` for this call; `AlbumListServer` answers with
  /// `req_0.data.albumList[]` (verified live 2026-10).
  static const String moduleAlbumList = 'music.musichallAlbum.AlbumListServer';
  static const String methodGetAlbumList = 'GetAlbumList';

  static const String moduleNewSong = 'newsong.NewSongServer';
  static const String methodGetNewSongInfo = 'get_new_song_info';

  static const String moduleSearch = 'music.search.SearchCgiService';
  static const String methodDesktopSearch = 'DoSearchForQQMusicDesktop';
  static const String methodMobileSearch = 'DoSearchForQQMusicMobile';
}
