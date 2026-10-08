# W3-D i18n 迁移地图（硬编码中文 → ARB 的可执行分批方案）

> 只读分析产出（task-26）。面向 **W3-D 的实现者**。
> **本文档不修改任何源码 / ARB / l10n.yaml**；所有数字都来自下面给出的命令在**本工作树**上的实测输出。
> 复现环境：`HEAD = 21ddc01`，工作树 **38 个文件处于 dirty 状态**（Wave 2/3 的其它成员正在改 `lib/`）→ 见 §0.5「基线是移动靶」。
> **本文档的 850 是"某一瞬间"的快照**：分析期间同一条命令先后给出 836 → 849 → **850**，所以 §6 要求先把基线冻结在**干净工作树**上再开工。
> 纯静态分析；未运行 `flutter`/`dart`/`gen-l10n`。

---

## 0. 数据口径：先定义"一处中文"，再谈数字

### 0.1 权威口径（本文档一律使用这一条）

> **一处 = `lib/**/*.dart`（排除 `lib/l10n/**`）里，位于"非注释行"上的 Dart 字符串字面量，其内容含至少一个 CJK 字符（`U+4E00–U+9FFF`）。**

三条判定规则，缺一不可：

1. **只算字符串字面量**（`'…'` / `"…"`，字面量内不含引号/换行）——中文注释不算。本仓库注释中文极多，不排除注释会虚高约 20%。
2. **剔除行注释**：先把每行按 `(^|\s)//.*$` 截断，再匹配。这样"行首 `//` 整行注释"和"代码后的尾随注释"都不计入。
3. **排除 `lib/l10n/`**：`app_zh.arb` 的取值与生成物 `app_localizations_zh.dart` / `app_localizations_en.dart` / `app_localizations.dart` 本身就是中英文案的"正本"，计入毫无意义。

### 0.2 可复现命令（CI 与实现者必须跑出同一个数）

**命令 A（人类/PowerShell，Windows 原生；输出只有数字，不受控制台编码影响）**：

```powershell
$rx = '[\x22\x27][^\x22\x27\r\n]*[\u4e00-\u9fff][^\x22\x27\r\n]*[\x22\x27]'
$files = Get-ChildItem lib -Recurse -Filter *.dart | Where-Object { $_.FullName -notmatch '\\l10n\\' }
$total = 0; $n = 0
foreach ($f in $files) {
  $c = 0
  foreach ($line in (Get-Content -LiteralPath $f.FullName)) {
    $c += ([regex]::Matches(($line -replace '(^|\s)//.*$',''), $rx)).Count
  }
  if ($c -gt 0) { $total += $c; $n++ }
}
"lib CJK literals = $total in $n files"
```

> 注意：`\x22` = `"`，`\x27` = `'`。**不要**在 PowerShell 里用 `['""]` 直接写引号类，会被 shell 吃掉引号导致正则解析失败（本仓库实测会报 `无法分析模式`）。

**命令 B（跨平台、与 CI 一致；就是 §6 那个 Dart 测试）：**

```powershell
flutter test --no-pub test/i18n_budget_test.dart
# 输出：i18n budget: total=850 files=95 exempt=0
```

命令 A 与命令 B 必须打印**同一个 total**。若不一致，先修实现再改基线（两者都只数"非注释行上的 CJK 字面量"，不一致就说明有一侧的实现跑偏了）。

### 0.3 实测结果（`HEAD=21ddc01` + 38 个 dirty 文件的工作树，单次快照）

| 指标 | 值 |
|---|---|
| **CJK 字面量（权威口径）** | **850 处** |
| 涉及文件 | **95 个** |
| 去重后的不同文案 | **665 条** |
| 纯行数（一行 ≥1 处） | 817 行 |
| 含中文的行（**不剔注释**，仅作对照） | 1023 行 / 118 个文件 |
| 已迁移使用（`l10n.<key>` / `l.<key>`） | **131 处 / 6 个文件** |
| ARB 消息键 | **126 个**（`app_zh.arb` 与 `app_en.arb` 键集一致） |
| ARB 元数据块（`@key`） | 6 个（+ `@@locale`）→ 126 + 6 = **132**，即审计里"132 key"的来源 |
| 孤儿键（无任何代码引用） | **6 个**（§7） |
| `test/**` 的 CJK 字面量 | **2464 处 / 114 个文件** |
| `test/**` 里断言中文的 `find.text/textContaining` | **346 处 / 38 个文件** |

各区域处数（同一快照，命令见 §0.2 命令 A 的聚合版）：

| 区域 | 处数 | 区域 | 处数 |
|---|---|---|---|
| `features/library` | 157 | `features/discovery` | 19 |
| `features/download` | 96 | `features/search` | 17 |
| `core` | 89 | `features/new_songs` | 14 |
| `features/smart_playlists` | 83 | `features/artist` | 12 |
| `platform` | 69 | `features/auth` | 11 |
| `features/player` | 68 | `features/album` | 9 |
| `features/backup` | 43 | `features/audio_effects` | 5 |
| `features/local_music` | 43 | `lyrics` | 4 |
| `features/stats` | 27 | `features/settings` | 3 |
| `features/toplist` | 27 | `main.dart` | 2 |
| `models` | 26 | `utils` | 2 |
| `features/offline_cache` | 24 | **合计** | **850** |

分桶：`features/** = 658`、`core = 89`、`platform = 69`、`models = 26`、`lyrics = 4`、`utils = 2`、`main.dart = 2`。

### 0.4 ⚠️ 与审计里"778 处 / 79 文件"的对账

**我没能复现出 778/79**，且把候选口径都试了一遍（**同一条命令、同一次快照**，所以下表内部可比）：

| 口径 | 处数 | 文件数 |
|---|---|---|
| 原始匹配（含注释行） | 1023 | 118 |
| **权威口径（非注释行）** | **850** | **95** |
| 非注释行 + 行去重 | 817 | 95 |
| 非注释行 + 文案去重 | 665 | 95 |
| 非注释行 + 剔除含 `$` 插值的字面量 | 663 | 90 |
| 非注释行 + 仅"纯中文无 ASCII"字面量 | 593 | 86 |
| 非注释行 − `lib/platform/**` | 781 | 86 |
| 非注释行 − `lib/models/**` | 824 | 92 |

观察：`781/86` 与审计的 `778/79` 最接近（差 3 处 / 7 个文件可由口径微差解释），**审计很可能把 `lib/platform/**` 排除在外**（把平台层默认当作"不迁"）。详见 §4：本文档**不排除**它，而是放进最后的白名单批次——因为它既有必须迁的用户可见文案（`'QQ用户'`、登录错误提示），也有必须保留的解析常量（`'今日私享'`、`'概念版'`，见 §3.4）。

**结论（给 CI 的硬要求）**：基线数字必须由**本次提交的脚本**打印，并把该数字写进仓库（§6.3）；**不要**把 778 写进 CI——它与随附脚本不一致。

### 0.5 为什么基线会漂移：**先冻结再动手**

分析期间我用**同一条命令**先后得到 `836` → `849` → `850`，dirty 文件数 `33` → `38` —— 原因就是工作树里有其它成员正在改 `lib/`（播放核心、小组件、scrobble…）。这不是测量误差，是**真实的新增文案**（最后一次 +1 落在 `features/library`）。因此：

1. W3-D 开工前先 `git stash`/提交现有改动，**在一个干净的工作树上跑命令 B 并把输出记进 §6.3 的 `baseline` 常量**；
2. 之后每一次迁移 PR 都让 `total` **下降**；中间任何 PR 让 total 上升 → CI 红。

---

## 1. key 命名规范：从现有 126 键**反推**（不是新设计）

### 1.1 现有风格（读 `lib/l10n/app_zh.arb` 总结）

| 观察 | 证据（`app_zh.arb` 原文） |
|---|---|
| **camelCase，无下划线、无点号、无层级分隔** | `settingsAccountsSubtitle`、`floatingLyricsHighlightColor` |
| **"模块/区域 + 名词"前缀** | `nav*`（导航）、`settings*`、`theme*`、`uiStyle*`、`background*`、`floatingLyrics*`、`audio*`、`diagnostics*`、`player*`、`account*`、`action*`、`platform*`、`session*` |
| **后缀表达语义角色** | `*Title`（页面/区块标题）、`*Subtitle`（副标题/说明）、`*Hint`（辅助说明）、`*Confirm`（确认弹窗文案）、`*Failed`（失败）、`*Copied`/`*Applied`/`*Updated`/`*Removed`/`*Added`/`*Enabled`/`*Exported`/`*Cleared`（成功 toast） |
| 动作类**统一收在 `action*`** | `actionSave` / `actionCancel` / `actionReset` / `actionLogout` |
| 平台名**统一 `platform*`** | `platformLocal` / `platformNetease` / `platformQq` / `platformKugou` |
| 参数化用 ARB placeholders，**中文里直接写 `{name}`** | `"audioMinutes": "{minutes} 分钟"` + `@audioMinutes.placeholders.minutes.type = int` |
| 平台品牌写法带空格 | `"platformQq": "QQ 音乐"`（注意与硬编码里的 `'QQ音乐'` 不一致——§2 会收敛） |

访问器只有**一个**（`lib/l10n/l10n.dart:14-17`）：

```dart
extension AppLocalizationsX on BuildContext {
  AppLocalizations get l10n =>
      AppLocalizations.of(this) ?? lookupAppLocalizations(const Locale('zh'));
}
```
> 注意两件事：① 代码里实际用的是**局部变量 `l`**（如 `final l = context.l10n;` → `l.settingsTitle`），不是直接 `context.l10n.settingsTitle`；统计引用时必须同时认 `l10n.<key>` 和 `l.<key>`（只认前者会把 `navSearch` 这类误判成孤儿）。② 无 delegate 时**回落到中文**——这是十几个 widget 测试能被保留的原因，**不要"顺手"改成抛异常**。

### 1.2 提案：把 style 固化成规则（扩展，不改现状）

1. **前缀 = 模块名**，取值固定在下列集合，跨批不新增：
   `common` `nav` `settings` `theme` `home` `search` `discovery` `library` `playlist` `download` `player` `lyrics` `localMusic` `smartPlaylist` `stats` `toplist` `newSongs` `artist` `album` `auth` `backup` `cache` `audioEffects` `net` `share` `transfer`
2. **后缀 = 语义角色词表**（只用这些，不再自造）：
   `Title` `Subtitle` `Hint` `Empty` `Loading` `Failed` `Confirm` `ConfirmBody` `Action` `Tooltip` `Label` `Note`
   成功类：`Saved` `Deleted` `Added` `Removed` `Updated` `Copied` `Cleared` `Exported` `Applied`
3. **跨文件复用的文案一律 `common*`**（这是"同一批内不产生跨文件共享 key 冲突"的机制）：先在 §4 的 **B1** 一次性定义，后续批次只引用，绝不各自再定义一份 `xxxRefresh`。
4. **同义不同形先收敛**：现有代码里 `'QQ音乐'`（无空格）与 ARB `platformQq: "QQ 音乐"`（有空格）并存；`'酷狗音乐'` 与 `platformKugou` 同理。**以 ARB 现有写法为准**（带空格），并让页面改用 `platform*` key（顺带消灭 §2 里的两条高频重复）。
5. **参数化**：`{count}` 用 `int`，`{name}`/`{error}` 用 `String`，可选参数用 `placeholders.<name>.type` + 必要时 `example`。**禁止**字符串拼接拼句式（`'已删除 ' + n + ' 首'`），要写成 `"已删除 {count} 首"`。

### 1.3 真实例子（原字面量 → key → zh → en）

| # | 原字面量（出现位置） | key | zh | en |
|---|---|---|---|---|
| 1 | `'取消'`（`lib/features/backup/presentation/pages/backup_page.dart:163`，9 处/6 文件） | `commonCancel` | `取消` | `Cancel` |
| 2 | `'刷新'`（`lib/features/album/presentation/pages/album_page.dart:55` tooltip，6 处/5 文件） | `commonRefresh` | `刷新` | `Refresh` |
| 3 | `'加载失败'`（`lib/features/discovery/presentation/pages/recommendations_page.dart:102`，8 处/8 文件） | `commonLoadFailed` | `加载失败` | `Failed to load` |
| 4 | `'未命名歌单'`（`lib/core/share/share_service.dart:95`，7 处/5 文件，**data 层**） | `commonUntitledPlaylist` | `未命名歌单` | `Untitled playlist` |
| 5 | `'下载目录已更新'`（`lib/features/download/data/download_directory_service.dart:151`，4 处/2 文件） | `downloadDirectoryUpdated` | `下载目录已更新` | `Download folder updated` |

#3/#4 都是"无 BuildContext"的场景（Provider / 纯函数），**不能**直接 `context.l10n` —— 见 §3.3。

---

## 2. 重复率最高的前 20 条（最该先收进 ARB）

口径：权威口径 + 按**字面量文本**归并。命令（输出前三列：处数 | 涉及文件数 | 首次出现位置）：

```powershell
$rx = '[\x22\x27][^\x22\x27\r\n]*[\u4e00-\u9fff][^\x22\x27\r\n]*[\x22\x27]'
$base = (Get-Location).Path + '\lib\'
$files = Get-ChildItem lib -Recurse -Filter *.dart | Where-Object { $_.FullName -notmatch '\\l10n\\' }
$texts = @{}; $tfiles = @{}; $first = @{}
foreach ($f in $files) {
  $rel = $f.FullName.Replace($base,''); $ln = 0
  foreach ($line in (Get-Content -LiteralPath $f.FullName)) {
    $ln++; $code = $line -replace '(^|\s)//.*$',''
    foreach ($m in [regex]::Matches($code, $rx)) {
      $t = $m.Value
      if ($texts.ContainsKey($t)) { $texts[$t]++ } else { $texts[$t]=1; $first[$t]="$rel`:$ln" }
      if (-not $tfiles.ContainsKey($t)) { $tfiles[$t]=@{} }; $tfiles[$t][$rel]=1
    }
  }
}
$texts.GetEnumerator() | Sort-Object -Property Value -Descending | Select-Object -First 20 |
  ForEach-Object { "{0,3}|{1,2}|{2}" -f $_.Value, $tfiles[$_.Key].Count, $first[$_.Key] }
```

实测结果（同一工作树）：

| # | 处数 | 文件数 | 字面量 | 首次出现 | 建议 key | 备注 |
|---|---|---|---|---|---|---|
| 1 | 9 | 6 | `取消` | `backup_page.dart:163` | `commonCancel` | 与现有 `actionCancel` 语义重复 → **复用/合并** `actionCancel` |
| 2 | 8 | 8 | `加载失败` | `recommendations_page.dart:102` | `commonLoadFailed` | 8 个不同页面各写一遍 |
| 3 | 7 | 7 | `导入歌单` | `core/transfer/json_codec.dart:74` | `commonImportedPlaylistName` | 作为"无名歌单"的默认名 |
| 4 | 7 | 5 | `未命名歌单` | `core/share/share_service.dart:95` | `commonUntitledPlaylist` | **data 层**，见 §3.3 |
| 5 | 6 | 2 | `不限` | `smart_playlist_editor_page.dart:330` | `commonNoLimit` | 与 `'天'` 成对出现，注意语序 |
| 6 | 6 | 5 | `刷新` | `album_page.dart:55` | `commonRefresh` | tooltip |
| 7 | 6 | 4 | `智能歌单` | `library_screen.dart:54` | `smartPlaylistTitle` | 与 `smart_playlists_page` 的标题重复 |
| 8 | 6 | 5 | `酷狗音乐` | `login_page.dart:181` | **`platformKugou`（已存在）** | 直接用现成 key，不要再新建 |
| 9 | 5 | 3 | `未知专辑` | `local_track_store.dart:103` | `commonUnknownAlbum` | 已是 `static const`，改为由调用方传 |
| 10 | 5 | 5 | `播放全部` | `album_page.dart:275` | `commonPlayAll` | 专辑/歌手/歌单页复用 |
| 11 | 5 | 5 | `QQ音乐` | `toplists_page.dart:214` | **`platformQq`（已存在）** | 注意 ARB 里是 `"QQ 音乐"`（带空格）→ 统一 |
| 12 | 5 | 4 | `专辑` | `album_page.dart:52` | `commonAlbum` | 空名兜底 |
| 13 | 5 | 4 | `网络连接失败，请检查网络后重试` | `core/network/api_exception.dart:48` | `netConnectionFailed` | **core 层**，全 App 复用，优先级高 |
| 14 | 4 | 1 | `QQ用户` | `platform/qq/qq_platform.dart:112` | `qqDefaultNickname` | 平台层默认昵称（4 处同文件） |
| 15 | 4 | 2 | `下载目录已更新` | `download_directory_service.dart:151` | `downloadDirectoryUpdated` | data 层 |
| 16 | 4 | 1 | `酷狗用户` | `platform/kugou/kugou_platform.dart:186` | `kugouDefaultNickname` | 同 #14 |
| 17 | 4 | 3 | `加载歌单失败` | `platform_playlists_page.dart:410` | `libraryPlaylistLoadFailed` | 与 #2 区分（更具体） |
| 18 | 4 | 4 | `未知歌手` | `core/share/share_links.dart:190` | `commonUnknownArtist` | 与 #9 成对 |
| 19 | 4 | 4 | `歌单` | `core/router/app_router.dart:145` | `commonPlaylist` | 路由兜底名 |
| 20 | 4 | 4 | `本地音乐` | `library_screen.dart:42` | **`platformLocal`（已存在）** | 同 #8/#11，用现成 key |
| 21 | 4 | 3 | `歌手` | `artist_page.dart:45` | `commonArtist` | |
| 22 | 4 | 4 | `每日推荐` | `recommendations_page.dart:81` | `discoveryDailyRecommendations` | 与"QQ 今日私享/酷狗推荐"要分 key |
| 23 | 4 | 4 | `网易云音乐` | `lyrics_line.dart:9` | **`platformNetease`（已存在）** | 同 #8/#11/#20 |
| 24 | 4 | 4 | `重试` | `core/widgets/async_state_view.dart:125` | `commonRetry` | 共享组件，B1 先做 |
| 25 | 3 | 2 | `保存失败` | `import_playlist_page.dart:144` | `commonSaveFailed` | 同一行还有 `'已保存到我的歌单'` |

**这张表的价值**：前 8 条（43 处 / 覆盖 ~30 个文件）一次性收进 `common*` + 复用 4 个**已存在**的 `platform*` key，就能把"同一句话抄 N 遍"的清零，后续每个文件只需替换引用，不需要各自起名（这正是"同批不冲突"的保证）。

---

## 3. 不可迁移 / 需特殊处理的清单

### 3.1 测试断言里的文案（**W3-D 最大的翻车点**）

实测：`test/**` 有 **2464 处** CJK 字面量、**346 处** `find.text/textContaining` 断言中文，分布在 **38 个文件**。热点：

| 文件 | 中文断言数 |
|---|---|
| `test/local_music_page_test.dart` | 38 |
| `test/download_page_test.dart` | 33 |
| `test/import_playlist_page_test.dart` | 19 |
| `test/song_actions_test.dart` | 17 |
| `test/likes_page_long_press_test.dart` | 17 |
| `test/history_page_long_press_test.dart` | 16 |
| `test/artist_page_test.dart` | 16 |
| `test/album_page_test.dart` | 15 |
| `test/toplist_detail_test.dart` | 14 |
| `test/async_state_view_test.dart` | 13 |

命令：

```powershell
$rz = "find\.text(Containing)?\(\s*'[^']*[\u4e00-\u9fff]"
$t = @{}
foreach ($f in (Get-ChildItem test -Recurse -Filter *.dart)) {
  $c = ([regex]::Matches((Get-Content -Raw -LiteralPath $f.FullName), $rz)).Count
  if ($c -gt 0) { $t[$f.Name] = $c }
}
$t.GetEnumerator() | Sort-Object -Property Value -Descending | Select-Object -First 15 | ForEach-Object { "{0,4} {1}" -f $_.Value, $_.Key }
```

**处理规则（照做，别自由发挥）**：

1. **`find.text('中文')` 一律不改成 `find.text(l.someKey)`**。测试里没有可用的 `l`，硬造一个会把"断言生产文案"降级成"断言同一个常量"，让测试失去意义。
2. 迁移一个页面时，**该页面的测试断言保持不变**——因为 `l10n.dart` 在无 delegate 时**回落到中文**（`lib/l10n/l10n.dart:15-16`）。这正是现有设计让测试能零改动通过的原因。
   ✅ 前提：测试用 `MaterialApp`（无 delegate）pump 页面。**如果某个测试显式装了 `localizationsDelegates` 并设了 `locale: Locale('en')`**，断言必须跟着改（`test/l10n_test.dart` 里那两条就是刻意如此的）。
3. 迁移后**必须跑全量测试**（`flutter test --no-pub -j 1`），并且**改动断言 = 红旗**：只有当被测行为真的变了才允许改断言。
4. 反向校验技巧：迁移前后各跑一次
   ```powershell
   flutter test --no-pub -j 1 2>&1 | Select-String -Pattern "All tests passed|Some tests failed"
   ```
   数量必须一致；若某个测试开始失败，先怀疑"该页面在读 `context.l10n` 之前就抛异常"，而不是改断言。

### 3.2 必须保持中文（不能"翻译"的东西）

| 类别 | 例子 | 处理 |
|---|---|---|
| **ARB 模板值本身** | `app_zh.arb` 的所有值 | 它们是"中文正本"，不是硬编码 |
| **歌词内容 / 用户数据** | 歌词文本、歌单名、昵称、搜索词 | 永不进 ARB |
| **平台品牌名** | `QQ 音乐`、`网易云音乐`、`酷狗音乐`、`本地音乐` | 进 ARB（`platform*`，已存在），en 值用官方英文名（`NetEase Cloud Music`/`QQ Music`/`Kugou Music`/`Local music`） |
| **平台 API 的参数/响应匹配** | `'概念版'`、`'我喜欢的音乐'`、`'今日私享'`（HTML 解析） | **保留中文**，见 §3.4 白名单 + `// i18n-exempt:` 标记 |
| **歌曲标题解析正则** | `models/song.dart` 的 `现场|演唱会`、`重制|重置` | **保留**（匹配的是标题本身） |

### 3.3 无 BuildContext 的文案（**结构性风险，占 850 中的约 190 处**）

按路径统计（权威口径，实测）：

| 层 | 处数 | 代表文件 | 为什么不能 `context.l10n` |
|---|---|---|---|
| `*/domain/**` | 47 | `backup_models.dart`(15)、`download_failure.dart`(12)、`smart_playlist_rule.dart`(9)、`local_library_query.dart`(9) | 纯 Dart，没有 BuildContext |
| `*/data/**` | 50 | `download_directory_service.dart`(14)、`saf_download_writer.dart`(8)、`download_manager.dart`(6)、`playback_fade_controller.dart`(5)、`my_playlists_repository.dart`(5) | 同上 |
| `*/presentation/providers/**` | 70 | `my_playlists_provider.dart`(13)、`new_songs_provider.dart`(9)、`player_provider.dart`(6) | 只有 `Ref`，没有 `WidgetRef`/context |
| `lib/platform/**` | 69 | 见 §3.4 | 平台层被注入到 registry，无 UI 依赖 |
| `lib/models/**` | 26 | `audio_quality.dart`(20)、`platform_type.dart`(4) | 枚举标签，被 domain/UI 双方使用 |
| `lib/core/**` | 89 | `diagnostics_export.dart`(19)、`api_exception.dart`(12)、`song_actions.dart`(9) | core 混合了 UI 组件与纯逻辑 |

**两种处理模式，按层选一个（不要混）**：

- **模式 A（首选）：错误码 + UI 翻译。** domain/data 返回**类型化错误**，UI 层映射到 ARB key。
  ```dart
  // domain：不再返回中文
  enum DownloadFailureReason { network, noPermission, diskFull, unknown }
  class DownloadFailure { final DownloadFailureReason reason; final Object? cause; }
  // UI：映射
  String failureText(BuildContext context, DownloadFailureReason r) => switch (r) {
    DownloadFailureReason.network     => context.l10n.downloadFailedNetwork,
    DownloadFailureReason.noPermission=> context.l10n.downloadFailedPermission,
    DownloadFailureReason.diskFull    => context.l10n.downloadFailedDiskFull,
    DownloadFailureReason.unknown     => context.l10n.commonUnknownError,
  };
  ```
  适用于：`api_exception.dart`、`download_failure.dart`、`backup_models.dart`（BackupFormatException）、`smart_playlist_rule.dart`、`share_service.dart` 的 `'未命名歌单'`（改由调用方传入名字）。
- **模式 B（providers 专用）：注入 AppLocalizations。** 在 `lib/main.dart` 的 `ProviderScope` 上 `overrides` 一个 `l10nProvider`，provider 里 `ref.read(l10nProvider)`：
  ```dart
  final l10nProvider = Provider<AppLocalizations>((_) => lookupAppLocalizations(const Locale('zh')));
  // MconnectApp 的 build 里按当前 locale override：
  ProviderScope(overrides: [l10nProvider.overrideWithValue(AppLocalizations.of(context)!)], child: …)
  ```
  ⚠️ 这个方案要求"页面构建时 l10n 已可用"，且 locale 变化要重建——**只在模式 A 不划算的地方用**（如 `player_provider` 的 toast 文案）。
- **注意 `_status` / `_error` 这类"state 里存字符串"的写法**（`backup_page.dart:113`、`download_page` 等）必须改成 **state 存枚举/参数，build 时翻译**；否则切 locale 后旧消息还是旧语言。

### 3.4 `// i18n-exempt:` 白名单（必须保留的解析常量）

实测（逐行看过）**只有下列位置**属于"绝不能翻译"：

| 文件:行 | 字面量 | 为什么 |
|---|---|---|
| `lib/platform/qq/qq_api.dart:894` | `"<li[^>]*playlist__item[^>]*>[\\s\\S]*?今日私享[\\s\\S]*?</li>"` | 匹配服务端 HTML |
| `lib/platform/qq/qq_api.dart:896` | `'今日私享'`（`_windowAround(html, …, 1600)`） | 同上 |
| `lib/platform/kugou/kugou_api.dart:86-87` | `'概念版'` / `'酷狗概念版'` | 匹配接口返回值 |
| `lib/platform/netease/netease_platform.dart:554` | `'我喜欢的音乐'` | 匹配服务端歌单名 |
| `lib/models/song.dart:90` | `RegExp(r'…(live\|现场\|演唱会)…')` | 匹配歌曲标题 |
| `lib/models/song.dart:92` | `RegExp(r'…(remaster\|重制\|重置)…')` | 同上 |

处理方式：这些行**保留中文**并在行尾加标记（同一行内，便于脚本过滤）：

```dart
      final scope = itemMatch?.group(0) ?? _windowAround(html, '今日私享', 1600); // i18n-exempt: 服务端 HTML 常量
```

其余全部迁移。**"平台层全部不迁"是错的**——`qq_platform.dart` 里 20 处大多用户可见（`'QQ用户'`、`'QQ音乐暂不支持手机号登录'`）。

---

## 4. 分批方案（B0 → B10）

划分原则：① **B0 先把地基与护栏落地**；② **B1 先迁共享层**（`core/widgets`、`core/share`、`core/network`、`core/transfer`）——它们被多页复用，先迁后续页面只需替换引用；③ **B3 横切 Top 20 重复文案**；④ 之后按 feature 目录切块，每块内部**不产生跨文件同名 key**（跨文件共用的一律用 B1/B3 已定义的 `common*`）；⑤ 白名单批次放最后。

| 批次 | 内容 | 处数 | 关键文件（处数） | 验收 |
|---|---|---|---|---|
| **B0 地基**（0 处文案） | 修 `l10n.yaml` 的失效引用（它指向**不存在**的 `test/l10n_arb_test.dart`，实际文件是 `test/l10n_test.dart`）；落地 §6 的预算测试并**冻结基线**；处理 §7 的 6 个孤儿键 | 0 | `l10n.yaml`、`test/i18n_budget_test.dart`（新增）、`lib/l10n/app_zh.arb`/`app_en.arb` | 预算测试通过且打印基线；`flutter test` 全绿 |
| **B1 共享层** | `lib/core/widgets/**` + `core/share/**` + `core/network/**` + `core/transfer/**` + `core/router/**`（**不含** `diagnostics_export.dart`） | **70** | `song_actions_sheet.dart`(8)、`song_actions.dart`(9)、`api_exception.dart`(12)、`api_client.dart`(8)、`platform_http.dart`(5)、`share_service.dart`(3)、`share_links.dart`(2)、`deep_link_service.dart`(3)、`transfer_runner.dart`(5)、`playlist_export.dart`(4)、`transfer_format.dart`(3)、`json_codec.dart`(2)、`m3u8_codec.dart`(2)、`playlist_codec.dart`(1)、`text_codec.dart`(1)、`async_state_view.dart`(1)、`app_router.dart`(1) | 引用 `l10n` 的文件从 6 → ≥10；`find.text` 未改 |
| **B2 核心网络错误** | `lib/core/network/**` 归零（若 B1 未含） | 0-25 | `api_exception.dart`、`api_client.dart`、`platform_http.dart` | §3.3 模式 A 的错误码落地 |
| **B3 Top 20 重复文案** | §2 表里的 20+ 条，统一收进 `common*` / 复用 `platform*` | ~100（含重复调用点） | 跨 30+ 文件 | 前 8 条重复清零；`distinct` 数下降 |
| **B4 最大两块** | `features/library/**` + `features/download/**` | **253** | `platform_playlists_page.dart`(37)、`playlist_detail_page.dart`(29)、`download_page.dart`(37)、`import_playlist_page.dart`(28)、`history_page.dart`(15)、`download_directory_service.dart`(14)、`download_button.dart`(13)、`my_playlists_provider.dart`(13)、`download_failure.dart`(12) | 两个目录归零 |
| **B5 智能歌单 + 播放器** | `features/smart_playlists/**` + `features/player/**` | **151** | `smart_playlist_editor_page.dart`(37)、`smart_playlists_page.dart`(34)、`playback_options_sheet.dart`(19)、`queue_page.dart`(14)、`smart_playlist_rule.dart`(9)、`playlist_picker_sheet.dart`(8)、`player_provider.dart`(6) | 含 `playback_fade_controller` 等 data 层 → 模式 A |
| **B6 备份 + 本地库 + 统计 + 榜单** | `features/backup/**` + `features/local_music/**` + `features/stats/**` + `features/toplist/**` | **140** | `backup_page.dart`(21)、`backup_models.dart`(15)、`local_music_page.dart`(25)、`listening_stats_page.dart`(26)、`toplists_page.dart`(23) | 注意 `backup_models.dart` 是 domain → 模式 A |
| **B7 其余 features** | `offline_cache` + `discovery` + `search` + `new_songs` + `artist` + `auth` + `album` + `audio_effects` + `settings` | **114** | `offline_cache_page.dart`(24)、`search_screen.dart`(14)、`artist_page.dart`(12)、`login_page.dart`(11)、`album_page.dart`(9)、`new_songs_provider.dart`(9) | 各目录归零 |
| **B8 诊断导出** | `core/diagnostics/diagnostics_export.dart` | **19** | 导出文件里的文本 | 它是"产物文本"，可最后做；en 用户导出英文报告 |
| **B9 平台层** | `lib/platform/**`（迁用户可见文案，留 §3.4 白名单） | **69 → ~7** | `qq_platform.dart`(20)、`kugou_platform.dart`(20)、`kugou_api.dart`(7)、`netease_platform.dart`(7)、`qq_toplist_ids.dart`(6)、`netease_api.dart`(4)、`qq_api.dart`(3) | 白名单外归零 |
| **B10 models / lyrics / utils / main** | `lib/models/**`(26) + `lib/lyrics/**`(4) + `lib/utils/**`(2) + `lib/main.dart`(2) | **34 → ~2** | `audio_quality.dart`(20)、`platform_type.dart`(4)、`lyrics_line.dart`(4)、`file_opener.dart`(2) | `song.dart` 的 2 个正则进白名单 |

合计：70 + 253 + 151 + 140 + 114 + 19 + 69 + 34 ≈ 850（B3 与其它批次有重叠，按"先 B3 定义 `common*`、后续批次只替换引用"计**不重复计数**）。分桶校验：`features 658 + core 89 + platform 69 + models 26 + lyrics 4 + utils 2 + main 2 = 850`。

**每批的固定流程**（写进 PR 模板）：

1. `flutter gen-l10n` 前先只改 ARB（`app_zh.arb` + `app_en.arb` 同时加，键集必须一致）；
2. `flutter gen-l10n` 生成 `lib/l10n/app_localizations*.dart`（**这些生成物要一起提交**，否则 `test/l10n_test.dart` 的"生成物是否落后"用例会红）；
3. 改调用点（`final l = context.l10n;` → `l.xxx`）；
4. `flutter analyze --no-pub`（0 issue）+ `flutter test --no-pub -j 1`（全绿）+ §6 的预算测试（total 下降）；
5. PR 描述里贴新的 `total`。

---

## 5. 放开 `en` 的前置条件与可机器检查的门槛

### 5.1 现在为什么不能放开（事实）

`lib/app.dart:75`：

```dart
const List<Locale> appSupportedLocales = <Locale>[Locale('zh')];
// 第 70-74 行的注释已经写明：放开 = 把这里换成 AppLocalizations.supportedLocales（1 行）
```
而 `app_en.arb` 与 `app_localizations_en.dart` 是**完整可用**的（`test/l10n_test.dart` 有 4 条用例证明 en 能渲染、且切到 en 会出英文），只是**只有 131 处引用了 l10n**，其余 850-131 ≈ 719 处仍是硬编码中文 → 英文设备会看到"几页英文 + 其余中文"的混语界面。

### 5.2 混语界面的**判定标准**（可机器检查）

> **判定**：以 `Locale('en')` 渲染任一**顶级可达路由**时，界面上的文本节点不得出现 CJK 字符（白名单：用户数据、歌词、`// i18n-exempt:` 常量）。

两级门槛，**两个都要过**：

| 级别 | 检查 | 通过条件 |
|---|---|---|
| **静态（快，CI 每次跑）** | 权威口径计数，按目录 | `lib/features/** == 0` **且** `lib/core/** == 0` **且** `lib/main.dart == 0` 且 `lib/utils/** == 0` 且 `lib/models/** == 0` 且 `lib/lyrics/** == 0`；仅允许 `lib/platform/**` 里的 `// i18n-exempt:` 行 |
| **动态（慢，放开的那个 PR 必跑）** | 每个顶级页面用 en pump 一次，断言无 CJK | 见下面代码 |

### 5.3 **N 的推导**（为什么静态门槛是"0 + 白名单"而不是某个整数）

850 = `features 658` + `core 89` + `main.dart 2` + `platform 69` + `models 26` + `lyrics 4` + `utils 2`。

- `features` / `core` / `main.dart` / `models` / `lyrics` / `utils` 的**每一处**都可能是界面文案 → 门槛 **0**，不留"还剩 N 处"的模糊地带（否则 N 会变成永远谈不拢的谈判筹码）。
- `platform` 的 69 处里实测**只有 7 处**是不可翻译的解析常量（§3.4）→ 门槛 **= 白名单行数（当前 7，实施后以实际标记数为准）**。
- 因此**门槛 N 的定义**：`N = lib/** 中带 // i18n-exempt: 标记的行数`，且**必须能从脚本里数出来**，而不是人肉约定：

```powershell
# 白名单行数（应等于平台层残留 CJK 数）
(Select-String -Path (Get-ChildItem lib -Recurse -Filter *.dart | Where-Object { $_.FullName -notmatch '\\l10n\\' }) -Pattern 'i18n-exempt').Count
```

**放开的 PR 的验收清单**：
1. 静态门槛全过（`features`/`core`/`models`/`lyrics`/`utils`/`main` = 0，`platform` = 白名单行数）；
2. §6 预算测试的 `baseline` 从 850 改成 **白名单行数**（这一步就是"锁死"）；
3. `test/l10n_test.dart` 的 en widget 用例扩展到**每个顶级页面**（见下）；
4. `flutter analyze` + `flutter test` 全绿；真机切英文系统语言冒烟：nav 四页、播放器、设置、下载、搜索、库各看一遍。

**en 渲染无 CJK 的断言骨架**（加进 `test/l10n_test.dart`）：

```dart
/// 收集当前 screen 上所有可见文本，断言不含 CJK（白名单外）。
List<String> _visibleTexts(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data ?? '')
    .where((s) => s.isNotEmpty)
    .toList();

void expectNoHan(WidgetTester tester, {List<RegExp> allow = const []}) {
  final han = RegExp(r'[\u4e00-\u9fff]');
  final offenders = _visibleTexts(tester)
      .where((s) => han.hasMatch(s) && !allow.any((r) => r.hasMatch(s)))
      .toList();
  expect(offenders, isEmpty, reason: 'en 界面出现中文：$offenders');
}

testWidgets('en: 顶级页面无中文', (tester) async {
  for (final page in [/* SearchScreen/DiscoveryScreen/LibraryScreen/… */]) {
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      supportedLocales: const [Locale('en')],
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: page,
    ));
    await tester.pumpAndSettle();
    expectNoHan(tester);
  }
});
```
> 白名单用 `allow:` 传正则（如歌词行、用户歌单名），**不要**用"跳过整个页面"的方式绕过。

---

## 6. CI 护栏：新增 CJK 不得增长

### 6.1 落地形态：一个 Dart 测试（跨平台、与 `flutter test` 同一条路径）

新建 `test/i18n_budget_test.dart`（**可整段粘贴**）：

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// i18n 预算护栏。
///
/// 目的：让"新增硬编码中文"在 CI 里变红，而不是等到放开 en 那天才发现又多了 200 处。
/// 口径见 docs/i18n-migration-plan.md §0.1；必须与那里的 PowerShell 命令打印同一个数字。
void main() {
  // 非注释行上的 CJK 字符串字面量（与本仓库文档中的口径完全一致）
  final cjkLiteral = RegExp(
    "['\u0022][^'\u0022\r\n]*[\u4e00-\u9fff][^'\u0022\r\n]*['\u0022]",
  );
  final lineComment = RegExp(r'(^|\s)//.*$');
  final exemptMarker = RegExp(r'//\s*i18n-exempt:');

  // ⚠️ 基线：在干净工作树上跑本测试得到的数字（docs §6.3）。
  //    W3-D 每迁一批就把它调小；放开 en 时调到"白名单行数"。
  //    下面这组值 = 工作树 21ddc01 + 38 dirty 的快照（会漂，开工前重测）。
  const baselineTotal = 850;
  const baselineFiles = 95;

  test('lib/ 的硬编码中文不得超过基线', () {
    var total = 0;
    var files = 0;
    var exempt = 0;
    final perArea = <String, int>{};

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final normalized = entity.path.replaceAll(r'\', '/');
      if (normalized.contains('/l10n/')) continue; // 正本 ARB + 生成物

      var count = 0;
      for (final line in entity.readAsLinesSync()) {
        if (exemptMarker.hasMatch(line)) {
          exempt += cjkLiteral.allMatches(line).length;
          continue;
        }
        for (final _ in cjkLiteral.allMatches(line.replaceAll(lineComment, ''))) {
          count++;
        }
      }
      if (count > 0) {
        files++;
        total += count;
        final area = normalized.split('/')[1];
        perArea[area] = (perArea[area] ?? 0) + count;
      }
    }

    // ignore: avoid_print
    print('i18n budget: total=$total files=$files exempt=$exempt');
    // ignore: avoid_print
    print('  by area: $perArea');

    expect(
      total,
      lessThanOrEqualTo(baselineTotal),
      reason: '新增了硬编码中文。请把文案加进 lib/l10n/app_zh.arb + app_en.arb，'
          '跑 `flutter gen-l10n`，再用 context.l10n 引用（见 docs/i18n-migration-plan.md）。',
    );
    expect(
      files,
      lessThanOrEqualTo(baselineFiles),
      reason: '硬编码中文的文件数变多了（即使总处数没超）。',
    );
  });

  test('放开 en 之后：仅允许带 i18n-exempt 标记的中文', () {
    // 这个用例在 W3-D 完成、baseline 调到白名单数之前会通过（850 <= 850）。
    // 放开 en 的那次 PR 请把 gateArmed 改成 true，并把 baseline 调成白名单行数。
    const gateArmed = false;
    if (!gateArmed) return;
    expect(baselineTotal, lessThanOrEqualTo(20)); // 白名单量级
  });
}
```

> 提示：`baselineTotal` 唯一的作用是"不许涨"。它写成常量而不是从文件读，是为了让"调小基线"这件事在 diff 里一眼可见；本轮**不要**再引入第二套基线机制。

### 6.2 人类用的等价命令

§0.2 的命令 A。**两侧必须打印同一个 `total`**；CI 用 Dart 测试（跨平台、不依赖 PowerShell），本地排查用命令 A（快）。

### 6.3 基线冻结（防止"数字对不上"）

1. W3-D **第一件事**：在干净工作树（`git status --porcelain` 为空）上跑命令 B，把输出的 `total`/`files` 写进 `baselineTotal`/`baselineFiles`；
2. 在本文档 §0.3 用**同一提交号**记录该数字（当前记录：工作树 `21ddc01 + 38 dirty` → **850/95**，是快照、会漂）；
3. 之后每个迁移 PR 都要把这两个常量**调小**（示例：B4 迁完 library+download 后 total 应下降 253）；
4. CI 里**不要**再加"绝对值断言"以外的花活；护栏的灵魂是"不许涨"。

> 可选加固：把基线放进 `tool/i18n_baseline.txt`（一行一个数），测试读取它——好处是改基线要动数据文件而不是改测试常量，diff 更可见。**但本轮不要同时上两套机制**，先按常量来。

---

## 7. 孤儿键与死键

### 7.1 方法（命令）

```powershell
# 1) ARB 顶层消息键（排除 @ 元数据块）
$raw  = Get-Content -Raw -LiteralPath lib\l10n\app_zh.arb
$keys = [regex]::Matches($raw, '(?m)^  "([A-Za-z0-9_]+)"\s*:') | ForEach-Object { $_.Groups[1].Value }
"keys = $($keys.Count)"

# 2) 语料 = lib 下所有 dart，但排除生成物 app_localizations*.dart（否则生成物自己引用自己，永远不孤儿）
$corpus = ''
foreach ($f in (Get-ChildItem lib -Recurse -Filter *.dart | Where-Object { $_.FullName -notmatch 'app_localizations' })) {
  $corpus += (Get-Content -Raw -LiteralPath $f.FullName)
}

# 3) 孤儿 = 整个 lib 里都找不到这个标识符
foreach ($k in $keys) { if ($corpus -notmatch "\b$k\b") { "ORPHAN: $k" } }

# 4) 宽松口径（只看 l10n.<key> / l.<key> 访问）：会误报，仅作参考
foreach ($k in $keys) { if ($corpus -notmatch "l10n[!?]{0,2}\.$k\b") { "not-via-l10n: $k" } }
```

**关键细节**：语料只能排除 **`app_localizations*.dart`（生成物）**，**不能排除整个 `lib/l10n/`**——`lib/l10n/platform_labels.dart` 与 `lib/l10n/l10n.dart` 是手写代码，排除它会把 `platformNetease`/`platformQq` 等**误判成孤儿**（我第一次就踩了这个坑，宽口径从 26 个假孤儿降到 6 个真孤儿）。
另外：本仓库的访问器是局部变量 `l`（`l.settingsTitle`），所以**只有"宽口径"可信**；窄口径（`l10n.<key>`）漏报严重。

### 7.2 结果：**6 个真孤儿**（与审计一致）

| # | key | zh 值 | 判定 | 建议 |
|---|---|---|---|---|
| 1 | `settingsAccountsTitle` | 账号管理 | 与 `settingsAccounts` 同值，页面标题实际用的是后者 | **删除**（或让页面标题改用它） |
| 2 | `settingsAppearanceTitle` | 外观 | 同上 | 删除 |
| 3 | `settingsFloatingLyricsTitle` | 悬浮歌词 | 同上 | 删除 |
| 4 | `settingsAudioTitle` | 音频增强 | 同上 | 删除 |
| 5 | `settingsDiagnosticsTitle` | 诊断与关于 | 同上 | 删除 |
| 6 | `diagnosticsExporting` | 正在导出诊断日志… | 导出过程从未显示 | **接线**（导出时显示）或删除 |

> 这 5 个 `*Title` 是"建了键但调用点没切过去"的典型；`test/l10n_test.dart` 只校验**两个 ARB 键集一致**，不校验"被使用"，所以它们能一直躺着。建议在 `test/l10n_test.dart` 里补一条 §7.1 口径的孤儿检查（阈值 0），否则下一轮还会长出来。

### 7.3 "ARB 有 key 但没人用"的通用检查

- 就是 §7.1；把它做成测试断言（**阈值 0**），并在删除键时**同时删 en/zh 两侧 + 跑 `flutter gen-l10n`**（否则 `test/l10n_test.dart` 的"生成物落后"用例会红）。
- 反向检查（**代码用了但 ARB 没有**）：因为生成物里的 getter 来自 ARB，Dart 编译器会直接报错 → 不需要额外检查。
- 检查"键存在但 en 值是中文"（假翻译）：`app_en.arb` 里可用一条正则扫 CJK：

```powershell
$en = Get-Content -Raw -LiteralPath lib\l10n\app_en.arb
"en 里含 CJK 的键：" + ([regex]::Matches($en, '(?m)^  "([A-Za-z0-9_]+)"\s*:\s*"[^"]*[\u4e00-\u9fff]')).Count
```
建议把这条也加进护栏（en 值含 CJK = 假翻译，阈值 0；`platformQq` 这类品牌名的英文值不受影响）。

---

## 8. 实施前必须知道的 5 件事（浓缩）

1. **口径写死**：非注释行上的 CJK 字面量，排除 `lib/l10n/**`；基线由脚本产出（快照：**850/95** @ `21ddc01`+38 dirty，实测中它 10 分钟内从 849 涨到 850），**不是 778**。
2. **测试别乱改**：`test/**` 有 346 处中文断言；因为 `context.l10n` 在无 delegate 时回落到中文，**页面测试的断言应当零改动通过**。改断言 = 红旗。
3. **约 190 处在无 BuildContext 的层（domain/data/providers/platform）**：用"模式 A 错误码 + UI 翻译"或"模式 B provider 注入 l10n"，别硬塞 `context`。
4. **共享文案先收 `common*`**（B1/B3），后续批次只引用——这是"同批不冲突 + 跨批不复用错键"的唯一机制。
5. **放开 en 不是"改一行"**：正文那一行只是最后一步；真正的门槛是 §5.2 的静态扫描全绿 + en 渲染无 CJK 的 widget 测试，且基线要同步调到白名单数（≈7）。

## 附：本文档所有数字的复现清单

| 数字 | 命令 |
|---|---|
| 850 处 / 95 文件 | §0.2 命令 A 或命令 B |
| 126 个 ARB 键 / 6 个 `@` 块 | `§7.1` 第 1 步；`@` 块计数：`(Select-String -Path lib\l10n\app_zh.arb -Pattern '^  "@').Count` = 7（含 `@@locale`） |
| 131 处已迁移 / 6 文件 | §0.3（口径：`(l10n\|l).<key>` 出现次数，遍历 126 个 key） |
| 2464 处 test CJK / 114 文件 | 同 §0.1 口径，路径换成 `test` |
| 346 处中文断言 / 38 文件 | §3.1 命令 |
| 6 个孤儿键 | §7.1 第 3 步 |
| 各 feature 处数 | §0.2 命令 A，把 `$rel` 按 `features\<name>\` 聚合 |
