/// 网易云音乐的**明文**接口端点表。
///
/// 本仓的 `netease_crypto.dart`（weapi / eapi 加密）在 `lib/` 内零引用，所以
/// 所有请求都走未加密的 `/api/` 接口 —— 不做加密、不签名，只带固定 cookie
/// （`os=pc; appver=3.0.18.203152`，见 [NeteaseApi._initCookie]）。
///
/// 每个端点的可用性与返回形状都实测过（2026-10-06，
/// 见 `docs/netease-wave-b-probe.md`）；需要拼接 id 的端点写成 `...Prefix`。
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
  static const String recommendResource = '/api/v1/discovery/recommend/resource';
  static const String like = '/api/radio/like';
  static const String qrKey = '/api/login/qrcode/unikey';
  static const String qrCheck = '/api/login/qrcode/client/login';
  static const String anonymousToken = '/api/register/anonimous';

  // ---------------------------------------------------------------------------
  // 榜单 / 新歌 / 艺人 / 专辑（Wave 1 补齐）
  // ---------------------------------------------------------------------------

  /// 全部榜单。实测 200 且 `list` 有 63 条，字段
  /// `id / name / coverImgUrl / updateFrequency / trackCount`。
  ///
  /// 注意：任务书里写的 `trackNumberUpdate` **不存在**，实测字段名是
  /// `trackNumberUpdateTime`（毫秒时间戳），曲目数在 `trackCount`。
  static const String toplist = '/api/toplist';

  /// 新歌速递（按地区）。`areaId`: 0 全部 / 7 华语 / 96 欧美 / 8 日本 / 16 韩国。
  ///
  /// 实测：服务端**忽略** `limit`/`offset`，固定返回 100 条 `data[]`。
  static const String newSongsByArea = '/api/v1/discovery/new/songs';

  /// 个性推荐新歌（`result[].song` 才是歌曲本体）。实测 `result[].type` 是
  /// **int 4**，不是字符串 `'song'`；而且该接口忽略地区参数。
  static const String personalizedNewSongs = '/api/personalized/newsong';

  /// 艺人信息 + 计数字段：`data.artist.{name,cover,avatar,briefDesc,musicSize,albumSize}`。
  static const String artistHeadInfo = '/api/artist/head/info/get';

  /// 艺人热门歌曲：`songs[]`，实测 50 首，用 `ar/al/dt` 命名。
  static const String artistTopSong = '/api/artist/top/song';

  /// 艺人专辑前缀，拼 id 使用：`/api/artist/albums/{artistId}?limit&offset`。
  /// 返回 `hotAlbums[]`，`limit`/`offset` 实测均生效。
  static const String artistAlbumsPrefix = '/api/artist/albums/';

  /// 专辑详情前缀，拼 id 使用：`/api/v1/album/{albumId}`。
  /// 曲目在**顶层** `songs[]`（`album.songs` 实测为空数组），`no` 为 1..N。
  static const String albumDetailPrefix = '/api/v1/album/';

  /// 旧明文艺人接口前缀，拼 id 使用：`/api/artist/{artistId}`。
  /// 一次返回艺人信息 + 50 首热门（`hotSongs`，用 `artists/album/duration` 命名）。
  static const String artistLegacyPrefix = '/api/artist/';

  // ---------------------------------------------------------------------------
  // 原先内联在 NeteaseApi / NeteasePlatform 里的路径，统一收拢到这里
  // ---------------------------------------------------------------------------

  /// 批量歌曲详情（POST，`ids` + `c` 两个 JSON 数组参数）。
  static const String songDetail = '/api/v3/song/detail';

  /// 新建歌单。
  static const String playlistCreate = '/api/playlist/create';

  /// 收藏 / 取消收藏歌单。
  static const String playlistSubscribe = '/api/playlist/subscribe';
  static const String playlistUnsubscribe = '/api/playlist/unsubscribe';

  /// 歌单内增删歌曲。
  static const String playlistTrackManipulate = '/api/playlist/manipulate/tracks';

  /// 删除**自建**歌单。
  ///
  /// ⚠️【未实测】本仓库的探测记录（`docs/netease-wave-b-probe.md`）没有覆盖这个
  /// 端点。它与 create/subscribe/manipulate 同属明文 `/api/` 家族、同一套参数
  /// 风格（`csrf` + id），所以形状是可推断的；但**调用点必须在拿到真实响应后
  /// 才敢说它可用** —— 失败时按"平台不支持"处理，不假装成功。
  static const String playlistDelete = '/api/playlist/delete';

  /// 更新歌单信息（改名 / 描述）。
  ///
  /// ⚠️【未实测】同上，见 [playlistDelete] 的说明。
  static const String playlistUpdate = '/api/playlist/update';

  /// 手机验证码相关。
  static const String smsCaptchaSent = '/api/sms/captcha/sent';
  static const String loginCellphone = '/api/login/cellphone';

  // ---------------------------------------------------------------------------
  // Web 页面地址（非 API，但同样属于"不要内联"的常量）
  // ---------------------------------------------------------------------------

  /// 站点根，同时是 `Dio` 的 `baseUrl`。
  static const String baseUrl = 'https://music.163.com';

  /// 扫码登录页地址（qr_flutter 渲染给用户扫的二维码内容）。
  static String qrLoginUrl(String key) => '$baseUrl/login?codekey=$key';
}
