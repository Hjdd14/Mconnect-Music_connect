/// Real QQ Music payload shapes captured from the live endpoints (2026-10-06).
///
/// These are trimmed copies — every structural detail that the parser depends on
/// (wrapper keys, `rankType` codes, string-typed counts) is preserved, while
/// unrelated bulk (`file`, `pay`, `preview`, wiki text) is dropped.
library;

/// Legacy chart endpoint `fcg_v8_toplist_cp.fcg?topid=26` (巅峰榜·热歌).
///
/// `songlist[i]` is wrapped in **`data`**, and `cur_count`/`old_count` are rank
/// positions as strings: rank movement is `old_count - cur_count`.
const Map<String, dynamic> kHotToplistCp = {
  'code': 0,
  'cur_song_num': 3,
  'total_song_num': 300,
  'date': '2026-10-06',
  'topinfo': {
    'ListName': '巅峰榜·热歌',
    'UpdateType': 1,
    'pic_v12':
        'http://y.gtimg.cn/music/photo_new/T003R300x300M000001xEeb01e5Jyf.jpg',
    'headPic_v12': 'http://y.gtimg.cn/music/common/upload/t_order_channel_hitlist_conf/1.png',
    'info': '1.榜单定义：QQ音乐站内播放热度前300首歌曲。<br>2.更新频率：每日更新。',
    'listennum': 19200000,
    'topID': 26,
  },
  'songlist': [
    {
      'Franking_value': '1',
      'cur_count': '1',
      'old_count': '1',
      'in_count': '180',
      'data': {
        'songmid': '001fsNdn1zuZnA',
        'songname': '我不难过',
        'songid': 8136,
        'singer': [
          {'id': 109, 'mid': '001pWERg3vFgg8', 'name': '孙燕姿'},
        ],
        'albummid': '004VSvF52mQoQp',
        'albumname': '未完成',
        'interval': 320,
        'strMediaMid': '000ao2Na47ZtsG',
        'vid': 'W0090PSvwtp',
      },
    },
    {
      'Franking_value': '2',
      'cur_count': '2',
      'old_count': '5',
      'in_count': '3',
      'data': {
        'songmid': '002toGvP1Cqzr2',
        'songname': 'Proof',
        'songid': 727791558,
        'singer': [
          {'id': 7733770, 'mid': '002NDCAj4d5ahV', 'name': '檀健次'},
        ],
        'albummid': '004WxXLs0ZCYBc',
        'albumname': 'Proof',
        'interval': 205,
        'vid': '',
      },
    },
    {
      'Franking_value': '3',
      'cur_count': '3',
      'old_count': '3',
      'in_count': '1',
      'data': {
        'songmid': '000KgIso4SbK9e',
        'songname': '神奇',
        'songid': 8135,
        'singer': [
          {'id': 109, 'mid': '001pWERg3vFgg8', 'name': '孙燕姿'},
        ],
        'albummid': '004VSvF52mQoQp',
        'albumname': '未完成',
        'interval': 262,
        'vid': 'B0090GM6sPW',
      },
    },
  ],
};

/// Legacy chart endpoint for a **score-ordered** chart (巅峰榜·流行指数,
/// `topid=4`): here `cur_count`/`old_count` are index scores, not ranks.
const Map<String, dynamic> kScoreToplistCp = {
  'code': 0,
  'cur_song_num': 2,
  'total_song_num': 100,
  'date': '2026-10-06',
  'topinfo': {'ListName': '巅峰榜·流行指数', 'topID': 4},
  'songlist': [
    {
      'Franking_value': '213709',
      'cur_count': '213709',
      'old_count': '76755',
      'data': {
        'songmid': 'aaa111',
        'songname': '指数第一',
        'singer': [
          {'mid': 'singer-a', 'name': '歌手A'},
        ],
        'albummid': 'album-a',
        'albumname': '专辑A',
        'interval': 200,
      },
    },
    {
      'Franking_value': '166026',
      'cur_count': '166026',
      'old_count': '0',
      'data': {
        'songmid': 'bbb222',
        'songname': '指数第二',
        'singer': [
          {'mid': 'singer-b', 'name': '歌手B'},
        ],
        'albummid': 'album-b',
        'albumname': '专辑B',
        'interval': 180,
      },
    },
  ],
};

/// `musicToplist.ToplistInfoServer/GetAll` — 4 groups, 30 charts live.
/// Trimmed to one full 巅峰榜 group plus one 地区榜 entry.
const Map<String, dynamic> kToplistCatalogue = {
  'code': 0,
  'toplist': {
    'code': 0,
    'data': {
      'group': [
        {
          'groupName': '巅峰榜',
          'groupType': 0,
          'toplist': [
            {
              'topId': 62,
              'title': '飙升榜',
              'titleDetail': '飙升榜 第279天',
              'intro': '1. 榜单定义：QQ音乐站内播放热度飙升最快的前100首歌曲。',
              'period': '2026-10-06',
              'updateTime': '2026-10-06',
              'updateTips': '每日更新',
              'totalNum': 100,
              'frontPicUrl': 'http://y.gtimg.cn/music/photo_new/T003R300x300M000002tqij603mptG.jpg',
              'headPicUrl': 'http://y.gtimg.cn/music/common/upload/t_order_channel_hitlist_conf/1.png',
              'mbFrontPicUrl': 'http://y.gtimg.cn/music/photo_new/T003R300x300M000002tqij603mptG.jpg',
            },
            {
              'topId': 26,
              'title': '热歌榜',
              'titleDetail': '热歌榜 第279天',
              'intro': '1.榜单定义：QQ音乐站内播放热度前300首歌曲。',
              'period': '2026-10-06',
              'updateTime': '2026-10-06',
              'updateTips': '7首歌新上榜',
              'totalNum': 300,
              'frontPicUrl': 'http://y.gtimg.cn/music/photo_new/T003R300x300M000001xEeb01e5Jyf.jpg',
            },
          ],
        },
        {
          'groupName': '地区榜',
          'groupType': 1,
          'toplist': [
            {
              'topId': 5,
              'title': '内地榜',
              'titleDetail': '内地榜 第40周',
              'intro': 'QQ音乐每周播放热度最高的内地歌曲TOP100，发行期为90天内。',
              'period': '2026_40',
              'updateTime': '2026-10-01',
              'updateTips': '每周更新',
              'totalNum': 100,
              'frontPicUrl': 'http://y.gtimg.cn/music/photo_new/T003R300x300M0000031k2OD0wbQrN.jpg',
            },
          ],
        },
      ],
    },
  },
};

/// `musicToplist.ToplistInfoServer/GetDetail` for 特色榜·说唱榜 (`topid=58`).
///
/// `song[]` carries the real `rank` plus `rankType`/`rankValue`;
/// `songInfoList[]` carries the songs but **no** rank. The `rankType` codes were
/// verified by diffing this payload against the legacy endpoint for the same
/// songs (1 = up by rankValue, 2 = down by rankValue, 3 = unchanged,
/// 4 = new entry, 6 = growth percentage).
Map<String, dynamic> modernChartDetail({int topId = 58}) => {
  'code': 0,
  'toplist': {
    'code': 0,
    'data': {
      'data': {
        'topId': topId,
        'title': '说唱榜',
        'intro': 'QQ音乐每周播放热度最高的中文说唱歌曲TOP 50。',
        'period': '2026_39',
        'totalNum': 50,
        'updateTips': '每周更新',
        'song': [
          {
            'rank': 1,
            'rankType': 3,
            'rankValue': '0',
            'songId': 706257656,
            'title': '周旋',
          },
          {
            'rank': 2,
            'rankType': 1,
            'rankValue': '2',
            'songId': 718660418,
            'title': '颜如玉2.0 (Live)',
          },
          {
            'rank': 3,
            'rankType': 2,
            'rankValue': '1',
            'songId': 724861673,
            'title': '飞鸟Remix',
          },
          {
            'rank': 8,
            'rankType': 4,
            'rankValue': '0',
            'songId': 999999,
            'title': '日落以后',
          },
        ],
      },
      'songInfoList': [
        {
          'id': 706257656,
          'mid': 'mid-up-flat',
          'name': '周旋',
          'singer': [
            {'id': 1, 'mid': 'singer-1', 'name': '王以太'},
          ],
          'album': {'id': 2, 'mid': 'album-1', 'name': '说唱专辑'},
          'interval': 201,
        },
        {
          'id': 718660418,
          'mid': 'mid-up-2',
          'name': '颜如玉2.0 (Live)',
          'singer': [
            {'id': 3, 'mid': 'singer-2', 'name': '李大奔'},
          ],
          'album': {'id': 4, 'mid': 'album-2', 'name': '颜如玉'},
          'interval': 190,
        },
        {
          'id': 724861673,
          'mid': 'mid-down-1',
          'name': '飞鸟Remix',
          'singer': [
            {'id': 5, 'mid': 'singer-3', 'name': '宝石Gem'},
          ],
          'album': {'id': 6, 'mid': 'album-3', 'name': '飞鸟'},
          'interval': 240,
        },
        {
          'id': 999999,
          'mid': 'mid-new',
          'name': '日落以后',
          'singer': [
            {'id': 7, 'mid': 'singer-4', 'name': '新歌手'},
          ],
          'album': {'id': 8, 'mid': 'album-4', 'name': '日落'},
          'interval': 233,
        },
      ],
    },
  },
};

/// `fcg_v8_singer_detail_cp.fcg?singermid=003Nz2So3XXYek` (legacy artist page).
const Map<String, dynamic> kSingerDetail = {
  'code': 0,
  'getSingerInfo': {
    'Fother_name': 'Eason Chan',
    'Fsinger_id': '143',
    'Fsinger_mid': '003Nz2So3XXYek',
    'Fsinger_name': '陈奕迅',
  },
  'singerBrief': '陈奕迅（Eason Chan），1974年7月27日出生于香港。',
  'total_album': 103,
  'total_song': 1400,
  'getSongInfo': [
    {
      'songmid': '001OyHbk2MSIi4',
      'songname': '十年',
      'singer': [
        {'mid': '003Nz2So3XXYek', 'name': '陈奕迅'},
      ],
      'albummid': '000GDz8k03UOaI',
      'albumname': '黑白灰',
      'interval': 205,
      'extra': {'Flisten_count1': '118819802'},
    },
    {
      'songmid': '001fsNdn1zuZnA',
      'songname': '我不难过',
      'singer': [
        {'mid': '001pWERg3vFgg8', 'name': '孙燕姿'},
      ],
      'albummid': '004VSvF52mQoQp',
      'albumname': '未完成',
      'interval': 320,
      'extra': {'Flisten_count1': '999999'},
    },
  ],
};

/// `music.musichallSinger.SingerInfoInter/GetSingerDetail` — the only source of
/// the artist avatar (`basic_info.singer_pmid` / `pic.pic`).
const Map<String, dynamic> kSingerProfile = {
  'code': 0,
  'singer': {
    'code': 0,
    'data': {
      'singer_list': [
        {
          'basic_info': {
            'singer_mid': '003Nz2So3XXYek',
            'name': '陈奕迅',
            'singer_id': 143,
            'singer_pmid': '003Nz2So3XXYek_4',
          },
          'ex_info': {'desc': '陈奕迅（Eason Chan）…'},
          'pic': {
            'big_black': 'https://y.gtimg.cn/music/photo_new/T001V28M301003Nz2So3XXYek_4.jpg',
            'pic': 'http://y.gtimg.cn/music/photo_new/T001R300x300M000003Nz2So3XXYek_4.jpg',
          },
        },
      ],
    },
  },
};

/// `music.musichallAlbum.AlbumListServer/GetAlbumList` — the module that works;
/// `music.musichallAlbum.AlbumListInter` answers `code 500003`.
const Map<String, dynamic> kSingerAlbumList = {
  'code': 0,
  'req_0': {
    'code': 0,
    'data': {
      'singerMid': '003Nz2So3XXYek',
      'total': 141,
      'albumList': [
        {
          'albumMid': '000J1pJ50cDCVE',
          'albumName': '不想放手',
          'publishDate': '2008-06-30',
          'totalNum': 0,
          'albumType': '录音室专辑',
          'pmid': '000J1pJ50cDCVE_6',
          'albumID': 35182,
          'singerName': '陈奕迅',
        },
        {
          'albumMid': '000GDz8k03UOaI',
          'albumName': '黑白灰',
          'publishDate': '2003-04-15',
          'totalNum': 0,
          'albumType': '录音室专辑',
          'pmid': '000GDz8k03UOaI_2',
          'albumID': 89526,
          'singerName': '陈奕迅',
        },
      ],
    },
  },
};

/// `music.search.SearchCgiService/DoSearchForQQMusicMobile` with
/// `search_type: 2` — the album-search fallback (`body.item_album.list[]`).
/// Note `singer_list[].mid` is empty here, so filtering uses `singer_id`.
const Map<String, dynamic> kAlbumSearch = {
  'code': 0,
  'req_0': {
    'code': 0,
    'data': {
      'body': {
        'item_album': {
          'list': [
            {
              'albummid': '002gBayj0ZPoR0',
              'name': 'Eason Chan Duo Concert 2010',
              'pic': 'http://y.gtimg.cn/music/photo_new/T002R180x180M000002gBayj0ZPoR0_1.jpg',
              'publish_date': '2010-07-02',
              'song_num': 37,
              'singer': '<em>陈奕迅</em>',
              'singer_id': '143',
              'singer_list': [
                {'id': 143, 'mid': '', 'name': '陈奕迅'},
              ],
            },
            {
              'albummid': '0001RB271K1UCi',
              'name': 'FEAR and DREAMS',
              'pic': 'http://y.gtimg.cn/music/photo_new/T002R180x180M0000001RB271K1UCi_1.jpg',
              'publish_date': '2025-08-25',
              'song_num': 31,
              'singer': '<em>陈奕迅</em>',
              'singer_id': '143',
              'singer_list': [
                {'id': 143, 'mid': '', 'name': '陈奕迅'},
              ],
            },
            {
              'albummid': 'unrelated-album',
              'name': '别人的专辑',
              'publish_date': '2024-01-01',
              'song_num': 10,
              'singer': '<em>其他歌手</em>',
              'singer_id': '999',
              'singer_list': [
                {'id': 999, 'mid': '', 'name': '其他歌手'},
              ],
            },
          ],
        },
      },
    },
  },
};

/// `fcg_v8_album_info_cp.fcg?albummid=004VSvF52mQoQp`.
const Map<String, dynamic> kAlbumInfo = {
  'code': 0,
  'data': {
    'aDate': '2003-01-10',
    'company': '华纳唱片',
    'cur_song_num': 2,
    'desc': '孙燕姿 未完成 to be continued。',
    'genre': 'Pop 流行',
    'lan': '国语',
    'mid': '004VSvF52mQoQp',
    'name': '未完成',
    'singermid': '001pWERg3vFgg8',
    'singername': '孙燕姿',
    'total_song_num': 2,
    'list': [
      {
        'songmid': '000KgIso4SbK9e',
        'songname': '神奇',
        'singer': [
          {'id': 109, 'mid': '001pWERg3vFgg8', 'name': '孙燕姿'},
        ],
        'albummid': '004VSvF52mQoQp',
        'albumname': '未完成',
        'interval': 262,
      },
      {
        'songmid': '001fsNdn1zuZnA',
        'songname': '我不难过',
        'singer': [
          {'id': 109, 'mid': '001pWERg3vFgg8', 'name': '孙燕姿'},
        ],
        'albummid': '004VSvF52mQoQp',
        'albumname': '未完成',
        'interval': 320,
      },
    ],
  },
};

/// `newsong.NewSongServer/get_new_song_info` — QQ ignores `num`: asking for 3
/// returns 32 rows, so the platform truncates client-side.
const Map<String, dynamic> kNewSongs = {
  'code': 0,
  'newsong': {
    'code': 0,
    'data': {
      'type': 5,
      'songlist': [
        {
          'id': 728759642,
          'mid': '00388U1G0yN0lK',
          'name': '蜚蜚',
          'singer': [
            {'id': 7733770, 'mid': '0046i1Eh0A9NCk', 'name': '亿轩_Kingston'},
          ],
          'album': {
            'id': 103078993,
            'mid': '003K21up4crPBp',
            'name': '煙灰Ash 影视原声带',
          },
          'interval': 220,
          'time_public': '2026-09-22',
        },
        {
          'id': 728759643,
          'mid': 'new-mid-2',
          'name': '新歌二',
          'singer': [
            {'id': 1, 'mid': 'singer-x', 'name': '歌手X'},
          ],
          'album': {'id': 9, 'mid': 'new-album-2', 'name': '新专辑二'},
          'interval': 180,
          'time_public': '2026-09-21',
        },
        {
          'id': 728759644,
          'mid': 'new-mid-3',
          'name': '新歌三',
          'singer': [
            {'id': 2, 'mid': 'singer-y', 'name': '歌手Y'},
          ],
          'album': {'id': 10, 'mid': 'new-album-3', 'name': '新专辑三'},
          'interval': 195,
          'time_public': '2026-09-20',
        },
      ],
    },
  },
};
