# 网易云 WS-B 端点实测（明文 /api/）

- 运行时间: 2026-10-06T22:26:44.743068
- Dart: 3.13.4 (stable) (Tue Sep 15 01:01:15 2026 -0700) on "windows_x64"
- 目标: https://music.163.com （明文 /api/，无 weapi/eapi 加密）
- cookie: `os=pc; appver=3.0.18.203152; …`（与 NeteaseApi 一致）

## 1. getToplists — GET /api/toplist

- OK (http 200), 耗时 236ms
- 顶层字段: code, list, artistToplist
- code=200
- `list` 长度: 63
- `list[0]` 字段: subscribers, subscribed, creator, artists, tracks, updateFrequency, backgroundCoverId, backgroundCoverUrl, titleImage, coverText, titleImageUrl, coverImageUrl, iconImageUrl, englishTitle, opRecommend, recommendInfo, socialPlaylistCover, tsSongCount, algType, originalCoverId, topTrackIds, promptedMgcInfo, playlistType, uiPlaylistType, trackNumberUpdateTime, trackUpdateTime, privacy, highQuality, specialType, updateTime, newImported, anonimous, coverImgId, coverImgUrl, trackCount, commentThreadId, totalDuration, playCount, mix, adType, …(52 keys)
- `list[0]` 样本: {"subscribers":[],"subscribed":null,"creator":null,"artists":null,"tracks":null,"updateFrequency":"刚刚更新","backgroundCoverId":0,"backgroundCoverUrl":null,"titleImage":0,"coverText":null,"titleImageUrl":null,"coverImageUrl":null,"iconImageUrl":null,"englishTitle":null,"opRecommend":false,"recommendInfo":null,"socialPlaylistCover":null,"tsSongCount":0,"algType":null,"originalCoverId":0,"topTrackIds":null,"promptedMgcInfo":null,"playlistType":"UGC","uiPlaylistType":"UGC","trackNumberUpdateTime":1791…(len=1139)
  - 契约字段 `id`: 存在
  - 契约字段 `name`: 存在
  - 契约字段 `coverImgUrl`: 存在
  - 契约字段 `updateFrequency`: 存在
  - 契约字段 `trackNumberUpdate`: **缺失**
- 字段类型抽样(list[0..2]):
  - `id`: int
  - `name`: String
  - `coverImgUrl`: String
  - `updateFrequency`: String
  - `trackNumberUpdate`: null
  - `playCount`: int
  - `description`: String

## 2. getRankedSongs — POST /api/v6/playlist/detail

- OK (http 200), 耗时 417ms
- 顶层字段: code, relatedVideos, playlist, urls, privileges, sharedPrivilege, resEntrance, fromUsers, fromUserCount, songFromUsers
- code=200
- `playlist` 字段: id, name, coverImgId, coverImgUrl, coverImgId_str, adType, userId, createTime, status, opRecommend, highQuality, newImported, updateTime, trackCount, specialType, privacy, trackUpdateTime, commentThreadId, playCount, trackNumberUpdateTime, subscribedCount, cloudTrackCount, ordered, description, tags, updateFrequency, backgroundCoverId, backgroundCoverUrl, titleImage, titleImageUrl, detailPageTitle, englishTitle, officialPlaylistType, copied, relateResType, coverStatus, mix, subscribers, subscribed, creator, …(68 keys)
- `playlist.name` = 热歌榜
- `playlist.updateTime` = 1791247481977
- `playlist.tracks` 长度: 200
- `playlist.trackIds` 长度: 200
- `playlist.trackCount` = 200
- `tracks[0]` 字段: name, mainTitle, additionalTitle, id, pst, t, ar, alia, pop, st, rt, fee, v, crbt, cf, al, dt, h, m, l, sq, hr, a, cd, no, rtUrl, ftype, rtUrls, djId, copyright, s_id, mark, originCoverType, originSongSimpleData, tagPicList, resourceState, version, songJumpInfo, entertainmentTags, awardTags, …(55 keys)
- `tracks[0]` 样本: {"name":"海屿你","mainTitle":null,"additionalTitle":null,"id":1973665667,"pst":0,"t":0,"ar":[{"id":13288861,"name":"马也_Crabbit","tns":[],"alias":[]}],"alia":["求你别离开我"],"pop":100.0,"st":0,"rt":"","fee":8,"v":54,"crbt":null,"cf":"","al":{"id":150006421,"name":"海屿你","picUrl":"http://p4.music.126.net/RfguLkQJ8aMVkiIaxdy70Q==/109951170483263672.jpg","tns":[],"pic_str":"109951170483249998","pic":109951170483249998},"dt":295940,"h":{"br":320000,"fid":0,"size":11839725,"vd":-52137.0,"sr":48000},"m":{"br":1…(len=1268)
- 结论: tracks 已含完整歌曲对象 = true
- `trackIds[0]` = {"id":1973665667,"v":20,"t":0,"at":1767573351833,"alg":null,"uid":1,"rcmdReason":"","rcmdReasonTitle":"编辑推荐","sc":null,"…(len=163)
- 分页判定: tracks(200) vs trackIds(200) → 需要 trackIds 补齐 = false

- 对照: `n=50` → OK (http 200)
  - tracks=50 trackIds=200

## 3. getNewSongs — GET /api/personalized/newsong

- 无 type 参数: OK (http 200), 耗时 133ms
- 顶层字段: code, category, result
- code=200, result 长度=20
- `result[0]` 字段: id, type, name, copywriter, picUrl, canDislike, trackNumberUpdateTime, song, alg
- `result[0].type` = 4
- `result[0].id` = 3433437362
- `result[0].name` = 两难pt.2
- `result[0].song` 存在 = true，字段: name, id, position, alias, status, fee, copyrightId, disc, no, artists, album, starred, popularity, score, starredNum, duration, playedNum, dayPlays, hearTime, sqMusic, hrMusic, ringtone, crbt, audition, copyFrom, commentThreadId, rtUrl, ftype, rtUrls, copyright, transName, sign, mark, originCoverType, originSongSimpleData, single, noCopyrightRcmd, hMusic, mMusic, lMusic, …(47 keys)
- `result[0]` 样本: {"id":3433437362,"type":4,"name":"两难pt.2","copywriter":null,"picUrl":"http://p1.music.126.net/jr4V-LHARj4EGtLeDCLB_Q==/109951173909480514.jpg","canDislike":false,"trackNumberUpdateTime":null,"song":{"name":"两难pt.2","id":3433437362,"position":0,"alias":[],"status":0,"fee":8,"copyrightId":0,"disc":"01","no":1,"artists":[{"name":"加木","id":49320722,"picId":0,"img1v1Id":0,"briefDesc":"","picUrl":"","img1v1Url":"http://p3.music.126.net/6y-UleORITEDbvrOLV0Q8A==/5639395138885805.jpg","albumSize":0,"alias":[],"trans":"","musicSize":0,"topicPerson":0}],"album":{"name":"两难pt.2","id":397217802,"type":"Sin…(len=3985)
- 全量 `type` 取值集合: [4]
- type=="song" 条数: 0

- `type=7`: OK (http 200), code=200, result=5, 首条 type=4

- `type=96`: OK (http 200), code=200, result=5, 首条 type=4

- `type=8`: OK (http 200), code=200, result=5, 首条 type=4

- `type=16`: OK (http 200), code=200, result=5, 首条 type=4
- 地区探测 `type=0`: OK (http 200), code=200, result=3, 首条 type=4
- 地区探测 `type=6`: OK (http 200), code=200, result=3, 首条 type=4
- 地区探测 `type=14`: OK (http 200), code=200, result=3, 首条 type=4
- 地区探测 `type=60`: OK (http 200), code=200, result=3, 首条 type=4

## 4. getArtistDetail — POST /api/artist/head/info/get

- OK (http 200), 耗时 92ms
- 顶层字段: code, message, data
- code=200
- 样本: {"code":200,"message":"ok","data":{"videoCount":8,"identify":{"imageUrl":null,"imageDesc":"歌手、作词、作曲、编曲、制作人、乐手","actionUrl":"orpheus://rnpage?component=music-reactnative-artistwiki&split=index&artistId=6452"},"artist":{"id":6452,"cover":"http://p4.music.126.net/NWv6PtSBkyWZzqbJVzBr7g==/109951169164936450.jpg","avatar":"http://p4.music.126.net/_ECPuM0s0qtWhkpQOSTZUg==/109951169164936940.jpg","name":"周杰伦","transNames":[],"alias":["Jay Chou","周董"],"identities":["作曲"],"identifyTag":null,"briefDesc":"周杰伦（Jay Chou），1979年1月18日出生于台湾省新北市，祖籍福建省永春县，华语流行乐男歌手、音乐人、演员、导演，毕业于淡江中学 。\n2000年，发行个人首张音乐专辑《Jay》 ，并在华语…(len=1759)

## 4b. getArtistDetail 备选 — GET /api/artist/{id}

- OK (http 200), 耗时 140ms
- 顶层字段: artist, hotSongs, more, code
- `artist` 字段: img1v1Id, topicPerson, briefDesc, picId, musicSize, albumSize, picUrl, img1v1Url, followed, trans, alias, name, id, publishTime, picId_str, img1v1Id_str, mvSize
- `artist.name` = 周杰伦
- `artist.picUrl` = https://p3.music.126.net/NWv6PtSBkyWZzqbJVzBr7g==/109951169164936450.jpg
- `artist.briefDesc` = 
- `artist.musicSize` = 568
- `artist.albumSize` = 44
- `artist.fansCount`(粉丝) = null
- `hotSongs` 长度: 50
- `hotSongs[0]` 字段: starred, popularity, starredNum, playedNum, dayPlays, hearTime, mp3Url, rtUrls, mark, noCopyrightRcmd, originCoverType, originSongSimpleData, artistClassics, songJumpInfo, artists, copyrightId, album, score, hMusic, mMusic, lMusic, audition, copyFrom, ringtone, disc, no, fee, mvid, bMusic, sqMusic, hrMusic, crbt, rtUrl, ftype, rtype, rurl, duration, status, alias, name, …(41 keys)
- `hotSongs[0]` 样本: {"starred":false,"popularity":100.0,"starredNum":0,"playedNum":0,"dayPlays":0,"hearTime":0,"mp3Url":"http://m2.music.126.net/hmZoNQaqzZALvVp0rE7faA==/0.mp3","rtUrls":null,"mark":17179877376,"noCopyrightRcmd":null,"originCoverType":0,"originSongSimpleData":null,"artistClassics":null,"songJumpInfo":null,"artists":[{"img1v1Id":18686200114669622,"topicPerson":0,"briefDesc":"","picId":0,"musicSize":0,"albumSize":0,"picUrl":"","img1v1Url":"https://p4.music.126.net/VnZiScyynLG7atLIZ2YPkw==/186862001146…(len=3146)
- 结论: 该端点一次返回 信息+热门 = true

## 4c. getArtistTopSongs 备选 — GET /api/artist/top/song

- OK (http 200), 耗时 108ms
- 顶层字段: code, more, songs
- `songs` 长度: 50
- `songs[0]` 字段: name, mainTitle, additionalTitle, id, pst, t, ar, alia, pop, st, rt, fee, v, crbt, cf, al, dt, h, m, l, sq, hr, a, cd, no, rtUrl, ftype, rtUrls, djId, copyright, s_id, mark, originCoverType, originSongSimpleData, tagPicList, resourceState, version, songJumpInfo, entertainmentTags, awardTags, …(54 keys)
- `songs[0]` 样本: {"name":"布拉格广场","mainTitle":null,"additionalTitle":null,"id":210049,"pst":0,"t":0,"ar":[{"id":7219,"name":"蔡依林","tns":[],"alias":[]},{"id":6452,"name":"周杰伦","tns":[],"alias":[]}],"alia":["单元剧《上班女郎》主题曲"],"pop":100.0,"st":0,"rt":"600902000000210868","fee":1,"v":98,"crbt":null,"cf":"","al":{"id":21349,"name":"看我72变","picUrl":"https://p4.music.126.net/8D2Pd7EuvGboMyE2xWc47A==/109951172453712025.jpg","…(len=2154)

## 5. getArtistAlbums — GET /api/artist/albums/{id}

- OK (http 200), 耗时 54ms
- 顶层字段: code, artist, hotAlbums, more, kindTabs
- code=200, more=true
- `hotAlbums` 长度: 5
- `hotAlbums[0]` 字段: songs, paid, onSale, mark, awardTags, displayTags, briefDesc, publishTime, company, artists, copyrightId, picId, artist, picUrl, commentThreadId, blurPicUrl, companyId, pic, subType, status, description, tags, alias, name, id, type, size, picId_str
- `hotAlbums[0]` 样本: {"songs":[],"paid":false,"onSale":false,"mark":0,"awardTags":null,"displayTags":null,"briefDesc":"","publishTime":1749139200000,"company":"杰威尔","artists":[{"img1v1Id":18686200114669622,"topicPerson":0,"briefDesc":"","musicSize":0,"albumSize":0,"picId":0,"picUrl":"","img1v1Url":"https://p3.music.126.net/VnZiScyynLG7atLIZ2YPkw==/18686200114669622.jpg","followed":false,"trans":"","alias":[],"name":"周杰伦","id":6452,"img1v1Id_str":"18686200114669622"}],"copyrightId":0,"picId":109951171855827699,"artis…(len=1339)
  - `hotAlbums[0].id`: 274336916
  - `hotAlbums[0].name`: 即兴曲
  - `hotAlbums[0].picUrl`: https://p3.music.126.net/O3jMNNilsLAdv1L85QlRZg==/1099511718…(len=72)
  - `hotAlbums[0].publishTime`: 1749139200000
  - `hotAlbums[0].size`: 1
  - `hotAlbums[0].company`: 杰威尔
  - `hotAlbums[0].artist`: {"img1v1Id":18686200114669622,"topicPerson":0,"briefDesc":""…(len=434)
  - `hotAlbums[0].description`: 
- 对照 `offset=5&limit=5`: OK (http 200), hotAlbums=5, 首条 id=90743831

## 6. getAlbumDetail — GET /api/v1/album/{id}

- 使用 albumId=274336916
- OK (http 200), 耗时 87ms
- 顶层字段: resourceState, songs, code, album
- code=200
- `album` 字段: songs, paid, onSale, mark, awardTags, displayTags, picId, artist, artists, copyrightId, publishTime, company, briefDesc, picUrl, commentThreadId, blurPicUrl, companyId, pic, subType, status, description, tags, alias, name, id, type, size, picId_str, info
  - `album.id`: 274336916
  - `album.name`: 即兴曲
  - `album.picUrl`: https://p3.music.126.net/O3jMNNilsLAdv1L85QlRZg==/109951171855827699.jpg
  - `album.publishTime`: 1749139200000
  - `album.size`: 1
  - `album.company`: 
  - `album.description`: 置身Beatles录音室　周杰伦一气呵成创作「即兴曲」
     乐坛天王周杰伦创作出许多脍炙人口的畅销歌曲，灵光乍现的瞬间，每每留下经典隽永的作品！这段造访英…(len=441)
  - `album.artist`: {"img1v1Id":109951169164936940,"topicPerson":0,"picId":109951169164936450,"brief…(len=437)
  - `album.subType`: 录音室版
  - `album.genre`: **缺失**
- `songs` 长度: 1
- `songs[0]` 字段: rtUrls, ar, al, st, noCopyrightRcmd, artistClassics, songJumpInfo, djId, no, fee, mv, cd, t, v, dt, rtype, rurl, pst, alia, pop, rt, mst, cp, crbt, cf, h, sq, hr, l, rtUrl, ftype, mark, a, m, name, id, privilege
  - `songs[0].id`: 2712553851
  - `songs[0].name`: 即兴曲
  - `songs[0].ar`: [{"id":6452,"name":"周杰伦","alia":["Jay Chou","周董"]}]
  - `songs[0].al`: {"id":274336916,"name":"即兴曲","picUrl":"https://p3.music.126.…(len=169)
  - `songs[0].dt`: 99000
  - `songs[0].no`: 1
- `songs[0]` 样本: {"rtUrls":[],"ar":[{"id":6452,"name":"周杰伦","alia":["Jay Chou","周董"]}],"al":{"id":274336916,"name":"即兴曲","picUrl":"https://p3.music.126.net/O3jMNNilsLAdv1L85QlRZg==/109951171855827699.jpg","pic_str":"109951171855827699","pic":109951171855827699},"st":-1,"noCopyrightRcmd":null,"artistClassics":null,"songJumpInfo":null,"djId":0,"no":1,"fee":0,"mv":0,"cd":"01","t":0,"v":4,"dt":99000,"rtype":0,"rurl":null,"pst":0,"alia":["Improvisation"],"pop":5.0,"rt":"","mst":9,"cp":0,"crbt":null,"cf":"","h":{"br":…(len=1863)
- 全量 `no` 序列: [1]

## 7. 字段级深挖（决定解析代码怎么写）

### 7a. `POST /api/artist/head/info/get` → `data.artist`
- `data` 字段: videoCount, identify, artist, blacklist, preferShow, showPriMsg, secondaryExpertIdentiy
- `data.artist` 字段: id, cover, avatar, name, transNames, alias, identities, identifyTag, briefDesc, rank, albumSize, musicSize, mvSize
  - `data.artist.id`: 6452
  - `data.artist.name`: 周杰伦
  - `data.artist.cover`: http://p4.music.126.net/NWv6PtSBkyWZzqbJVzBr7g==/109951169164936450.jpg
  - `data.artist.avatar`: http://p4.music.126.net/_ECPuM0s0qtWhkpQOSTZUg==/109951169164936940.jpg
  - `data.artist.briefDesc`: 周杰伦（Jay Chou），1979年1月18日出生于台湾省新北市，祖籍福建省永春县，华语流行乐男歌手、音乐人、演员、导演，毕业于淡江中学 。
2000年，发行个人首张音乐专辑《Jay》 ，并在华语乐…(len=665)
  - `data.artist.musicSize`: 568
  - `data.artist.albumSize`: 44
  - `data.artist.fansCount`: **缺失**
  - `data.artist.followCount`: **缺失**
  - `data.artist.albumSizeS`: **缺失**
  - `data.artist.songSize`: **缺失**
  - `data.artist.mvCount`: **缺失**
  - `data.artist.identities`: ["作曲"]
  - `data.artist.alias`: ["Jay Chou","周董"]
- `data.artist.briefDesc` 长度: 665

### 7b. `GET /api/personalized/newsong` type 取值与 `song` 字段命名
- 条数: 100
- `type` 取值集合: {4 (int)}
- 含 `song` 子对象的条数: 100/100
- `song` 是否用搜索接口的 ar/al/dt 命名: ar=false al=false dt=false
- `song` 是否用 artists/album/duration 命名: artists=true album=true duration=true
- `song.artists[0]` = {"name":"加木","id":49320722,"picId":0,"img1v1Id":0,"briefDesc":"","picUrl":"","img1v1Url":"http://p3.music.126.net/6y-UleORITEDbvrOLV0Q8A==/56393951388…(len=227)
- `song.album` 字段 = name, id, type, size, picId, blurPicUrl, companyId, pic, picUrl, publishTime, description, tags, company, briefDesc, artist, songs, alias, status, copyrightId, commentThreadId, artists, subType, transName, onSale, mark, gapless, dolbyMark, picId_str
- `song.duration` = 259956

### 7c. 地区 type 是否真的改变结果
- `type=0` → [两难pt.2, 牵我的手好吗, Rendezvous, 全息恋人, 花骨朵]
- `type=7` → [两难pt.2, 牵我的手好吗, Rendezvous, 全息恋人, 花骨朵]
- `type=96` → [两难pt.2, 牵我的手好吗, Rendezvous, 全息恋人, 花骨朵]
- `type=8` → [两难pt.2, 牵我的手好吗, Rendezvous, 全息恋人, 花骨朵]
- `type=16` → [两难pt.2, 牵我的手好吗, Rendezvous, 全息恋人, 花骨朵]
- `type=6` → [两难pt.2, 牵我的手好吗, Rendezvous, 全息恋人, 花骨朵]
- `type=14` → [两难pt.2, 牵我的手好吗, Rendezvous, 全息恋人, 花骨朵]
- `type=60` → [两难pt.2, 牵我的手好吗, Rendezvous, 全息恋人, 花骨朵]
- 不同 type 得到的不同结果组数: 1 / 8
- 结论: 地区过滤 **无效（所有 type 返回同一批歌曲）**

### 7d. 多曲目专辑 `no` 序列（trackNumber 依据）
- 取回 30 张专辑
- `size` 最大者: id=2489195 name=天台 电影原声带 size=35 company=杰威尔 artistName=周杰伦
- `hotAlbums[]` 里 `artist`/`artists[0]` 命名: artist=true artists=true
- 详情 `size`=35 顶层 `songs`=35 `album.songs`=0
- `no` 序列: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35]
- `no` 是否 1..N 连续: true
- `album.tags` = , `album.genre` 存在=false
- `album.info` 字段 = commentThread, latestLikedUsers, liked, comments, resourceType, resourceId, commentCount, likedCount, shareCount, threadId
- `album.company`(大专辑) = 杰威尔
- 顶层 `songs[0].ar`/`al`/`dt` = true/true/true

### 7e. 地区筛选的其他候选端点
- `type=0` → `category`=5, 歌名=[两难pt.2, 牵我的手好吗, Rendezvous]
- `type=7` → `category`=5, 歌名=[两难pt.2, 牵我的手好吗, Rendezvous]
- `type=96` → `category`=5, 歌名=[两难pt.2, 牵我的手好吗, Rendezvous]
- `type=8` → `category`=5, 歌名=[两难pt.2, 牵我的手好吗, Rendezvous]
- `type=16` → `category`=5, 歌名=[两难pt.2, 牵我的手好吗, Rendezvous]
- GET `/api/v1/discovery/new/songs?areaId=0` → OK (http 200), code=200, 条数=100, 歌名=[Birth, 月姑姑, 这么爱你为什么, MELTING SNOW 雪融, Butterfly Girl, 失序爱, Fukk A Interview, Brand New, 纸飞机, If You Don’t Mean It (ถ้าไม่คิด อย่าทำให้คิด), 不擅生长的树, 宿草经年, Honey Butter, 倾斜的婚礼, 命运在手心（feat.初音ミク&洛天依）, Sleeping like a log, Night Shift, Sweet Sweet Boy, Business & Personal (Intro), 我不想孤独的离开, いつまでも, Encore（无尽夏）, 天上地下, 小小的眼泪, 天海一心, Little Bouquet, 你是真的不懂, うつくしじごく, 本原(TheVeryBeginning), 3 Years, 再会日暮里, 天海一心, My Summer Rain (Live), 成为你想成为的大人 – From THE FIRST TAKE, 眼里的蓝(feat. 袁娅维TIA RAY), 纠（feat.黄誉博）, 落叶知秋🍂, 想要在你生日为你奔赴几万里, 冬蛾 (feat.早安), 北征赋, 我系我 (Short Version), 野火, 瓷话千秋, 我和春天有个约会, Pretty, 余悸, 呼吸, 能不能成为你的唯一, Don’t Wanna Know, 爱错 (feat. 单依纯)(Live), 才发现最喜欢是过万圣节, Black Veil Bride, 虚构, MAGIC, 跟悲伤结了帐, 悼念爱情, 秋实丹, 生活麻辣烫, The Fate of Ophelia (Alone In My Tower Acoustic Version), 气势如虹 (粤语版), Intro：翻山越岭, 气势如虹, 弦歌月明, One night in 解放碑, Make A Wish, 水仙倒影, 岁穗, 烂人, 52Hz鲸鱼, 下一页, 顽疾 (Live), The Cure, Chariot, 诗人与商人, 可以是朋友, K歌之王 AIR (Night Version), 骊龙吟, K歌之王 AIR (Day Version), 不沐春风不遇你, 你是我的风景 (2025), 自恋是骄傲, 有且, 意外勇敢的脸庞, 不要骗我, 房间里的大象, Bonus track 暧昧（2025 Version）, 如果不是我的 (电影《女孩》主题曲), 勇敢的心(《故事奶奶》动画片片头曲), 一小部分的我, นับหนึ่ง (From now on), 没了命爱你, 花开中国 (中英文版本 舒楠监制), 为爱狂欢, 冠冕, 风火戏, 耍赖, 月光光, Changes, 马师, f.r.i.e.n.d.s]
- GET `/api/v1/discovery/new/songs?areaId=7` → OK (http 200), code=200, 条数=100, 歌名=[要去什么地方, 归城, 温柔的存在, Thank You, 沧海一粟, Mars（火星）, GO GIRL, 破局者, 英雄本色 The Essence Of A Hero, 成功它会奖励一直在前进的人, 总有一天会再见到你, 乘着大热气球, 说分手的人也会难过, 冲破迷雾, 我就是赤峰, 待解锁, 最浪漫的或许是, 聪明, 雾渡, 我只是个配角而已 (DJ版), 醒时歌, Town/Blunt (Extended Intro Remix), Intro宿命, 自由的你, 一诺为家, 爱已经无路可退 (DJ版), 小团圆（China-E）, 时间的年轮, DOSE, 潮, 动物园梦游 (影集《动物园》片头曲), 拜青山, See You in the Dark, 一双草鞋万里路, 人生天地间, 感官, 感物赋, BOW DOWN, heartman., 月亮与星光, Free Time, 一遍又一遍, 风之谷(live), 越, 风之谷, Dear John (Live), 还不快来尝尝石河子的凉皮, 拟生态, 我要吃糖葫芦, 红色, 朴实, 1N ONLY, 悄悄, 思念顺着流水飘向你, 山居赋 上, 流星, 长路, 立潮头, 一念江山, 对手, 我和我的祖国, 简述中国, 山海入我怀, 时间的年轮, 现在空了, 月亮之下, 小孩角色卡, 拥夜Glow., 快点快点, “神童”专属EP-《阿开的避风港》, 1+1, 还能去哪里, 月光下的皮囊, 甲乙丙丁 (合唱版), 春眠下雨声, WHERE YOU AT, 随风飘逸 (台北的午后阵雨), 9.12 EDC PRE-PARTY @ WITCH SET 01, 无人知晓处爱你, 爱的码头, SPIRIT OF YOUTH（少年之气）, 360 (Feat. Mabelz PiXXiE), 心跳动 (2026), 关山酒, 城中村生存日记, EveryBodyKilla, Where Is My Sock? (Remix), 枫叶红透就枯黄, 爱你是我的秘密 (降调 DJ氛围版), 风吹过的轨迹, 我又想起那片繁华, 王之蔑视, 雨阑珊, 那就去看山吧, 音乐就要酱玩, 问号（Possession）, 初见她, 慢冷 (Live), Ice In My Walk, 薄荷糖口味的再见]
- GET `/api/v1/discovery/new/songs?areaId=96` → OK (http 200), code=200, 条数=100, 歌名=[Let’s Get Married, Party, AGUA, Versailles, So Good, Pillow Fight, Backwards, Bring It On, When In Rome, Bass Persuades, Weight Of It All, GASS (feat. Travis Scott), Nicole Kidman, LET ME BE, serena joy, SANYA, Solace Feat. Emily Vaughn, Mariô, All I Need (Intro), Serotonin, Bigger Than, Ai Caralho, Molly, DANGER DANGER, ANIMAL, Bonfire, Contact (Intro), Nights Prayed, Draw You Out, Drive My Car (2026 Mix), Prelude in D Major, BWV 925, Cuadros del Sur:XV. Gran Promenade Final, Guitarras & $hit, Rusty Intro, Backwards, Say My Name, Burnin' Deep, What's Up Man, In The Zone, Wait For Me, Bye Bye Inhibitions, World's Greatest, Big Ideas (feat. Rachel Brown), options, Mr Charm, c*ntry girl rock, Too Cute To Be Lonely, Paradise, Leave Me, XO, The Witcher 3: Wild Hunt - Remastered Orchestral Medley, pikito pikito, FMTYLM, Miku-Maxxing, Tomorrow Tonight, Singer, Light the Way, Inception/Intro - Unshatter Film Soundtrack (Live in São Paulo), Sunglasses, Polyester, Stray Dogs, Tough Love, Loser (Fcukers Remix), Zukara, Nothing Lasts Forever, Let's Ride, This Ain't Just Music, cool, Simulation, Ruin A Good Thing, Perreo, I Won’t Cry, Fireflies, There's Nothing Holdin' Me Back, While The Flood Rages, Runaway, Overture - The Flavors of Life, The Fate of Ophelia, Polka Dots and Moonbeams, Miami Vice, Save Me, Dynamo, Too Seksi, Love That I Like, The Movement, Violin Concerto No. 1 in F-Sharp Minor, Op. 14:I. Allegro moderato, The Fate of Ophelia, Air, 7 Miles High, Runaway, 叶隙之光 Light Through the Leaves, Booster Ignition, Angel Eyes, Danceteria Afterhours, Blink Twice, IT GOES... (ft. 吴栩维Noshvia), Roses, Mars（火星）, Celebration, what do I do]
- GET `/api/personalized/newsong/area?areaId=0` → OK (http 200), code=404, 条数=0, 歌名=[]
- GET `/api/personalized/newsong/area?areaId=7` → OK (http 200), code=404, 条数=0, 歌名=[]
- GET `/api/personalized/newsong/area?areaId=96` → OK (http 200), code=404, 条数=0, 歌名=[]
- POST `/api/v1/discovery/new/songs` (areaId=7) → OK (http 200), code=200, 顶层=data, code

### 7f. `GET /api/v1/discovery/new/songs` 细节
- 顶层字段: data, code
- `data` 条数（**请求 limit=3**）: 100 → limit 参数被服务端忽略
- `data[0]` 字段: starred, popularity, starredNum, playedNum, dayPlays, hearTime, albumData, mp3Url, rtUrls, privilege, videoInfo, relatedVideo, st, exclusive, copyrightId, alias, artists, score, album, commentThreadId, fee, mvid, hMusic, mMusic, lMusic, rtype, rurl, disc, no, ringtone, crbt, bMusic, audition, copyFrom, rtUrl, ftype, duration, status, position, name, …(41 keys)
- `data[0]` 样本: {"starred":false,"popularity":100.0,"starredNum":0,"playedNum":0,"dayPlays":0,"hearTime":0,"albumData":null,"mp3Url":"http://m2.music.126.net/hmZoNQaqzZALvVp0rE7faA==/0.mp3","rtUrls":null,"privilege":{"id":3439441799,"fee":8,"payed":0,"st":0,"pl":320000,"dl":0,"sp":7,"cp":1,"subp":1,"cs":false,"maxbr":999000,"fl":320000,"toast":false,"flag":1544196,"preSell":false,"playMaxbr":999000,"downloadMaxbr":999000,"maxBrLevel":"jymaster","playMaxBrLevel":"jymaster","downloadMaxBrLevel":"jymaster","plLevel":"exhigh","dlLevel":"none","flLevel":"exhigh","rscl":null,"freeTrialPrivilege":{"resConsumable":false,"userConsumable":false,"listenType":null,"cannotListenReason":null,"playReason":null},"rightSour…(len=3505)
- 命名: ar=false al=false dt=false | artists=true album=true duration=true
- `data[0].ar[0]` = null
- `data[0].al` = null
- `data[0].dt` = null
- `offset=100`: 条数=100, 首条=要去什么地方, 与 offset=0 首条相同=true → offset **无效/被忽略**

- areaId 映射探测（取首 3 首歌名对比）：
  - areaId=0 → [Birth, 月姑姑, 这么爱你为什么]
  - areaId=7 → [要去什么地方, 归城, 温柔的存在]
  - areaId=96 → [Let’s Get Married, Party, AGUA]
  - areaId=8 → [Never Leave You feat. Stephanie, DEMON'S SHOT (feat. DEMONDICE), プロジェクト4]
  - areaId=16 → [new trick, 이 별로부터, Dear my crazy soulmate]
  - areaId=6 → []
  - areaId=14 → []
  - areaId=60 → []
  - areaId=3 → []
  - areaId=4 → []
- 不同 areaId 的不同结果组数: 6 / 10

### 7g. 榜单分页 `n` 语义
- `n=1000` tracks 前 5 首: [海屿你, 我不难过, 明知故犯, 甲乙丙丁 (你我怎么两清), 恋人]
- `n=3` tracks 长度=3, 歌名=[海屿你, 我不难过, 明知故犯]
- `n` 是否返回榜单前 n 首（顺序一致）: true
- id 序列一致: true ([1973665667, 287398, 3342319503] vs [1973665667, 287398, 3342319503])

## 汇总

| 端点 | 方法 | 判定 | 耗时 |
| --- | --- | --- | --- |
| `toplist` | GET | OK (http 200) | 236ms |
| `playlistDetail` | POST | OK (http 200) | 417ms |
| `playlistDetail(n=50)` | POST | OK (http 200) | 368ms |
| `newsong(default)` | GET | OK (http 200) | 133ms |
| `newsong(type=7)` | GET | OK (http 200) | 57ms |
| `newsong(type=96)` | GET | OK (http 200) | 64ms |
| `newsong(type=8)` | GET | OK (http 200) | 54ms |
| `newsong(type=16)` | GET | OK (http 200) | 65ms |
| `newsong(type=0)` | GET | OK (http 200) | 66ms |
| `newsong(type=6)` | GET | OK (http 200) | 55ms |
| `newsong(type=14)` | GET | OK (http 200) | 51ms |
| `newsong(type=60)` | GET | OK (http 200) | 71ms |
| `artistHeadInfo` | POST | OK (http 200) | 92ms |
| `artistLegacy` | GET | OK (http 200) | 140ms |
| `artistTopSong` | GET | OK (http 200) | 108ms |
| `artistAlbums` | GET | OK (http 200) | 54ms |
| `artistAlbums(offset=5)` | GET | OK (http 200) | 55ms |
| `albumDetail` | GET | OK (http 200) | 87ms |
| `newsong(limit=100)` | GET | OK (http 200) | 257ms |
| `newsong region names(type=0)` | GET | OK (http 200) | 57ms |
| `newsong region names(type=7)` | GET | OK (http 200) | 56ms |
| `newsong region names(type=96)` | GET | OK (http 200) | 116ms |
| `newsong region names(type=8)` | GET | OK (http 200) | 56ms |
| `newsong region names(type=16)` | GET | OK (http 200) | 54ms |
| `newsong region names(type=6)` | GET | OK (http 200) | 165ms |
| `newsong region names(type=14)` | GET | OK (http 200) | 54ms |
| `newsong region names(type=60)` | GET | OK (http 200) | 98ms |
| `artistAlbums(limit=30)` | GET | OK (http 200) | 85ms |
| `albumDetail(big)` | GET | OK (http 200) | 138ms |
| `newsong category(type=0)` | GET | OK (http 200) | 53ms |
| `newsong category(type=7)` | GET | OK (http 200) | 50ms |
| `newsong category(type=96)` | GET | OK (http 200) | 51ms |
| `newsong category(type=8)` | GET | OK (http 200) | 167ms |
| `newsong category(type=16)` | GET | OK (http 200) | 51ms |
| `newSongs /api/v1/discovery/new/songs areaId=0` | GET | OK (http 200) | 147ms |
| `newSongs /api/v1/discovery/new/songs areaId=7` | GET | OK (http 200) | 178ms |
| `newSongs /api/v1/discovery/new/songs areaId=96` | GET | OK (http 200) | 247ms |
| `newSongs /api/personalized/newsong/area areaId=0` | GET | OK (http 200) | 30ms |
| `newSongs /api/personalized/newsong/area areaId=7` | GET | OK (http 200) | 30ms |
| `newSongs /api/personalized/newsong/area areaId=96` | GET | OK (http 200) | 31ms |
| `POST /api/v1/discovery/new/songs` | POST | OK (http 200) | 185ms |
| `newSongs areaId=7 limit=3` | GET | OK (http 200) | 215ms |
| `newSongs areaId=7 offset=100` | GET | OK (http 200) | 213ms |
| `newSongs areaId=0` | GET | OK (http 200) | 233ms |
| `newSongs areaId=7` | GET | OK (http 200) | 206ms |
| `newSongs areaId=96` | GET | OK (http 200) | 267ms |
| `newSongs areaId=8` | GET | OK (http 200) | 265ms |
| `newSongs areaId=16` | GET | OK (http 200) | 312ms |
| `newSongs areaId=6` | GET | OK (http 200) | 38ms |
| `newSongs areaId=14` | GET | OK (http 200) | 40ms |
| `newSongs areaId=60` | GET | OK (http 200) | 38ms |
| `newSongs areaId=3` | GET | OK (http 200) | 41ms |
| `newSongs areaId=4` | GET | OK (http 200) | 39ms |
| `playlistDetail(n=3)` | POST | OK (http 200) | 307ms |

_由 `dart run scripts/test_netease_artist_album_toplist.dart` 生成；失败项即"未实测"，不得在实现中声称已验证。_
