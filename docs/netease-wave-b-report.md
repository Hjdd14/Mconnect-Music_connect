# WS-B（网易云 艺人/专辑/新歌/榜单）实测与实现报告

任务：`task-2`。写范围：`lib/platform/netease/**`、`scripts/test_netease_artist_album_toplist.dart`、`test/netease_*`。

两份证据：

| 文件 | 内容 | 生成方式 |
|---|---|---|
| `docs/netease-wave-b-probe.md` | **端点级**实测：19 个明文端点/参数组合的 HTTP 状态、字段名、样本值 | `dart run scripts/test_netease_artist_album_toplist.dart`（可重复执行，会覆盖本文件） |
| 本文 | **实现级**实测结论 + 对任务书契约的三处纠正 + 诚实降级清单 | `NETEASE_LIVE=1 flutter test --no-pub -j 1 test/netease_live_probe_test.dart` |

> 环境更正：任务书说"本机沙箱 HTTPS(443) 不可达（`curl https://...` 返回 http=000）"。
> 实测 **Dart/Flutter 侧 HTTPS 完全可用**：19 个端点全部 HTTP 200，`flutter test` 的
> live 探针 10/10 通过。只有 `curl` 不通（疑似 curl 自身/证书链问题），因此
> **没有任何端点需要按"未实测"降级**，全部按实测结果实现。

---

## 1. 对任务书契约的三处事实性纠正（都有实测证据）

### 1.1 `getNewSongs`：`result[].type` 是 **int 4**，不是字符串 `'song'`

任务书要求"必须过滤 `type=='song'`"。按字面实现会**把 100 条全部滤掉 → 恒返回空列表**。

```
probe 7b: newsong(limit=100) → `type` 取值集合: {4 (int)}；含 song 子对象: 100/100
```

正确做法（已实现，`netease_platform.dart:826-880`）：真实歌曲在 `result[].song`，
过滤条件接受 `type == 4 || type == 'song' || type == null`，并且**必须有 `song` 子对象**。
单测 `test/netease_content_test.dart` 里的
`getNewSongs falls back to personalized/newsong and filters type==4 (int), not the string "song"`
把这个行为钉死了。

另外该接口的 `song` 子对象用 `artists/album/duration` 命名，**不是** 搜索接口的 `ar/al/dt`。

### 1.2 `getToplists`：没有 `trackNumberUpdate` 字段

```
probe 1: `list[0]` 字段: …updateFrequency, trackNumberUpdateTime, trackCount…
        契约字段 `trackNumberUpdate`: **缺失**
```

真实字段：`id` / `name` / `coverImgUrl` / `updateFrequency` / **`trackCount`**（曲目数），
`trackNumberUpdateTime` 是毫秒时间戳。实现按 `trackCount` 取 `songCount`。

### 1.3 `/api/personalized/newsong?type=` **不筛选地区**；真正的地区端点是 `/api/v1/discovery/new/songs?areaId=`

```
probe 7c: type=0/7/96/8/16/6/14/60 → 8 种 type 返回**同一批歌曲**（不同结果组数: 1/8）
probe 7e: 同上，连响应里的 `category` 都是同一个值 5
probe 7f: /api/v1/discovery/new/songs?areaId=0/7/96/8/16 → 6 组不同结果
          areaId=6/14/60/3/4 → data 为空数组
```

所以地区筛选走 `areaId`：

| NewSongRegion | areaId | live 实测首曲 |
|---|---|---|
| all | 0 | Birth — EasyPop, 初音ミク, 巡音ルカ |
| chinese | 7 | 要去什么地方 — 田馥甄 |
| western | 96 | Let's Get Married — Miley Cyrus |
| japanese | 8 | Never Leave You feat. Stephanie — DJ OKAWARI |
| korean | 16 | new trick — ROSÉ |
| **hongKongTaiwan** | — | **网易云没有港台新歌速递**（6/14/60 全空）→ 抛 `UnsupportedActionException` |

live 探针还断言了 5 个地区的歌曲 id 集合两两不同（`distinct region result sets: 5/5`），
避免"地区筛选"变成假承诺。

---

## 2. 端点实测表（全部 HTTP 200）

| 端点 | 方法 | 用途 | 关键实测字段 |
|---|---|---|---|
| `/api/toplist` | GET | `getToplists` | `list[]`(63 条) `id/name/coverImgUrl/updateFrequency/trackCount` |
| `/api/v6/playlist/detail` | POST | `getRankedSongs`/`getRankingList` | `playlist.tracks[]` 完整歌曲；`n` = "前 n 首"（probe 7g 逐一对上）；`n` 只截 tracks 不截 trackIds |
| `/api/v1/discovery/new/songs` | GET | `getNewSongs` | `data[]`；**忽略 limit/offset，固定 100 条**；`artists/album/duration` 命名 |
| `/api/personalized/newsong` | GET | `getNewSongs` 兜底 | `result[].song`；`type` 恒为 int 4 |
| `/api/artist/head/info/get` | POST | `getArtistDetail` 首选 | `data.artist`：`name/cover/avatar/briefDesc(665 字)/musicSize/albumSize`；**无 fansCount** |
| `/api/artist/{id}` | GET | `getArtistDetail` 兜底 + `hotSongs` 兜底 | `artist{musicSize,albumSize}` + `hotSongs[]`(50)；`briefDesc` 是**空字符串** |
| `/api/artist/top/song?id=` | GET | `getArtistTopSongs` 首选 | `songs[]`(50)，`ar/al/dt` 命名 |
| `/api/artist/albums/{id}` | GET | `getArtistAlbums` | `hotAlbums[]{id,name,picUrl,publishTime,size,company,description,tags,artist}`；limit/offset 都生效 |
| `/api/v1/album/{id}` | GET | `getAlbumDetail`/`getAlbumSongs` | `album{}` + **顶层 `songs[]`**（`album.songs` 是空数组）；`no` = 1..N 连续 |

必须记住的两个"反直觉"点：

1. **同一实体两套字段名**。新接口用 `ar/al/dt`，旧接口（`hotSongs`、`newsong.song`、
   `discovery/new/songs`）用 `artists/album/duration`。只认一套会让另一套端点静默退化成
   "无名无歌手"。实现里 `_parseSong`（`netease_platform.dart:254`）两套都认。
2. **曲目在顶层 `songs[]`**：`/api/v1/album/{id}` 的 `album.songs` 实测为 `[]`，
   读它会得到 0 首。

---

## 3. 实现级 live 实测（`NETEASE_LIVE=1 flutter test test/netease_live_probe_test.dart`）

```
00:03 +10: All tests passed!

  toplist id=19723756 name=飙升榜 freq=刚刚更新 count=100 cover=https://p4.music.126.net/…
  toplist id=3779629 name=新歌榜 freq=刚刚更新 count=100 cover=https://p3.music.126.net/…
  toplist id=2884035 name=原创榜 freq=每周四更新 count=100 cover=https://p4.music.126.net/…
  getToplists -> 63 charts

  artist id=6452 name=周杰伦 avatar=http://p3.music.126.net/… songs=568 albums=44 fans=null briefDesc=665 chars

  topSong id=210049 name=布拉格广场 artists=蔡依林, 周杰伦 album=看我72变 cover=https://p4.music.126.net/… dur=294s
  topSong id=5257138 name=屋顶 artists=周杰伦, 温岚, 吴宗宪 album=男女情歌对唱冠军全记录 cover=https://p3.music.126.net/… dur=319s
  topSong id=509781655 name=想你就写信 (Live) artists=周杰伦, 李硕, 张鑫 album=中国新歌声第二季 第13期 cover=https://p3.music.126.net/… dur=238s
  getArtistTopSongs -> 50 songs

  album id=274336916 name=即兴曲 artist=周杰伦 tracks=1 company=杰威尔 date=2025-06-06 cover=https://p4.music.126.net/…
  album id=147779282 name=最伟大的作品 artist=周杰伦 tracks=12 company=杰威尔 date=2022-07-15 cover=https://p3.music.126.net/…
  page2 first id=90743831 name=Mojito            ← offset 真的生效

  albumDetail id=2489195 name=天台 电影原声带 tracks=35 company=杰威尔 artist=周杰伦 genre=null desc=201 chars date=2013-07-08
  albumSongs -> 35, trackNumbers=[1, 2, 3, 4, 5, 6, 7, 8, 9, 10]… first=美术馆

  region=NewSongRegion.all -> 5 songs, first=Birth artists=EasyPop, 初音ミク, 巡音ルカ
  region=NewSongRegion.chinese -> 5 songs, first=要去什么地方 artists=田馥甄
  region=NewSongRegion.western -> 5 songs, first=Let's Get Married artists=Miley Cyrus
  region=NewSongRegion.japanese -> 5 songs, first=Never Leave You feat. Stephanie artists=DJ OKAWARI
  region=NewSongRegion.korean -> 5 songs, first=new trick artists=ROSÉ
  distinct region result sets: 5/5

  rank=1 name=海屿你 artists=马也_Crabbit
  rank=2 name=我不难过 artists=孙燕姿
  rank=3 name=明知故犯 artists=Max李玄
  rank=4 name=甲乙丙丁 (你我怎么两清) artists=李佳薇
  rank=5 name=恋人 artists=李荣浩
  page2 -> 6:遐想, 7:茶汤, 8:碎碎念, 9:罗生门（Follow）, 10:玻璃

  rankingList -> 30, first=海屿你
```

live 探针同时断言了 `getAlbumSongs` 的 `trackNumber` 恰为 `1..N`、`getRankedSongs` 第 2 页
排名为 6..10 且与第 1 页 id 无交集（分页真的生效）、艺人简介 > 50 字（证明用的是
`head/info/get` 而不是 `briefDesc` 为空的旧接口）。

---

## 4. 诚实降级清单（没有编造任何数据）

| 位置 | 行为 | 依据 |
|---|---|---|
| `getNewSongs(region: hongKongTaiwan)` | 抛 `UnsupportedActionException`（"新歌速递不提供港台地区"） | areaId 6/14/60 实测 `data` 为空 |
| 非 `all` 地区请求失败 | 抛翻译后的 `ApiException`，**不**回退到 `personalized/newsong` | 该接口忽略地区参数，用它冒充"华语新歌"= 造假 |
| 艺人 `fansCount` | 恒 `null` | 两个端点实测都没有该字段 |
| 专辑 `genre` | 仅当 `album.tags` 非空时拼 `A/B`，否则 `null` | 实测无 `album.genre`，tags 多数为空 |
| `RankedSong.rankChange` / `isNew` | `null` / 不设置 | 网易云榜单不返回名次变化 |
| `getArtistDetail` 两端点都 200 但无艺人 | 返回 `null` | "服务端说没有" ≠ "请求失败" |
| `getArtistDetail` 两端点都没应答 | 抛 `apiExceptionOf(...)` 类型化异常 | 不把请求失败伪装成"没有这个艺人" |
| `getRankedSongs(period:)` | 忽略 | 网易云榜单不按周期寻址 |

---

## 5. 改动文件清单

| 文件 | 内容 |
|---|---|
| `lib/platform/netease/netease_endpoints.dart` | 补齐 8 个新端点 + 收拢原先内联的 9 处路径/URL（`baseUrl`、`qrLoginUrl()`、`songDetail`、`playlistCreate/Subscribe/Unsubscribe`、`playlistTrackManipulate`、`smsCaptchaSent`、`loginCellphone`） |
| `lib/platform/netease/netease_api.dart` | 默认 Dio 改走 `createPlatformDio(label: '网易云音乐')`；8 个新 API 方法；`get/post` 支持 `cancelToken` |
| `lib/platform/netease/netease_platform.dart` | 7 个平台方法 override + 3 个能力 getter；双字段名 `_parseSong`；播放失败改抛 typed 异常；取消不被兜底吞掉；`getRankingList` 走 `getRankedSongs` |
| `scripts/test_netease_artist_album_toplist.dart` | 新增（端点级探针，19 个组合，自动写 `docs/netease-wave-b-probe.md`） |
| `test/netease_content_test.dart` | 新增 25 个单测（每个新方法都有） |
| `test/netease_live_probe_test.dart` | 新增（10 个 live 探针，默认跳过，`NETEASE_LIVE=1` 打开） |
| `docs/netease-wave-b-probe.md`、`docs/netease-wave-b-report.md` | 证据与本报告 |

## 6. 门禁

```
# 1) 本任务范围内的静态检查
flutter analyze --no-pub lib/platform/netease test/netease_api_test.dart test/netease_content_test.dart scripts/test_netease_artist_album_toplist.dart
→ No issues found!

# 2) 整仓静态检查（最终态）
flutter analyze --no-pub
→ No issues found!

# 3) 网易云相关单测
flutter test --no-pub -j 1 test/netease_content_test.dart test/netease_api_test.dart
→ +32: All tests passed!        (新增 25 个 + 既有 7 个)

# 4) 整仓测试（最终态）
flutter test --no-pub -j 1
→ +572 ~10: All tests passed!   (~10 = 本任务的 live 探针，默认跳过)

# 5) 实现级 live 实测（打真实网络）
$env:NETEASE_LIVE=1; flutter test --no-pub -j 1 test/netease_live_probe_test.dart
→ +10: All tests passed!
```

（`test/netease_content_test.dart` 不设 `NETEASE_LIVE` 时是 `+0 ~10 All tests skipped`，
即默认门禁不含任何真实网络调用。）

### 6.1 红→绿验证（证明这些断言不是空断言）

把 `getNewSongs` 的兜底过滤**临时改回任务书写的 `type == 'song'`**：

```
flutter test --no-pub -j 1 test/netease_content_test.dart --plain-name "filters type==4"
→ Expected: ['A', 'D']
  Actual:   MappedListIterable<Song, String>:['D']      ← 真实的 type:4 条目全部被滤掉
  Failing tests: … getNewSongs falls back to personalized/newsong and filters type==4 …
```

改回 `type == 4 || type == 'song' || type == null` 后恢复 `+25: All tests passed!`。
即：**按任务书字面实现，真实歌曲会被 100% 滤掉**；这条断言真的在守这个行为。

另外两个 bug 是单测直接逼出来的（不是事后补的断言）：

1. 空 `data: []` 时 `(res['data'] as List?)?.first` 抛 `StateError: No element`，
   绕过了"歌曲不可用"的类型化异常（`netease_platform.dart:334-335`）。
2. `getArtistTopSongs` 首次看到 `songs: []` 就 `return`，导致旧接口的 50 首热门
   兜底永远走不到（`netease_platform.dart:691-694`）。

## 7. 需要 Lead 知道的三件事

1. **`cancelToken` 只能接到 API 层**。`MusicPlatform` 的方法签名在 Wave 0 冻结
   （`getToplists()` 等不接受 `CancelToken`），平台层没法从 UI 透传一个 token，
   所以 `NeteaseApi.get/post` 与新查询方法都加了可选 `CancelToken? cancelToken` 参数，
   平台层则保证**取消不会被兜底逻辑吞掉**（`_isCancellation` → `throw apiExceptionOf(e)`，
   类型保持 `RequestCancelledException`）。若要让 UI 真正能取消，需要扩契约。
2. **旧方法的"吞异常返回空"未动**。`getRankingList`/`search`/`getLyrics` 等既有实现仍然
   `catch → return []/null`。改成抛 typed 异常会影响既有调用方与测试，超出本任务范围，
   仅在报告里标注。
3. `docs/netease-wave-b-probe.md` 是脚本**覆盖写**的；重新跑探针脚本会覆盖它，但不会动本报告。
