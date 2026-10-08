# Changelog

## 2026-10-08 - v1.5.0 跨源换源、播放与歌词增强、库与统计、scrobble、Android 小组件、可访问性与工程护栏

一次性的阶段发布（Wave 0–4）。**音源仍固定为内置三平台**（网易云 / QQ / 酷狗），无任何外部音源导入能力。

### 版本与产物

| 项 | 值 |
|---|---|
| 版本 | `1.5.0+16` |
| Android | **分包三 APK**（`flutter build apk --release --split-per-abi`），**不提供 universal 包** |
| Windows | `flutter build windows --release` + Inno Setup 安装器（见下方"已知未验证"） |

### 播放与失败链

- **跨源换源失败后当次即失效该缓存条目**：源侧本来就有 `invalidate()`，但**没有任何地方调用它**，于是一个"按时间仍有效、实际在服务端已死"的 URL 会被复用满 20 分钟 TTL。现在在**两个时刻**失效——换源 URL 重放失败（知道确切平台）、以及**播放中途出错**而 `sourcePlatform` 已设置（跨源流半途断掉）；原平台永不被失效，且**每条失败链只解析一次**（不是每个音质档位一次）。
- 播放失败**可见**：失败链的每一环都给出用户可读的原因，SnackBar 与三态统一。

### 歌词

- **整首丢失修复**；分享图（屏幕外挂载**确实被绘制**的守卫、真 PNG 头断言、假 channel 收到恰一个存在的 PNG）。
- Android **歌词候选发现**：`lyrics/` 子目录 + `artist - title` 尾巴匹配 + rank 排序（精确同名恒优先）。

### 库、统计与歌单

- 歌单**导入/导出**、歌单详情三态、听歌历史/我喜欢页面、听歌统计页三态。
- Android **MediaStore + ContentObserver 监听**：1500 ms 去抖（一次突发 = 一个事件），Dart 侧只调 `rescan()`、**Kotlin 内零扫描逻辑**。**已知限制**：SAF 选的目录不一定在 MediaStore 索引内 ⇒ 监听是"锦上添花"，**手动刷新仍然必要**。

### scrobble（Last.fm / Libre.fm / ListenBrainz / Maloja）

- 传输层 + 队列协调器 + 设置页区块（**默认关闭**；关闭时不构造后端、不发请求）。
- 设置区块接线曾因 provider 图成环（`CircularDependencyError`）**三次未果**，最终根因是一个**死锁**：refresh 的门槛依赖"只有该 refresh 才会填上"的值。改为直接读偏好 + 仅开启时读凭据后消除。
- 持久化改为**可注入**（`AutoSourceSwitchStore` / `AudioEffectsSettingsStore`，Hive 生产实现 + 记录写入的内存实现），修掉一个**点击开关即让测试挂死 10 分钟**的问题——根因是 UI 回调里的 fire-and-forget 真实 Hive 写，其 continuation 留在假时钟队列上，`tearDown` 的 `Hive.close()` 永远等不到。

### 工程护栏

- `flutter analyze` 0 issue + 全量测试绿为**每次提交的硬门禁**；版本号 **7 处机器校验**（`version_sync_test`）。
- **i18n 硬编码计数棘轮**（`i18n_budget_test`，只降不升）。本版把 `core/network` 25 → 0 等批次迁入 ARB，基线冻结于 **875/98**。
  **说明**：本版**只发布中文**（`app.dart` 的 `appSupportedLocales` 仅 `zh`），因此**剩余 177 处迁移留待将来放开 `en` 的版本**——它们对本版用户**零可观察变化**，不应阻塞发布。棘轮继续防止新增硬编码。
- 可访问性：新增 `accessibility_audit_test`，对图标按钮与封面/头像断言**真实语义节点上的字段**（并记录两个通道的区别：`IconButton(tooltip:)` → tooltip 通道；`Icon(semanticLabel:)` → label 通道，后者为**实测结论**）。

### 已知未验证（交付时如实标注）

- **安装器编译**：本机**没有 Inno Setup**（`ISCC.exe` 不存在）⇒ 安装器未在本机构建验证。
- **Android release 的 R8 收缩**已实测**构建通过**（分包三 APK 成功），但**运行期行为**需真机验证。
- 其余【需真机】项：换源真机可播与来源角标、预解析实际请求量、通知栏小图标、Android 小组件渲染与点击（含冷启动）、Android Auto 全链路、系统分享面板、悬浮窗视觉、KRC `[language:]`、Maloja 端点、`user.getInfo` 探针。
- **签名**：release 仍指向 **debug keystore**（用户 2026-10-04 的明确选择）⇒ 换签名会让已安装用户丢本地数据；`C:\Users\PC\.android\debug.keystore` **丢失或重生成后老用户将永远无法升级**，请备份。

### 未做（有理由，已入档）

- **gapless**：现状是单 URL 传输 ⇒ 要改接口 + 3 个实现 + MediaSession 队列语义；完整方案要拆掉 `_safeStop()` 这条防线（本项目最贵的 bug 区），且"预解析到可播"只是**语义近似**；验收判据**全部需要真机**。⇒ 本版不做，留能力位与接口草案。
- **缓存 LRU**：仓库**已有一个生产中的 LRU**（`download_provider.dart` 的 `cleanupOfflineCache` + `policy.sizeLimitMb`）。再写一份等于同一块磁盘两个清理器互相淘汰。⇒ 复用现有清理器，不新写。



门禁：`flutter analyze --no-pub` **0 issue**、`flutter test --no-pub -j 1` **1093 passed / 10 skipped / 0 failed**。


## 2026-10-07 - v1.4.4 悬浮歌词行序修复：让翻译紧跟在正在唱的那句下方
### 问题

悬浮歌词显示三行时**顺序错了**：**正在唱的那句**（高亮）、**下一句的原文**、**本句的翻译**。下一句被夹在"本句"和"本句自己的翻译"之间，所以看着混乱 —— 例如：

```
DAMIDAMIDAMIO~ River guides the…     ← 正在唱（高亮）
When the night is gone, journey…     ← 下一句（却出现在翻译前面）
哒咪哒咪哒咪哟~沿着河流                ← 本句的中文翻译
```

**原因**：歌词列（原生纵向布局）的添加顺序是「本句 → **下一句** → 翻译」，而数据里 `translation` 字段指的是**正在唱这一句**的翻译、`nextText` 才是下一句。两者的语义没有被对齐。

### 修复

把歌词列的添加顺序改为「**正在唱的那句 → 它的翻译 → 下一句**」，每个视图各带自己的间距参数一起移动，字号、透明度、颜色、高亮逐字推进、跑马灯等**全部不变**：

```
DAMIDAMIDAMIO~ River guides the…     ← 正在唱（高亮）
哒咪哒咪哒咪哟~沿着河流                ← 它自己的翻译（紧贴下方）
When the night is gone, journey…     ← 下一句（压底作为预览）
```

已核实**不会引入新问题**：
- 没有任何逻辑依赖行序（这两个视图只被创建、设色、设字号、设文本/可见性、销毁，不存在按"第二行是下一句"做的测量、定位、动画或手势判断）。
- 空行不会多出来：**翻译与下一句都**做了"空则隐藏"，所以「无翻译 → 本句+下一句」「最后一句 → 本句+翻译」都正常，中间不会留空行。
- 逐字高亮只施加在"正在唱的那句"上，因此换序后高亮仍在本句推进；跑马灯与帧循环的条件与行序无关。
- 应用内播放页的歌词**本来就没有这个问题**（它是"每句后面紧跟它自己的翻译"的逐句结构），本次未改、也不需要改。

### 回归护栏（新增）

Kotlin 布局无法用 Dart 测试触达，因此按本仓库既有做法（`test/local_music_android_test.dart` 用源码断言守 `MainActivity.kt`）新增了一条**源码级顺序断言**，并额外加一条"翻译必须属于正在唱的那句"的语义断言 —— 后者防止有人反过来去**改数据字段**来"修"布局问题（那会导致把下一句的翻译当成当前句的翻译显示，是更严重的错误）。

**红→绿**：把行序临时还原成旧顺序后该断言精确失败（`Expected: ['lyricText','translationText','nextText'] / Actual: ['lyricText','nextText','translationText']`），恢复后文件**逐字节一致**（SHA256 相同）且断言通过。

### 版本与产物

- `versionName` **v1.4.3 → v1.4.4**，Android build number `14` → **`15`**；同版本号已同步到 `AppConstants.appVersion`（设置页显示）、`test/settings_page_test.dart`、`installer/mconnect.iss`、`windows/runner/Runner.rc`（两处）、`PROJECT.md`
- 签名未变（仍为 `debug` keystore）
- 分包产物（`AGENTS.md` §1 规定一律分包，禁止 universal）：
  - `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`
  - `build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk`
  - `build/app/outputs/flutter-apk/app-x86_64-release.apk`

### 需要你在真机上验收

1. **本句有翻译 + 有下一句**（截图那种）：顺序必须是 **本句（高亮）→ 本句翻译 → 下一句**。
2. **最后一句**（没有下一句）：显示 **本句 → 翻译**，底部不留空行。
3. **本句没有翻译**：显示 **本句 → 下一句**，中间不留空行。
4. 逐字高亮仍在**本句**上推进；长句仍滚动；拖动/锁定/改尺寸/改配色/改字号都不受影响。
5. 连续切句时不得闪烁。
6. 顺带回归上一版：悬浮歌词开关往返 3 次都要出现，且出现后**会滚动**；进度环在「暂停→恢复」时不再抽搐。

### 已知未覆盖（诚实说明）

- **Android 真机行为本机零验证**：原生布局只能在真机上看，本机做到的是"源码顺序断言 + Kotlin 编译通过 + 打包成功"。
- 本次**只改行序**，没有顺手调整视觉比例（例如"本句与翻译的间距"仍与"翻译与下一句的间距"相同）。若你希望翻译更贴近本句、下一句更疏远，那是一个独立的视觉调整，可以再做。

## 2026-10-07 - v1.4.3 修复：悬浮歌词消失（v1.4.2 回归）+ 小播放器进度条抽搐

门禁：`flutter analyze --no-pub` **0 issue**、`flutter test --no-pub -j 1` **1091 passed / 10 skipped / 0 failed**。

### 一、悬浮歌词彻底消失（**v1.4.2 引入的回归**，已修复）

**现象**：悬浮歌词完全不再出现，**即使把开关打开也没有**。

**原因**：v1.4.2 为了防止"关闭之后又被 200ms 的进度更新把窗口重建回来"，在原生 `update` 上加了一道门禁：只要之前被 `hide()` 过就直接返回、**不创建窗口**。问题在于：

- App 在**功能关闭时就会调用 `hide()`**（其中包括默认的关闭状态），所以这道门禁**必然被锁上**；
- 而 App 侧**只会调用 `update`，从不调用 `show`** —— 能解开这道门禁的入口，App 根本不会走。

结果：锁一旦合上，进程内再也无法把窗口建回来。这是一个典型的"**永久闩锁 + 唯一解锁入口 App 不会调用**"。

**修复**：`update` 的语义就是"App 要求显示"，因此它现在会**清除这道闩锁并（必要时）创建窗口** —— 注意只删掉提前返回是不够的，因为同一个标志还兼作**帧循环与跑马灯的开关**，不清掉就会变成"歌词出现了却不滚动、不逐字推进"。同时，当初想防的那个抖动改用**不产生永久闩锁的方式**解决：用户从悬浮窗自身关闭时，App 在等待原生返回之前就**同步停掉 200ms 的更新心跳**。注释里已写明这条不变量，禁止再引入"只有 `show` 能解开、而 App 不调用 `show`"的闩锁。

### 二、下方小播放器外圈进度条抽搐（**既有缺陷**，已修复）

**现象**：外圈进度会"突然缩短一截，然后又返回"；**暂停后再次开始必然出现**，播放中偶发。

**原因**：进度是用"锚点 + 计时器"插值出来的，而计时器取的是**自动画计时器启动以来的累计值**。暂停会停掉计时器、恢复会重启它 —— **重启后累计值从 ~0 重新开始，而锚点里还留着暂停前的大值**，于是插值瞬间算到接近 0（"缩短一截"）；下一次整秒进度更新重新锚定后又跳回去（"又返回"）。这就是"暂停后恢复必现"的原因。播放中偶发则来自 Android 在缓冲/过渡时会短暂上报"暂停"（本项目自己记录过这个行为），同样会停表+重启。

同一处数学还有第二个错误：拖动进度条（seek）时锚点被设成"零"，而累计值是几十秒 → 向后拖动会造成**向前的大跳**。

**修复**：
- 把"**重绘驱动**"与"**时间基准**"解耦：改用**单调时钟**作为时间来源（启动一次、永不重置），动画计时器只负责驱动重绘（暂停仍然停表，保住 v1.4.2 的性能优化）。这样计时器的停/启**不再影响进度数学**。
- 因为单调时钟在暂停期间仍在走，**恢复播放时必须重新锚定**，否则会凭空前跳（例如暂停 60 秒后恢复会多出 60 秒）。
- 拖动进度条统一使用同一时间基准（修掉向前大跳）。
- 加一道护栏：插值结果**不得小于最后一次权威进度**。正常播放与拖动都不会触发它，它只兜住"插值算到权威值之前"这种畸形；向后拖动仍会立刻变小。
- 把插值数学抽成**公开的纯函数**（沿用本文件既有的做法：几何那段之所以公开，正是为了"让这类 bug 无法悄悄发布"），测试可以直接驱动"暂停→恢复→整秒更新"的序列。

### 版本与产物

- `versionName` **v1.4.2 → v1.4.3**，Android build number `13` → **`14`**；同版本号已同步到 `AppConstants.appVersion`（设置页显示）、`test/settings_page_test.dart`、`installer/mconnect.iss`、`windows/runner/Runner.rc`（两处）、`PROJECT.md`
- 签名未变（仍为 `debug` keystore）
- 分包产物（`AGENTS.md` §1 规定一律分包，禁止 universal）：
  - `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`
  - `build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk`
  - `build/app/outputs/flutter-apk/app-x86_64-release.apk`

### 需要你在真机上验收

**悬浮歌词（第 1~3 条正是本次回归的原症状）**
1. **默认关闭状态下冷启动 → 打开「悬浮歌词」开关 → 悬浮窗必须立刻出现**（修复前怎么点都不出现）。
2. 出现后**必须会动**：播放时逐字高亮推进、长歌词滚动；暂停时停住。（若"窗口在但不滚动"，说明闩锁只删了一半没清干净。）
3. **关掉开关再打开，往返 3 次**：每次都要重新出现。
4. 点悬浮窗自带的关闭按钮：窗口消失、开关变关，之后**不应自己冒回来**。
5. 撤销「显示在其他应用上层」权限后再开关 → 应按权限提示处理，不静默失败；授权后再开 → 正常出现。

**进度条**
6. **暂停 → 恢复：进度环不得先缩一截再弹回**（原来必现）。
7. 连续播放数分钟无偶发抖动；拖动进度条向前/向后应立刻跟随、不回弹。
8. 暂停时进度环应停住（不持续增长/重绘）。

**回归确认（v1.4.2 的卡死修复不能被破坏）**
9. 快速连点「下一首」20 次以上、连续快速点迷你播放器 10 次、快速来回切 tab 30 秒 → 不出现「应用无响应」；`logcat` 中 `ANR in com.mconnect.mconnect` 为空。
10. `adb shell dumpsys gfxinfo com.mconnect.mconnect reset` → 暂停 10 秒 → 帧数应≈0；隐藏悬浮窗后同样≈0 且窗口不自恢复。

### 已知未覆盖（诚实说明）

- **Android 真机行为本机零验证**：Kotlin 侧只做到编译通过 + Dart 侧回归测试；悬浮歌词那条不变量的最终确认必须在真机上按上面第 1~3 条走。
- 进度环那条"播放中偶发抖动"的触发源（Android 短暂上报暂停）是**依据本项目既有记录的最可能解释**，未在真机逐帧实测；但"暂停后恢复必现"已在 widget 测试里被精确复现并锁死。

## 2026-10-07 - v1.4.2 卡死修复（快速切页/连点导致整机无响应）

用户报告：**快速切换页面或连续快速点按钮，会导致 App 整个无响应，必须退出重进**。这是本次修复的全部内容。门禁：`flutter analyze --no-pub` **0 issue**、`flutter test --no-pub -j 1` **1083 passed / 10 skipped / 0 failed**。

### 诊断（依据用户提供的日志 `10-7.txt`）

日志里有确凿证据：**8 分钟内进程级启动 6 次**（与"无响应→强杀→重进"循环一致）；播放位置**冻住十几分钟不变**（`position_ms` 170045 从 13:19 冻到 15:24，换歌后又冻在 1199）；`[background_playback] reassert` 高频成簇且**全部 `is_playing:false`**（生命周期抖动，ANR 对话框/强杀会制造这种抖动）。

关键前提：**Android 上 Flutter 的 Dart isolate 与原生主线程是同一条线程**，所以原生主线程阻塞 = UI 冻结 + 所有 `await` 停摆。于是共查出**两类**原因，且它们互相放大。

### 一、"一次失败后进程内再也起不来"（播放器状态机）

1. **音频串行点没有超时、没有上界**：所有音频操作排在一条 `await` 链上，任一平台调用吊住，后面每次点击都永久排队；连点则无界堆积。→ 现在等待带超时、等待数有上界，超时会记录可诊断事件（`audio_mutex_wedged` / `audio_mutex_overflow`）并继续执行；一个早抛异常也不再可能断链把后续全部吊死。正常路径仍是唯一串行点（这是防止音频平台通道被并发重入的关键设计）。
2. **播放器重建没有并发防护**：7 个失败路径都会触发"销毁并重建播放器"，其中几处是 fire-and-forget，**并发重建会取消掉正在进行中的操作仍在使用的订阅**，并在其脚下换掉控制器。→ 改为单飞（进行中的重建只可能有一个）。
3. **自愈机制被它要修的状态关死**：停滞自愈的启动条件是"正在播放"，所以一旦落到"已判定为暂停 + 位置不动"，**12 秒自愈永远不会触发** —— 这正是"一次失败后只能强杀"的原因。→ 新增独立的卡死看门狗，**不再以"正在播放"为前提**，触发时作废陈旧请求、清掉所有忙标志、重建播放器，并明确告诉用户"播放未能恢复，已重置播放器，请重试"。
4. 顺带：转场看门狗此前在"新请求已推进序号但卡在队列里"时**拒绝复位**（这恰恰是最需要它的时候）；恢复播放的失败路径会留下一个永久为真的标志，导致之后每次点击都重进一条必然失败的路径。两处都已修。

### 二、"把主线程压死"（UI 与原生）

5. **打开播放器毫无防护**：点一下迷你播放器就叠一层播放页（连点 10 次 = 10 层），而每层都是全屏模糊 + 玻璃层并各自带定时器。→ 加实例级在途守卫，同一帧只放行一次；关闭后立刻再点仍正常打开。
6. **底栏模糊层每帧重采样**：模糊层的进度环在播放时逐帧重绘，而两者之间没有重绘边界，于是 backdrop 被每帧重新采样、持续耗尽帧预算 —— 这条把第 5 条从"卡一下"放大成"永久无响应"。→ 加 `RepaintBoundary` 隔离（不改变任何像素）。
7. **通知/媒体会话被无条件重建**：每次状态变化都把**整条歌单**重新映射成媒体条目并重新发布，一次播放连发 3-4 次、位置更新也走同一条路。大歌单时这是 O(n) 的重活，还会让 Android 主线程反复重建通知。→ 改为"真的变了才发"（换歌/歌单/序号/控件/喜欢/悬浮歌词），位置类只做广播并按 1 秒节流，拖动进度条仍立即生效。
8. **tab 切换在生产路径上没有防抖**：已有的一套 80ms 防抖写在了实际不会执行的代码路径上（外壳接管底栏后才生效的那条），于是每次点击都重建整个外壳并导航。→ 防抖挪到真正执行的那条路径上，点当前 tab 直接忽略。
9. **在 `build` 里做同步文件访问**：外壳的三处、以及**本地音乐列表的每一个行**都在构建时 `existsSync()`（几百首时每次重建几百次同步 stat，Android 外置存储上单次可达数百微秒）。→ 全部改为按路径记忆的缓存（测试可注入可计数探针），行级缓存键包含曲库版本。
10. **原生侧在主线程做 binder/磁盘 I/O**：SAF 权限查询/授权/释放、文件打开器的存在性检查与三次"能否打开"探测、悬浮歌词的权限查询都在主线程。→ 移到后台执行器，结果回主线程再回调（通道名与方法签名保持不变）。
11. **两条永不回调的通道分支**会让界面**永久转圈**：选择目录过程中页面被销毁、以及扫描结果跨 `onDestroy`。→ 现在任何路径都会明确返回错误，不再有"无人应答的等待"。
12. **悬浮歌词让主线程永不停表**：16ms 帧循环自重排、三个永不结束的跑马灯、隐藏后又被下一次更新**重建窗口**、每次更新都重查一次权限。→ 帧循环与跑马灯只在"可见且确实在播放"时运行，隐藏即停，隐藏后不再被重建，权限结果缓存。
13. 顺带：离线缓存页此前"队列任意变化就全盘重扫"，改为监听已完成项并 500ms 合并；聚合搜索补上了代际守卫（快速改两次查询时，旧结果不再覆盖新结果）。

### 版本与产物

- `versionName` **v1.4.1 → v1.4.2**，Android build number `12` → **`13`**；同版本号已同步到 `AppConstants.appVersion`（设置页显示）、`test/settings_page_test.dart`、`installer/mconnect.iss`、`windows/runner/Runner.rc`（两处）、`PROJECT.md`
- 签名未变（仍为 `debug` keystore）
- 分包产物（`AGENTS.md` §1 规定一律分包，禁止 universal）：
  - `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`
  - `build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk`
  - `build/app/outputs/flutter-apk/app-x86_64-release.apk`

### 需要你在真机上验收（本机无法复现真实 ANR）

1. **原症状**：播放中连续快速点"下一首"20 次以上、以及连续快速点迷你播放器 10 次 → 不应出现无响应；连点后最多只进一层播放页，返回一次即回到原页。
2. **一次失败后能恢复**：复现日志里那首歌（QQ、返回"该歌曲在QQ音乐不可用"）→ 失败后应能**直接播放其他歌**，不需要重启；日志中如出现 `player_forced_reset`，说明看门狗按预期介入过。
3. **快速来回切 tab + 快速进出一个榜单/歌单页** 30 秒 → 不出现"应用无响应"；`logcat` 中 `ANR in com.mconnect.mconnect` 应为空。
4. **悬浮歌词可量化判据（最有力）**：开悬浮歌词播放 → `adb shell dumpsys gfxinfo com.mconnect.mconnect reset` → **暂停 10 秒** → 再查帧数应基本为 0（修复前会持续增长）；隐藏悬浮窗后再等 10 秒同样应≈0，且窗口**不会自己再出现**。
5. **不再永久转圈**：点「选择其他位置」调起系统选择器后直接返回 → 弹窗立刻恢复可用；扫描进行中把 App 划掉再重开 → 下载设置弹窗不再永久 loading。
6. 若仍出现无响应：把新日志给我，这次会带 `audio_mutex_wedged`（等待毫秒）、`audio_mutex_overflow`、`player_forced_reset`，可以直接定位挂在哪一步。

### 已知未覆盖（诚实说明）

- **Android 真机行为本机零验证**：Kotlin 侧只做到编译通过 + 打包含新类 + Dart 侧全链路单测。
- 本地音乐封面缓存缺少"行级计数"测试（机制与背景那条同源，背景已有红→绿）；离线缓存合并缺少直接测试。
- 悬浮歌词 16ms 帧循环仍是 16ms（那是逐字高亮的本意），只是现在**只在真正需要时**运行。

## 2026-10-07 - v1.4.1 遗留缺口修复


v1.4.0 发布后复核发现的遗留问题与失效路径修复。共 5 项，另有若干"看起来能用、实际没有执行者"的路径被补齐。门禁：`flutter analyze --no-pub` **0 issue**、`flutter test --no-pub -j 1` **1027 passed / 10 skipped / 0 failed**。

### 1. 会话失效现在会被真正发现（覆盖全部路径，而不是只有一个）

**问题**：v1.4.0 里只有「平台歌单」这一处调用点会处理 HTTP 401，其他路径（每日推荐、榜单、下载、取流）cookie 失效时，App **继续显示已登录**而每个请求都失败，最坏情况静默降级成游客数据。

**修复**：上报改到**检测到 401 的地方**（网络层的错误翻译拦截器），经一个全局汇通知登出，由 `lib/app.dart` 安装一次处理器。三个平台适配器各自传递自己的平台身份，因此**所有调用路径（含将来新增的）自动覆盖**。最容易做错的一点被抽成可测函数：**未登录时的 403 不会被误判为过期**；且因为登出后登录态已清空，真实过期后接连而来的 401 **只会提示一次**。

**已知边界（明示）**：只识别 **HTTP 401/403**。这三家 API 常见的「HTTP 200 + 业务错误码」不作为过期处理，因此仍可能出现"看不出发生了什么"的降级。

### 2. 长按歌曲菜单补齐三个页面

长按菜单此前只在 7 处列表生效，「我喜欢」「听歌历史」「本地音乐」长按无反应 —— 用户在别的列表学会了这个手势，回到这三页会以为坏了。现已全部接上；本地音乐页会自动隐藏不适用的动作（下载/分享/加入歌单）。

### 3. 删除没有消费者的死代码

`rankingsProvider` 已无任何界面使用（榜单页早已改走榜单中心），保留它会让人有机会去修改"没人用的那一份"错误处理。已删除该 provider 及其 4 条测试。平台层的扁平接口 `getRankingList()` **有意保留**（平台探针与多处测试仍在使用，是非破坏性回退），但其接口文档已明确写出"界面走榜单中心，不要围绕它重建 provider"。

### 4. 酷狗只保留扫码登录，并收口明文凭据链路

- **手机号 + 验证码登录整体移除**（不是隐藏入口）：登录页只保留扫码；平台层对应方法明确返回"请使用扫码登录"且**不发出任何网络请求**。这一条消除了"手机号与验证码明文传输"这条最高危链路。
- **顺带纠正一处此前的错误结论**：酷狗明文白名单里 `kugou.com` 是**整域一条**规则，同时支撑十余个明文端点，因此**只留扫码并没有缩小白名单**（也没有可单独删除的条目）—— 消除的是那条链路本身。
- **另发现并修复同类风险**：`tracker.kugou.com` 的 HTTPS 经实测**是可用的**（证书有效），它返回的**私密取流地址**此前走明文、可被同路径中间人改写后被下载器落盘 —— 现已改 HTTPS，这类端点至此清零。其余三个**带 token 的明文端点**（酷狗收藏/取消收藏、会员信息）经实测其主机 443 报 `CERTIFICATE_VERIFY_FAILED: Hostname mismatch`，客户端无法改用 HTTPS；因替代方案是永久禁用"收藏到酷狗"，而暴露的是用户自己的 token 且动作可逆，故**保留功能并在代码中就地标注风险与理由**，不静默降级。
- 取流兜底：`priv_url` 路由全部失败时回退到已走 HTTPS 的 `getSongInfo`，并记录可见的诊断事件，而不是静默失败。

### 5. 下载自定义目录：修掉"卡死 + 零提示"，并补上 SAF 真能力

**修掉一个此前未被报告的真 bug**：选择目录的按钮把 `Future` 当同步回调丢弃，因此"目录不可写"时异常被吞掉，用户看到的是**底部弹层永久转圈、两个按钮全灰、没有任何提示**。修法分两层：数据层**永不抛异常**（返回"不可写/无法创建/不是目录/根目录/存储失败"等类型化原因），UI 层 `finally` 保证状态复位，并把原因**同时**显示在弹层内（该弹层在 root navigator 上，只靠 SnackBar 会被挡住）。此外还有一个**真实写探针**：创建并删除一个临时文件 —— "目录存在"不等于"可写"（Android 11+ 对多个受保护位置会返回已存在的目录）。

**顺带修掉同类静默失败**：选择器抛异常时此前什么都不做；现在会明确提示。（选择器返回空视为"用户取消"，保持静默 —— 该 API 无法区分"取消"与"云盘位置无法映射"，把每次取消都误报成失败是更差的取舍。）

**SAF 真能力**：用户指定的目录现在通过 Android 的存储访问框架写入 —— 选择目录时取得**可持久保留**的授权，下载先落在应用临时目录（沿用原有的断点续传与大小校验），完成后经 SAF 搬入目标目录并校验大小，失败保留临时文件以便重试。**权限失效不会静默写到别处**，而是明确要求重新选择目录（否则用户以为文件在 A 目录、实际在 B，比失败更糟）。"打开下载文件夹"对 SAF 目标改用树 URI 打开，没有可用文件管理器时给出提示而不是点了没反应。

#### 需要你在真机上验收（本机无法验证 Android 存储行为）

1. **选目录**：下载设置 →「选择目录」→ 系统选择器 → 在 SD 卡或 `Download` 下新建 `Mconnect` → 返回后界面显示 `Mconnect（自定义目录）`（若显示成一串路径或提示"无法长期保留该目录的访问权限"，即失败）。
2. **下载**：下一首歌 → 完成后用系统文件管理器进该目录 → 文件存在、可播放、大小与 App 内一致（无 0 字节或半截文件）。
3. **重启后仍可写（最关键）**：从最近任务划掉 App → 重开 → **不重新选目录**直接再下一首 → 应成功且仍在同一目录。这才证明持久授权真的生效。
4. **权限失效不静默**：在系统设置里撤销该目录授权（或把该文件夹改名/删除）→ 再下载 → **必须**提示"自定义下载目录的访问权限已失效，请在下载设置中重新选择目录"，且**不得**悄悄写到应用私有目录。
5. **打开文件夹**：点「打开下载文件夹」→ 能打开最好；没有可用文件管理器时**必须**有提示（不得点了没反应）。
6. **Android 13+**：全程不请求 `READ_EXTERNAL_STORAGE`/存储权限；写非沙箱目录不再报 EACCES。
7. **续传**：下载中断网后继续、暂停后继续 → 目录里只有**一个**完整文件，无残留半截文件。
8. **删除**：已完成记录删除 → 系统文件管理器里该文件**真的消失**；被平台拒绝时 App 报"删除下载文件失败"。
9. **恢复默认**：「恢复默认」→ 显示默认位置 → 再下载落到默认位置（自定义目录不再被使用）。
10. **长按菜单**：本地音乐页长按 → 只出现「下一首播放 / 复制链接」。
11. **重启后下载列表不丢记录**：下载 2 首以上到自定义目录 → 杀掉 App 重开 → 进「下载」页 → **这些记录仍在「已完成」里**、大小显示正常（不是 0）、文件夹图标仍能打开该目录；删除其中一条 → 文件真的从用户目录消失。

> 第 11 条是本轮在接线过程中发现并修掉的一个缺陷：自定义目录里的下载其记录路径是 `content://…`，而恢复逻辑此前用 `File(path).exists()` 校验，导致**重启后这些记录会从下载列表消失并被持久化**（文件仍在用户目录里，但列表再也回不来）。

#### 已知限制（明示，不粉饰）

- **下载到自定义目录的歌不走"离线播放优先"**：`content://` 无法当作文件路径交给播放器，因此离线模式对它们会回退到在线流。这是该存储方案的直接后果，不是缺陷；若将来要支持，需要在播放层直接接受 `content://`。
- **自定义目录中已发布文件的大小按下载时记录值显示**：若用户在系统文件管理器里删掉该文件，缓存统计仍显示记录值（普通路径是"删了就归零"，`content://` 无法低成本探测）。
- **磁盘空间预检探的是应用临时目录所在卷**，不是用户选的目录所在卷：写满用户卡会在拷贝阶段失败，归类为"磁盘"（可重试）并保留临时文件，不必重新下载。
- **会话失效只识别 HTTP 401/403**：这三家 API 常见的"HTTP 200 + 业务错误码"不作为过期处理，因此仍可能出现看不出原因的降级。

### 版本与产物

- `versionName` **v1.4.0 → v1.4.1**，Android build number `11` → **`12`**；同版本号已同步到 `AppConstants.appVersion`（设置页显示）、`test/settings_page_test.dart`、`installer/mconnect.iss`、`windows/runner/Runner.rc`（两处）、`PROJECT.md`
- 签名未变（仍为 `debug` keystore，未切换正式签名）
- 分包产物（`AGENTS.md` §1 规定一律分包，禁止 universal）：
  - `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`
  - `build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk`
  - `build/app/outputs/flutter-apk/app-x86_64-release.apk`

## 2026-10-07 - v1.4.0 全面改进与功能补全


本轮按《Mconnect v1.4.0 全面改进与功能补全实施计划》执行：Wave 0 冻结共享契约，Wave 1-3 由 13 条工作流并行完成，Wave 4 集成出包。用例数 438 → **960**，`flutter analyze` 全程 0 issue。

### 修复四个「已上线但实际失效」的功能

它们的共同根因是**有界面、有开关、有数据结构，但没有执行者**：

- **离线缓存是死队列**：`cacheSongs` 只创建 `waiting` 任务、从不调用下载器，全仓没有调度器；且 `waiting` 行没有任何操作按钮。现在有真正的队列调度器（FIFO、并发上限、可暂停、连接状态闸门），`waiting` 行可开始/取消。
- **缓存过的歌再也无法手动下载**：缓存任务与手动下载共用同一个 id，去重只看状态，导致点下载直接被 return。现在两者 id 区分，互不阻塞。
- **四个开关纯装饰**：「仅 Wi-Fi 下载」「失败自动重试」「自动清理」「离线模式」此前**没有任何读取点**。现在分别接入下载调度、重试策略、完成回调与播放优先级。
- **重启不续传**：恢复后一律停在暂停态。现在按"失败自动重试"开关自动续传。

### 用户点名的问题

- **QQ 音乐热歌榜**：此前**没有入口能看到**。两条硬根因——代码写的是 `topId=4`（实测那是"流行指数榜"，热歌榜是 **26**），且解析路径错一层（真实结构是 `data.data` + `data.songInfoList`，且每首歌曲包在 `data` 里需要解包）。两者叠加导致 QQ 榜单恒为空，而榜单页只收录"返回了内容的平台"，于是 QQ 标签页直接消失。现已修复，并新增**QQ 热歌榜专属界面**：榜单元信息头 + **300 首**（该端点单次上限 50 首，内部翻 6 页取满）+ 本期名次与**涨跌箭头**。
- **每日推荐不再只有网易云**：QQ 与酷狗一并接入。QQ 登录后取「今日私享」，未登录时回退到榜单；酷狗的官方推荐接口已被服务端下线（实测 5 种签名变体全部被拒），改为取首页推荐模块。**每个平台都会在界面上标注列表来源**，不会把"榜单回退"伪装成"每日推荐"。

### 新增功能

- **榜单中心**：按平台分组展示真实榜单（QQ 4 组 30 榜、网易云、酷狗 25 榜），QQ 热歌榜置顶，任一平台失败都保留并显示错误与重试（不再静默消失）。
- **专辑页 / 艺人页 / 新歌速递**：专辑含发行信息与按曲目号排序的曲目列表；艺人含热门 50 与专辑列表（各分区独立容错）；新歌支持 6 个地区筛选，平台不支持的地区会明确说明而不是显示空白。
- **聚合搜索**：一次搜索同时查三个平台，按归一化键合并同名歌曲并标注来源数量，可切换播放来源；支持**真分页/无限滚动**（此前页码恒为第 1 页）、下拉刷新、骨架屏、搜索历史与联想词、区分"无结果"与"网络失败"。
- **长按歌曲菜单**：下一首播放 / 添加到歌单 / 下载 / 收藏 / 复制链接 / 分享（此前全仓没有任何长按菜单）。
- **多选批量操作**与**自建歌单拖拽排序**。
- **分享与深链**：分享歌曲/歌单链接；支持 `mconnect://` 深链回流，以及**接收系统分享**的歌单链接直接导入。
- **数据备份与恢复**：导出收藏/歌单/智能歌单/统计/设置为单文件 JSON；导入是**合并**语义（按歌曲主键与归一化键去重、同名歌单合并、设置只覆盖文件里有的键），更高格式版本或损坏文件在写库前拒绝。
- **诊断日志导出**：一键导出脱敏后的诊断日志并调起分享（此前用户拿不到日志文件）。脱敏覆盖 Cookie/Authorization 整行、Bearer 令牌、40 个敏感键名的两种形态，以及任何 URL 的整段 query。
- **播放器高级能力**：倍速、跳过静音、A-B 循环、手动歌词偏移、随机播放"已播集合"（修复长队列重复）、睡眠定时持久化并在到点时淡出。
- **本地音乐**：读取真实 ID3/FLAC 元数据与内嵌封面（此前只读文件名）、增量扫描落库（1000 首实测：首次 274ms/1000 次标签读取，二次 **56ms/0 次**）、专辑/艺人/文件夹三种视图、与在线曲库去重、KRC/QRC 歌词解码。Android 复用已授权的目录，重扫无需再次选择。
- **界面国际化起步**（架构 + 设置页/播放器/底栏四文件，含 Material 内置控件文案中文化；其余文案待后续迁移）、**无障碍起步**（播放器控制键补语义标签、消除固定宽度装文本、硬编码黑白收敛到语义色、统一提示样式）。

### 稳定性与数据安全

- **歌词请求补 8 秒超时**（此前是全 App 唯一没有超时的关键请求，平台挂起即永久转圈）。
- **音质切换闸门**：此前某个分支会让"正在切换音质"标志永远为真，并连带关闭卡顿自愈与音量守护——即"后台有进度但没声音"时唯一能自愈的路径被关掉。现在无条件复位。
- **卡顿自愈移入音频互斥锁**：此前它与音质切换并发抢播放器。
- **统计不再销毁数据**：此前只保留前 100 首并据此重建索引，第 101 首会把被挤出的旧统计**永久抹掉**，而总数仍是全量、无法对账。现在明细落库、从明细重算，支持歌手/专辑/平台/时段多维。
- **暂停后恢复不再被计为新播放**；听歌历史补上已听时长并在时间窗内合并重复行。
- **数据库升级路径**：此前只有建表、没有升级逻辑，drift 对未处理的版本升级会直接报错——第一次加列就会让所有已安装用户升级即崩（而库里有收藏、历史、歌词缓存）。现在有真实升级路径与迁移测试（构造带数据的旧库→升级→断言数据保留）。
- **下载**：断点续传、落盘大小校验、开始前磁盘余量检查、统一失败分类（网络/鉴权/会员/磁盘/不存在）、离线缓存按最近访问淘汰、用量按扫盘统计。
- 网络层此前整层是死代码（重试与错误翻译从未生效）；现在真正接上，且**只对幂等请求重试**（重放点赞/歌单写入会重复生效），并区分"用户主动取消"与"网络故障"。
- 会话失效（401）现在会明确提示并引导重新登录，而不是长期显示"已登录"。

### 安全

- **明文 HTTP 收窄**：此前整个 App 放行明文流量，而酷狗有 16 个端点走 http，其中包含**手机号验证码**与**播放地址**（后者被中间人替换后会被下载器落盘）。现改为默认拒绝 + 域名白名单，并在实测确认 443 可用后把 4 个端点（含播放地址那条路）改为 HTTPS。
- 登录会话相关存储全部加了异常兜底；清除会话改为按前缀删除，不再清空整个安全存储。

### 工程化

- **新增 CI**：静态检查（必须 0 issue）+ 全量测试 + 分包构建产物；并显式断言"不得出现 universal 包"、以及"没有源码被 .gitignore 隐藏"（后者正是本轮发现的一个真实事故：一条未锚定的 `backup/` 规则把整个备份功能源码挡在版本控制之外，本机全绿但别人 clone 后编译不过）。
- lint 加严（`unawaited_futures`、`use_build_context_synchronously`）；启动路径中互不依赖的初始化改为并发；图片缓存上限常量此前从未被读取（源码写 200MB、实际跑框架默认 100MB），现已真正生效。
- 文档事实修正：README 的打包命令此前与 `AGENTS.md`「一律分包」直接冲突；工具链版本、`PROJECT.md` 的"平台：Android"、"build_runner 不兼容"、以及"待完成"里其实早已完成的项（图标/启动页、后台播放、深色模式）均已更正。

### 版本与产物

- `versionName` **v1.3.2 → v1.4.0**，Android build number `10` → **`11`**；同版本号已同步到 `AppConstants.appVersion`（设置页显示）、`test/settings_page_test.dart`、`installer/mconnect.iss`、`windows/runner/Runner.rc`、`PROJECT.md`
- 签名未变（仍为 `debug` keystore，未切换正式签名）
- 分包产物（`AGENTS.md` §1 规定一律分包，禁止 universal）：
  - `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`
  - `build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk`
  - `build/app/outputs/flutter-apk/app-x86_64-release.apk`
- 门禁：`flutter analyze --no-pub` **0 issue**；`flutter test --no-pub -j 1` **960 passed / 10 skipped / 0 failed**

## 2026-10-04 - v1.3.2：二级页「白影」与退出时底部不模糊；改为分包出包

### 修复一：二级页亚克力背板透出上一页文字（白影）

**根因**：`BackdropFilter` 的输入不是「下面那一页」，而是该绘制位置之前**已合成的整个场景**（官方定义 "filters the existing painted content"）；而转场全程上一页确实还在画——`TransitionRoute._handleStatusChanged` 只在 `completed` 时把 `overlayEntries.first.opaque` 置回，`forward`/`reverse` 期间一律 `false`。于是 280ms/220ms 窗口内上一页的白字必然落进模糊里。填充救不了：alpha 合成是线性的，同一个填充把文字与背景图的对比度按同一系数压低。

**修复**：让背板不再读场景，改为**自包含的不透明磨砂层**——自己画一份用户背景图并模糊它，底下垫不透明底（`ColoredBox(surface)` + `ImageFiltered(blur)` + `OverflowBox`/`ClipRect`）。`ImageFiltered` 只过滤自己的子节点，结构上不可能采到别的路由，白影不再"被压下去"而是不可能存在；又因为底色本身就是那张图，"不透明"不再等于"看不见背景"。顺带修掉 `reduceMotion` 分支的纯色 scrim（α=0.6 会让上一页以 40% 透出，用户一直在看双曝光）。

### 修复二：退出二级页时底部约 20% 不模糊

**根因**：`MiuixBottomStack` 把底部净空做成**包在 Navigator 外面**的 `Padding`，而它包的正是 go_router 的嵌套 Navigator；嵌套 Navigator 的 Overlay 在 `Padding` 内，`_RenderTheater.paint` 会 `pushClipRect` 到自身边界，所以**没有任何路由能画到 `H − 144dp` 那一条**。唯一覆盖它的是「根 Shell 页」背板，而它由 `state.uri.path == '/'` 决定——`pop()` 一开始 location 就翻转，补丁第一帧消失，而滑出页背板还要 220ms 才走完 → 上下断层。

**修复**：把底部净空从「Navigator 外面」移到「路由内容里面」（`MiuixBottomStack` 新增 `insetChild`，`AppRouteShell` 传 `false`；新增 `RouteBottomInset` 施加于路由内容；`_transparentAppPage` 拆成 `_appShellPage` / `_appLeafPage`）。磨砂背板从此满屏并随页面横向滑走，上下永远是同一层。连带修正：嵌套 Navigator 满屏后 shell 内的 `showModalBottomSheet` 会被画在其上的胶囊压住，两处调用改为 `useRootNavigator: true`。

### 打包方式变更（本项目约定）

- 出 Android release **一律分包**：`flutter build apk --release --split-per-abi`
- 理由：universal 包把三套 ABI 原生库全塞进去，实测 `lib/` 占 76.1 MB / 80.5 MB（95%），而一台 arm64 真机永远用不到 x86_64 与 32 位 ARM 的那 50 MB
- 规则已写入 `AGENTS.md`，以后打包按它执行

### 测试

- `flutter analyze --no-pub` 0 issue；`flutter test --no-pub -j 1` **438/438 通过**
- 新增/改写断言：背板子树内**不得存在 `BackdropFilter`**（白影消失的结构性证据）；push/pop 各时间点**磨砂背板宽高等于整个视口**；页面内容仍按 `contentInsetFor` 让开胶囊；`insetChild` 两个方向的语义；shell 内弹窗**不在** shell 子树内
- 两处红→绿验证：还原旧结构后几何断言报 `Expected 820.0 / Actual 684.0`（正好是 136 dp 的清晰带）；去掉 `useRootNavigator` 后弹窗断言报 `Found 1 BottomSheet descending from MiuixBottomStack`

### 版本与产物

- `versionName` **v1.3.1 → v1.3.2**，Android build number `9` → **`10`**；同步更新 `AppConstants.appVersion`（设置页显示）、`installer/mconnect.iss`、`windows/runner/Runner.rc`（含此前漂移在 `1,3,1,8` 的兜底值）、`PROJECT.md`、`test/settings_page_test.dart`
- 签名未变（仍用 `debug` keystore），本次不切换正式签名
- 产物：`build/app/outputs/flutter-apk/app-{arm64-v8a,armeabi-v7a,x86_64}-release.apk`

## 2026-09-30 - 修复「关闭悬浮歌词再打开后字号变成最小号」

### 根因

字号是否写进 View 的门用的是**「传入值 vs 缓存字段」**，而不是「已应用到 View 的快照」：

```kotlin
val sizeChanged = size != fontSize      // 字段 vs 传入值
fontSize = size
if (sizeChanged || shadowChanged) applyTextSize()
```

而 `removeOverlay()` 会把 `appliedFontSize = -1f` 归零、**却不重置 `fontSize` 字段**。于是：关闭悬浮歌词 → 三个 TextView 销毁（字段仍留上次字号）→ 再打开 → `createOverlay()` 新建的 TextView 是 **Android 默认 14sp（正好等于最小值）** → 紧接着 `applyData()` 传入的还是同一个字号 → `sizeChanged == false` → **`applyTextSize()` 根本没被调用** → 停在第 14sp。点 T+/T- 会直接调用 `applyTextSize()`，它内部那道正确的快照守卫通过，于是字号立刻“变回之前设置的值”。Hive 里的字号一直是好的，设置页显示的也是对的 —— 漏的只是**新建 View 后的一次样式应用**。

### 修复

- `applyBaseStyle()`：改为**无条件调用** `applyTextSize()`（删掉 `sizeChanged/shadowChanged` 这两个基于字段的门）；`applyTextSize()` 自身的 `appliedFontSize/appliedShadowOpacity` 快照守卫保证幂等
- 新增 `resetAppliedState()`：在 `createOverlay()` 与 `removeOverlay()` 都调用，统一作废全部「已应用快照」（文本/进度/span/字号/阴影/底色/圆点/背景/播放/锁）——**任何 applier 在 View 重建后都不可能再跳过应用**
- 兜底：新建三个 TextView 时先按当前字段给出初始 `textSize`（主行/下一句 0.92×/译文 0.62×），避免万一 `applyData` 迟到时出现一帧 14sp

### 测试

- `test/floating_lyrics_service_test.dart`：新增断言 `args['fontSize'] == settings.fontSize`（每次展示都下发持久化字号）；新增原生源码断言：不得再出现 `if (sizeChanged || shadowChanged)`，且必须存在 `resetAppliedState()` 与 `appliedFontSize = -1f`

### 版本与产物

- `versionName` 保持 **v1.3.1**，Android build number `8` → **`9`**（让覆盖安装更干净；应用内显示仍为 v1.3.1）
- `flutter analyze --no-pub` 0 issue；`flutter test --no-pub -j 1` **424/424 通过**；`flutter clean` 后 `flutter build apk --release` 通过
- `aapt2` 核验：`versionCode='9' versionName='1.3.1'`；`apksigner verify` 正常；`audio_service_lyrics_*` / `audio_service_favorite_*` 资源均 PRESENT
- 构建期间遇到一次 `lintVitalAnalyzeRelease` 的 lint 缓存文件锁（Windows 文件占用），`gradlew --stop` + 删除 `build/app/intermediates/lint-cache` 后重试成功

## 2026-09-30 - 版本号统一到 v1.3.1 并出 release 包

### 版本号（全部对齐到 1.3.1）

- `pubspec.yaml`：`1.3.0+7` → **`1.3.1+8`**（`versionName=1.3.1`、`versionCode=8`；build number 必须大于已装的 7，否则系统拒绝覆盖安装）
- `lib/core/constants/app_constants.dart`：`appVersion` `v1.2.5` → **`v1.3.1`**（这是应用内「诊断与关于」页显示的版本号）
- `test/settings_page_test.dart`：版本断言同步为 `v1.3.1`
- `installer/mconnect.iss`：`MyAppVersion` `1.3.0` → **`1.3.1`**（安装包版本与输出名 `Mconnect-Setup-1.3.1.exe`）
- `windows/runner/Runner.rc`：兜底 `VERSION_AS_NUMBER 1,0,0,0` → `1,3,1,8`，`VERSION_AS_STRING "1.2.5"` → `"1.3.1"`
- `PROJECT.md`：版本行 `1.2.4+5` → `1.3.1+8`
- **未动**：`pubspec.lock` 里的 `1.3.0` 是依赖包（build_config / logging）版本，与 App 版本无关；`docs/mconnect-improvement-plan.md` 里那句是历史审计记录

### 验证

- `flutter analyze --no-pub` 0 issue；`flutter test --no-pub -j 1` 全量 **423/423 通过**（含「settings page shows the current app version」= 应用内显示版本已为 v1.3.1）
- `flutter clean` 后重新 `flutter build apk --release` → 通过
- 用 SDK `aapt2 dump badging` 核验产物：`versionCode='8' versionName='1.3.1'`；`apksigner verify` 签名正常（项目 release 用 debug keystore）
- 复核 release 资源压缩未吃掉按名字引用的通知图标：`audio_service_lyrics_on/off`、`audio_service_favorite_filled/outline` 以及全部 `fl_ic_*` 均在资源表中 PRESENT

## 2026-09-30 - 悬浮窗当前句「整行消失」根治：退回单 TextView + 文字色 span

### 你问的「改了什么导致」——答案

第 6 轮为了修「长句滚动时高亮脱离文字」，我给当前句加了**第二层 TextView（高亮层）+ `clipBounds` 裁剪 + 自己驱动 `scrollX`**，并把两层都改成不用系统 marquee。高亮层是「多出来的一个 View」，它的可见性、裁剪、滚动偏移都需要逐帧维持；**任何一次没维持住，这一行就整行空掉**（`minHeight` 仍占位，所以是「那行空着、位置还在」），点一下触发布局/窗口重排又把它刷回来 —— 与你描述的「只有点击后才出现」完全一致。第 7 轮我只修了自管滚动里的超宽判定，没有消除这套软状态，所以现象仍在（同一首歌同一句，图二渲染正常、图一空白，就是绘制状态问题而非数据问题）。

### 修复：回到已证明能渲染的单 TextView + span

- 当前句恢复**单个 TextView**：`configureMarquee()`（`singleLine + horizontallyScrolling + ellipsize=MARQUEE + isSelected`），长句滚动交回系统 marquee
- 高亮改成**文字自身的颜色 span**：每帧按 `highlightProgress` 把 `SpannableString` 涂成三段
  - `[0, whole)` → 高亮色；`[whole, whole+1)` → 底色与高亮色的**插值**（按该字进度 lerp，24 档量化）；其余 → 底色
  - 只在 `whole`/档位变化时 `removeSpan/setSpan` + `invalidate()`，**不 `setText`** → 不重排、marquee 不中断
- **因为颜色是文字自身的属性**：marquee 滚动时颜色跟着字形走 → 「高亮与滚动文字分离」在结构上不可能再发生；也不存在任何会变脏的绘制状态 → 当前句不可能再整行消失
- 删除：`progressText`、`clipBounds`/`Rect`、`applyScroll`/`scrollOffsetFor`/`scrollCycleStart`、`maxScrollPx`/`lineMetrics`、`configureScrollingLine`、`SCROLL_*` 常量
- 保留：Dart 的 `highlightProgress`(连续) + `highlightRate` 契约与 200ms 锚点、16ms 帧循环与「播放中且可见才跑」门控、暂停冻结、两句/译文布局、透明度、锁定穿透；DEBUG 日志字段改为 `len/whole/step/progress/rate`

### 权衡

扫过粒度回到「按字推进」，用**边界字的颜色插值**软化过渡（观感接近网易云，但不是像素级连续）。像素级连续只有自定义 `onDraw` 或双层+可控滚动两条路，都会重新引入需要维持的软状态，留作单独一轮评估。

### 验证

- `flutter analyze --no-pub` 0 issue
- `flutter test --no-pub -j 1` 全量通过（源码断言改为 `ForegroundColorSpan`/`applyProgressSpans`/`blendColor`，并断言 `progressText`、`clipBounds`、`paint.shader = `、`configureScrollingLine`、`scrollTo(` **都不存在**）
- `flutter build apk --debug` 通过
- 真机待查：当前句全程可见（搜索页/播放器页/切歌/换行都不再消失、无需点击救回）；高亮按字推进且长句滚动时颜色跟随

## 2026-09-30 - 修复悬浮窗「当前歌词整行消失、点一下才回来」

### 根因

上一轮为修「长句滚动时高亮脱离文字」把当前句改成自管滚动，滚动距离来自 `layout.getLineRight(0) - layout.getLineLeft(0)`。当前句的 TextView 是 `setHorizontallyScrolling(true)`，**这种情况下 Layout 的这两个值给的是版面/段落边界而不是字形行宽度**，于是只有 250px 的短句也被判定为「严重超宽」，`maxScrollPx()` 返回巨大值：

1. 滚动周期先停留 1.5s，所以换行后最初一秒多还看得见；
2. 停留结束后按那个巨大距离滚动 → 当前句整行滑出可视区；
3. `currentLineBlock` 的 `minHeight` 仍占位 → **那一行空着但位置还在**（截图现象）；
4. 点击歌词触发一次布局/窗口重排 → TextView 重新测量、`maxScrollPx()` 恢复正常 → `scrollX` 归零 → 文字回来；
5. 播放继续、再次换行后又走同一路径 → 又消失。

### 修复

- `maxScrollPx()` 改为**用 TextView 自己的 `paint.measureText(text)` 实测字形宽度**（与绘制同一个 Paint，随 setText/setTextSize 自动更新），并留 2dp 容差；放得下就返回 0，**永不滚动**
- 裁剪边界同样不再用 Layout 的 `getLineLeft/getLineRight`：改用实测宽度与 `startX`（放得下时按 `gravity=CENTER` 居中，需要滚动时为 0）+ `− scrollX`
- 两层始终写同一个 `scrollX`（长句滚动时高亮仍与文字贴合），短句 `scrollX` 恒为 0

### 可观测性

DEBUG 包下限频日志补全为 `len / measure / overflow / progress / rate / clipPx / scrollX`，如果还有异常，一条 logcat 就能区分是「判定超宽」「文本为空」还是「进度不对」。

### 验证

- `flutter analyze --no-pub` 0 issue
- `flutter test --no-pub -j 1` 全量通过（源码断言新增 `measureText` / `lineMetrics`，并断言**不得**再出现 `layout.getLineRight(0) - layout.getLineLeft(0)`）
- `flutter build apk --debug` 通过
- 真机待查：短句当前行全程可见不再消失；长句才滚动且高亮贴合

## 2026-09-30 - 修复悬浮窗长句「高亮与滚动文字分离」+ 内歌词换行「两行同时高亮」

### 问题 1：悬浮窗长句滚动时高亮层不跟着走

- 当前句原本用**系统 marquee** 滚动（`configureMarquee()` 里 `isSelected = true`）。现代 Android 的 marquee 是在 `onDraw` 里用 **canvas 位移**画的，`view.scrollX` 始终为 0，而那个位移**没有公开 API 可读** → 上一版「镜像 `base.scrollX`」等于没做：底色层滚走了、裁剪出的高亮层留在原处
- 修复：**当前句改由控制器自己接管横向滚动**
  - 新增 `configureScrollingLine()`：当前句两层都 `setSingleLine + setHorizontallyScrolling(true)`、`ellipsize = null`、`isSelected = false`（无系统 marquee 参与）；`nextText` / 译文行维持系统 marquee（单层不受影响）
  - 在既有 16ms 帧循环里驱动：仅在文字宽度超出可视宽度时滚动（短句 `scrollX = 0`，行为与之前完全一致）；模式为「起始停留 1.5s → 约 40dp/s 滚到末尾 → 停留 1.2s → 滚回」循环
  - **两层写入同一个偏移**（`lyricText.scrollTo` + `progressText.scrollTo`），裁剪边界继续用 `… + lineWidth × progress − scrollX` → 高亮永远贴在文字上
  - 帧循环条件扩展为「播放中且可见，且（进度在推进 或 长句需要滚动）」；暂停/隐藏时扫过与滚动一起停

### 问题 2：播放器内换行歌词两行同时高亮

- 内歌词原本用一个**横向 `ShaderMask`** 盖住整段文字；文字换成两行后，渐变仍是一维横向的「竖带」，于是两行从头到尾同时被染色
- 修复：`PlayedLyricsText` 改回**按字符的 `Text.rich` 两段染色**（已播放前缀 / 其余），span 天然按阅读顺序流动 → 第一行先填满、再第二行；数值用现成且已有单测的 `playedCharacterCount()`
- `lyrics_display` 的 `_playedProgress`(double) 换成 `_playedChars`(int)，Ticker 仍逐帧算，但**只有字符边界变化才通知**（比之前重建更少）；删除 `ShaderMask` 与 `playedLyricsGradient`

### 验证

- `flutter analyze --no-pub` 0 issue
- `flutter test --no-pub -j 1` 全量通过（新增「换行歌词按阅读顺序上色」用例；源码断言新增「当前句自管滚动」；内歌词断言回到两段 span）
- `flutter build apk --debug` 通过
- 真机待查：长句黄边与文字始终贴合、两端停留顺滑；短句不滚动；内歌词换行逐行亮起；暂停一并冻住

## 2026-09-30 - 修复悬浮歌词「没有过渡、只在整句唱完时整句变色」

### 根因：shader 被阴影层吃掉了（不是数值问题）

- Dart 侧数值已经**被测试证明是连续的**：`playedFraction` + `PlayedProgressRate` 有单测，`floating_lyrics_provider_test` 断言「同一句唱到一半时推给原生的 `highlightProgress ≈ 0.5`、`highlightRate > 0`」并通过 → 通道里不是 0/1 跳变
- 问题在原生渲染：上一版在 `0 < progress < 1` 时用 `lyricText.paint.shader = LinearGradient(...)` 染色，而**带 `setShadowLayer` 的 TextView 在硬件加速画布上只会用纯色绘制字形，shader 不生效**（Android 上「渐变 + 阴影」是已知难点，[参考](https://stackoverflow.com/questions/34489494/apply-gradient-and-shadow-simultaneously-with-different-colors-on-textview-andro)）。我们每行都设了阴影，于是：
  - 唱的过程中：shader 被忽略 → 走 `setTextColor(底色)` → **整句一直底色**
  - 唱完（progress ≥ 1）：走纯色分支 → **整句变高亮色**
  - 与用户描述的「没有过渡、只有唱完才整句变色」完全一致；也解释了为什么更早的整字 span 版本是能变色的（span 设纯色，不依赖 shader）

### 修复：改成「双层文字 + 裁剪」，彻底不依赖 shader

- 当前句改为**两层叠加**：`lyricText`（底色 + 阴影，照旧驱动 marquee）与 `progressText`（高亮色 + 同款阴影、同字号/粗细/版式），后者叠在同一个 `FrameLayout` 里完全重合
- 每帧只改 `progressText.clipBounds = Rect(0, 0, boundaryX, height)`（**不触发布局**，也不改度量），`boundaryX = compoundPaddingLeft + lineLeft + lineWidth × progress − scrollX`；并把底层的 `scrollX` 镜像给上层，超长句滚动时两层保持对齐
- `progress ≤ 0` → 上层 `GONE`；`progress ≥ 1` → `clipBounds = null`（整句高亮）；中间态 → 精确裁剪出已播放部分
- 删掉 `paint.shader` / `LinearGradient` / `clearShader` / `setSolidColor` 整套；帧循环、锚点、速率外推、门控条件保持不变（`runFrame` / `FRAME_INTERVAL_MS` / `anchorProgress` / `anchorRatePerMs`）
- 端点不再需要来回切 `setTextColor`，每帧开销只有一次 `clipBounds` + `invalidate`

### 可观测性

- DEBUG 包下每秒最多一条 `Log.d("FloatingLyrics", "progress=… rate=… clipPx=… scrollX=…")`；若真机仍不对，一条 logcat 即可区分「数值没到」还是「绘制没生效」

### 验证

- `flutter analyze --no-pub` 0 issue
- `flutter test --no-pub -j 1` 全量通过（原生源码断言改为 `progressText` / `clipBounds` / `scrollTo(base.scrollX, 0)`，并断言**不得**再出现 `paint.shader = `）
- `flutter build apk --debug` 通过
- 真机待查：唱的过程中能看到连续前移的色边（暂停冻住、切行从 0 重新开始）、超长句 marquee 两层不错位、阴影观感不变

## 2026-09-30 - 已播放高亮改为「从左往右连续扫过」（对齐网易云）

原来的实现是**按整数个字符**上色 + 200/250ms 才刷新一次，所以每个字都是瞬间整块变色。这次把「进度」变成连续值、把「渲染」换成渐变，并用逐帧动画补上两次数据之间的空档。

### 数据：整数个字符 → 连续进度

- `lib/lyrics/lyrics_progress.dart` 新增
  - `playedFraction()`：返回 0..1 的连续进度，逐字格式累加整字 + **正在唱的那个字按其自身进度取小数**（前缀校验 + 按字长比例兜底），纯 LRC 按本句→下一句时间比例
  - `PlayedProgressRate`：把连续两次采样的 Δprogress/Δt 做指数平滑，得到「每毫秒推进量」，暂停/空拍/倒退（seek、换行）时归零
- 通道契约：`highlightCharacters: int` → `highlightProgress: double` + `highlightRate: double`（200ms 一次锚点，流量不变）

### 悬浮窗：Paint 渐变 + 16ms 帧循环

- 去掉逐字 `ForegroundColorSpan`，改为对当前句画一条横向 `LinearGradient`：`已播放色 → 已播放色 → 底色 → 底色`，边界落在 `lineLeft + 行宽 × progress`，中间留约 8dp 过渡带（`PROGRESS_SOFTNESS_DP`），看起来是"扫过去"而不是"跳一格"
- `Handler(Looper.getMainLooper())` 每 16ms 按 `anchorProgress + rate × 已过时间` 外推并重画；**只在「播放中 && progress<1 && rate>0 && 窗口可见」时运行**，暂停/唱完/熄屏立即停下
- 渐变坐标按 `lineLeft + compoundPaddingLeft - scrollX` 计算，长句 marquee 滚动时色带跟着文字走
- progress ≤0 / ≥1 时清空 shader 回落纯色，避免端点残留；只改 shader + `invalidate()`，不重排、不打断 marquee

### 播放器内歌词：Ticker + ValueNotifier + ShaderMask

- `PlayedLyricsText` 改为按连续进度渲染：`0<p<1` 用 `ShaderMask(blendMode: srcIn)` + `playedLyricsGradient()`（纯函数，可单测），两端退化为单色 `Text`
- `lyrics_display` 新增 `SingleTickerProviderStateMixin` 的 `Ticker`（仅播放中且歌词可见时运行）逐帧写 `ValueNotifier<double>`，当前句通过 `ValueListenableBuilder` 订阅 → **只有当前句这一小段子树逐帧重建**，ListView 不重建、不 setState
- 暂停/未播放时走静态进度（每次 build 由 `_position` 算出），保证不播放时也是正确的一帧

### 验证

- `flutter analyze --no-pub` 0 issue
- `flutter test --no-pub -j 1` 全量通过（新增 `playedFraction`、`PlayedProgressRate`、`playedLyricsGradient`、ShaderMask 相关用例；更新原先断言"两个 TextSpan"的用例）
- `flutter build apk --debug` 通过
- 真机待查：连续扫过的观感、暂停即冻结、长句 marquee 时色带是否跟随、熄屏后台是否还在逐帧重绘

## 2026-09-30 - 修复悬浮歌词已播放高亮失效 + 播放器内歌词同款高亮

### 根因：span 被丢掉了（悬浮窗一直没有高亮）

- `setTextIfChanged()` 之前写的是 `text = SpannableString(value)`，等价于 `setText(value)`，默认走 `BufferType.NORMAL`；AOSP 在该分支会经 `TextUtils.stringOrSpannedString()` 把 `Spanned` **复制成不可变的 `SpannedString`**（[CommonsWare](https://commonsware.com/Android/Android-8.0-CC.pdf#321#126)："If the Spannable you wound up with is a SpannedString… you cannot change it"）
- 于是 `applyPlayedHighlight()` 里的 `view.text as? Spannable` 恒为 null → 直接 return，**一个 span 都没上**；而快照已被更新，之后也不会重试。Dart 侧一直是对的（测试已断言中途位置会推送 `highlightCharacters`）
- 修复：改用 `setText(SpannableString(value), TextView.BufferType.SPANNABLE)`（SPANNABLE 分支经 `mSpannableFactory.newSpannable()` 得到可变 `SpannableString`）；拿不到 `Spannable` 时打 `Log.w` 而不是静默失败
- 新增源码断言 `contains('BufferType.SPANNABLE')` 把这个回归钉死

### 共享进度模块（悬浮窗与播放器内歌词同一套逻辑）

- 新增 `lib/lyrics/lyrics_progress.dart`：
  - `playedCharacterCount()`：逐字格式（QRC/KRC）累加已唱完整字 + 正在唱的字按自身进度取小数、前缀校验、失败按字长比例兜底；纯 LRC 按「本句→下一句」时间比例扫过
  - `LyricsProgressEstimator`：把悬浮窗里的"按墙钟插值播放位置"提取出来（可注入时钟），两处共用
- 悬浮窗 provider 的 `highlightCharactersFor` 改为委托共享函数；插值改由共享 estimator 提供

### 播放器内歌词也显示已播放高亮

- `PlayedLyricsText`：当前句按「已播放前缀 = `colorScheme.primary`、剩余 = `colorScheme.onSurface`」渲染；未播放/整句播完时退化为单色 `Text`，非当前句保持原有 outline 样式
- `_PlainLyricsLine`（LRC）与 `WordByWordLine`（QRC/KRC）都改用该组件与共享的 `playedCharacters`，逐字格式获得字内小数精度（不再是整字跳变）
- `lyrics_display` 的轮询由 500ms 提到 250ms，新增 `_highlightPosition`（仅播放中用 estimator 插值）；**行切换与自动滚动仍用播放器原始位置**，不会提前跳行；只有已播放字符数变化才 `setState`，暂停时不插值

### 验证

- `flutter analyze --no-pub` 0 issue
- `flutter test --no-pub -j 1` 全量通过（新增 `test/lyrics_progress_test.dart`，新增播放器内歌词分段染色 widget 测试，更新 `_nearestAnimatedTextStyle` 以支持 RichText 当前句）
- `flutter build apk --debug` 通过
- 真机走查：悬浮窗当前句随播放逐字变色（长句滚动不被重置）、播放器内歌词页同一句分段染色

## 2026-09-30 - 悬浮歌词第二轮：横屏居中、锁定穿透、已播放高亮、透明度、双句歌词

在第一轮改版之上做 5 项调整。仍然只动 Android 与悬浮歌词相关的 Dart/设置层，Windows 桌面歌词未改。

### 1. 横屏也居中

- 窗口宽度由「按 `displayMetrics` 算像素」改成 **`MATCH_PARENT`**：旋转/尺寸变化时由 WindowManager 自己重新度量，彻底消灭「旋转后窗口还是竖屏宽度、歌词挤在左半边」
- `onConfigurationChanged` 不再算宽度，只做 `y` 回拉 + `updateViewLayout`，避免横屏后停在屏幕外

### 2. 锁定后整窗不可交互（可穿透）

- 锁定时给窗口加 **`FLAG_NOT_TOUCHABLE`**（解锁时移除，走 `updateViewLayout`），触摸完全不进悬浮窗，直接落到下面的 App/桌面
- 锁定后只保留左下角一个小锁图标（纯指示，点不动）
- 解锁路径：新增 App 设置页「锁定位置」开关；**关闭悬浮歌词时自动清锁**（设置页开关与通知卡片按钮都走 `setEnabled(false)`），所以关掉再打开必定可交互

### 3. 底色 + 已播放进度高亮

- 底色（未播放部分）默认改为**纯白**，App 设置页的「歌词颜色」改名「歌词底色」；「高亮颜色」改名「已播放高亮色」
- 悬浮窗内 5 个圆点改为调整**高亮色**（选中打 ✓ 逻辑同步）
- Dart 计算 `highlightCharacters`：QRC/KRC 有逐字时间时累加已唱完的整字 + 当前字按自身进度取小数（并校验前缀，失败时按字长比例映射）；LRC 无逐字时间时按「本句 → 下一句」时间比例线性扫过
- 原生用**单个 `ForegroundColorSpan`** 覆盖已播放前缀，底色仍是 `textColor`；只改 span + `invalidate()`，不 `setText`，颜色不影响度量所以 **marquee 不会重启**
- 播放位置进 state 只有每秒一次，因此新增 200ms 的插值驱动（仅在 enabled && isPlaying 时运行）：高亮用插值位置，**换行仍用原始 state 位置**，歌词只会最多晚 1 秒、绝不提前跳行

### 4. 按钮透明度

- 未锁定：全部按钮（含颜色圆点、`T±`）`alpha = 0.5`
- 锁定：仅剩的锁头 `alpha = 0.2`

### 5. 一次显示两句歌词

- 载荷新增 `nextText`（下一句有文字的行，最后一句为空则隐藏该行）；原生列布局为「当前句（粗体、带高亮）→ 下一句（常规字重、0.92×字号、底色 70% 不透明）→ 译文（0.62×字号、底色 55% 不透明）→ 控制行 → 设置面板」
- `payloadForPosition` 改为索引扫描，复用既有「跳过空行/纯译文行」的可见性判断

### 性能与稳定性

- 原生 `applyData` 全面幂等化（文字/字号/颜色/阴影/图标/可见性/圆点各自有应用快照），每秒 5 次的进度更新只改 span，不会再触发 `setTextSize`/`setImageResource`/`setText` 引起重排与 marquee 重启
- 悬浮窗内刚改过的字号/高亮色有 1.5 秒「本地优先」窗口，避免进度更新携带旧值把用户刚改的样式顶回去
- `styleChanged` 事件字段由 `textColor` 改为 `highlightColor`（圆点现在改的是高亮色）

### 验证

- `flutter analyze --no-pub` 0 issue
- `flutter test --no-pub -j 1` 全量通过（新增逐字/整行高亮、双句选句、进度更新、sweep 插值、关灯清锁等用例；更新了因「同一句歌词会随进度多次推送」而变化的旧断言）
- `flutter build apk --debug` 通过
- 仍需真机走查：先开悬浮歌词再旋转到横屏看居中、锁定后点击穿透、圆点/T± 生效、两句歌词与译文、按钮透明度

## 2026-09-30 - 安卓悬浮歌词改版（对齐网易云桌面歌词）

把过于简略的安卓系统悬浮歌词重做成参考图形态：全屏宽度、只能上下拖动、点击切换按钮、锁头锁定、内置配色/字号面板，并在播放器通知卡片上新增「歌词」开关作为锁定后的关闭途径。仅动 Android 与悬浮歌词相关的 Dart 层，Windows 桌面歌词与其缩放、配色渲染完全未改。

### 原生悬浮窗（FloatingLyricsController.kt 重写）

- 窗口改为**全屏宽度 + 高度自适应**，`x` 恒为 0；去掉 `//` 缩放把手与 `windowResized` 上报（Dart 侧监听保留，Windows 仍在用）
- 拖动改为**仅竖向**：`ACTION_MOVE` 只写 `params.y`，并按 `0..(屏幕高-内容高)` 回拉，`addOnLayoutChangeListener` 在内容变高（切按钮/改字号）后再次回拉
- 新增 `FLAG_NOT_TOUCH_MODAL`，悬浮歌词之外的区域不再被覆盖层吞掉触摸
- 点击切换：位移小于 `scaledTouchSlop` 判定为点击 → 隐藏/显示控制行（只留歌词），再点恢复
- 控制行：锁头 / 上一首 / 播放暂停 / 下一首 / 设置 / 关闭（右上角），新增 10 个矢量图标资源（`fl_ic_*`、`audio_service_lyrics_on/off`）
- 锁头：锁定后不可拖动、按钮无法唤出、关闭按钮不可达，只保留一个小锁图标用于解锁
- 设置面板：5 个颜色圆点（选中显示 ✓）+ `T+` / `T-`（步长 2，clamp 14–48），改动立即生效并上报
- 新通道事件：`styleChanged`（颜色按无符号 32 位回传）、`controlRequested`、`positionChanged`（仅拖动结束时发一次）
- 新载荷字段：`isPlaying`、`hasSong`（无歌曲时隐藏三枚传输键）、`positionY`（仅在创建窗口时应用，避免换行时顶掉用户刚拖的位置）
- `MainActivity.onConfigurationChanged` 转交控制器：旋转后重算宽度、`x=0`、回拉 y，Activity 不重建

### Dart 层

- `FloatingLyricsSettings` 新增 `positionY`（像素，旧数据回落 160）；`FloatingLyricsPayload` 新增 `isPlaying` / `hasSong` 与 `copyWith`
- `FloatingLyricsService` 新增 `styleChangedStream` / `controlRequestedStream` / `positionChangedStream`
- `FloatingLyricsSyncController`：新增 isPlaying 触发同步（暂停时图标也能立刻更新）；样式/传输/位置事件分别落到 `setTextColor`+`setFontSize`、`togglePlay`/`skipToPrevious`/`skipToNext`、`setPositionY`；`positionY` 刻意不进原生签名，拖动落盘不再产生多余的 `update` 往返
- `FloatingLyricsNotifier.toggleEnabled()`：通知栏开关共用的开关逻辑（关闭时 hide，开启时先要悬浮窗权限再启用）

### 播放器通知卡片

- 新增自定义 action `toggle_floating_lyrics`，与既有「喜欢」按钮同机制（`MediaControl.custom` + `customAction`）；图标/文案随开关变化（`歌词` ↔ `关闭歌词`，`audio_service_lyrics_off/on`）
- `PlaybackNotificationActions` / `update()` / `buildPlaybackNotificationState()` 新增 `isFloatingLyricsEnabled`；`playerProvider` 接线并监听开关变化刷新通知
- 不新增独立通知、不申请通知权限（媒体通知本身豁免 Android 13+ 通知权限）

### 刻意行为变更

- 移除 `//` 缩放把手，宽度不再可调（改为全屏宽、高度随字号自适应）
- Android 不再发送 `windowResized`

### 验证

- `flutter analyze --no-pub` 0 issue
- `flutter test --no-pub -j 1` 全量通过（新增/更新 `floating_lyrics_service_test`、`floating_lyrics_provider_test`、`playback_notification_service_test`、`player_provider_test`）
- `flutter build apk --debug` 通过（Kotlin 编译与资源链接校验）
- 原生覆盖层观感与手势需真机走查（本机无 adb）：全宽只能上下拖 / 横竖屏 / 点击切换按钮 / 锁定与解锁 / 齿轮面板 / 通知卡片开关

## 2026-09-08 - 后台播放静音诊断埋点、音量守护与卡滞修复合并

针对安卓后台播放"静音但进度仍走、需切歌恢复"的问题，先把已实现的后台卡滞自动恢复修复合并进 main，再补充诊断埋点和音量守护，供真机复现定位剩余故障。

### 合并 fix-android-background-playback-stall 分支

- 将 `fix-android-background-playback-stall`（ae66dde）合并进 main，包含：
  - Android 在线播放健康监测器：5 秒轮询，position/processing 卡滞 12 秒判定，自动重新取 URL、重载歌曲、seek 回原位置、恢复音量并继续播放；带 30 秒冷却、每首歌最多 2 次自动恢复、启动宽限期与日志事件
  - Android 均衡器防削波与响度补偿（负数安全增益 + LoudnessEnhancer + 代际守卫）
  - 通知栏 canonical 状态恢复（后台 transient 事件后还原 playing 状态与时长）、歌词居中/自动滚动修复
- 冲突解决：7 个冲突文件，5 个纯版本号取 main 侧 1.2.4，`settings_page_test.dart` 取 main 重构版，`player_screen.dart` 取 main 的 AnimatedSwitcher 结构（分支 `LyricsDisplay.isVisible` 为可选参数自动并入）
- 清理误提交的 `android/build/reports/problems/problems-report.html` 并补充 `.gitignore`

### 新增诊断埋点（只记录不干预）

- 音量埋点：每次 `setVolume` 记录 `player/volume_set`（含音量值），失败记录为 `error/player.setVolume`
- 播放状态埋点：playing / processingState 变化时记录 `player/player_state`（去重，仅在跳变时记录）
- 焦点事件埋点：新增 `AudioFocusDiagnosticsObserver`，订阅 `interruptionEventStream`（begin/end + type）与 `becomingNoisyEventStream`，记录 `audio_focus/interruption_*` 与 `audio_focus/becoming_noisy`；`AudioServicePlayerController.initialize` 中启动、dispose 中取消
- 播放器控制器接口新增 `volume` getter（JustAudio / AudioService / MediaKitWindows 及各测试 fake 同步更新）

### 音量守护

- 在健康监测 tick 中新增 `_ensurePlaybackVolume()`：播放中且非切歌/切音质/恢复中时，若播放器音量低于 1.0 且已过淡入淡出窗口，则恢复为满音量，并记录 `player/volume_watchdog_restore`（含泄漏时的音量值）
- 与淡入淡出协调：淡入淡出开启时按 `_lastVolumeWriteAt` 静默窗口判断，避免顶掉进行中的淡入淡出

### 版本与验证

- 版本 1.2.5+6（pubspec / app_constants / mconnect.iss / Runner.rc / settings 断言一致，generated_config.cmake 由构建重写）
- `flutter test --no-pub -j 1` 全量 291/291 通过（含新增诊断埋点、焦点观察器、音量守护测试）
- `flutter analyze --no-pub --no-fatal-infos` 0 error / 0 warning
- 待真机复现后按诊断日志判读故障模式，再实施针对性修复

## 2026-06-22 - Bump release to v1.2.4 and package

Changed the current app-facing release version from `v1.2.3` to `v1.2.4`
because `v1.2.3` had already been used for an earlier release.

### Changes

- Updated app release versions:
  - `pubspec.yaml`: `1.2.4+5`
  - `AppConstants.appVersion`: `v1.2.4`
  - Android `flutter.versionName`: `1.2.4`
  - Android `flutter.versionCode`: `5`
  - Inno Setup `MyAppVersion`: `1.2.4`
  - Windows runner fallback `VERSION_AS_STRING`: `1.2.4`
  - settings page test expectation: `v1.2.4`
- Kept historical changelog entries for previous `v1.2.3` releases unchanged.
- Removed the obsolete temporary `v1.2.3` package generated during this
  packaging pass so `flutter analyze` no longer scans a duplicated source
  snapshot.

### Verification

- `flutter test --no-pub test/settings_page_test.dart --reporter expanded -j 1`
  passed: 12/12.
- `flutter test --no-pub --reporter compact -j 1` passed: 251/251.
- `flutter analyze --no-pub --no-fatal-infos` exited 0 with the existing
  416 info-level lints.
- Android `assembleRelease` passed via Gradle with the Aliyun mirror init
  script and the Flutter-configured JDK 17.
- Android APK metadata was checked with `aapt dump badging`:
  `versionName='1.2.4'` and `versionCode='5'`.
- The sqlite3 Android native asset cache reused SHA256-verified package
  binaries after the earlier GitHub download timeout.
- `flutter build windows --release --no-pub --build-name=1.2.4
  --build-number=5` passed.
- Windows EXE version info reports `FileVersion` / `ProductVersion` as
  `1.2.4+5`.
- Inno Setup compile passed and produced `Mconnect-Setup-1.2.4.exe`.

### Artifacts

- Android APK:
  `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\app\outputs\flutter-apk\app-release.apk`
  - Size: 82,285,007 bytes / 78.47 MB
  - Last write time: 2026-06-22 21:38:35
  - SHA256:
    `DAC62560027F5B03C3AF048687DDB24AE9F072DF8BC0942A279083DB61E6E4FB`
- Windows portable zip:
  `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\windows\x64\Mconnect-windows-x64.zip`
  - Size: 21,950,947 bytes / 20.93 MB
  - Last write time: 2026-06-22 21:39:42
  - SHA256:
    `AB22763E08D67B45C4C761CDA1272FC8ACC0D7471A32D475676AE2E3C8F2718F`
- Windows installer:
  `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\windows\x64\Mconnect-Setup-1.2.4.exe`
  - Size: 18,032,436 bytes / 17.20 MB
  - Last write time: 2026-06-22 21:40:02
  - SHA256:
    `9526838C141EF4A320C80330F75E665579E7EF5970FCD2779A12B2E29FB3DAFC`
- Source snapshot:
  `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\package\Mconnect-1.2.4-20260622-214053\source\Mconnect-source-current.zip`
  - Size: 91,452,428 bytes / 87.22 MB
  - Last write time: 2026-06-22 21:41:09
  - SHA256:
    `E5B44777069E5E17AE94E550C816A91007F57BDE90546AE283E5233220B8B7B5`
- All-in-one delivery zip:
  `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\package\Mconnect-1.2.4-all-20260622-214053.zip`
  - Size: 262,950,777 bytes / 250.77 MB
  - Last write time: 2026-06-22 21:41:22
  - SHA256:
    `0D8904E90C079DAE2A503DD40FD8B76E493FA9C4740E31C99BDA595641897F63`

## 2026-06-22 - Package current workspace artifacts

Packaged the current workspace state after the download/search/player/settings
UX fixes.

### Verification

- `flutter test --no-pub --reporter compact -j 1` passed: 251/251.
- `flutter analyze --no-pub --no-fatal-infos` exited 0 with the existing
  416 info-level lints and no errors or warnings.
- Android release packaging initially hit Gradle dependency TLS failures against
  Google Maven. A temporary ignored Gradle init script under `.build/` pointed
  the build to Aliyun Maven mirrors for this packaging run.
- Direct Gradle release packaging used the Flutter-configured JDK 17 at
  `C:\Users\PC\flutter\jdk17\jdk-17.0.12+7`.
- The `sqlite3` hook could not download release assets via Dart/PowerShell TLS,
  so the required Android sqlite3 binaries were downloaded with `curl.exe`,
  verified by SHA256 against the package's published hashes, and used through a
  temporary `pubspec.yaml` hook override. That temporary override was removed
  after the APK was built.

### Artifacts

- Android APK:
  `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\app\outputs\flutter-apk\app-release.apk`
  - Size: 82,285,007 bytes / 78.47 MB
  - Last write time: 2026-06-22 14:30:05
  - SHA256:
    `CA800B0490414B821BB0C296ABD006E17ECCBFE2C2D62406E335575DBE9C489C`
- Windows portable zip:
  `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\windows\x64\Mconnect-windows-x64.zip`
  - Size: 21,950,852 bytes / 20.93 MB
  - Last write time: 2026-06-22 14:33:01
  - SHA256:
    `312D98D74750A2C3CDBB3A9F54EB01284A1564E7E5093A15C54C79CA98598CBF`
- Windows installer:
  `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\windows\x64\Mconnect-Setup-1.2.2.exe`
  - Size: 18,032,835 bytes / 17.20 MB
  - Last write time: 2026-06-22 14:33:08
  - SHA256:
    `B4C0B23DA7BF8FA895BE4069742D3FC218EF62DCCD11B5F759AF011B1E2FE0D8`
- A source snapshot and all-in-one delivery zip were generated under
  `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\package\`.

## 2026-06-20 - Improve download, search, player, and settings UX

Fixed several experience issues without changing provider names, persisted
settings keys, platform login logic, or audio effect storage.

### Changes

- Fixed playback notification compact actions so Android receives at most three
  compact action indices.
- Added JSON serialization for download tasks and a Hive-backed download task
  store. Startup recovery keeps completed downloads only when the file still
  exists, preserves failed tasks, and restores unfinished tasks as paused.
- Persisted download task changes after add, progress/completion, failure,
  pause/resume, cancellation, and removal.
- Added a confirmation dialog before deleting a completed download, with copy
  that states the local file will be deleted. Failed task removal stays
  lightweight and does not ask for file deletion confirmation.
- Changed search input to debounce typing for 300 ms, clear results
  immediately when the field is cleared, and distinguish initial prompt from
  no-results empty state.
- Changed the player lyrics mode to use an independent taller lyrics panel
  while keeping artwork mode square.
- Split Settings into a hub page plus account, appearance, floating lyrics,
  audio, and diagnostics/about pages. Existing settings providers, Hive keys,
  and business behavior were kept in place.

### Tests

- Added/updated coverage for download task JSON round-trip, persisted download
  restore normalization, completed download delete confirmation, search
  debounce/clear/no-results states, player lyrics panel sizing, and settings
  subpage entry/control visibility.

### Verification

- `flutter test --no-pub --reporter compact
  test/playback_notification_service_test.dart test/download_provider_test.dart
  test/download_page_test.dart test/search_screen_test.dart test/widget_test.dart
  test/settings_page_test.dart` passed: 45/45.
- `flutter test --no-pub --reporter compact -j 1` passed: 251/251.
- `flutter analyze --no-pub` reported only the existing 416 info-level lints,
  with no errors or warnings. `flutter analyze --no-pub --no-fatal-infos`
  exited 0.

## 2026-06-07 - Fix lyrics centering and package v1.2.3

Fixed the full lyrics panel so the active lyric is centered when the lyrics
view is opened, then bumped the release version to `v1.2.3` and produced the
Android and Windows release artifacts.

### Root Cause / Evidence

- `AnimatedCrossFade` kept the lyrics widget alive while it was hidden. During
  that hidden period, playback position changes could update the active lyric
  and schedule scrolling before the user actually opened the lyrics view.
- The old centering path relied on `Scrollable.ensureVisible(alignment: 0.5)`.
  With lazily built lyrics rows and variable-height translated rows, the target
  row could be missing its render context or the whole row could be centered
  while the main lyric text still looked offset.
- The newly added RED test failed before the fix because `LyricsDisplay` had no
  `isVisible` parameter and the settings page still displayed `v1.2.2`.

### Changes

- Added `LyricsDisplay.isVisible` and passed `LyricsDisplay(isVisible:
  _showLyrics)` from `PlayerScreen`, so hidden lyrics no longer scroll to a
  stale hidden-panel position.
- When lyrics become visible, the widget schedules a forced next-frame recenter
  of the current lyric.
- Replaced the `ensureVisible` centering path with a real `RenderBox` center
  calculation against the `ListView` viewport.
- Added primary text anchors for plain and word-by-word lyric rows, so translated
  or variable-height rows center the main current lyric text rather than the
  entire row block.
- Added a two-stage fallback for lazily built off-screen lines: first scroll near
  the estimated current line, then recenter using the real render box once it is
  built.
- Kept existing behavior for auto-follow, user drag pause, song/document reset,
  empty lyric skipping, and first-visible-line highlighting.
- Updated app release versions:
  - `pubspec.yaml`: `1.2.3+4`
  - `AppConstants.appVersion`: `v1.2.3`
  - Inno Setup `MyAppVersion`: `1.2.3`
  - Windows runner fallback `VERSION_AS_STRING`: `1.2.3`
  - settings page test expectation: `v1.2.3`
- Did not change dependency versions, protocol/cookie versions, CMake versions,
  or the Windows manifest schema identity version.
- Preserved the existing Android background playback, notification, lyrics
  auto-scroll, Android EQ safety, and Android EQ loudness compensation changes.

### Tests

- Added `test/lyrics_display_test.dart` coverage for:
  - opening lyrics after hidden playback progress changes centers the current
    lyric text in the viewport;
  - translated / variable-height current lyric rows use real render geometry
    instead of fixed row-height assumptions.
- Updated `test/settings_page_test.dart` to expect `v1.2.3`.

### Verification

- RED check: `flutter test --no-pub test\lyrics_display_test.dart
  test\settings_page_test.dart --reporter expanded -j 1` failed before the
  implementation because `LyricsDisplay` had no `isVisible` parameter and the
  version text still expected the new value.
- `flutter test --no-pub test\lyrics_display_test.dart
  test\settings_page_test.dart --reporter expanded -j 1` passed: 18/18.
- `flutter test --no-pub test\lyrics_line_test.dart --reporter expanded -j 1`
  passed: 5/5.
- `flutter test --no-pub test\lyrics_display_test.dart
  test\player_provider_test.dart test\playback_notification_service_test.dart
  test\player_audio_controller_test.dart
  test\media_kit_windows_audio_controller_test.dart
  test\audio_enhancement_settings_test.dart test\settings_page_test.dart
  --reporter expanded -j 1` passed: 89/89.
- `flutter analyze --no-pub --no-fatal-infos` exited 0 with the existing
  info-level lint baseline.
- `flutter build apk --release --no-pub` passed.
- `flutter build windows --release --no-pub` passed.
- `& 'C:\Users\PC\AppData\Local\Programs\Inno Setup 6\ISCC.exe'
  installer\mconnect.iss` passed.

### Artifacts

- Android APK:
  `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\app\outputs\flutter-apk\app-release.apk`
  - Size: 81,621,599 bytes / 77.84 MB
  - Last write time: 2026-06-07 20:05:46
  - SHA256:
    `111BC405C3053212A43E87FE3F531D94DBA28EC4AEF25C92412BAA4CCC4C6B6F`
- Windows release directory:
  `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\windows\x64\runner\Release\`
  - Main executable:
    `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\windows\x64\runner\Release\mconnect.exe`
  - Last write time: 2026-06-07 20:06:55
- Windows installer:
  `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\windows\x64\Mconnect-Setup-1.2.3.exe`
  - Size: 18,029,943 bytes / 17.19 MB
  - Last write time: 2026-06-07 20:07:15
  - SHA256:
    `40130CD33C95C3A0C3945C2700469C280A4D7B7611C019E284CF10495714979E`

### Manual Acceptance

- On Android and Windows, start playback, wait until a later lyric line is
  active, then open the lyrics view. The active main lyric text should appear
  near the vertical center of the lyrics viewport.
- Repeat with translated lyrics and longer wrapping lyric lines; the current
  main lyric should still visually center.
- Drag the lyrics manually and confirm auto-follow pauses briefly, then resumes.
- Confirm Settings shows `v1.2.3`.

## 2026-06-07 - Add Android EQ loudness compensation

Improved Android equalizer loudness after the clipping-safe EQ change. Android
still never sends positive band gain to the platform equalizer, but positive EQ
curves now get capped `AndroidLoudnessEnhancer` compensation so enabled EQ does
not sound as obviously quieter.

### Root Cause / Evidence

- The previous Android EQ clipping fix correctly converted positive curves into
  relative non-positive band gains. Example: `[6, 4, 1, 0, 0]` became
  `[0, -2, -5, -6, -6]`.
- That safety headroom prevents clipping, but it also reduces perceived
  loudness because the whole curve is shifted downward.
- Windows already keeps its separate `media_kit` EQ path and mpv headroom
  compensation; this change only applies to Android `just_audio` effects.
- `just_audio 0.9.46` supports `AndroidLoudnessEnhancer` with target gain in
  decibels, so Android can recover some perceived loudness without restoring
  positive Equalizer band gains.

### Changes

- Updated `lib/features/player/data/player_audio_controller.dart` so Android
  `JustAudioController` attaches both `AndroidLoudnessEnhancer` and
  `AndroidEqualizer` to the `AudioPipeline`.
- Extended the Android EQ plan to return safe EQ band gains plus loudness
  compensation. The loudness target equals the removed positive headroom, capped
  at `+6 dB`.
- Positive presets keep safe relative curves and enable compensation. Example:
  `[6, 4, 1, 0, 0]` still sends `[0, -2, -5, -6, -6]` to EQ, then applies
  `+6 dB` loudness compensation.
- Flat, disabled, negative-only, and non-attenuating-device plans disable
  LoudnessEnhancer; extreme custom boosts are capped instead of amplified
  indefinitely.
- Apply order now disables or zeros LoudnessEnhancer first, writes all safe EQ
  bands, enables EQ, then sets and enables LoudnessEnhancer.
- LoudnessEnhancer failures are caught separately, so the fallback remains the
  previous safe-EQ behavior and never sends positive EQ band gains.
- Added generation guards so a superseded async EQ apply cannot keep clearing
  loudness or applying stale EQ after a newer setting wins.
- Kept user-saved EQ settings, EQ UI slider ranges, PlayerNotifier settings
  propagation, Windows EQ logic, lyrics fixes, and Android background playback
  fixes unchanged.

### Tests

- Updated `test/player_audio_controller_test.dart` coverage for:
  - bass, vocal, and rock positive presets generating safe EQ curves plus
    loudness compensation;
  - subtle `+1 dB` boosts compensating without positive EQ band gain;
  - extreme `+12 dB` boosts capping loudness compensation at `+6 dB`;
  - negative-only and flat curves leaving LoudnessEnhancer disabled;
  - unsupported gain ranges being clamped before safety and compensation;
  - extra Android device bands still participating in safe headroom;
  - non-attenuating devices disabling both EQ and loudness;
  - safe apply order around LoudnessEnhancer and Equalizer;
  - superseded EQ apply operations not continuing stale loudness clearing;
  - LoudnessEnhancer failures leaving safe EQ applied.

### Verification

- RED check: `flutter test --no-pub test\player_audio_controller_test.dart
  --reporter expanded -j 1` failed before the implementation because
  `androidEqualizerPlanForTest` had no loudness fields and
  `applyAndroidEqualizerPlanForTest` had no loudness callbacks.
- RED check: the same command failed after adding the superseded-apply test
  because `applyAndroidEqualizerPlanForTest` had no `shouldContinue` guard.
- `flutter test --no-pub test\player_audio_controller_test.dart --reporter
  expanded -j 1` passed: 13/13.
- `flutter test --no-pub test\player_audio_controller_test.dart
  test\player_provider_test.dart test\media_kit_windows_audio_controller_test.dart
  test\audio_enhancement_settings_test.dart --reporter expanded -j 1` passed:
  64/64.
- `flutter analyze --no-pub --no-fatal-infos` exited 0 with the existing
  info-level lint baseline.
- `flutter build apk --release --no-pub` passed.

### Android Manual Acceptance

- Still needs real-device listening verification:
  - play a loud track, enable EQ, and switch bass boost / vocal / rock /
    custom; it should remain free of pop or clipping while sounding closer to
    EQ-off loudness;
  - drag a band slightly above 0 dB and confirm Android EQ still has no harsh
    clipping;
  - test an extreme custom positive curve and confirm any compression is
    controlled rather than turning into clipping;
  - switch EQ off and confirm volume and tone return to normal.

### Artifact

- Android APK:
  `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\app\outputs\flutter-apk\app-release.apk`
  - Size: 81,621,599 bytes / 77.84 MB
  - Last write time: 2026-06-07 15:51:34
  - SHA256:
    `2195F4650E81823852CAAB9396C4E41F9ACC6A109E85E7EBCD25B8CD2FD4B684`

## 2026-06-07 - Fix lyrics auto-scroll and Android transition pause

Fixed two playback-facing regressions: full-screen lyrics could stop following
the active line, and Android background playback could briefly become paused
with a `0:00` duration while a new song was starting.

### Root Cause / Evidence

- `LyricsDisplay` treated programmatic list scrolling as user scrolling because
  it listened to every `UserScrollNotification`. The auto-scroll lock could
  therefore be refreshed by the widget's own `Scrollable.ensureVisible` call.
- The full lyrics view selected the last timestamp before the current position
  even when that line had no visible text, and returned no active line before
  the first timestamp.
- During Android song transitions, `stop()` / `setUrl()` / loading events from
  the platform player can emit transient `playing=false` and null or zero
  duration values. `PlayerNotifier` and the notification handler accepted those
  transient values as canonical state, so the UI/notification could show paused
  playback at `0:00`.

### Changes

- Updated `lib/features/player/presentation/widgets/lyrics_display.dart` so
  only real drag updates pause auto-follow, programmatic scrolling keeps
  following, song or lyrics document changes clear the manual-scroll lock, and
  the active line is the nearest visible lyric before the current position with
  a first-visible-line fallback.
- Updated `lib/features/player/presentation/providers/player_provider.dart` so
  Android transitions initialize duration from song metadata, preserve the
  app's play intent through transient stopped/loading events, and ignore
  transient null/zero duration while a valid duration is already known.
- Updated `lib/features/player/data/playback_notification_service.dart` so app
  canonical playback updates can restore the notification's playing state and
  media item duration after transient bound-controller events.
- Kept the existing Android playback health monitor, Android EQ safety
  conversion, Windows EQ headroom logic, playlist behavior, and EQ UI/settings
  unchanged.

### Tests

- Added `test/lyrics_display_test.dart` coverage for:
  - continuous auto-follow after programmatic scrolls;
  - first visible line highlighting before the first timestamp;
  - empty lyric lines not becoming the current visible line;
  - manual drag pausing auto-follow and then recovering;
  - song changes resetting the manual-scroll lock.
- Added `test/player_provider_test.dart` coverage for:
  - Android transition `playing=false` events not clearing the intended playing
    state;
  - Android transition null/zero duration events not replacing song metadata;
  - explicit pause still clearing the playing state.
- Added `test/playback_notification_service_test.dart` coverage for:
  - app canonical playback updates restoring notification playing state,
    position, and duration while an audio controller is bound.

### Verification

- RED check: `flutter test --no-pub test\lyrics_display_test.dart --reporter
  expanded -j 1` failed before the implementation on first-line highlighting,
  empty-line selection, and song-change scroll-lock reset.
- RED check: `flutter test --no-pub test\player_provider_test.dart
  test\playback_notification_service_test.dart --reporter expanded -j 1`
  failed before the implementation because Android transition state accepted
  transient `playing=false`, transition duration stayed at `0:00`, and media
  item duration ignored the app-level override.
- `flutter test --no-pub test\lyrics_display_test.dart --reporter expanded -j
  1` passed: 6/6.
- `flutter test --no-pub test\player_provider_test.dart
  test\playback_notification_service_test.dart --reporter expanded -j 1`
  passed: 48/48.
- `flutter test --no-pub test\lyrics_display_test.dart
  test\player_provider_test.dart test\playback_notification_service_test.dart
  test\player_audio_controller_test.dart
  test\media_kit_windows_audio_controller_test.dart
  test\audio_enhancement_settings_test.dart --reporter expanded -j 1` passed:
  73/73.
- `flutter analyze --no-pub --no-fatal-infos` exited 0 with the existing
  info-level lint baseline.
- `flutter build apk --release --no-pub` passed.

### Android Manual Acceptance

- Still needs real-device verification:
  - play a song with lyrics, seek forward/backward, manually drag lyrics, and
    confirm auto-follow resumes after a short delay;
  - switch to the next online song while the app is backgrounded and confirm
    playback does not pause or show `0:00`;
  - use notification next/previous controls during background playback and
    confirm the notification remains in the expected playing state.

### Artifact

- Android APK:
  `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\app\outputs\flutter-apk\app-release.apk`
  - Size: 81,621,599 bytes / 77.84 MB
  - Last write time: 2026-06-07 15:16:06
  - SHA256:
    `FF04C27D99590E835A3CB2B191ACC126BBD2603E2CB47CFEBE69EA75035AC3E1`

## 2026-06-07 - Fix Android equalizer clipping pop

Fixed Android equalizer output so positive EQ presets no longer push the
underlying Android audio effect above 0 dB.

### Root Cause / Evidence

- Windows EQ already builds an mpv filter with
  `volume=-最大正增益 dB`, so positive EQ curves keep headroom.
- Android EQ passed the user's positive band gains directly to
  `just_audio`'s `AndroidEqualizer`. A preset such as `[6, 4, 1, 0, 0]`
  could therefore raise the output and clip on loud tracks.
- The old Android path also enabled the equalizer before setting the new band
  gains, which could briefly apply stale positive gains.

### Changes

- Added Android-only safe EQ planning in
  `lib/features/player/data/player_audio_controller.dart`.
- Android now clamps requested gains to the device's
  `minDecibels/maxDecibels`, subtracts the curve's maximum positive gain, and
  sends only non-positive relative gains to the platform effect.
  Example: `[6, 4, 1, 0, 0]` becomes `[0, -2, -5, -6, -6]`.
- Flat or disabled EQ now directly calls `setEnabled(false)`, so a 0 dB EQ
  does not remain in the audio chain.
- Non-flat EQ writes every device band first, including extra Android bands
  beyond the app's five saved sliders, then enables the Android effect.
- Cached Android EQ parameters after the platform effect becomes available and
  guarded delayed applications with a generation counter so an older preset
  cannot overwrite a newer one.
- Kept user-saved EQ settings, UI slider ranges, PlayerNotifier settings
  propagation, and Windows `media_kit` EQ logic unchanged.

### Tests

- Added `test/player_audio_controller_test.dart` covering:
  - positive preset curves are shifted down so max band gain is `0 dB`;
  - subtle `+1 dB` boosts never send positive platform gain;
  - negative-only curves are not lifted and flat curves disable EQ;
  - unsupported values are clamped before safe headroom is applied;
  - extra Android device bands participate as `0 dB` input;
  - devices that cannot attenuate fall back to disabled flat output;
  - safe band gains are written before Android EQ is enabled.

### Verification

- RED check: `flutter test --no-pub test\player_audio_controller_test.dart
  --reporter expanded -j 1` failed before the implementation because
  `JustAudioController.androidEqualizerPlanForTest` did not exist.
- RED check: the same test command failed after adding call-order tests because
  `JustAudioController.applyAndroidEqualizerPlanForTest` did not exist.
- `flutter test --no-pub test\player_audio_controller_test.dart --reporter
  expanded -j 1` passed: 9/9.
- `flutter test --no-pub test\player_audio_controller_test.dart
  test\player_provider_test.dart test\media_kit_windows_audio_controller_test.dart
  test\audio_enhancement_settings_test.dart --reporter expanded -j 1` passed:
  57/57.
- `flutter analyze --no-pub --no-fatal-infos` exited 0 with the existing
  info-level lint baseline.
- `flutter build apk --release --no-pub` passed.

### Android Manual Acceptance

- Still needs real-device listening verification:
  - play a loud track, enable EQ, switch bass boost / vocal / rock / custom,
    and drag any band slightly above 0 dB; there should be no pop or clipping;
  - flat preset should sound close to disabled EQ;
  - disabling EQ should restore normal volume and tone.

### Artifact

- Android APK:
  `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\app\outputs\flutter-apk\app-release.apk`
  - Size: 81,605,215 bytes / 77.82 MB
  - Last write time: 2026-06-07 14:29:15
  - SHA256:
    `15175305B2E4C45D4750942C9D29E274BC2B4F23724D1A81DB730CF559421DC5`

## 2026-06-07 - Release APK packaging

Built a fresh Android release APK for the current workspace state.

### Verification

- `flutter build apk --release --no-pub` passed.

### Artifact

- Android APK:
  `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\app\outputs\flutter-apk\app-release.apk`
  - Size: 81,588,831 bytes / 77.81 MB
  - Last write time: 2026-06-07 13:42:34
  - SHA256:
    `EF512BB23DFAB1593236366B15CE27F964FCD3C2DD0590A767278EA4134138DA`

## 2026-06-07 - Fix Android background online playback stall recovery

Fixed an Android background playback issue where online songs could become
silent until the user changed tracks from the notification and then returned to
the original song.

### Root Cause / Evidence

- The expanded media notification added a favorite action, but the playback
  state also exposed all four controls as Android compact actions. The current
  `audio_service` version asserts that compact actions must contain at most
  three indices, and `test\playback_notification_service_test.dart` failed
  before the fix with that assertion.
- Android online playback had no recovery path for a stream that stayed marked
  as playing but stopped advancing or remained in a loading/buffering/idle
  state. The reported manual workaround, next track then back, effectively
  reloaded the URL and player source.

### Changes

- Kept the favorite button in the expanded notification while limiting Android
  compact controls to previous / play-pause / next.
- Added an Android-only online playback health monitor in `PlayerNotifier`.
  When a current online song is still marked playing but remains stalled beyond
  the threshold, it refreshes the current URL, reloads the same song, seeks back
  to the previous position, restores volume to `1.0`, and resumes playback.
- Added false-positive guards: local songs are excluded, user actions and
  transitions reset the health window, short buffering and near-end playback are
  ignored, recovery is cooldown-limited, and automatic recovery stops after two
  attempts for the same continuous playback request.
- Added diagnostics for recovery start, success, failure, and recovery-limit
  events.

### Verification

- RED check: `flutter test --no-pub test\playback_notification_service_test.dart
  --reporter expanded -j 1` failed before the compact-index fix because
  `androidCompactActionIndices.length <= 3` was violated.
- RED check: `flutter test --no-pub test\player_provider_test.dart --reporter
  expanded -j 1` failed after adding the playback-health tests because
  `PlayerNotifier` did not yet expose the health-check configuration or test
  hook.
- `flutter test --no-pub test\playback_notification_service_test.dart
  --reporter expanded -j 1` passed: 6/6.
- `flutter test --no-pub test\player_provider_test.dart --reporter expanded -j
  1` passed: 39/39.
- `flutter test --no-pub test\player_provider_test.dart
  test\playback_notification_service_test.dart
  test\playback_keep_alive_service_test.dart --reporter expanded -j 1` passed:
  50/50.
- `flutter analyze --no-pub --no-fatal-infos` exited 0 with the existing
  info-level lint baseline.
- `flutter build apk --release --no-pub` passed and built
  `build\app\outputs\flutter-apk\app-release.apk` at 77.8 MB.

### Notes

- Do not run multiple `flutter test` commands in parallel in this workspace.
  A parallel test attempt crashed Flutter while copying
  `build\unit_test_assets\NativeAssetsManifest.json`; serial test runs passed.

## 2026-06-03 - v1.2.2 release packaging

Restored the normal app-page transition pacing to the earlier 280ms/220ms
tuning, updated app-facing release version metadata to v1.2.2, checked ignore
coverage for generated artifacts, and rebuilt Android and Windows packages.

### Changes

- Set normal app-page enter duration back to 280ms and reverse duration back to
  220ms.
- Updated app version metadata:
  - `pubspec.yaml`: `1.2.2+3`
  - `installer/mconnect.iss`: `1.2.2`
  - `lib/core/constants/app_constants.dart`: `v1.2.2`
  - `windows/runner/Runner.rc`: `1.2.2`
- Updated the settings-page version test to expect `v1.2.2`.
- Checked exclusions:
  - `.gitignore` already excludes `/build/`, `*.apk`, `*.zip`, runtime data,
    logs, and local `CHANGELOG.md`.
  - `.git/info/exclude` only contains default comments.
  - Current new source/test files and Android drawable resources should remain
    visible to Git; no new ignore rule was needed.

### Verification

- RED check: `flutter test --no-pub test\widget_test.dart --plain-name "app
  router gives normal pages a readable transition pace" --reporter expanded -j
  1` failed before the router timing rollback because `/likes` still used a
  350ms enter duration.
- `flutter test --no-pub test\widget_test.dart --plain-name "app router gives
  normal pages a readable transition pace" --reporter expanded -j 1` passed.
- `flutter test --no-pub test\settings_page_test.dart --plain-name "settings
  page shows the current app version" --reporter expanded -j 1` passed.
- `flutter test --no-pub test\widget_test.dart test\app_background_shell_test.dart
  --reporter expanded -j 1` passed: 25/25.
- `flutter test --no-pub test\app_background_provider_test.dart
  test\settings_page_test.dart --reporter expanded -j 1` passed: 14/14.
- `flutter analyze --no-pub --no-fatal-infos` exited 0 with existing info-level
  lint output only.
- `flutter build apk --release --no-pub` passed.
- `flutter build windows --release --no-pub` passed.
- `Compress-Archive -Path build\windows\x64\runner\Release\*
  -DestinationPath build\windows\x64\Mconnect-windows-x64.zip -Force` passed.
- `C:\Users\PC\AppData\Local\Programs\Inno Setup 6\ISCC.exe
  installer\mconnect.iss` passed.

### Artifacts

- Android APK:
  `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\app\outputs\flutter-apk\app-release.apk`
  - Size: 81,588,831 bytes / 77.81 MB
  - SHA256:
    `748F1747C67E0B9A024144AB45A410F317BC1FD891FBED1FAD9EDDF779CFF345`
- Windows EXE:
  `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\windows\x64\runner\Release\mconnect.exe`
  - Size: 223,744 bytes / 0.21 MB
  - SHA256:
    `3809B478B203B214157027ADCABC694B11F5ADFB3A60340059CD62788C274DCA`
- Windows libmpv runtime:
  `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\windows\x64\runner\Release\libmpv-2.dll`
  - Size: 15,525,902 bytes / 14.81 MB
  - SHA256:
    `0A5A0B476866C91A639A4E511E8153968F8FA23564461B0AA09ACDBA816164A4`
- Windows portable zip:
  `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\windows\x64\Mconnect-windows-x64.zip`
  - Size: 21,445,781 bytes / 20.45 MB
  - SHA256:
    `B267315780F0971508B6F35EF9F6D91AFDD042139CE71A6876422FCECC1E2DC5`
- Windows setup installer:
  `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\windows\x64\Mconnect-Setup-1.2.2.exe`
  - Size: 18,030,461 bytes / 17.20 MB
  - SHA256:
    `4B48A670BF28AC1216930B1458485881FD0104E37E3DD93CF638236BF59E77FF`

## 2026-06-03 - Tune normal page transition pacing and rebuild APK

Adjusted the custom background-backed transition used by normal app pages so
entering pages such as Likes, History, and Settings has a slower, readable
transition while still avoiding the custom-background flash.

### Changes

- Kept the project-specific transparent `CustomTransitionPage` route wrapper
  that prevents the Material transition surface from flashing over the custom
  background.
- Increased normal app-page enter duration to 350ms. This replaces the
  intermediate 280ms tuning, which still felt too quick.
- Increased normal app-page reverse duration to 300ms. This replaces the
  intermediate 220ms tuning.
- Made the content scale start at 0.975 instead of 0.985 so the transition has
  a more readable sense of movement.
- Kept the player glass route and custom background import/crop/rendering logic
  unchanged.

### Verification

- RED check: `flutter test --no-pub test\widget_test.dart --plain-name "app
  router gives normal pages a readable transition pace" --reporter expanded -j
  1` failed before the latest router timing change because `/likes` still used a
  280ms enter duration.
- `flutter test --no-pub test\widget_test.dart --plain-name "app router gives
  normal pages a readable transition pace" --reporter expanded -j 1` passed.
- `flutter test --no-pub test\widget_test.dart test\app_background_shell_test.dart
  --reporter expanded -j 1` passed: 25/25.
- `flutter test --no-pub test\app_background_provider_test.dart
  test\settings_page_test.dart --reporter expanded -j 1` passed: 14/14.
- `flutter analyze --no-pub --no-fatal-infos` exited 0 with existing info-level
  lint output only.
- `flutter build apk --release --no-pub` passed.
- `flutter build windows --release --no-pub` passed.
- `Compress-Archive -Path build\windows\x64\runner\Release\*
  -DestinationPath build\windows\x64\Mconnect-windows-x64.zip -Force` passed.
- `C:\Users\PC\AppData\Local\Programs\Inno Setup 6\ISCC.exe
  installer\mconnect.iss` passed.

### Artifacts

- Android APK:
  `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\app\outputs\flutter-apk\app-release.apk`
  - Size: 81,588,831 bytes / 77.81 MB
  - SHA256:
    `3A614AA751151D853748C9A1640415C69D5DD057E43719CE701CBE762141CB2F`
- Windows EXE:
  `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\windows\x64\runner\Release\mconnect.exe`
  - Size: 223,744 bytes / 0.21 MB
  - SHA256:
    `8F5237C05F4CDAF95C40797A0C49738C0B2F69B1204FB5360BB2074B802726C9`
- Windows libmpv runtime:
  `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\windows\x64\runner\Release\libmpv-2.dll`
  - Size: 15,525,902 bytes / 14.81 MB
  - SHA256:
    `0A5A0B476866C91A639A4E511E8153968F8FA23564461B0AA09ACDBA816164A4`
- Windows portable zip:
  `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\windows\x64\Mconnect-windows-x64.zip`
  - Size: 21,445,800 bytes / 20.45 MB
  - SHA256:
    `06EAA36949795FB72B7C7D16B183E6C3490A1D42EF7E30EB40BC719633136D35`
- Windows setup installer:
  `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\windows\x64\Mconnect-Setup-1.2.1.exe`
  - Size: 18,031,223 bytes / 17.20 MB
  - SHA256:
    `38B28967348DC010256B8599D97BD13E46E5B346782164D2887B7598BB80E29C`

## 2026-06-03 - Fix Material transition background flash on app pages

Fixed the remaining brief fallback to the plain theme surface when entering or
leaving normal app pages such as Likes, History, Settings, and other shell
routes.

### Changes

- Root cause: disabling route snapshotting was not sufficient. Flutter's
  default Material page transitions, especially the zoom transition path, paint
  a `colorScheme.surface` transition scrim/background while animating. Because
  the app pages intentionally use transparent `Scaffold` surfaces, that scrim
  briefly covered the custom background and looked like a return to the old
  plain surface.
- Replaced non-player app pages with a project-specific `CustomTransitionPage`
  helper that keeps the same page keys, names, arguments, restoration IDs, and
  widgets.
- The custom app-page transition draws `AppBackgroundShell` inside the route
  transition and animates only the page content with a short fade/scale. It does
  not draw any Material surface, black scrim, or other full-screen color layer.
- Kept the full-screen player glass route unchanged.
- Kept custom background import, crop geometry, black padding, large-image
  decode hints, and settings editor behavior unchanged.

### Verification

- RED check: `flutter test --no-pub test\widget_test.dart --plain-name "app
  router uses background-backed custom transitions for transparent pages"
  --reporter expanded -j 1` failed before the route change because
  `app-route-background-surface` was absent.
- `flutter test --no-pub test\widget_test.dart test\app_background_shell_test.dart
  --reporter expanded -j 1` passed: 24/24.
- `flutter test --no-pub test\app_background_provider_test.dart
  test\settings_page_test.dart --reporter expanded -j 1` passed: 14/14.
- `flutter analyze --no-pub --no-fatal-infos` exited 0 with existing info-level
  lint output only.
- `flutter build apk --release --no-pub` passed.
- `flutter build windows --release --no-pub` passed.
- `Compress-Archive -Path build\windows\x64\runner\Release\* -DestinationPath
  build\windows\x64\Mconnect-windows-x64.zip -Force` passed.
- `C:\Users\PC\AppData\Local\Programs\Inno Setup 6\ISCC.exe
  installer\mconnect.iss` passed.

### Artifacts

- Android APK:
  `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\app\outputs\flutter-apk\app-release.apk`
  - Size: 81,588,831 bytes / 77.81 MB
  - SHA256:
    `ADE926527F066E8C6640535CA1B02AC6C3CBA2298130F50B6ACE1778D7866D47`
- Windows EXE:
  `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\windows\x64\runner\Release\mconnect.exe`
  - Size: 223,744 bytes / 0.21 MB
  - SHA256:
    `8F5237C05F4CDAF95C40797A0C49738C0B2F69B1204FB5360BB2074B802726C9`
- Windows libmpv runtime:
  `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\windows\x64\runner\Release\libmpv-2.dll`
  - Size: 15,525,902 bytes / 14.81 MB
  - SHA256:
    `0A5A0B476866C91A639A4E511E8153968F8FA23564461B0AA09ACDBA816164A4`
- Windows portable zip:
  `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\windows\x64\Mconnect-windows-x64.zip`
  - Size: 21,445,796 bytes / 20.45 MB
  - SHA256:
    `A7E82BF8A7D2F9587F72DB887977CED60F9E95AF661C9D0556AF83865B7689DB`
- Windows setup installer:
  `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\windows\x64\Mconnect-Setup-1.2.1.exe`
  - Size: 18,030,765 bytes / 17.20 MB
  - SHA256:
    `BD546385BB7E463B4211B92259AF3A97DC60D9D34849510FFD03AA5553B313A6`

## 2026-06-03 - Earlier snapshot-only page flicker mitigation

Fixed a brief fallback to the plain theme surface when entering normal app
pages such as Likes, History, Settings, and other shell routes.

### Changes

- Root cause: GoRouter's default Material pages enable route snapshotting. With
  transparent `Scaffold` and `AppBar` surfaces, the transition snapshot could
  briefly precompose transparent pages against the theme surface instead of the
  live custom background.
- Changed non-player shell pages to use explicit `MaterialPage` instances with
  `allowSnapshotting: false`, while preserving the same page keys, names,
  arguments, restoration IDs, and page widgets.
- Kept the existing custom background import, crop geometry, black padding, and
  large-image decode handling unchanged.
- Kept the full-screen player's custom slide/glass route unchanged.

### Verification

- `flutter test --no-pub test\widget_test.dart --reporter expanded -j 1`
  passed: 16/16.
- `flutter test --no-pub test\app_background_provider_test.dart
  test\app_background_shell_test.dart test\settings_page_test.dart --reporter
  expanded -j 1` passed: 22/22.
- `flutter analyze --no-pub --no-fatal-infos` exited 0 with existing info-level
  lint output only.
- `flutter build apk --release --no-pub` passed.
- `flutter build windows --release --no-pub` passed.
- `Compress-Archive -Path build\windows\x64\runner\Release\* -DestinationPath
  build\windows\x64\Mconnect-windows-x64.zip -Force` passed.
- `C:\Users\PC\AppData\Local\Programs\Inno Setup 6\ISCC.exe
  installer\mconnect.iss` passed.

### Artifacts

- Android APK:
  `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\app\outputs\flutter-apk\app-release.apk`
  - Size: 81,588,831 bytes / 77.81 MB
  - SHA256:
    `30240731F0C6B459BF72B5DAA252F5D204AEF0E7A7B763E7D187F39ABB383812`
- Windows EXE:
  `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\windows\x64\runner\Release\mconnect.exe`
  - Size: 223,744 bytes / 0.21 MB
  - SHA256:
    `8F5237C05F4CDAF95C40797A0C49738C0B2F69B1204FB5360BB2074B802726C9`
- Windows libmpv runtime:
  `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\windows\x64\runner\Release\libmpv-2.dll`
  - Size: 15,525,902 bytes / 14.81 MB
  - SHA256:
    `0A5A0B476866C91A639A4E511E8153968F8FA23564461B0AA09ACDBA816164A4`
- Windows portable zip:
  `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\windows\x64\Mconnect-windows-x64.zip`
  - Size: 21,445,742 bytes / 20.45 MB
  - SHA256:
    `0E9B8D715C443C45BACD3FC388A991B3ABC5CCE491B312F0C1970172306D09B7`
- Windows setup installer:
  `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\windows\x64\Mconnect-Setup-1.2.1.exe`
  - Size: 18,030,440 bytes / 17.20 MB
  - SHA256:
    `7AF521590615D0CEF0674C885932B94FA412AE44ECF560443A3426FA21381608`

## 2026-06-03 - Fix custom background import without stretching

Reworked custom background placement so every decodable image can be imported,
small images are padded with black, and large images avoid stretched or black
rendering while still allowing manual zoom and pan.

### Changes

- Removed the custom background minimum-resolution rejection. Picked images now
  proceed to the editor as long as Flutter can decode a positive image size.
- Changed the shared custom background geometry from forced cover to
  aspect-preserving contain, with a black crop frame behind the image for
  letterbox or pillarbox areas.
- Reused the same no-stretch geometry in the app shell, player glass
  background, and settings editor preview.
- Added capped image decode hints for very large background files, limiting the
  longest decoded side to 4096 px without rewriting the user's selected image.
- Changed the editor preview surface to black so the edit view matches the final
  padded background output.

### Verification

- `flutter test --no-pub test\app_background_provider_test.dart
  test\app_background_shell_test.dart test\settings_page_test.dart --reporter
  expanded -j 1` passed: 22/22.
- `flutter test --no-pub test\widget_test.dart --reporter expanded -j 1`
  passed: 15/15.
- `flutter analyze --no-pub --no-fatal-infos` exited 0 with existing info-level
  lint output only.
- `flutter build apk --release --no-pub` passed.
- `flutter build windows --release --no-pub` passed.
- `Compress-Archive -Path build\windows\x64\runner\Release\* -DestinationPath
  build\windows\x64\Mconnect-windows-x64.zip -Force` passed.
- `C:\Users\PC\AppData\Local\Programs\Inno Setup 6\ISCC.exe
  installer\mconnect.iss` passed.

### Artifacts

- Android APK:
  `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\app\outputs\flutter-apk\app-release.apk`
  - Size: 81,588,831 bytes / 77.81 MB
  - SHA256:
    `743BB9D5E16A27D52F6F9746B8D7852B41A26A3BF55E76F0F7EA50AD59B869AB`
- Windows EXE:
  `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\windows\x64\runner\Release\mconnect.exe`
  - Size: 223,744 bytes / 0.21 MB
  - SHA256:
    `8F5237C05F4CDAF95C40797A0C49738C0B2F69B1204FB5360BB2074B802726C9`
- Windows libmpv runtime:
  `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\windows\x64\runner\Release\libmpv-2.dll`
  - Size: 15,525,902 bytes / 14.81 MB
  - SHA256:
    `0A5A0B476866C91A639A4E511E8153968F8FA23564461B0AA09ACDBA816164A4`
- Windows portable zip:
  `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\windows\x64\Mconnect-windows-x64.zip`
  - Size: 21,445,559 bytes / 20.45 MB
  - SHA256:
    `E78449BF9C6DCB4412A67B10D6B146679634B56EC0B54A65B3421A0B194DDC5E`
- Windows setup:
  `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\windows\x64\Mconnect-Setup-1.2.1.exe`
  - Size: 18,030,401 bytes / 17.20 MB
  - SHA256:
    `8FEE277A92B5E14CBEC1F6A7ED2B6DFD40DD43263D9CE1A183E8D0A3F3998530`

## 2026-06-03 - Fix custom background editor and rebuild artifacts

Fixed custom background flashing, crop editing, and image switching reliability
without changing unrelated player, navigation, or library behavior.

### Changes

- Restored saved background settings synchronously when the Hive settings box is
  already open, so route changes do not briefly fall back to the plain theme
  surface.
- Added reusable cover-canvas geometry for custom backgrounds. The app shell,
  player glass surface, and editor now use the same image scaling and offset
  model.
- Updated the background editor to use the current window aspect ratio:
  landscape crops on desktop/tablet-style windows and portrait crops on phone
  windows.
- Kept the full cover image canvas available inside the editor preview, so
  dragging can bring off-screen image regions into the crop instead of being
  limited to the visible editor window.
- Saved crop viewport dimensions with background settings and kept old saved
  background JSON compatible.
- Saved newly picked images with unique filenames and evicted related
  `FileImage` cache entries, avoiding stale-image reuse when switching
  backgrounds.
- Added a resolution check before opening the editor. Images below the active
  crop shape's minimum usable size now show a "picture too small" prompt instead
  of silently failing to switch.
- Added a stable settings tile key for the custom background row so tests do not
  depend on localized text construction.

### Verification

- `flutter test --no-pub test\app_background_provider_test.dart
  test\app_background_shell_test.dart test\settings_page_test.dart --reporter
  expanded -j 1` passed: 20/20.
- `flutter test --no-pub test\widget_test.dart --reporter expanded -j 1`
  passed: 15/15.
- `flutter analyze --no-pub --no-fatal-infos` exited 0 with existing info-level
  lint output only.
- `flutter build apk --release --no-pub` passed.
- `flutter build windows --release --no-pub` passed.
- `Compress-Archive -Path build\windows\x64\runner\Release\* -DestinationPath
  build\windows\x64\Mconnect-windows-x64.zip -Force` passed.
- `C:\Users\PC\AppData\Local\Programs\Inno Setup 6\ISCC.exe
  installer\mconnect.iss` passed.

### Artifacts

- Android APK:
  `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\app\outputs\flutter-apk\app-release.apk`
  - Size: 81,588,831 bytes / 77.81 MB
  - SHA256:
    `8125E3D43AE1F7657CA395D2885C103F262E547F782798956341FF22B1D69057`
- Windows EXE:
  `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\windows\x64\runner\Release\mconnect.exe`
  - Size: 223,744 bytes / 0.21 MB
  - SHA256:
    `8F5237C05F4CDAF95C40797A0C49738C0B2F69B1204FB5360BB2074B802726C9`
- Windows libmpv runtime:
  `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\windows\x64\runner\Release\libmpv-2.dll`
  - Size: 15,525,902 bytes / 14.81 MB
  - SHA256:
    `0A5A0B476866C91A639A4E511E8153968F8FA23564461B0AA09ACDBA816164A4`
- Windows portable zip:
  `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\windows\x64\Mconnect-windows-x64.zip`
  - Size: 21,441,727 bytes / 20.45 MB
  - SHA256:
    `5031BC77BA005022F7A869628D8ED7AFC2EA770B582AAB1A1C1916D245FBBA75`
- Windows setup:
  `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\windows\x64\Mconnect-Setup-1.2.1.exe`
  - Size: 18,029,612 bytes / 17.19 MB
  - SHA256:
    `3A95C239196C72C0AFF0244AEF0B684C189DB9BAD6299FD8A8BAA40ED46120AC`

## 2026-06-03 - Add player glass background and rebuild artifacts

Updated the full-screen player route from a plain opaque surface to a balanced
glass/acrylic background that reuses the configured custom app background while
still preventing the underlying library or likes page from showing through.

### Changes

- Extracted the custom background image rendering into a reusable
  `AppBackgroundImageLayer`, so the global shell and player route share the
  same image path, scale, and offset behavior.
- Replaced the `/player` route's plain opaque wrapper with
  `PlayerGlassRouteSurface`.
- The player route now keeps a solid theme surface as its base, redraws the
  configured custom background when available, applies a 24px blur, and overlays
  a balanced theme scrim for readability.
- Missing, disabled, or stale background images fall back to the normal theme
  surface without showing the previous route.
- Added test-only image builder injection for stable widget tests without
  changing production `Image.file` rendering.

### Verification

- Red tests first failed because the player route still exposed only the old
  opaque route surface and `PlayerGlassRouteSurface` did not exist.
- `flutter test --no-pub test\widget_test.dart
  test\app_background_shell_test.dart --reporter expanded -j 1` passed: 19/19.
- `flutter analyze --no-pub --no-fatal-infos` exited 0 with existing info-level
  lint output only.
- `flutter build apk --release --no-pub` passed.
- `flutter build windows --release --no-pub` passed.
- `Compress-Archive -Path build\windows\x64\runner\Release\* -DestinationPath
  build\windows\x64\Mconnect-windows-x64.zip -Force` passed.
- `C:\Users\PC\AppData\Local\Programs\Inno Setup 6\ISCC.exe
  installer\mconnect.iss` passed.

### Artifacts

- Android APK:
  `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\app\outputs\flutter-apk\app-release.apk`
  - Size: 81,572,447 bytes / 77.79 MB
  - SHA256:
    `7B0FD7B2A9AF1796EFF04B43CC5370B51862401543D0155FF5202FE33B2B3FBA`
- Windows EXE:
  `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\windows\x64\runner\Release\mconnect.exe`
  - Size: 223,744 bytes / 0.21 MB
  - SHA256:
    `8F5237C05F4CDAF95C40797A0C49738C0B2F69B1204FB5360BB2074B802726C9`
- Windows libmpv runtime:
  `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\windows\x64\runner\Release\libmpv-2.dll`
  - Size: 15,525,902 bytes / 14.81 MB
  - SHA256:
    `0A5A0B476866C91A639A4E511E8153968F8FA23564461B0AA09ACDBA816164A4`
- Windows portable zip:
  `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\windows\x64\Mconnect-windows-x64.zip`
  - Size: 21,437,623 bytes / 20.44 MB
  - SHA256:
    `8AD715E6937A3DE19F2BEC5FB67C64E366C775F49EFF9634D1EE86E66C29415D`
- Windows setup:
  `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\windows\x64\Mconnect-Setup-1.2.1.exe`
  - Size: 18,026,276 bytes / 17.19 MB
  - SHA256:
    `EE64F90392F66E3C8F7A817E0B91F176CD424D9D7712EA25829A1ACFDF53FD43`

## 2026-06-03 - Fix opaque full player route transition

Fixed the full-screen player entry transition so underlying library or likes
page controls no longer flash behind the player when opened from the mini
player.

### Changes

- Added an opaque route surface around the `/player` `CustomTransitionPage`
  using the active theme surface color.
- Kept the global transparent scaffold/background behavior and mini-player
  translucency unchanged, so custom app backgrounds still show on normal pages.
- Added a widget regression test that opens the player from the mini player and
  verifies the player route owns an opaque transition surface.

### Verification

- Red test first failed because the player route had no opaque route surface.
- `flutter test --no-pub test\widget_test.dart --plain-name "player route has
  an opaque surface during its transition" --reporter expanded -j 1` passed.
- `flutter build apk --release --no-pub` passed.
- `flutter build windows --release --no-pub` passed.
- `Compress-Archive -Path build\windows\x64\runner\Release\* -DestinationPath
  build\windows\x64\Mconnect-windows-x64.zip -Force` passed.
- `C:\Users\PC\AppData\Local\Programs\Inno Setup 6\ISCC.exe
  installer\mconnect.iss` passed.

### Artifacts

- Android APK:
  `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\app\outputs\flutter-apk\app-release.apk`
  - Size: 81,572,447 bytes / 77.79 MB
  - SHA256:
    `7B72BEBB1712632082F3B8DF465A481DB6F38D0D7712B0F68324395EF7B2A35B`
- Windows EXE:
  `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\windows\x64\runner\Release\mconnect.exe`
  - Size: 223,744 bytes / 0.21 MB
  - SHA256:
    `8F5237C05F4CDAF95C40797A0C49738C0B2F69B1204FB5360BB2074B802726C9`
- Windows libmpv runtime:
  `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\windows\x64\runner\Release\libmpv-2.dll`
  - Size: 15,525,902 bytes / 14.81 MB
  - SHA256:
    `0A5A0B476866C91A639A4E511E8153968F8FA23564461B0AA09ACDBA816164A4`
- Windows portable zip:
  `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\windows\x64\Mconnect-windows-x64.zip`
  - Size: 21,437,941 bytes / 20.44 MB
  - SHA256:
    `34D03B1A551D4F7C37E2F0D2E45A0F415B77BB077758BC4C6CAC958B3F1D98E0`
- Windows setup:
  `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\windows\x64\Mconnect-Setup-1.2.1.exe`
  - Size: 18,026,357 bytes / 17.19 MB
  - SHA256:
    `5FEF6028549C817A4C8B1E02E8C17A131AF551D6BDF3549EF67E068A97DB3171`

## 2026-06-03 - Add notification like toggle and custom app background

Implemented the local notification like toggle and a user-configurable
application background.

### Changes

- Added an expanded Android media notification favorite action. The compact
  notification still keeps previous / play-pause / next.
- The notification action now toggles only the local Mconnect "我喜欢" record:
  outline heart when not liked, filled heart when liked, and a second tap removes
  the local like without deleting the song cache.
- Synced notification favorite state with `likesProvider`, so player UI changes
  and notification state refresh from the same local likes source.
- Added notification drawable resources for outline and filled hearts.
- Added persistent `AppBackgroundSettings` through Riverpod + Hive.
- Wrapped `MaterialApp.router` with a global background shell that renders the
  saved image behind the app with a fixed readability scrim.
- Added a settings-page "自定义背景" entry. Users can pick an image, preview it,
  drag/scale it in an editor, save it, re-edit it, or remove it.
- Adjusted scaffold, app bar, navigation bar, and mini-player surfaces so the
  background can show through while keeping key UI readable.

### Verification

- Red tests were added first for notification favorite state/action behavior,
  local likes toggling, background persistence, background shell rendering, and
  the settings-page custom background entry.
- `dart analyze` on the changed source and test files passed.
- `flutter analyze --no-pub --no-fatal-infos` passed with existing info-level
  lint output only.
- `flutter test --no-pub test\playback_notification_service_test.dart
  test\likes_provider_test.dart test\app_background_provider_test.dart
  test\app_background_shell_test.dart test\settings_page_test.dart --reporter
  expanded -j 1` was blocked before running tests by the `sqlite3` native asset
  hook failing to download `sqlite3.x64.windows.dll` from GitHub because of a
  Windows socket timeout. I did not change the project to globally use system
  SQLite because that could alter Android release linking.
- `flutter build apk --release --no-pub` passed.
- `git diff --check` passed.

### Artifacts

- Android APK:
  `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\app\outputs\flutter-apk\app-release.apk`
  - Size: 81,572,447 bytes / 77.79 MB
  - SHA256:
    `B468488CC15F2D167A0F7FDAB0103D955F054579C30C1551CF6C0D4F0E4EBAF8`

## 2026-06-01 - Bump release version to v1.2.1 and rebuild artifacts

Updated the app release version and rebuilt all requested Android and Windows
artifacts.

### Changes

- Updated Flutter package version to `1.2.1+2`.
- Updated the in-app settings version constant to `1.2.1`.
- Updated the settings page regression test to expect `1.2.1`.
- Updated Inno Setup to emit `Mconnect-Setup-1.2.1.exe`.
- Updated the Windows resource fallback version string to `1.2.1`; the Windows
  release build regenerated `FLUTTER_VERSION` as `1.2.1+2`.

### Verification

- `flutter test --no-pub test\settings_page_test.dart --reporter expanded -j 1`
  passed: 6/6.
- `flutter analyze --no-pub --no-fatal-infos` exited 0 with existing info-level
  lint output only.
- `flutter build apk --release --no-pub` passed.
- `flutter build windows --release --no-pub` passed.
- `Compress-Archive -Path build\windows\x64\runner\Release\* -DestinationPath
  build\windows\x64\Mconnect-windows-x64.zip -Force` passed.
- `ISCC.exe installer\mconnect.iss` passed and generated the v1.2.1 setup.
- Version search found no remaining `1.2.0` in the checked source/version
  files.
- Windows EXE `FileVersion` and `ProductVersion` are both `1.2.1+2`.
- Windows portable zip contents include `libmpv-2.dll`,
  `media_kit_libs_windows_audio_plugin.dll`, and `mconnect.exe`.
- `git diff --check` passed.

### Artifacts

- Android APK:
  `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\app\outputs\flutter-apk\app-release.apk`
  - Size: 81,210,563 bytes / 77.45 MB
  - SHA256:
    `016BD0C16F1FF23F6D29BB9982F299F3C431A920BF0A8F9F9420CD1838E57583`
- Windows EXE:
  `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\windows\x64\runner\Release\mconnect.exe`
  - Size: 223,744 bytes / 0.21 MB
  - SHA256:
    `8F5237C05F4CDAF95C40797A0C49738C0B2F69B1204FB5360BB2074B802726C9`
- Windows libmpv runtime:
  `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\windows\x64\runner\Release\libmpv-2.dll`
  - Size: 15,525,902 bytes / 14.81 MB
  - SHA256:
    `0A5A0B476866C91A639A4E511E8153968F8FA23564461B0AA09ACDBA816164A4`
- Windows portable zip:
  `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\windows\x64\Mconnect-windows-x64.zip`
  - Size: 21,392,483 bytes / 20.4 MB
  - SHA256:
    `24A719D003CC730E797FA841140FCBB5D11F38C861DE6D1BD64B148E46FBEAE0`
- Windows setup:
  `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\windows\x64\Mconnect-Setup-1.2.1.exe`
  - Size: 17,994,379 bytes / 17.16 MB
  - SHA256:
    `E4F8C25B349311A12080F3027E2F1F8BF81616058C2002C6665EE012C48BF173`

## 2026-06-01 - Fix Windows local media_kit playback duration and packaging

Fixed the Windows local music regression where scanned songs could open as
`0:00` and fail to play after switching Windows playback to `media_kit`.

### Root Cause / Evidence

- The previous Windows Release directory did not contain `libmpv-2.dll`, while
  `MediaKitWindowsAudioController` requires libmpv at runtime.
- The media_kit controller did not surface backend error events into
  `PlayerNotifier`, so native playback failures could leave the UI looking like
  it was still playing or loading.
- Local file `setUrl()` did not re-publish a known duration after media_kit
  opened the file, so the UI could remain at `0:00` until a later duration event.
- A red test first failed because local file `setUrl()` emitted no duration,
  backend errors did not reach `playerStateStream`, and `PlayerNotifier` kept
  `isPlaying=true` after a stream error.

### Changes

- Added `duration` and `errorStream` to the Windows media_kit backend boundary.
- Windows local file playback now publishes a known non-zero duration after
  `open()`, waiting briefly for media_kit duration readiness when needed.
- Windows media_kit backend errors now flow through `playerStateStream` and reset
  playing/buffering state.
- `PlayerNotifier` now clears playing/loading state and shows
  `Playback failed: ...` when the active audio controller stream reports an
  error.
- The real Windows media_kit backend checks local file existence before opening,
  producing a clear stale-file error instead of silently staying at `0:00`.
- Fixed the local music Android picker constructor so `flutter analyze` no
  longer reports the previous `invalid_constant` build blocker.

### Verification

- Red tests failed first for the missing duration/error propagation behavior.
- Target tests passed: `flutter test --no-pub
  test\media_kit_windows_audio_controller_test.dart
  test\player_provider_test.dart test\local_music_repository_test.dart
  --reporter expanded -j 1` reported 37/37.
- Full tests passed: `flutter test --no-pub --reporter expanded -j 1`
  reported 222/222.
- `flutter analyze --no-pub --no-fatal-infos` exited 0 with existing info-level
  lint output only.
- `flutter build windows --release --no-pub` passed.
- `flutter build apk --release --no-pub` passed.
- `git diff --check` passed.

### Artifacts

- Android APK:
  `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\app\outputs\flutter-apk\app-release.apk`
  - Size: 81,210,563 bytes / 77.45 MB
  - SHA256:
    `F88E5136AB2611CF0B01BDAB690ED6ED5B0F97F68EA89C7E41E5D84B870E3E4F`
- Windows EXE:
  `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\windows\x64\runner\Release\mconnect.exe`
  - Size: 223,744 bytes / 0.21 MB
  - SHA256:
    `14A51DF9CB6A0E02E5262649F5F3B5B24FB5B365B92C38005011A3563CDC127A`
- Windows libmpv runtime:
  `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\windows\x64\runner\Release\libmpv-2.dll`
  - Size: 15,525,902 bytes / 14.81 MB
  - SHA256:
    `0A5A0B476866C91A639A4E511E8153968F8FA23564461B0AA09ACDBA816164A4`
- Windows portable zip:
  `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\windows\x64\Mconnect-windows-x64.zip`
  - Size: 21,392,430 bytes / 20.4 MB
  - SHA256:
    `BF2EB5988EA13639ED37C420AF2C6FFB3E09AD5FA27C272A4B51F262F1446878`
  - Verified contents include `libmpv-2.dll`,
    `media_kit_libs_windows_audio_plugin.dll`, and `mconnect.exe`.
- Windows setup:
  `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\windows\x64\Mconnect-Setup-1.2.0.exe`
  - Size: 17,992,779 bytes / 17.16 MB
  - SHA256:
    `F7C6DD2C66CB03FB5D0493CEAB3718C75EF611E823C2639DA1C1591DD154238F`
  - Inno Setup compile log confirmed `libmpv-2.dll` was compressed into the
    installer.

### Manual Validation Needed

- Install or unzip the new Windows build and play a real scanned local music
  file to confirm audible playback and a non-zero displayed duration.
- Confirm the Windows EQ sliders still change the sound in the new package.

## 2026-06-01 - Local music SAF scan and Windows media_kit EQ

Implemented the local music scan fix and the Windows equalizer backend change
without touching downloads, search, platform music APIs, lyrics parsing,
floating lyrics, or Android background playback.

### Root Cause / Evidence

- The previous local music picker depended on a plain filesystem folder path and
  `Directory.list()`. On Android scoped storage and SAF providers, the reliable
  selectable folder identity is a `content://` tree URI, not a traversable Dart
  file path.
- Android 13+ requires the granular audio media permission path for direct media
  reads. The app did not declare `READ_MEDIA_AUDIO`, and the old storage
  permission was not scoped by SDK version.
- Local `content://` song IDs would have been wrapped by `Uri.file()`, producing
  an invalid playback URL.
- Windows already exposed the 5-band EQ UI, but `just_audio_windows` does not
  provide an equalizer path. A Windows-specific `media_kit`/libmpv backend is
  needed for app-local EQ.
- `.gitignore` had a broad `local_music/` runtime-data rule that also ignored
  `lib/features/local_music/` source files, so the source fix needed a precise
  unignore rule.

### Changes

- Added injectable local music picker/scanner abstractions so provider tests no
  longer depend on static `FilePicker.getDirectoryPath()`.
- Kept desktop scanning on the existing `Directory.list()` path.
- Added Android SAF folder picking through `ACTION_OPEN_DOCUMENT_TREE`, persisted
  URI permission, and recursive `DocumentFile.fromTreeUri` scanning.
- Android scan results return playable `content://` song IDs and same-name lyric
  text where found.
- Added `READ_MEDIA_AUDIO`, limited old `READ_EXTERNAL_STORAGE` to SDK 32, and
  avoided `MANAGE_EXTERNAL_STORAGE`.
- Local playback now preserves `content://` and `file://` IDs and only wraps
  plain disk paths with `Uri.file()`.
- Added `MediaKitWindowsAudioController` for Windows, backed by `media_kit` and
  `media_kit_libs_windows_audio`.
- Windows EQ maps the existing 5 bands to mpv filters at 60 Hz, 230 Hz, 910 Hz,
  3600 Hz, and 14000 Hz. Positive EQ gain appends a matching negative preamp.
- Windows plugin registration was regenerated by `flutter pub get`.
- `.gitignore` now explicitly unignores `lib/features/local_music/` while still
  ignoring runtime `local_music/` folders.

### Verification

- Red tests first failed for missing local picker/scanner abstractions, Android
  SAF native code, Android permissions, and Windows media_kit controller.
- Target tests passed: `flutter test --no-pub
  test\local_music_repository_test.dart test\local_music_provider_test.dart
  test\local_music_android_test.dart test\player_provider_test.dart
  test\audio_enhancement_settings_test.dart
  test\media_kit_windows_audio_controller_test.dart --reporter expanded -j 1`
  reported 42/42.
- Full tests passed: `flutter test --no-pub --reporter expanded -j 1`
  reported 218/218.
- `git diff --check` passed after the `.gitignore` unignore adjustment.
- `flutter analyze --no-pub --no-fatal-infos` and release builds were not run in
  this pass because the required sandbox escalation was rejected by the runtime
  usage limit. Build/package verification still needs to be rerun when approval
  is available.

### Pending

- Run `flutter analyze --no-pub --no-fatal-infos`.
- Run `flutter build apk --release --no-pub`.
- Run `flutter build windows --release --no-pub`.
- Recreate the Windows portable zip and setup installer, then record SHA256
  hashes.
- Manual validation: Android SAF local folder scan on a real device, Windows EQ
  audible effect on the packaged build.

### Packaging Blocker Found

- `flutter --version`, `dart.bat --version`, `flutter analyze`, Android build,
  and Windows build all hung with no useful compiler output when run from the
  sandboxed session.
- Direct `dart.exe --version` from the bundled Dart SDK succeeds, so the Dart VM
  itself is not broken.
- Running the Flutter tool snapshot directly fails with:
  `Flutter failed to open a file at
  "C:\Users\PC\flutter\flutter\bin\cache\lockfile"`.
- `whoami` reports `desktop-bt26ch3\codexsandboxoffline`.
- `icacls` shows `DESKTOP-BT26CH3\CodexSandboxUsers` has only `(RX)` access on
  `C:\Users\PC\flutter\flutter` and its cache lock files, while Flutter startup
  requires write access to `bin/cache\lockfile` and `flutter.bat.lock`.
- The Flutter SDK git repo also reports dubious ownership because it belongs to
  `DESKTOP-BT26CH3\PC`, not the sandbox user.
- Conclusion: packaging is blocked by Flutter SDK ownership/write permissions
  under the sandbox user, not by a confirmed app compile error. Build commands
  must run outside the sandbox/as the owning `PC` user, or the Flutter SDK cache
  permissions and git safe-directory configuration must be adjusted.

## 2026-06-01 - Stabilize Android floating lyrics rendering

Fixed the Android native floating lyrics overlay still showing as a blank window
after the duplicate-update marquee reset fix.

### Root Cause / Evidence

- The previous fix reduced repeated native `update()` calls and avoided
  unnecessary text resets, but real-device feedback still showed an empty
  overlay.
- That made the remaining risky path the Android custom self-drawn
  `FastMarqueeTextView`, especially its `Canvas.drawText` measurement and draw
  path.
- A red static regression test first failed while `FastMarqueeTextView`,
  `override fun onDraw`, and `canvas.drawText` were still present.

### Changes

- Replaced Android lyric and translation views with normal system
  `TextView(activity)` instances.
- Removed the custom `FastMarqueeTextView`, custom `onDraw(Canvas)`, manual
  `canvas.drawText`, and custom timing-based marquee logic.
- Kept `setTextIfChanged` so the same lyric line does not repeatedly reset the
  system marquee.
- Added explicit `minHeight` values for lyric and translation text views so an
  initially empty text value cannot collapse the visible text area.
- Kept the existing Flutter native-update signature de-duplication and did not
  change playback, background audio, downloads, search, lyrics parsing, or
  Windows floating lyrics.

### Verification

- Red test first failed because Android native floating lyrics still contained
  `FastMarqueeTextView`.
- `flutter test --no-pub test\floating_lyrics_provider_test.dart
  test\floating_lyrics_service_test.dart --reporter expanded -j 1` passed:
  22/22.
- `flutter test --no-pub --reporter expanded -j 1` passed: 205/205.
- `flutter analyze --no-pub --no-fatal-infos` passed with existing info-level
  lints only.
- `flutter build apk --release --no-pub` passed after stopping a stale Gradle
  daemon that had temporarily locked `classes.dex`.

### Artifact

- Android APK:
  `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\app\outputs\flutter-apk\app-release.apk`
- Android APK size: 81,098,876 bytes / 77.34 MB
- Android APK SHA256:
  `1CB572CB46D8B19A6106B8AB8F1146E79CF39B5F9141CE03ADF69A21136EC456`
- Real-device validation is still required to confirm visible lyrics after
  install.

## 2026-06-01 - Fix Android floating lyrics blank overlay

Fixed the Android floating lyrics regression where the native overlay window
appeared but no lyric text was visible.

### Root Cause / Evidence

- Flutter sent a native `update()` on every playback position tick even when the
  active lyric line and display settings were unchanged.
- Android `FloatingLyricsController` unconditionally assigned `TextView.text`
  for every update, which reset the custom marquee start time.
- `FastMarqueeTextView` started long text from the right edge outside the
  visible clip, so repeated resets could keep long lyrics invisible.

### Changes

- Added a native-update signature in `FloatingLyricsSyncController` so repeated
  position ticks for the same lyric and settings no longer call the native
  overlay.
- The signature is cleared when the overlay is disabled, closed, or lyrics are
  not ready, so re-enable and new lyric loads still push the current line.
- Android native floating lyrics now only changes `TextView.text` when the text
  actually changed.
- Android long-lyric marquee now starts inside the visible text area before
  scrolling.

### Verification

- Red tests first failed for repeated same-line native updates and Android
  native marquee/text-reset static checks.
- `flutter test --no-pub test\floating_lyrics_provider_test.dart
  test\floating_lyrics_service_test.dart --reporter expanded -j 1` passed:
  23/23.
- `flutter test --no-pub --reporter expanded -j 1` passed: 206/206.
- `flutter analyze --no-pub --no-fatal-infos` passed with only existing
  info-level lints.
- `flutter build apk --release --no-pub` passed.

### Artifact

- Android APK:
  `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\app\outputs\flutter-apk\app-release.apk`
- Android APK size: 81,098,876 bytes / 77.34 MB
- Android APK SHA256:
  `74EE360B9ECEC5FDC4509A1E2DE7C7DCEA494D3796F527308FD806B0EDC38B57`

## 2026-05-31 - Fix Android screen-off silent playback regression

Fixed the Android regression where audio could go silent about 55 seconds after
screen-off while the UI progress continued to advance.

### Root Cause / Evidence

- The previous Android background path mirrored `PlayerNotifier` state into the
  AudioService notification while the real `just_audio` player still lived in
  the foreground Flutter layer.
- Reasserting booleans and wake locks helped preserve state, but did not make
  the real audio pipeline owned by the foreground media service.
- The fix moves the Android default real playback controller behind the
  AudioService handler, so notification state is now derived from actual
  `just_audio` player streams.

### Changes

- Added `lib/features/player/data/player_audio_controller.dart` and moved the
  shared playback controller abstractions out of the UI provider.
- Added `AudioServicePlayerController`, an Android singleton that implements
  both playback control and notification updates while delegating real audio to
  `JustAudioController`.
- Bound `MconnectAudioHandler` to the real controller streams for playing,
  buffering, ready, completed, position, and duration state broadcasts.
- Kept notification button callbacks routed through `PlaybackNotificationActions`
  while direct player calls use the underlying controller to avoid recursion.
- Kept non-Android defaults on `JustAudioController` with a no-op notification
  controller, so desktop playback behavior is not moved onto Android's service
  singleton.
- Extended Android `PlaybackKeepAliveController.kt` to hold and release a
  non-reference-counted high-performance Wi-Fi lock together with the existing
  partial wake lock.
- Added diagnostics for forced background playback reassertions, including
  playing state and native lock-held status.

### Verification

- `flutter test --no-pub test\playback_notification_service_test.dart
  test\playback_keep_alive_service_test.dart test\player_provider_test.dart
  --reporter expanded -j 1` passed: 36/36.
- `flutter test --no-pub --reporter expanded -j 1` passed: 200/200.
- `flutter analyze --no-pub --no-fatal-infos` passed with only existing
  info-level lints.
- `flutter build apk --release --no-pub` passed.

### Artifact

- Android APK:
  `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\app\outputs\flutter-apk\app-release.apk`
- Android APK size: 81,098,876 bytes / 77.34 MB
- Android APK SHA256:
  `712831A21DB794815B9EC7DB8F4EBD93796D8C451A5F75188372559D78A34D7A`

## 2026-05-31 - Package latest color-fix release artifacts

Rebuilt the requested release artifacts after the Windows floating lyrics text
color parser fix. The Windows exe, portable zip, and setup now include the
latest native color parsing change.

### Verification

- `flutter build apk --release --no-pub` passed.
- `flutter build windows --release --no-pub` passed.
- `Compress-Archive -Path build\windows\x64\runner\Release\* -DestinationPath
  build\windows\x64\Mconnect-windows-x64.zip -Force` passed.
- `C:\Users\PC\AppData\Local\Programs\Inno Setup 6\ISCC.exe
  installer\mconnect.iss` passed.

### Artifacts

- Android APK:
  `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\app\outputs\flutter-apk\app-release.apk`
- Android APK size: 81,098,876 bytes / 77.34 MB
- Android APK SHA256:
  `9DEF472DFEF370FAA7420A7800438DEA21A1502AF8C1EDBD13A3D8C3B0E256CA`
- Windows release exe:
  `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\windows\x64\runner\Release\mconnect.exe`
- Windows exe size: 223,232 bytes / 0.21 MB
- Windows exe SHA256:
  `4186F25453EC8CCDEC5A7EA58859B3EAA010BC28477D393C78862574C912FF03`
- Windows portable zip:
  `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\windows\x64\Mconnect-windows-x64.zip`
- Windows portable zip size: 14,051,895 bytes / 13.40 MB
- Windows portable zip SHA256:
  `0D010D33B2DB04E6539A7AEF1A47CFDA0A64BE75D3E0E6BA63894C432B6C354E`
- Windows setup:
  `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\windows\x64\Mconnect-Setup-1.2.0.exe`
- Windows setup size: 12,384,062 bytes / 11.81 MB
- Windows setup SHA256:
  `781F1AC34BDDE2836D0535EB97BEFF4B10DDE9AA180E7BC87388B56E42D6293B`

## 2026-05-31 - Fix Windows floating lyrics text color updates

Investigated the Windows-only issue where changing the floating lyric text
color from settings did not affect the desktop floating lyrics window.

### Root Cause / Evidence

- Flutter was already sending `textColor` through the floating lyrics method
  channel.
- Windows native code parsed ARGB colors through a signed `int` helper and used
  `argb < 0` as the missing-value check.
- Opaque Flutter colors such as `0xFFFFF4F8` are larger than signed 32-bit
  range and can become negative after conversion, so Windows treated valid
  colors as missing and fell back to white.

### Changes

- Updated `windows/runner/floating_lyrics_channel.cpp` to parse color payloads
  as raw `std::uint32_t` ARGB bits and only fall back when the key is absent or
  has an unsupported type.
- Added a regression test that prevents the Windows color parser from
  reintroducing the signed-negative fallback.

### Verification

- Red test first failed on `Windows native color parser accepts opaque ARGB
  values`.
- `flutter test --no-pub test/floating_lyrics_service_test.dart --reporter
  expanded -j 1` passed: 8/8.
- `flutter build windows --release --no-pub` passed and rebuilt
  `build/windows/x64/runner/Release/mconnect.exe`.
- `flutter test --no-pub --reporter expanded -j 1` passed: 197/197.

## 2026-05-31 - Package APK, Windows exe, portable zip, and setup

Built the requested release artifacts from branch
`codex/floating-lyrics-playback-regressions`, including the latest floating
lyrics and Android background playback fixes.

### Verification

- `flutter build apk --release --no-pub` passed.
- `flutter build windows --release --no-pub` passed.
- `Compress-Archive -Path build\windows\x64\runner\Release\* -DestinationPath
  build\windows\x64\Mconnect-windows-x64.zip -Force` passed.
- `C:\Users\PC\AppData\Local\Programs\Inno Setup 6\ISCC.exe
  installer\mconnect.iss` passed.

### Artifacts

- Android APK:
  `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\app\outputs\flutter-apk\app-release.apk`
- Android APK size: 81,098,876 bytes / 77.34 MB
- Android APK SHA256:
  `9DEF472DFEF370FAA7420A7800438DEA21A1502AF8C1EDBD13A3D8C3B0E256CA`
- Windows release exe:
  `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\windows\x64\runner\Release\mconnect.exe`
- Windows exe size: 223,232 bytes / 0.21 MB
- Windows exe SHA256:
  `1237F2177147FB20513CFA66008AC40091055D7DFD84BAAEC4B60D97F1592123`
- Windows portable zip:
  `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\windows\x64\Mconnect-windows-x64.zip`
- Windows portable zip size: 14,051,897 bytes / 13.40 MB
- Windows portable zip SHA256:
  `77262BA7F3F7E5CC24EBE53233423249B3022DDC5D8C3A306637CB86D91BE236`
- Windows setup:
  `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\windows\x64\Mconnect-Setup-1.2.0.exe`
- Windows setup size: 12,382,027 bytes / 11.81 MB
- Windows setup SHA256:
  `3CB3F624EACF849D7CB7E2D143AC3C700DE7346A3B3D1466A988376E9C5156C3`

## 2026-05-31 - Fix floating lyrics regressions and reassert Android background playback

Addressed regressions reported after the floating lyrics and Android background
playback changes: unclear desktop floating-lyrics color entry, blank Android
floating lyrics, Windows floating lyrics reopening after `X`, and renewed risk
of Android screen-off playback becoming silent while progress continues.

### Root Cause / Evidence

- Floating lyric text/highlight colors used the full picker internally, but the
  row only exposed a generic `Custom` chip and no quick color swatches, making
  the desktop entry easy to miss.
- Floating lyrics sync pushed an empty payload while lyrics were still loading
  or before the first timed line, so native overlays could be updated into an
  invisible blank state.
- A delayed sync could still finish after native `closedByUser`, see the old
  enabled settings, and call native `update()`, which reopened the Windows
  window.
- Android playback keep-alive skipped repeated `true` states by design; that
  was good for normal state changes but left no way to force reassertion when
  the app moves into the background.

### Changes

- Added visible quick swatches and a clear custom-color entry for floating lyric
  text/highlight colors while preserving the HSV full picker.
- Changed floating lyric payload selection to use the first visible lyric before
  its timestamp and to avoid sending empty native updates when lyrics are not
  ready.
- Added a sync generation guard around native close events so delayed updates
  cannot reopen a closed floating lyrics window.
- Added forced playback keep-alive reassertion and call it when the app enters
  inactive/paused/detached lifecycle states, without removing the existing
  `AudioService`, wake-lock, or Windows audio paths.

### Verification

- Red tests first failed for missing force reassertion, missing visible custom
  color entry, empty first-line payloads, empty native updates, and delayed
  close-event reopening.
- `flutter test --no-pub test/floating_lyrics_provider_test.dart
  test/settings_page_test.dart test/playback_keep_alive_service_test.dart
  test/player_provider_test.dart --reporter expanded -j 1` passed: 44/44.
- `flutter test --no-pub --reporter expanded -j 1` passed: 196/196.
- `flutter analyze --no-pub` still exits non-zero on the existing info-level
  lint baseline: 416 info issues.
- `flutter analyze --no-pub --no-fatal-infos` passed with the same 416 info
  issues and no error/warning-level failures.
- `flutter build apk --release --no-pub` passed and built
  `build/app/outputs/flutter-apk/app-release.apk` at 77.3 MB.

## 2026-05-31 - Fix floating lyrics controls, marquee speed, and color picker

Investigated Android floating lyrics controls disappearing, slow long-lyrics
marquee speed on Android and Windows, and Windows close events not updating the
settings switch.

### Root Cause / Evidence

- The Android native overlay only created lyric text views and the resize
  handle; the lock and close controls from the earlier Android parity work were
  no longer present in the current controller.
- The Windows native overlay sent `closedByUser`, but Flutter only listened for
  resize events, so the settings switch stayed enabled after closing the native
  floating window.
- Windows marquee speed was still `42 px/s` with a 900 ms delay, which made long
  lyric flow visibly too slow. Android used the platform `TextView` marquee with
  limited speed control.
- Floating lyric color settings were limited to preset swatches instead of a
  full color picker.

### Changes

- Restored Android floating lyric `LOCK` and `X` controls and wired them through
  the existing floating lyrics method channel.
- Added persisted floating lyric lock state and native `lockChanged` handling.
- Added Flutter handling for native `closedByUser` so the settings switch is
  turned off and persisted after closing the Windows or Android native overlay.
- Replaced Android long-lyrics marquee text with a small native fast marquee
  text view, and increased Windows marquee speed to `96 px/s` with a shorter
  delay.
- Changed floating lyric text and highlight colors from fixed swatches to an
  HSV full color picker. The app theme color presets are unchanged.

### Verification

- `flutter test --no-pub test/floating_lyrics_provider_test.dart
  test/floating_lyrics_service_test.dart test/settings_page_test.dart
  --reporter expanded -j 1` passed: 18/18.
- `flutter build apk --release --no-pub` passed.
- `flutter build windows --release --no-pub` passed.

## 2026-05-31 - Restore Android background playback and Windows audio loading

Investigated the reported regressions where Android audio became silent about
30 seconds after backgrounding, and Windows showed `00:00` duration with lyrics
loaded but audio not loaded.

### Root Cause / Evidence

- The earlier 30-second trial URL diagnosis did not match the new evidence:
  playback continues normally in the foreground and seeking past one minute
  still plays.
- `CHANGELOG.md` recorded Android background playback fixes, but the current
  tree had lost the actual `AudioService` notification bridge and native
  playback keep-alive channel. Commit `74e9614` kept only the orphan
  `_lastKeepAlivePlaying` field after conflict cleanup, while the controller
  wiring and service files were absent.
- Windows had `just_audio_windows` only through generated plugin metadata, not
  as a direct app dependency, and the player was again constructing
  `AndroidEqualizer` for every platform. That restored an Android-only audio
  pipeline on Windows, matching the symptom where lyrics/network data loaded
  but the desktop audio source stayed at `00:00`.
- The floating lyrics service had a native event parser for Windows resize
  events, but the method call handler was not attached to the channel.

### Changes

- Restored Android background playback support:
  - `lib/features/player/data/background_audio_initializer.dart`
  - `lib/features/player/data/playback_notification_service.dart`
  - `lib/features/player/data/playback_keep_alive_service.dart`
  - `android/app/src/main/kotlin/com/mconnect/mconnect/PlaybackKeepAliveController.kt`
- Made `MainActivity` extend `AudioServiceActivity`, registered the
  `com.ryanheise.audioservice.AudioService` service and
  `MediaButtonReceiver`, and re-added the `playback_keep_alive` method channel.
- Reconnected `PlayerNotifier` to notification updates and wake-lock state
  changes, including immediate keep-alive release on pause and dispose.
- Restored a platform guard so `AndroidEqualizer` is only created on Android;
  Windows now uses a plain `AudioPlayer` pipeline.
- Added direct dependencies on `audio_session` and `just_audio_windows`.
- Registered the floating lyrics native MethodChannel handler so Windows native
  resize events reach Flutter again.
- Updated Windows generated plugin CMake FFI list to include `jni`.

### Verification

- `flutter test --no-pub test/playback_keep_alive_service_test.dart
  test/playback_notification_service_test.dart test/player_provider_test.dart
  test/floating_lyrics_service_test.dart --reporter expanded -j 1` passed:
  36/36.
- `flutter build apk --release --no-pub` passed.
- `flutter build windows --release --no-pub` passed.
- `C:\Users\PC\AppData\Local\Programs\Inno Setup 6\ISCC.exe
  installer\mconnect.iss` passed.

### Artifacts

- Android APK:
  `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\app\outputs\flutter-apk\app-release.apk`
- Android APK size: 81,098,856 bytes / 77.34 MB
- Android APK SHA256:
  `CADCB8430CC8241250AE056C38D73414C231ED0B1E70C89907B27A44B60EC496`
- Windows release exe:
  `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\windows\x64\runner\Release\mconnect.exe`
- Windows exe size: 223,232 bytes / 0.21 MB
- Windows exe SHA256:
  `9D43D3415947F5C3CD944A7DA6F17CA5C8B37618B0858BC753EA22C0902205D2`
- Windows setup:
  `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\windows\x64\Mconnect-Setup-1.2.0.exe`
- Windows setup size: 12,378,688 bytes / 11.81 MB
- Windows setup SHA256:
  `724261C789387EA5C2172F359F06C7CFB0C4076D1FDCBDF80FE841BD3035B0A9`
- Windows portable zip:
  `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\windows\x64\Mconnect-windows-x64.zip`
- Windows portable zip size: 14,044,372 bytes / 13.39 MB
- Windows portable zip SHA256:
  `06D98EFB54BF3761156B62B602EDE5F604D123A032895DA395BCB5B9F365A42C`

## 2026-05-31 - Build Android APK and Windows packages

Built fresh Android and Windows release artifacts after the lyrics auto-scroll
and Netease trial-playback fixes.

### Build Fixes

- `android/app/src/main/kotlin/com/mconnect/mconnect/FloatingLyricsController.kt`
  - Removed stale Android floating-lyrics lock/close helper references that were
    not wired to the current controller constructor and caused release Kotlin
    compilation to fail.
  - Kept the active drag/resize handle and long-lyrics marquee behavior.
- Restored missing Windows Flutter runner scaffold files needed by CMake:
  `windows/flutter/CMakeLists.txt`, generated plugin registration files,
  `windows/runner/CMakeLists.txt`, `flutter_window.*`, `utils.*`,
  `resource.h`, and `runner.exe.manifest`.
  The runner CMake file includes the existing Windows floating-lyrics native
  sources.
- Cleared the stale Windows `.plugin_symlinks` cache after Flutter reported a
  `PathExistsException`; Flutter then recreated valid plugin symlinks.

### Verification

- `flutter build apk --release --no-pub` passed.
- `flutter build windows --release --no-pub` passed.
- `C:\Users\PC\AppData\Local\Programs\Inno Setup 6\ISCC.exe
  installer\mconnect.iss` passed.

### Artifacts

- Android APK:
  `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\app\outputs\flutter-apk\app-release.apk`
- Android APK size: 66,497,072 bytes / 63.42 MB
- Android APK SHA256:
  `6F47661DAB70AB154BA0EFB4620738EE6FD3305EBDA70D089E030CC3B49B66F1`
- Windows release exe:
  `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\windows\x64\runner\Release\mconnect.exe`
- Windows exe size: 223,232 bytes / 0.21 MB
- Windows exe SHA256:
  `914575308F7ACBC2DFD5B1F7618E08599E023929709CDD7DC6091D17E9059D1E`
- Windows setup:
  `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\windows\x64\Mconnect-Setup-1.2.0.exe`
- Windows setup size: 12,373,207 bytes / 11.80 MB
- Windows setup SHA256:
  `9F7607B45A60B89E181BAC1FB795A6D755828B7FE1DD91553F296B5E5C788D41`
- Windows portable zip:
  `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\windows\x64\Mconnect-windows-x64.zip`
- Windows portable zip size: 14,037,528 bytes / 13.39 MB
- Windows portable zip SHA256:
  `A280C0FD7C8F14C8ED3634313F99ECCC51B42B8BCBC99FA98667C27E292DDDC9`

## 2026-05-31 - Fix lyrics auto-scroll and reject Netease trial playback

Investigated two playback-page issues: full-screen lyrics did not follow the
current playback position, and some songs became silent around 35 seconds while
the progress bar continued.

### Root Cause / Evidence

- `LyricsDisplay` only used `Scrollable.ensureVisible()` on the active line's
  widget context. For later lyrics, that widget often had not been built yet by
  the virtualized `ListView`, so no scroll command ran and the offset stayed at
  zero.
- Netease playback responses can include a non-null `freeTrialInfo` together
  with a short trial URL. The old code logged `freeTrialInfo` but still returned
  the URL to the player. That matches the reported symptom: audio output stops
  after the trial segment, while the UI can still show playback progress.

### Changes

- `lib/features/player/presentation/widgets/lyrics_display.dart`
  - Added an estimated-offset fallback so the current lyric line scrolls toward
    the center even when its widget context is not currently built.
- `lib/platform/netease/netease_platform.dart`
  - Rejects trial-only playback responses instead of returning the short trial
    URL as a normal song URL.
- `test/lyrics_display_test.dart`
  - Added coverage proving the lyrics view scrolls down when playback reaches
    later lines.
- `test/netease_api_test.dart`
  - Added coverage proving Netease trial-only URLs are rejected.

### Verification

- `flutter test --no-pub test/lyrics_display_test.dart
  test/netease_api_test.dart test/player_provider_test.dart
  test/lyrics_line_test.dart --reporter expanded -j 1` passed: 32/32.

## 2026-05-31 - Diagnose GitHub large file push rejection

GitHub rejected the push because
`windows/flutter/ephemeral/flutter_windows.dll.pdb` is a generated Flutter
Windows debug symbol file larger than GitHub's 100 MB per-file limit.

### Evidence

- `git ls-files windows/flutter/ephemeral/flutter_windows.dll.pdb` showed the
  file is tracked.
- `git log --oneline --all -- windows/flutter/ephemeral/flutter_windows.dll.pdb`
  showed it entered history in commit `fdde6c4`.

### Local Prevention

- Added `windows/flutter/ephemeral/` and `*.pdb` to `.gitignore` so generated
  Windows build/debug artifacts are not committed again.

### Cleanup Result

- Rewrote the current branch history with `git filter-branch` to remove
  `windows/flutter/ephemeral/flutter_windows.dll.pdb`.
- Removed the `refs/original` backup ref, expired reflogs, and ran Git garbage
  collection so the oversized object is no longer retained locally.
- Verified both `git log --all -- windows/flutter/ephemeral/flutter_windows.dll.pdb`
  and `git ls-files windows/flutter/ephemeral/flutter_windows.dll.pdb` return no
  entries after cleanup.

## 2026-05-31 - Build Android APK after playback and window fixes

Built a fresh Android release APK after resolving leftover conflict markers from
the previous stash/apply state and restoring the Dart sources to a compilable
state.

### Verification

- `flutter build apk --release --no-pub` passed.

### Artifacts

- Android APK:
  `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\app\outputs\flutter-apk\app-release.apk`
- Android APK size: 66,530,184 bytes / 63.45 MB
- Android APK SHA256:
  `8617DAA27510B23B1120CC851223D21693BA7973E0B5651E167DD73899DBE8DA`

## 2026-05-31 - Fix playback race conditions and Windows close behavior

Investigated the reported intermittent playback skips and silent playback with
the progress bar still moving, then added targeted playback guards and refreshed
the Windows packages.

### Root Cause / Evidence

- A duplicate or stale `ProcessingState.completed` event could arrive while the
  next song was still loading. Because completion handling looked only at the
  current playlist state, that event could call `skipToNext()` again and skip
  over the song that had just been selected.
- Fade operations were asynchronous and had no generation guard. An older
  fade-out/fade-in task could continue writing volume after a newer playback
  request started, leaving the active player at a reduced volume until another
  next/previous operation reset the audio path.
- The Windows runner destroyed the main window immediately on `WM_CLOSE`, so
  closing the window exited the app instead of letting playback continue.

### Changes

- `lib/features/player/presentation/providers/player_provider.dart`
  - Ignores stale stream events from replaced audio controllers.
  - Ignores duplicate or premature completed events while a song is
    transitioning or while the position is not near the known duration.
  - Adds diagnostics for ignored completed events.
  - Adds fade generation tracking so stale fade tasks cannot change the current
    playback volume.
  - Restores volume to `1.0` after fade-enabled playback starts, preventing the
    active song from being left silent after an interrupted fade.
- `test/player_provider_test.dart`
  - Added regression coverage for duplicate completed events during next-song
    loading.
  - Added regression coverage for stale fade tasks after a pause/play race.
- `windows/runner/win32_window.cpp` / `windows/runner/win32_window.h`
  - Added close confirmation on Windows.
  - Choosing Yes minimizes the window and keeps playback running.
  - Choosing No exits Mconnect.
- `windows/runner/main.cpp`
  - Enabled the close confirmation behavior for the main app window.

### Verification

- `flutter test --no-pub test/player_provider_test.dart --reporter expanded -j 1`
  passed: 26/26.
- `flutter test --no-pub test/player_provider_test.dart
  test/playback_keep_alive_service_test.dart
  test/playback_notification_service_test.dart test/settings_page_test.dart
  --reporter expanded -j 1` passed: 39/39.
- `flutter build windows --release --no-pub` passed.
- Inno Setup 6.7.3 compile passed with
  `C:\Users\PC\AppData\Local\Programs\Inno Setup 6\ISCC.exe installer\mconnect.iss`.

### Artifacts

- Windows release exe:
  `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\windows\x64\runner\Release\mconnect.exe`
- Windows exe size: 223,744 bytes / 0.21 MB
- Windows exe SHA256:
  `F097135DE1B6FB9516D2C5FE545D51FEABF16DC3D6D1D2D9589C5A2F9AB3CBD9`
- Windows portable zip:
  `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\windows\x64\Mconnect-windows-x64.zip`
- Windows portable zip size: 14,063,927 bytes / 13.41 MB
- Windows portable zip SHA256:
  `7651A99B2C0D90B93BCE09AD25FD4425CF1F06AD59E2DB8D2CB34F86FFF42E9D`
- Windows setup:
  `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\windows\x64\Mconnect-Setup-1.2.0.exe`
- Windows setup size: 12,390,929 bytes / 11.82 MB
- Windows setup SHA256:
  `46D97EB3EB0C98066CF2F77FBA3D0430D1A172AC9CC030754A52D3023D236000`

## 2026-05-31 - Bump app version to 1.2.0

Updated the application version after the floating lyrics and Windows packaging
work.

### Changes

- `pubspec.yaml`
  - Updated Flutter package version from `1.1.0+1` to `1.2.0+1`.
- `lib/core/constants/app_constants.dart`
  - Updated `AppConstants.appVersion` to `1.2.0`.
- `lib/features/settings/presentation/pages/settings_page.dart`
  - Settings now displays `AppConstants.appVersion` instead of a duplicated
    hard-coded version string.
- `installer/mconnect.iss`
  - Updated installer version/output naming to `1.2.0`.
- `windows/runner/Runner.rc`
  - Updated the fallback Windows resource version string to `1.2.0`.
- `PROJECT.md`
  - Updated the project overview version to `1.2.0+1`.
- `test/settings_page_test.dart`
  - Added coverage that the settings page shows `1.2.0`.

### Verification

- `flutter pub get` completed and regenerated Flutter version metadata.
- `flutter test --no-pub test/settings_page_test.dart --reporter expanded -j 1`
  passed: 6/6.
- App-owned old version search found no remaining `1.1.0+1`, hard-coded
  settings `1.1.0`, `AppConstants.appVersion = '1.0.0'`, or installer
  `MyAppVersion "1.1.0"` values. Remaining `1.1.0` / `1.0.0` matches are
  third-party dependency versions, external API client versions, or historical
  changelog artifact records.
- `android/local.properties` generated by Flutter now contains
  `flutter.versionName=1.2.0` and `flutter.versionCode=1`.
- Windows `mconnect.exe` resource metadata reports:
  `FileVersion=1.2.0+1`, `ProductVersion=1.2.0+1`.
- `flutter build windows --release --no-pub` passed.
- `flutter build apk --release --no-pub` passed.
- Inno Setup 6.7.3 compile passed with
  `C:\Users\PC\AppData\Local\Programs\Inno Setup 6\ISCC.exe installer\mconnect.iss`.

### Artifacts

- Windows release exe:
  `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\windows\x64\runner\Release\mconnect.exe`
- Windows exe size: 223,744 bytes / 0.21 MB
- Windows exe SHA256:
  `902D5CFCA859FD1B7FEA6B3C88211D1750C120E544537BA0D47C2BD56E554675`
- Windows portable zip:
  `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\windows\x64\Mconnect-windows-x64.zip`
- Windows portable zip size: 14,062,655 bytes / 13.41 MB
- Windows portable zip SHA256:
  `A19362861940223313E4E4B221C95C1EDE78B9F944C182A7C0FF351E646AFE88`
- Windows setup:
  `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\windows\x64\Mconnect-Setup-1.2.0.exe`
- Windows setup size: 12,387,049 bytes / 11.81 MB
- Windows setup SHA256:
  `AC35330079D2A385FD961CC70CD8CEB9DBCE23064BEE9FAF3370BA2FD3569215`
- Android APK:
  `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\app\outputs\flutter-apk\app-release.apk`
- Android APK size: 66,775,944 bytes / 63.68 MB
- Android APK SHA256:
  `7E815716DBCE324132F8B055B9AD9AEDF98E70C07F143408658371B54AA1D419`

## 2026-05-31 - Rebuild floating lyrics marquee and Windows packages

Reworked the floating lyrics overlay after the previous Windows implementation
still clipped long lyrics and diverged from the Android interaction model.

### Root Cause / Evidence

- Android used native `TextView` instances with fixed line limits, so long
  lyric lines could be folded or clipped inside the overlay window.
- Windows used `DrawTextW(... DT_END_ELLIPSIS)`, which always truncated long
  lyrics instead of letting them flow.
- The previous Windows overlay added a separate resize mode button, while the
  Android overlay model is direct drag + bottom-right resize + lock/close.

### Changes

- `android/app/src/main/kotlin/com/mconnect/mconnect/FloatingLyricsController.kt`
  - Changed lyric and translation text views to single-line marquee text.
  - Long lyrics now flow from right to left; short lyrics remain centered.
- `windows/runner/floating_lyrics_window.cpp` /
  `windows/runner/floating_lyrics_window.h`
  - Rebuilt the native transparent topmost overlay window.
  - Added Android-parity interactions: drag when unlocked, bottom-right resize
    handle, lock button, close button, and close event.
  - Replaced ellipsis truncation with right-to-left marquee for long lyric and
    translation lines.
  - Starts the marquee timer only when text actually exceeds the visible area.
- `windows/runner/floating_lyrics_channel.cpp` /
  `windows/runner/floating_lyrics_channel.h`
  - Sends `lockChanged` with the actual lock boolean.
  - Sends `windowResized` with the native window size so Flutter can persist it.
- `lib/features/floating_lyrics/data/floating_lyrics_service.dart`
  - Added typed `windowResizedStream`.
- `lib/features/floating_lyrics/presentation/providers/floating_lyrics_provider.dart`
  - Persists native Windows resize events into floating lyric settings.
- `lib/features/settings/presentation/pages/settings_page.dart`
  - Updated Windows floating lyrics subtitle to show drag, resize, and lock
    support.
- `test/floating_lyrics_service_test.dart`
  - Added native resize event coverage.
- `test/floating_lyrics_provider_test.dart`
  - Added native resize persistence coverage.
- `installer/mconnect.iss`
  - Used with Inno Setup 6.7.3 to produce the final Windows setup installer.

### Verification

- `flutter test --no-pub test/floating_lyrics_service_test.dart
  test/floating_lyrics_provider_test.dart test/settings_page_test.dart
  --reporter expanded -j 1` passed: 17/17.
- `flutter test --no-pub --reporter expanded -j 1` passed: 191/191.
- `flutter analyze --no-pub`: `ERROR_COUNT=0`, `WARNING_COUNT=0`,
  `INFO_COUNT=415`; the command exits non-zero because existing info-level
  lints remain in the baseline.
- `flutter build windows --debug --no-pub` passed.
- `flutter build windows --release --no-pub` passed.
- `flutter build apk --release --no-pub` passed.
- Inno Setup compile passed with
  `C:\Users\PC\AppData\Local\Programs\Inno Setup 6\ISCC.exe installer\mconnect.iss`.

### Artifacts

- Windows release exe:
  `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\windows\x64\runner\Release\mconnect.exe`
- Windows exe size: 223,744 bytes / 0.21 MB
- Windows exe SHA256:
  `E30AAF400B0B0AEA02043DC08F31D0FA1FF0B59C188D66141AAB87E7702693D3`
- Windows portable zip:
  `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\windows\x64\Mconnect-windows-x64.zip`
- Windows portable zip size: 14,062,673 bytes / 13.41 MB
- Windows portable zip SHA256:
  `D7AF8D1689FEE818F9A74BB6114AEC9910603C30FA4221851A102BC4995DD39D`
- Windows setup:
  `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\windows\x64\Mconnect-Setup-1.1.0.exe`
- Windows setup size: 12,387,485 bytes / 11.81 MB
- Windows setup SHA256:
  `BCA56D816523B389E1BB973ACE6A0D1E48AEAE553F5F564818B341E75ACA083B`
- Android APK:
  `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\app\outputs\flutter-apk\app-release.apk`
- Android APK size: 66,775,944 bytes / 63.68 MB
- Android APK SHA256:
  `912DD888CD01FD231BF242083C19E75DE787E0603AC70B37B524A8562BBBC05A`

## 2026-05-31 - Add Windows floating lyrics drag, resize, close, and lock

Brought the Windows floating lyrics overlay to feature parity with Android:
draggable, resizable, closeable, and lockable.

### Changes

- `windows/runner/floating_lyrics_window.h`
  - Added `is_locked_`, `close_hovered_`, event callback, close button rect,
    resize border constants.
  - Updated `Show`/`Update` to accept `locked` parameter.
- `windows/runner/floating_lyrics_window.cpp`
  - Added `WM_NCHITTEST` handling: `HTCAPTION` for drag (when unlocked),
    `HTLEFT`/`HTRIGHT`/`HTTOP`/`HTBOTTOM`/corners for resize (when unlocked).
  - Added close button rendering (× icon in top-right with hover highlight).
  - Added `WM_LBUTTONDOWN` close button click sending `closedByUser` event.
  - Added `WM_MOUSEMOVE` close button hover tracking.
  - Added `WM_GETMINMAXINFO` minimum window size enforcement.
  - Added lock indicator in top-left when locked.
  - Window position preserved across updates (no re-centering).
  - Added rounded corners via `CreateRoundRectRgn`.
- `windows/runner/floating_lyrics_channel.h`
  - Added `SendEventToFlutter` method.
- `windows/runner/floating_lyrics_channel.cpp`
  - Reads `isLocked` from payload and passes to window.
  - Sets up event callback to invoke Flutter MethodChannel for native events.
- `lib/features/settings/presentation/pages/settings_page.dart`
  - Updated floating lyrics subtitle for Windows.
- `installer/mconnect.iss`
  - Added Inno Setup 6 installer script.

### Verification

- `flutter test --no-pub --reporter expanded -j 1` passed: 189/189.
- `flutter build windows --release --no-pub` passed.

### Verification

- `flutter test --no-pub --reporter expanded -j 1` passed: 189/189.
- `flutter analyze --no-pub`: `ERROR_COUNT=0`, `WARNING_COUNT=0`,
  `INFO_COUNT=415`; the command exits non-zero because existing info-level
  lints remain in the baseline.
- `flutter build windows --release --no-pub` passed.
- Windows release exe:
  `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\windows\x64\runner\Release\mconnect.exe`
- Windows exe size: 134,656 bytes / 0.13 MB
- Windows exe SHA256:
  `CBC889DC55F08F9E62BB425A0A57361AB31EB1F3E284A5D4A7EDABB383DD60FB`
- Windows exe LastWriteTime: `2026-05-31 12:40:36`
- Windows portable zip:
  `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\windows\x64\Mconnect-windows-x64.zip`
- Windows portable zip size: 13,957,673 bytes / 13.31 MB
- Windows portable zip SHA256:
  `6D0CD02DC3848F6620A0185EC312154A8DE5F17EA8C65B7CAF4D39CFA93F84AE`

## 2026-05-31 - Harden Android screen-off playback and notification controls

The previous Android media notification bridge added queue metadata and compact
previous/play-next controls, but the reported screen-off silence still showed a
remaining risk: the Android wake path could still be separated from the app's
actual playback state. This change adds an app-owned native keep-alive channel
that holds a `PARTIAL_WAKE_LOCK` only while Mconnect believes playback is active.

### Changes

- Added `lib/features/player/data/playback_keep_alive_service.dart`.
- Added Android native `PlaybackKeepAliveController`, exposed through
  `com.mconnect.mconnect/playback_keep_alive`.
- `PlayerNotifier` now synchronizes playback keep-alive state when playback
  starts, pauses, stops, or the notifier is disposed.
- Native Android code releases the wake lock from `MainActivity.onDestroy` as a
  final safety net.
- Kept the Android media notification controls as previous, play/pause, next,
  routed back to the existing playlist controls.

### Verification

- `flutter test --no-pub --reporter expanded -j 1` passed: 189/189.
- `flutter analyze --no-pub`: `ERROR_COUNT=0`, `WARNING_COUNT=0`,
  `INFO_COUNT=415`; the command exits non-zero because existing info-level
  lints remain in the baseline.
- `flutter build apk --release --no-pub` passed.
- Android APK:
  `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\app\outputs\flutter-apk\app-release.apk`
- Android APK size: 66,775,944 bytes / 63.68 MB
- Android APK SHA256:
  `D4B72D6A291C2C47FA994F692B89F74DCF84AC4ACE4E6BB6CAFC5B18CB5D7DEA`
- Android APK LastWriteTime: `2026-05-31 12:14:52`

## 2026-05-31 - Rework Android playback notification bridge

Replaced the previous single-source background metadata path with an app-owned
`audio_service` bridge for Android playback notifications.

### Root Cause / Evidence

- The previous fix only tagged the current `just_audio` source with a
  `MediaItem`. That is enough for title/art metadata, but it does not give the
  Android media notification a queue.
- Local `just_audio_background` source shows previous/next notification buttons
  are only emitted when its internal sequence has previous/next items. Mconnect
  loads one source at a time, so the system notification had no way to know the
  app playlist.
- The persistent screen-off silence also pointed to the simple wrapper being
  insufficient: playback state lived mostly in Flutter UI state, while Android
  needed a foreground media session with current playing state.

### Changes

- Added `lib/features/player/data/playback_notification_service.dart`.
- Declared direct `audio_service` and `audio_session` dependencies.
- Configured the Android audio session with `AudioSessionConfiguration.music()`.
- Initialized an app-owned `AudioService` handler with
  `androidStopForegroundOnPause: false` to keep the foreground media service
  stable across pause/resume and background transitions.
- Synchronized the current song, playlist queue, index, position, duration, and
  playing state from `PlayerNotifier` into the media session.
- Added compact Android notification controls in this order: previous,
  play/pause, next.
- Routed notification previous/next/play/pause/seek callbacks back to the
  existing `PlayerNotifier` methods.
- Kept the existing non-Android playback path unchanged.

### Verification

- Added tests for notification media controls, queue mapping, handler callbacks,
  queue/media/playback state publishing, and PlayerNotifier notification sync.
- `flutter test --no-pub test/playback_notification_service_test.dart
  test/player_provider_test.dart --reporter expanded -j 1` passed: 26/26.
- `flutter test --no-pub --reporter expanded -j 1` passed: 184/184.
- `flutter analyze --no-pub`: `ERROR_COUNT=0`, `WARNING_COUNT=0`,
  `INFO_COUNT=415`; the command exits non-zero because info-level lints remain
  in the existing baseline.
- `flutter build apk --release --no-pub` passed.
- Android APK:
  `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\app\outputs\flutter-apk\app-release.apk`
- Android APK size: 66,775,944 bytes / 63.68 MB
- Android APK SHA256:
  `FEE507DBFE69082578EFFE5B0EFD5C8194C842849EAE19A1395BF2179632B520`
- Android APK LastWriteTime: `2026-05-31 11:42:31`

## 2026-05-31 - Add floating lyrics close and lock controls

Added direct controls on the Android floating lyrics overlay.

### Changes

- Added a native `X` control on the floating lyrics window. Tapping it removes
  the overlay and sends a `closedByUser` event back to Flutter.
- Flutter now listens for native floating lyrics events and persists the app
  switch as disabled when the user closes the overlay from the window itself.
- Added a persistent `isLocked` floating lyrics setting.
- Added a native `LOCK` / `MOVE` control on the overlay. `LOCK` disables window
  dragging and resizing; `MOVE` restores dragging and resizing. The close
  control remains usable while locked.
- Added dark text and highlight presets for floating lyrics colors while keeping
  the existing light presets.

### Verification

- Added tests for persisted lock state, native close event switch sync, native
  lock event persistence, `isLocked` channel payloads, and dark color presets.
- `flutter test --no-pub test/floating_lyrics_provider_test.dart
  test/floating_lyrics_service_test.dart test/settings_page_test.dart
  --reporter expanded -j 1` passed: 15/15.
- `flutter test --no-pub --reporter expanded -j 1` passed: 178/178.
- `flutter analyze --no-pub`: `ERROR_COUNT=0`, `WARNING_COUNT=0`,
  `INFO_COUNT=415`; the command exits non-zero because info-level lints remain
  in the existing baseline.
- `flutter build apk --release --no-pub` passed.
- Android APK:
  `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\app\outputs\flutter-apk\app-release.apk`
- Android APK size: 66,825,096 bytes / 63.73 MB
- Android APK SHA256:
  `0B590888B3EE8411909086BA4BC144D5F179CCDB965880FE32F7821FC59E6B8A`
- Android APK LastWriteTime: `2026-05-31 11:10:24`

## 2026-05-31 - Fix Android playback silence after screen off

Added real Android background media playback support for the mobile app.

### Root Cause / Evidence

- The app declared `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_MEDIA_PLAYBACK`,
  and `WAKE_LOCK`, but no Android media playback service or media button
  receiver was registered.
- The Flutter playback layer used a plain `just_audio` `setUrl` path, so loaded
  sources had no `MediaItem` metadata for a background media session.
- This matches the user symptom: after screen-off/background time, the UI could
  still believe playback was active while Android had no foreground media
  service keeping the audio pipeline healthy. Switching tracks rebuilt the
  audio source, which restored audible output.

### Changes

- Added `just_audio_background`.
- Initialized Android background audio before the app creates its first
  `AudioPlayer`.
- Changed Android source loading to use
  `AudioSource.uri(..., tag: MediaItem(...))`, preserving the existing direct
  `setUrl` path on non-Android platforms.
- Registered `com.ryanheise.audioservice.AudioService` and
  `MediaButtonReceiver` in `AndroidManifest.xml`.
- Made the existing custom `MainActivity` extend `AudioServiceActivity` so the
  previous file-opener and floating-lyrics MethodChannels remain in place.

### Verification

- Added a regression test proving Android playback sources include `MediaItem`
  metadata.
- `flutter test --no-pub test/player_provider_test.dart test/widget_test.dart
  --reporter expanded -j 1` passed: 34/34.
- `flutter test --no-pub --reporter expanded -j 1` passed: 175/175.
- `flutter analyze --no-pub`: `ERROR_COUNT=0`, `WARNING_COUNT=0`,
  `INFO_COUNT=415`; the command exits non-zero because info-level lints remain
  in the existing baseline.
- `flutter build apk --release --no-pub` passed.
- Android APK:
  `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\app\outputs\flutter-apk\app-release.apk`
- Android APK size: 66,825,096 bytes / 63.73 MB
- Android APK SHA256:
  `25CBA0EC7CDF18C7318F22D42EB9DB6F48DFAD8B0C36268B6300836D7835DFB5`
- Android APK LastWriteTime: `2026-05-31 10:48:58`

## 2026-05-31 - Build Windows desktop MVP

Implemented the first Windows desktop build pass while preserving Android
behavior.

### Root Cause / Build Findings

- `flutter build windows --debug --no-pub` initially failed in
  `permission_handler_windows` because the current MSVC toolchain treats
  `<experimental/coroutine>` deprecation as a hard error.
- The plan initially suggested deleting `permission_handler`, but a full
  non-ignored search showed `DownloadManager` still uses it for Android storage
  permission requests. Removing it would risk changing existing Android download
  behavior.
- `just_audio` needed an explicit Windows backend; `just_audio_windows` resolved
  cleanly and registered as a Windows plugin.
- `just_audio_windows` also needed the coroutine suppression macro, plus
  `/utf-8` to avoid C4819 encoding warnings being promoted to errors.

### Changes

- Created branch `codex/windows-desktop-port`.
- Added `just_audio_windows` and removed unused `audio_service` and
  `mobile_scanner`.
- Kept `permission_handler` for Android downloads and scoped Windows CMake
  compile definitions to `permission_handler_windows_plugin` and
  `just_audio_windows_plugin`.
- Added `PlatformUtils` with test overrides.
- Made `AndroidEqualizer` optional so Windows does not create Android audio
  effects.
- Added Windows `FileOpener` support via `explorer.exe` and `cmd /c start`,
  while preserving the Android MethodChannel path.
- Disabled MVP-unimplemented Windows floating lyrics and Android-native
  equalizer controls in Settings.
- Configured Windows runner title, initial size, and minimum resize bounds.

### Verification

- `flutter test --no-pub --reporter expanded -j 1` passed: 174/174.
- `flutter analyze --no-pub`: `ERROR_COUNT=0`, `WARNING_COUNT=0`,
  `INFO_COUNT=415`; the command exits non-zero because info-level lints remain
  in the existing baseline.
- `flutter build windows --debug --no-pub` passed.
- `flutter build windows --release --no-pub` passed.
- Windows release exe:
  `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\windows\x64\runner\Release\mconnect.exe`
- Windows exe size: 91,648 bytes / 0.09 MB
- Windows exe SHA256:
  `0C45CE747597E2288D583CB957E457D38A1A8A2785A14A31B80E396D3B4A949F`
- Windows exe LastWriteTime: `2026-05-31 00:30:08`
- Release folder includes `flutter_windows.dll`, plugin DLLs, SQLite DLLs, and
  `data/`.
- Windows portable zip:
  `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\windows\x64\Mconnect-windows-x64.zip`
- Windows portable zip size: 13,921,263 bytes / 13.28 MB
- Windows portable zip SHA256:
  `5D63DF040F513D1FA653FDCCBD4930B4993580888D59829D44436A993AC44EDE`
- Windows portable zip LastWriteTime: `2026-05-31 00:38:49`
- Portable zip smoke test extracted to
  `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\windows\x64\portable-test-20260531003905`.
  The extracted `mconnect.exe` started and did not exit within 5 seconds; the
  test process was then closed.
- Android regression gate: `flutter build apk --release --no-pub` passed.
- Android APK:
  `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\app\outputs\flutter-apk\app-release.apk`
- Android APK size: 66,491,964 bytes / 63.41 MB
- Android APK SHA256:
  `1E847C8A490E473E3388ED1FCF6B922CDDC638884B2BCC4ADDE9D8B6AF170E95`
- Android APK LastWriteTime: `2026-05-31 00:31:43`

## 2026-05-31 - Rewrite Windows desktop port plan

Replaced the earlier optimistic Windows desktop migration plan with an
MVP-first, build-evidence-driven plan.

### Findings

- `windows/` has already been generated, but `.metadata` needs to track both
  `web` and `windows`.
- A real Windows debug build failed in `permission_handler_windows` with MSVC's
  `<experimental/coroutine>` deprecation error.
- `permission_handler`, `mobile_scanner`, and `audio_service` are present in
  `pubspec.yaml` but are not imported by current Dart source or tests.
- `just_audio` does not provide Windows playback by itself in this project;
  current package documentation requires an additional Windows implementation.
- `dart pub add --dry-run just_audio_windows` resolves successfully with one
  added dependency, making it the preferred MVP backend.

### Changes

- `docs/superpowers/plans/2026-05-30-windows-desktop-port-plan.md`
  - Marked as superseded.
- `docs/superpowers/plans/2026-05-31-windows-desktop-port-plan.md`
  - Added a complete executable plan covering dependency cleanup, platform
    detection, Android-only equalizer gating, Windows file opening, floating
    lyrics MVP gating, window configuration, playback validation, Windows
    release build, packaging, and optional Win32 floating lyrics parity.

## 2026-05-30 - Handle missing floating lyrics native channel

Prevented startup floating lyrics synchronization from writing global
`MissingPluginException` errors when the optional Android floating lyrics method
channel is unavailable.

### Root Cause

- `MconnectApp` creates `floatingLyricsSyncProvider` during app startup.
- When floating lyrics are disabled, `FloatingLyricsSyncController.sync()` calls
  `FloatingLyricsService.hide()` to make sure no overlay remains visible.
- If the currently running APK/engine has no handler registered for
  `com.mconnect.mconnect/floating_lyrics`, `MethodChannel.invokeMethod('hide')`
  throws `MissingPluginException`.
- The exception was not handled in the optional floating lyrics service, so it
  bubbled into `runZonedGuarded` and was recorded as an app-level error.

### Changes

- `lib/features/floating_lyrics/data/floating_lyrics_service.dart`
  - Treats `MissingPluginException` as "floating lyrics native capability is
    unavailable" and returns `false` for optional overlay calls.
  - Keeps other platform exceptions visible instead of swallowing unrelated
    native failures.
- `test/floating_lyrics_service_test.dart`
  - Added regression coverage proving `hide()` returns `false` instead of
    throwing when the native overlay channel is unavailable.

### Verification

- Red test first failed with `MissingPluginException(No implementation found for method hide on channel com.mconnect.mconnect/floating_lyrics)`.
- `flutter test --no-pub test/floating_lyrics_service_test.dart --reporter expanded -j 1` passed: 4/4.
- `flutter test --no-pub --reporter expanded -j 1` passed: 166/166.
- `flutter analyze --no-pub`: `ERROR_COUNT=0`, `WARNING_COUNT=0`, `INFO_COUNT=415`; the command exits non-zero because info-level lints remain in the existing baseline.
- `flutter build apk --release --no-pub` passed.
- APK path: `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\app\outputs\flutter-apk\app-release.apk`
- Size: 80,836,344 bytes / 77.09 MB
- SHA256: `31EA54A3404E6746B3FA2399B4FAB7DBF5607CF73000021ACA016C80A6BFD7A3`
- LastWriteTime: `2026-05-30 23:27:52`

## 2026-05-30 - Fix listening stats page stuck loading

Fixed the Listening Stats page staying on the loading spinner forever after opening it from the Music Library.

### Root Cause

- `ListeningStatsNotifier` initialized with `isLoading: true`.
- Its initial load was stored as `late final Future<void> ready = load()`.
- In Dart, a `late final` field with an initializer is lazy; `load()` only runs when `ready` is first read.
- Tests explicitly awaited `notifier.ready`, but the production page only watched `listeningStatsProvider` state and never read `ready`.
- Therefore the page could enter with `isLoading: true` and no load operation running, leaving the UI permanently on `CircularProgressIndicator`.

### Changes

- `lib/features/stats/presentation/providers/listening_stats_provider.dart`
  - Changed `ready` to a constructor-started future so `load()` begins as soon as the notifier is created.
- `test/listening_stats_provider_test.dart`
  - Added regression coverage proving listening stats starts loading without explicitly reading `ready`.

### Verification

- Red test first failed because `notifier.state.isLoading` remained `true` when `ready` was not read.
- `flutter test --no-pub test/listening_stats_provider_test.dart --reporter expanded -j 1` passed: 3/3.
- `flutter test --no-pub --reporter expanded -j 1` passed: 165/165.
- `flutter analyze --no-pub`: `ERROR_COUNT=0`, `WARNING_COUNT=0`, `INFO_COUNT=415`; the command exits non-zero because info-level lints remain in the existing baseline.

## 2026-05-30 - Release APK after Kugou Concept playlist fix

Built a release APK for device testing after fixing Kugou Concept/Lite cloud playlist request identity and playlist creation routing.

### Verification

- `flutter build apk --release --no-pub` passed.
- APK path: `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\app\outputs\flutter-apk\app-release.apk`
- Size: 80,836,344 bytes / 77.09 MB
- SHA256: `074296C2B7E815F96DFC8946F9F2A90BFC24178FB9723619AB07E184C946CBCC`
- LastWriteTime: `2026-05-30 22:53:58`

## 2026-05-30 - Fix Kugou Concept playlist cloudlist requests

Fixed Kugou Concept/Lite accounts still failing to load user playlists and create new playlists after login.

### Root Cause

- The login page defaults Kugou to Concept/Lite mode, and the session correctly persists `client: lite`.
- The cloud playlist APIs did not reuse that client mode:
  - `getUserPlaylists()` signed requests as ordinary Kugou Android (`appid=1005`, `clientver=20489`) instead of Concept/Lite (`appid=3116`, `clientver=11440`).
  - `getUserPlaylistSongs()` had the same client identity mismatch for user `listid` detail fallback.
  - `createPlaylist()` also signed as ordinary Android and omitted the required `x-router: cloudlist.service.kugou.com` gateway header.
- As a result, real Concept/Lite sessions could be logged in but still rejected or treated inconsistently by Kugou cloudlist endpoints.

### Changes

- `lib/platform/kugou/kugou_api.dart`
  - `getUserPlaylists()` now signs cloudlist requests with the current `_clientMode`.
  - `getUserPlaylistSongs()` now signs user playlist detail requests with the current `_clientMode`.
  - `createPlaylist()` now signs with the current `_clientMode` and sends the cloudlist `x-router` header.
- `test/kugou_login_test.dart`
  - Added red-green coverage for Concept/Lite playlist list, user playlist songs, and playlist creation request identity/router behavior.

### Verification

- Red tests first failed because Concept playlist requests used `appid=1005` instead of `3116`, and create playlist had no cloudlist `x-router` header.
- `flutter test --no-pub test/kugou_login_test.dart --reporter expanded -j 1` passed: 17/17.
- `flutter test --no-pub test/kugou_login_test.dart test/kugou_playlist_test.dart test/platform_playlists_provider_test.dart --reporter expanded -j 1` passed: 34/34.
- `flutter test --no-pub --reporter expanded -j 1` passed: 164/164.
- `flutter analyze --no-pub`: `ERROR_COUNT=0`, `WARNING_COUNT=0`, `INFO_COUNT=415`; the command exits non-zero because info-level lints remain in the existing baseline.

## 2026-05-30 - Fix Kugou playlist loading race condition

Fixed Kugou playlists not loading and new playlist creation failing due to a session restoration timing issue.

### Root Cause

- `authProvider.notifier.init()` is called without `await` in `app.dart`, so session restoration runs asynchronously in the background.
- `PlatformPlaylistsPage` loads playlists in a `postFrameCallback` immediately after the widget builds.
- `loadPlatform()` checks `platform.isLoggedIn` before calling `getUserPlaylists()`, but if `restoreSession()` hasn't completed yet, `KugouPlatform._currentUser` is still `null` �?`isLoggedIn` returns `false` �?playlists are silently skipped.
- The existing code was structurally correct but had no mechanism to reload playlists after session restore completed.

### Changes

- `lib/features/library/presentation/pages/platform_playlists_page.dart`: added `ref.listenManual(authProvider, ...)` that triggers `load()` when new users appear in auth state after session restore completes.

### Verification

- `flutter test --no-pub --reporter expanded -j 1` passed: 161/161.
- `flutter build apk --release --no-pub` passed.
- APK path: `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\app\outputs\flutter-apk\app-release.apk`
- Size: 80,836,344 bytes / 77.09 MB
- SHA256: `8FC837256207CE461E991FE415A6B42AEB181289FE349D094C9045626B89595A`

## 2026-05-30 - Fix theme color persistence and startup flash

Fixed theme color (and audio effects / floating lyrics settings) not persisting across app restarts, and eliminated the brief flash of default color on startup.

### Root Cause

- `ThemeSettingsNotifier`, `AudioEffectsSettingsNotifier`, and `FloatingLyricsNotifier` all used `late final Future<void> ready = _load()`.
- In Dart, `late final` with an initializer is lazily evaluated �?the expression only runs when the field is first read.
- No production code ever read `ready`, so `_load()` never executed. The Hive box was never opened on startup, and saved settings were silently ignored.
- Even after fixing eager execution, `_load()` was async (`await Hive.openBox()`), so the first frame still rendered with defaults before the saved value arrived.

### Changes

- `lib/main.dart`: pre-open the `'settings'` Hive box before `runApp()` so it is available synchronously.
- `lib/core/theme/theme_provider.dart`: `_load()` now reads `Hive.box()` synchronously; `ready` kept as `Future.value()` for test compatibility.
- `lib/features/audio_effects/presentation/providers/audio_effects_provider.dart`: same pattern.
- `lib/features/floating_lyrics/presentation/providers/floating_lyrics_provider.dart`: same pattern.
- Test files: added `await Hive.openBox('settings')` in `setUp()` for all affected test suites.

### Verification

- `flutter test --no-pub --reporter expanded -j 1` passed: 161/161.
- `flutter build apk --release --no-pub` passed.
- APK path: `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\app\outputs\flutter-apk\app-release.apk`
- Size: 80,836,344 bytes / 77.09 MB
- SHA256: `50A9BCCEAB1946B1DD8C4DFC7EB53F5CDAF3F6D3A5753F4CACB60F0F7197D679`

## 2026-05-30 - Release APK after equalizer cache and smart playlists

Built a release APK for device testing after adding the equalizer, Offline Cache Center, and smart playlist rule editor.

### Verification

- `flutter build apk --release --no-pub` passed.
- APK path: `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\app\outputs\flutter-apk\app-release.apk`
- Size: 80,770,808 bytes / 77.03 MB
- SHA256: `85B223A1887DC884C52C63408734C3EA3EEB478A97EE906B499189E3C1E3B2CB`
- LastWriteTime: `2026-05-30 19:24:21`

## 2026-05-30 - Equalizer, offline cache center, and smart playlists

Implemented the higher-risk enhancement batch with focused regression coverage before production code.

### Changes

- Added Android equalizer support through `just_audio` audio effects:
  - persisted equalizer switch, preset, and five-band gain settings;
  - settings-page equalizer controls;
  - guarded player application with a short timeout so unsupported devices do not block playback.
- Added an Offline Cache Center:
  - persisted cache size limit, Wi-Fi-only, auto retry, auto cleanup, and offline mode settings;
  - Music Library entry and `/offline-cache` route;
  - download queue cache helpers with duplicate avoidance and cache-task marking;
  - oldest-completed-cache cleanup based on the configured size limit.
- Added local smart playlists:
  - persisted rule model and repository;
  - generator filters by platform, keyword, minimum play count, recently played window, liked-only, and cached-only;
  - Music Library entry plus list/editor routes;
  - preview/play behavior uses already-loaded local likes, history, stats, and cache state without network calls.
- Fixed a new lazy-load bug found during testing by starting new notifier `ready` futures in constructors, so pages do not remain in a loading state when nothing explicitly awaits `ready`.

### Verification

- Red tests first failed for missing offline cache provider/page, missing `DownloadNotifier.cacheSongs`, and missing smart playlist modules.
- `flutter test --no-pub test\audio_enhancement_settings_test.dart test\player_provider_test.dart test\settings_page_test.dart test\offline_cache_provider_test.dart test\offline_cache_page_test.dart test\smart_playlist_rule_test.dart test\smart_playlist_generator_test.dart test\smart_playlists_provider_test.dart test\smart_playlists_page_test.dart --reporter expanded -j 1` passed: 33/33.
- `flutter test --no-pub --reporter expanded -j 1` passed: 161/161.
- `flutter analyze --no-pub`: `ERROR_COUNT=0`, `WARNING_COUNT=0`, `INFO_COUNT=415`; the command exits non-zero because info-level lints remain in the existing project/scripts baseline.

## 2026-05-30 - Release APK after music library scrolling fix

Built a release APK for device testing after fixing the compact-screen Music Library scrolling issue.

### Verification

- `flutter build apk --release --no-pub` passed.
- APK path: `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\app\outputs\flutter-apk\app-release.apk`
- Size: 80,475,156 bytes / 76.75 MB
- SHA256: `A1E70F354A931B964DB652B601AC04C08BD3942ED1DC779560FFF9A801EF6C57`
- LastWriteTime: `2026-05-30 18:47:47`

## 2026-05-30 - Fix music library compact-screen scrolling

Fixed the Music Library page being unable to scroll on compact screens, which could leave the Settings entry hidden behind the always-visible mini player.

### Root Cause

- `LibraryScreen` used a fixed `Column` inside `SafeArea`.
- After adding more library entries and keeping `MiniPlayerBar` at the bottom of `HomeScreen`, the fixed column could overflow vertically and the lower entries were not reachable by touch or scroll.

### Changes

- Replaced the fixed `Column` in `LibraryScreen` with the project-standard `AppScrollbar` plus `ListView`.
- Added bottom padding to the library list so the last entry remains comfortably above the mini player and bottom navigation area.
- Added a compact-screen widget regression test that opens the Music Library tab with a visible mini player, scrolls to Settings, and verifies the Settings route can still be opened.

### Verification

- Red test first failed with a `LibraryScreen` bottom overflow and no descendant `Scrollable`.
- `flutter test --no-pub test\widget_test.dart --name "library tab scrolls to settings" --reporter expanded -j 1` passed.
- `flutter test --no-pub test\widget_test.dart --reporter expanded -j 1` passed: 14/14.
- `flutter test --no-pub --reporter expanded -j 1` passed: 149/149.
- `flutter analyze --no-pub` severity count: `ERROR_COUNT=0`, `WARNING_COUNT=0`, `INFO_COUNT=415`; remaining items are existing info-level lints.

## 2026-05-30 - Release APK after low-risk enhancements

Built a release APK for device testing after the low-risk listening stats, sleep timer, and fade switch changes.

### Verification

- `flutter build apk --release --no-pub` passed.
- APK path: `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\app\outputs\flutter-apk\app-release.apk`
- Size: 80,475,156 bytes / 76.75 MB
- SHA256: `8610999521D9EB29D78DD0C0C1EB81176E9470F440596C2E30406ED526E86167`
- LastWriteTime: `2026-05-30 18:31:52`

## 2026-05-30 - Low-risk listening stats, sleep timer, and fade switch

Implemented the first low-risk batch from the larger enhancement plan.

### Changes

- Added local listening statistics backed by Hive:
  - total play count;
  - accumulated real listening duration;
  - top song list;
  - Music Library entry and `/listening-stats` route.
- Added an app-level playback statistics tracker that records starts and counts only small forward position deltas, ignoring large seek jumps.
- Added audio enhancement settings backed by Hive:
  - fade in/out switch, disabled by default;
  - fade duration slider;
  - sleep timer duration slider.
- Added a sleep timer provider that pauses playback when the countdown expires and cancels cleanly when switched off.
- Added guarded volume control to the player abstraction for optional fade in/out.
- Kept this batch away from platform APIs, download routing, and SQLite migrations to reduce regression and freeze risk.

### Verification

- Red tests first failed for missing audio effects, sleep timer, listening stats, and player fade APIs.
- `flutter test --no-pub test\audio_enhancement_settings_test.dart test\listening_stats_provider_test.dart test\sleep_timer_provider_test.dart test\player_provider_test.dart test\settings_page_test.dart --reporter expanded -j 1` passed: 25/25.
- `flutter test --no-pub --reporter expanded -j 1` passed: 148/148.
- `flutter analyze --no-pub`: `ERROR_COUNT=0`, `WARNING_COUNT=0`, `INFO_COUNT=415`; remaining items are info-level lints.

## 2026-05-30 - Transparent floating lyrics and custom theme color

Implemented user-selectable theme color and Android floating lyrics overlay.

### Changes

- Added `ThemeSettings` persistence for both theme mode and Material 3 seed color.
- Updated app theme creation so selected theme color applies to light and dark themes.
- Added settings-page controls for theme color presets.
- Added floating lyrics settings with transparent background by default:
  - enable/disable desktop floating lyrics;
  - request/open Android overlay permission settings;
  - choose lyric text color and highlight color;
  - adjust font size, stroke strength, and shadow strength.
- Added Flutter MethodChannel service for floating lyrics: permission check, open settings, show, update, and hide.
- Added lyric sync controller that maps current playback position to the active timed lyric line and sends it to the native overlay.
- Added Android `SYSTEM_ALERT_WINDOW` permission and native `WindowManager` overlay implementation.
- Native overlay uses a transparent background, text shadow for readability, drag-to-move, and bottom-right resize handling.
- Cleaned the settings page Chinese labels while touching that UI.

### Verification

- Red tests first failed for missing theme settings, floating lyrics service/provider, and settings UI controls.
- `flutter test --no-pub test\theme_provider_test.dart test\floating_lyrics_service_test.dart test\floating_lyrics_provider_test.dart test\settings_page_test.dart --reporter expanded -j 1` passed: 10/10.
- `flutter test --no-pub --reporter expanded -j 1` passed: 139/139.
- `flutter analyze --no-pub`: `ERROR_COUNT=0`, `WARNING_COUNT=0`, `INFO_COUNT=416`; remaining items are existing info-level lints.
- `flutter build apk --release --no-pub` passed.
- APK path: `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\app\outputs\flutter-apk\app-release.apk`
- Size: 80,360,120 bytes / 76.64 MB
- SHA256: `D329607B776900B16C4D5E1A1ABB9522D148E82012B2A845837F3C55C63844FE`
- LastWriteTime: `2026-05-30 17:53:46`

## 2026-05-30 - Floating lyrics preview background adjustment

Updated the local visual preview for the planned floating lyrics feature.

### Changes

- Changed the floating lyrics mockup background to fully transparent.
- Added stronger text shadow and light stroke in the mockup so lyrics remain readable over complex app backgrounds.
- Updated the planned style copy to make transparent background the default behavior.

### Verification

- Inspected `docs/superpowers/mockups/floating-lyrics-theme-preview.html`.
- This is a local ignored mockup only; no Flutter or Android runtime code was changed.

## 2026-05-30 - Preserve playback quality preference across songs

Fixed playback quality being reset to standard quality whenever a new song starts.

### Root Cause

- `PlayerNotifier.playSong()` forced `currentQuality` back to `AudioLevel.low` for every new song.
- The new-song URL request also omitted the selected quality, so platform playback always used the default standard-quality route.

### Changes

- Added `AudioQualityPreference` with fixed-quality and highest-quality modes.
- `playSong()` now resolves the effective playback quality before requesting the song URL:
  - fixed mode keeps the user's selected quality for the next song;
  - highest mode fetches the new song's available qualities and selects that song's highest available quality;
  - if available qualities cannot be loaded, playback falls back to the last effective quality.
- The quality picker now treats tapping the highest available quality as "always use highest quality".
- Playback memory now persists the quality preference so it survives app restarts.
- Added regression tests for fixed-quality carryover, highest-quality carryover, and quality preference persistence.

### Verification

- `flutter test --no-pub test\player_provider_test.dart --reporter expanded -j 1` passed: 14/14.
- `flutter test --no-pub --reporter expanded -j 1` passed: 130/130.
- `flutter analyze --no-pub`: `ERROR_COUNT=0`, `WARNING_COUNT=0`, `INFO_COUNT=416`; remaining items are existing info-level lints.

## 2026-05-29 - Rename project folder to Mconnect-Music_connect

Renamed the project directory from `Mconnect` to `Mconnect-Music_connect` and verified the app still works from the new path.

### Changes

- Moved the project to `D:\Code_Work\My_Projects\Mconnect-Music_connect`.
- Removed the old `D:\Code_Work\My_Projects\Mconnect` residual directory after confirming it only contained leftover generated build cache from the interrupted move.
- Updated current local project documentation path references in `PROJECT.md`.

### Verification

- `flutter clean` passed from the new directory.
- `flutter pub get` passed from the new directory.
- `flutter test --no-pub --reporter expanded -j 1` passed: 127/127.
- `flutter analyze --no-pub` check: `ERROR_COUNT=0`, `WARNING_COUNT=0`, `INFO_COUNT=417`; the remaining items are existing info-level lints.
- `flutter build apk --release --no-pub` passed from the new directory.
- APK path: `D:\Code_Work\My_Projects\Mconnect-Music_connect\build\app\outputs\flutter-apk\app-release.apk`
- Size: 79,884,024 bytes / 76.18 MB
- SHA256: `9CA01DC1AC79DBF0F6C94BEE6086996D254C8D0B6208090B7C51232FA0641DC5`
- LastWriteTime: `2026-05-29 20:29:55`
- `OLD_PATH_REFERENCE_COUNT=0` for active project files, excluding historical changelog entries.

## 2026-05-29 - Add MIT license

Added a project license file.

### Changes

- Added `LICENSE` with the MIT License text.

### Verification

- Inspected `LICENSE`.
- `git check-ignore -v -- LICENSE` reports `VISIBLE`, so the license file is not ignored and can be uploaded with the project.

## 2026-05-29 - Personal data ignore audit

Rechecked upload visibility and expanded ignore rules for personal runtime data.

### Changes

- Expanded `.gitignore` to cover common copied personal data folders: downloads, local music, playlist exports, backups, app data, shared preferences, databases, cache, cookies, sessions, tokens, and account exports.
- Added media, lyric, playlist, archive, backup, and JSONL runtime-output extensions to the ignore rules.
- Added common standalone cookie, token, session, secret, and account export filename patterns.

### Verification

- `git check-ignore -v` confirms typical personal/runtime paths are ignored: APK/build outputs, `.dart_tool`, `.idea`, `android/local.properties`, Android Gradle/Kotlin caches, logs, downloads, local music, playlist exports, backups, app data, cookies, sessions, tokens, account exports, lyrics, signing keys, and `.env`.
- `git check-ignore -v` confirms normal project files remain visible: `README.md`, `lib/main.dart`, `pubspec.yaml`, and `assets/icon/app_icon.png`.
- `git ls-files -- My_Projects/Mconnect` returned `TRACKED_FILE_COUNT=0`, so no Mconnect personal/runtime file is already tracked in the current Git index.
- A precise `rg --files` suspicious-file scan returned `WORKTREE_SUSPICIOUS_COUNT=0` after excluding ignored/build/cache/local-memory paths.

## 2026-05-29 - Release APK after brand icon update

Built a release APK after applying the new Mconnect launcher icon and splash assets.

### Verification

- `flutter build apk --release --no-pub` passed.
- APK path: `D:\Code_Work\My_Projects\Mconnect\build\app\outputs\flutter-apk\app-release.apk`
- Size: 79,883,792 bytes / 76.18 MB
- SHA256: `49B9C52DF2B07A72647A3B315C2D8FB448D0FA6CC9A29135D792EB66203366FB`
- LastWriteTime: `2026-05-29 20:01:37`

## 2026-05-29 - Mconnect brand icon generation

Generated a new project-specific launcher icon and splash logo using Python.

### Changes

- Added `scripts/generate_brand_assets.py` for reproducible icon generation.
- Regenerated `assets/icon/app_icon.png`, `assets/icon/app_icon_foreground.png`, and `assets/images/splash_logo.png`.
- Updated launcher icon and native splash background colors in `pubspec.yaml` to match the new dark connected-wave brand direction.
- Limited `flutter_launcher_icons` to Android because this project has no `ios/` directory.
- Created a local preview image under `build/brand_preview/`.

### Verification

- `python scripts\generate_brand_assets.py` passed and generated source assets plus `build\brand_preview\mconnect_brand_preview.png`.
- `flutter pub run flutter_launcher_icons` passed after limiting launcher icon generation to Android.
- `flutter pub run flutter_native_splash:create` passed and refreshed Android/Web splash resources.
- Inspected generated image sizes:
  - `assets/icon/app_icon.png`: 1024x1024
  - `assets/icon/app_icon_foreground.png`: 1024x1024
  - `assets/images/splash_logo.png`: 1024x1024
  - `build/brand_preview/mconnect_brand_preview.png`: 1240x520
- `flutter analyze --no-pub` check: `ERROR_COUNT=0`, `WARNING_COUNT=0`, `INFO_COUNT=417`; the remaining items are existing info-level lints.

## 2026-05-29 - Ignore local project memory docs

Updated repository ignore rules so local memory and planning documents are not uploaded with the main app source.

### Changes

- Added `CHANGELOG.md` and `PROJECT.md` to `.gitignore`.
- Added `docs/superpowers/` to `.gitignore` for local agent plans and implementation notes.
- Kept `README.md`, source files, tests, assets, and build configuration unaffected.

### Verification

- `git check-ignore -v` confirms `CHANGELOG.md`, `PROJECT.md`, and `docs/superpowers/plans/2026-05-29-kugou-vip-playback.md` are ignored.
- `git check-ignore -v` confirms `README.md`, `lib/main.dart`, `test/widget_test.dart`, `pubspec.yaml`, and `android/app/build.gradle.kts` remain visible.

## 2026-05-29 - README project purpose rewrite

Updated the README to focus on what the project does instead of repository upload guidance.

### Changes

- Removed the README sections that described local runtime data as GitHub upload exclusions.
- Removed the README GitHub upload checklist and `git rm --cached` instructions.
- Added detailed Chinese sections for project purpose, usage scenarios, core workflows, and architecture intent.

### Verification

- Inspected `README.md` after the rewrite.
- `rg -n "GitHub 上传说明|建议提交|不要提交|git rm --cached|账号 cookie、VIP token|不应提交�?GitHub" README.md` returned no matches.
- `rg -n "## 项目作用|## 使用场景|## 核心工作流|## 架构思路" README.md` confirms the new project-purpose sections are present.

## 2026-05-29 - README and GitHub ignore rules

Updated repository documentation and tightened ignore rules for GitHub uploads.

### Changes

- Replaced the default Flutter `README.md` with a project-specific Chinese README covering features, stack, structure, development commands, runtime data paths, and GitHub upload guidance.
- Expanded `.gitignore` to hide build artifacts, APK/AAB files, local Flutter and Android caches, local secrets, signing keys, logs, runtime databases, Hive files, and downloaded media folders.
- Adjusted `android/.gitignore` so local Android caches and signing files stay ignored while Gradle wrapper files remain trackable for reproducible builds.

### Verification

- Inspected `README.md`, root `.gitignore`, and `android/.gitignore`.
- `git check-ignore -v` confirms APKs, Android local properties, Kotlin logs, runtime logs, downloaded media folders, signing key files, and `.env` files are ignored.
- `git check-ignore -v` confirms `android/gradlew`, `android/gradlew.bat`, and `android/gradle/wrapper/gradle-wrapper.jar` are not ignored.

## 2026-05-29 - Release APK build

Built a release APK from the current workspace state.

### Verification

- `flutter build apk --release --no-pub` passed.
- APK path: `D:\Code_Work\My_Projects\Mconnect\build\app\outputs\flutter-apk\app-release.apk`
- Size: 78,303,792 bytes / 74.68 MB
- SHA256: `8EAB2049062482F44ADCF72FE68B0B5781A572623BC2B8E3FCF8B095DBEA8CA0`
- LastWriteTime: `2026-05-29 19:28:47`

## 2026-05-29 - Kugou Concept VIP high-quality download routing

Fixed the Kugou high-quality download path for Concept/Lite VIP sessions.

### Root Cause

- The download VIP gate called `getVipStatus()`, but Kugou VIP status only trusted the ordinary VIP-info endpoint. A valid Concept/Lite session with `vip_token` and `vip_type` could still be treated as `free`, so lossless and Hi-Res downloads were blocked before URL resolution.
- `KugouPlatform.getSongUrl()` returned the old song-info direct URL before checking the requested quality. For non-standard qualities this could return an ordinary `128.mp3` URL and skip the authenticated Concept private route.
- The Kugou private URL request sent `qualities` with `128` first, so a server that honors list order could return low quality even when the user selected lossless or another VIP quality.

### Changes

- `lib/platform/kugou/kugou_platform.dart`
  - `getVipStatus()` now trusts the restored Concept/Lite session fields first: `vip_type >= 2` maps to `SVIP`, `vip_type >= 1` maps to `VIP`, and a complete `token/userid/vip_token` playback session is treated as SVIP-capable for the download gate.
  - `getSongUrl()` now only accepts the old song-info direct URL for standard quality. Higher qualities continue through the authenticated private route first, then signed Android/Lite fallbacks.
- `lib/platform/kugou/kugou_api.dart`
  - Private playback/download URL requests now order `qualities` with the selected quality first, then lower fallbacks.
- Tests
  - Added regression coverage for Concept VIP session status, download VIP gate allowance, high-quality URL route priority, and private URL quality ordering.

### Verification

- Red tests initially failed because Concept VIP was reported as `VipLevel.free`, the high-quality request returned `https://ordinary.example.test/128.mp3`, and the download gate rejected lossless downloads.
- `flutter test --no-pub test\kugou_login_test.dart test\kugou_playback_test.dart test\download_provider_test.dart --reporter expanded -j 1` passed: 27/27.
- `flutter test --no-pub --reporter expanded -j 1` passed: 127/127.
- `flutter analyze --no-pub`: `ERROR_WARNING_COUNT=0`, `INFO_COUNT=417`; remaining items are existing info-level lints.

## 2026-05-29 - Custom download directory and open-folder workflow

Implemented the download-directory workflow requested by the user.

### Changes

- `lib/features/download/data/download_directory_service.dart`
  - Added persistent download root management backed by Hive.
  - Default root remains the app documents download directory: `getApplicationDocumentsDirectory()/downloads`.
  - Custom roots are validated and persisted; empty paths and filesystem roots are rejected.
- `lib/features/download/data/repositories/download_manager.dart`
  - Download target paths now come from `DownloadDirectoryService`.
  - Added helpers for reading, setting, and resetting the download root.
  - Added completed-file deletion support for removed download records.
- `lib/features/download/presentation/providers/download_provider.dart`
  - Added injectable constructor for tests.
  - `removeTask()` now deletes the completed local file before removing the task.
  - Added provider methods for current/custom/default download directory actions.
- `lib/features/download/presentation/screens/download_page.dart`
  - Added a download-directory button in the download manager AppBar.
  - Added a bottom sheet showing the current directory, with "选择目录" and "恢复默认目录".
  - The completed-download folder button now opens the containing folder instead of opening the song file.
  - Cleaned the download page's visible Chinese labels.
- `lib/utils/file_opener.dart`
  - Added `FileOpener.openFolder()`.
- Android native layer
  - Added `openFolder` handling in `MainActivity.kt`.
  - Added AndroidX `FileProvider` support and `res/xml/file_paths.xml` so files/folders can be shared with external apps on modern Android.
  - Added `androidx.core:core-ktx` dependency for `FileProvider`.
- Tests
  - Added regression coverage for default/custom download directory behavior, deleting files when removing completed downloads, MethodChannel `openFolder`, and the download page folder action.

### Verification

- Red tests initially failed for missing `DownloadNotifier(manager:)`, missing `FileOpener.openFolder()`, and missing folder-opening UI behavior.
- `flutter test --no-pub test\download_directory_service_test.dart test\download_provider_test.dart test\file_opener_test.dart test\download_page_test.dart --reporter expanded -j 1` passed: 6/6.
- `flutter test --no-pub --reporter expanded -j 1` passed: 124/124.
- `flutter analyze --no-pub`: `ERROR_WARNING_COUNT=0`, `INFO_COUNT=417`; remaining items are existing info-level lints.
- `flutter build apk --release --no-pub` passed.
- APK path: `D:\Code_Work\My_Projects\Mconnect\build\app\outputs\flutter-apk\app-release.apk`
- Size: 78,303,792 bytes / 74.68 MB
- SHA256: `77C9CC0C5BCE6CA756DCB424C6A817AB06769BAB2AB51B33BA1534FD0AF05C0A`
- LastWriteTime: `2026-05-29 18:48:34`

## 2026-05-29 - Release APK after player progress sync

Built a new release APK after the full player initial progress synchronization fix.

### Verification

- `flutter build apk --release --no-pub` passed.
- APK path: `D:\Code_Work\My_Projects\Mconnect\build\app\outputs\flutter-apk\app-release.apk`
- Size: 78,286,664 bytes / 74.66 MB
- SHA256: `5D3AC94179E213B1225522DEB44DF6B5AA04689F3C3594E434BDB1BAAC36E4CB`
- LastWriteTime: `2026-05-29 17:56:16`

## 2026-05-29 - Player screen initial progress sync

Fixed the short `00:00` flash when opening the full player from the mini player.

### Root Cause

- `PlayerScreen` kept local `_position` and `_duration` fields initialized to zero.
- The page only copied playback progress from `playerProvider` after the one-second timer fired, so the first frame could show `00:00` even while the song was already playing.

### Changes

- `lib/features/player/presentation/screens/player_screen.dart`
  - Added immediate progress synchronization from `playerProvider` in `initState`.
  - Reused the same synchronization helper in the existing one-second timer.
- `test/widget_test.dart`
  - Added a regression test proving the player screen shows the existing playback position on the first rendered frame.

### Verification

- Red test before the fix: `player screen shows existing progress on first frame` failed because `01:23` was not found.
- `flutter test --no-pub test\widget_test.dart --reporter expanded` passed: 13/13.
- `flutter test --no-pub --reporter expanded` passed: 118/118.
- `flutter analyze --no-pub`: `ERROR_WARNING_COUNT=0`, `INFO_COUNT=418`; remaining items are existing info-level lints.

## 2026-05-29 - Kugou Concept account mode and VIP playback diagnostics

Fixed the remaining Kugou VIP playback session gap exposed by the user's log:

`[kugou_playback] url_resolution_failed ... "has_vip_session":false,"routes":"android_v5:no_url,lite_v5:no_url"`

### Root Cause

- The app had Lite/Concept playback fallback code, but login still behaved like an ordinary Kugou account session.
- The saved Kugou session did not record whether the account was logged in as ordinary Kugou or Kugou Concept/Lite.
- When a Concept VIP song needed private playback, the app often had `token/userid` but no `vip_token`, so it skipped the private VIP route and only tried ordinary public URL routes.

### Changes

- `lib/platform/kugou/kugou_api.dart`
  - Added persistent Kugou client mode: `android` and `lite`.
  - Made QR key, QR polling, user-info lookup, signed web params, and phone-code request mode-aware.
  - Added safe session capability flags: `hasToken`, `hasUserId`, `hasVipToken`, and `clientModeName`.
- `lib/platform/kugou/kugou_platform.dart`
  - Added `setClientVariant()` so the auth layer can select ordinary Kugou or Kugou Concept without creating a fourth platform.
  - QR display URL now uses `appid=3116` when Concept/Lite login is selected.
  - Saved Kugou session JSON now includes `client`, and restore keeps old `token|userid` compatibility.
  - Playback failure diagnostics now include sanitized booleans and client mode: `kugou_client`, `has_token`, `has_userid`, `has_vip_token`, and `has_vip_session`.
  - Concept phone login now explicitly asks the user to use QR login, because the real Concept phone-login route requires encrypted AES/RSA parameters and should not be faked through the ordinary Kugou login path.
- `lib/features/auth/presentation/providers/auth_provider.dart`
  - Passes the selected Kugou auth variant into QR, polling, phone-code, and phone-login calls.
- `lib/features/auth/presentation/pages/login_page.dart`
  - Added a Kugou-only segmented selector for `酷狗概念版` and `酷狗音乐`.
  - Defaults to `酷狗概念版`, matching the user's VIP use case.
  - Switching modes regenerates the QR code and restarts polling.
- `test/kugou_login_test.dart`, `test/kugou_playback_test.dart`
  - Added regression coverage for Concept QR appid/clientver, QR display URL, session `client` persistence, Concept phone-login guard, and sanitized playback diagnostics.

### Verification

- `flutter test --no-pub test\kugou_login_test.dart test\kugou_playback_test.dart --reporter expanded` passed: 23/23.
- `flutter test --no-pub --reporter expanded` passed: 117/117.
- `flutter analyze --no-pub`: `ERROR_WARNING_COUNT=0`, `INFO_COUNT=418`; remaining items are existing info-level lints.
- `flutter build apk --release --no-pub` passed.
- APK path: `D:\Code_Work\My_Projects\Mconnect\build\app\outputs\flutter-apk\app-release.apk`
- Size: 78,286,664 bytes / 74.66 MB
- SHA256: `2AD0A25C149628C336FFECF279C965F6CF87013205217F64769235DA6AAB3D20`
- LastWriteTime: `2026-05-29 17:40:52`

### Notes

- This fixes the app-side problem where Concept/Lite login mode was not persisted or used consistently.
- Actual VIP playback is still decided by Kugou's server for the specific real account and track. If a VIP song still fails, the next log should now show whether the app has `has_vip_token:true` and whether the `private` route returned `no_url`.
- Reference behavior was checked against MakcRe/KuGouMusicApi Concept/Lite appid/clientver and private playback route examples.

## 2026-05-29 - Release APK rebuild

Rebuilt the release APK on user request and verified the output artifact.

### Verification

- `flutter build apk --release --no-pub` passed.
- APK path: `D:\Code_Work\My_Projects\Mconnect\build\app\outputs\flutter-apk\app-release.apk`
- Size: 78,270,148 bytes / 74.64 MB
- SHA256: `19AE4FF4C24FB7138510044B9F13B4DBD804BC44EAAD547AACD03E3AA6523718`
- LastWriteTime: `2026-05-29 17:00:56`

## 2026-05-29 - Kugou VIP playback route and VIP channel checks

Implemented the Kugou VIP playback plan and checked the request-level VIP playback channels for NetEase Cloud Music and QQ Music.

### Root Cause

- Kugou login was only persisted as `token|userid`; VIP/private playback needs additional fields such as `vip_token`, `vip_type`, `dfid`, `mid`, and `uuid`.
- Kugou playback fallback used only the ordinary Android `v5/url` route, so a logged-in VIP account could still request protected songs like an ordinary client.
- QQ Music playback URL requests hardcoded `uin=0` and `guid=0`, so the vkey request did not properly represent the logged-in QQ Music account.
- NetEase already uses `/api/song/enhance/player/url/v1` with level names and cookie headers; this was verified with a regression test.

### Changes

- `lib/platform/kugou/kugou_api.dart`
  - Added extended session fields and JSON session support hooks.
  - Added `KugouPlaybackClient` with ordinary Android and Lite/Concept signing.
  - Added Lite `v5/url` request parameters and signing keys.
  - Added `v6/priv_url` private playback request with `vip_token`, `vip_type`, `userid`, `token`, `dfid`, `mid`, and `uuid`.
- `lib/platform/kugou/kugou_platform.dart`
  - Extracts extended session fields from QR login, profile fetch, and phone login responses.
  - Saves Kugou sessions as JSON while keeping backward compatibility with old `token|userid`.
  - Tries private VIP playback first for VIP-capable sessions, then ordinary `v5/url`, then Lite `v5/url`.
  - Records sanitized `kugou_playback url_resolution_failed` diagnostics without logging tokens or full song hashes.
- `lib/platform/kugou/kugou_endpoints.dart`
  - Added `http://tracker.kugou.com/v6/priv_url`.
- `lib/platform/qq/qq_api.dart`
  - QQ vkey playback requests now use the logged-in QQ Music `uin`, cookie tokens, and a stable non-zero playback `guid`.
- `test/kugou_login_test.dart`, `test/kugou_playback_test.dart`
  - Added red-green coverage for extended Kugou session persistence, Lite playback signing, private VIP playback request body, fallback order, and sanitized diagnostics.
- `test/netease_api_test.dart`
  - Added request-level check that NetEase VIP playback requests keep login cookie, csrf, and requested `level`.
- `test/qq_api_test.dart`
  - Added request-level check that QQ VIP playback requests include logged-in `uin`, cookie token, non-zero `guid`, and high-quality filename.

### Verification

- `flutter test --no-pub test\kugou_login_test.dart test\kugou_playback_test.dart test\netease_api_test.dart test\qq_api_test.dart --reporter expanded` passed: 31/31.
- `flutter test --no-pub --reporter expanded` passed: 112/112.
- `flutter analyze --no-pub`: `ERROR_WARNING_COUNT=0`, `INFO_COUNT=418`; remaining items are existing info-level lints.
- `flutter build apk --release --no-pub` passed.
- APK path: `D:\Code_Work\My_Projects\Mconnect\build\app\outputs\flutter-apk\app-release.apk`
- Size: 78,270,148 bytes / 74.64 MB
- SHA256: `19AE4FF4C24FB7138510044B9F13B4DBD804BC44EAAD547AACD03E3AA6523718`
- LastWriteTime: `2026-05-29 16:53:59`

### Notes

- NetEase and QQ checks prove the app sends the right login and quality request data at code level.
- Real VIP playback still depends on each platform's server-side authorization for the user's actual account and the specific song.
- If a Kugou VIP song still fails, check the app diagnostics log for `kugou_playback url_resolution_failed`; it should show which route failed without exposing account tokens.

## 2026-05-29 - Kugou VIP playback implementation plan

Created a TDD implementation plan for the remaining Kugou VIP playback issue where some Kugou songs can enter the player but remain stuck at `0:00`.

### Root Cause Hypothesis

- The app currently persists only `token|userid` for Kugou login.
- Known Kugou Lite/Concept and VIP/private playback routes require extra session fields such as `vip_token`, `vip_type`, `dfid`, `mid`, and `uuid`.
- The current playback fallback still uses ordinary Kugou Android playback parameters, so a logged-in VIP user can still look like an ordinary client when requesting a protected playback URL.

### Plan

- Saved executable plan at `docs/superpowers/plans/2026-05-29-kugou-vip-playback.md`.
- The plan covers failing tests, extended session persistence, Lite playback signing, `v6/priv_url` VIP playback, fallback order, sanitized diagnostics, full verification, and APK build steps.

### Notes

- The plan does not guarantee every VIP track will play without real-account validation, because final playback authorization is decided by Kugou's server.
- If server-side refusal remains after the request chain is corrected, the diagnostics log should show which route failed without leaking tokens.

## 2026-05-29 - Release APK after Kugou playback and mini player progress fixes

Built a new release APK after the Kugou playback URL fallback and mini player progress updates.

### Verification

- `flutter build apk --release --no-pub` passed.
- APK path: `D:\Code_Work\My_Projects\Mconnect\build\app\outputs\flutter-apk\app-release.apk`
- Size: 78,270,148 bytes / 74.64 MB
- SHA256: `AA1E5A4F43A26A444C8A95483A7C7E1849677A4FB1106722374E7464DA33619B`
- LastWriteTime: `2026-05-29 15:56:13`

## 2026-05-29 - Kugou playback URL and mini player progress fixes

This change fixes two playback issues reported by the user:

- Kugou playlist songs could open the player but remain stuck at `0:00`.
- The mini player progress bar did not update in real time until the full player page was opened.

### Root Cause

- `KugouPlatform.getSongUrl()` only read the old song-info endpoint's top-level `url`. Real Kugou responses can place playable URLs under nested fields such as `data.play_url`, or in backup URL lists. Some tracks also return an empty `url` from the old endpoint, so the player never receives a usable audio source.
- `MiniPlayerBar` used `ref.read(playerProvider)` for `position/duration`, so it did not rebuild when only playback progress changed.

### Changes

- `lib/platform/kugou/kugou_platform.dart`
  - Added robust playable URL extraction for top-level, nested, and backup URL response shapes.
  - Added fallback from the old song-info endpoint to the signed Kugou `v5/url` playback endpoint when no playable URL is found.
- `lib/platform/kugou/kugou_api.dart`
  - Added `getSongPlaybackUrl()` with Android-style signed parameters and `trackercdn.kugou.com` routing.
  - Added Kugou playback quality mapping for `128/320/flac/high/viper_*`.
- `lib/features/player/presentation/widgets/mini_player_bar.dart`
  - Changed mini player progress to watch `position/duration`, so progress updates while staying in any page.
- `test/kugou_playback_test.dart`
  - Added regression coverage for nested `play_url`, backup URLs, signed `v5/url` fallback, and request parameters.
- `test/widget_test.dart`
  - Added regression coverage for mini player progress updates when only playback progress changes.

### Verification

- `flutter test --no-pub test\kugou_playback_test.dart --reporter expanded` passed: 4/4.
- `flutter test --no-pub test\widget_test.dart --reporter expanded` passed: 12/12.
- `flutter test --no-pub --reporter expanded` passed: 103/103.
- `flutter analyze --no-pub`: `ERROR_WARNING_COUNT=0`, `INFO_COUNT=418`; remaining items are existing info-level lints.

## 2026-05-29 - 播放记忆版本 Release APK 打包

本次按用户要求，在加入播放记忆与断点恢复功能后重新生�?release APK，并完成产物校验�?
### 验证结果

- `flutter build apk --release --no-pub` 构建通过�?- APK 路径: `D:\Code_Work\My_Projects\Mconnect\build\app\outputs\flutter-apk\app-release.apk`
- Size: 78,253,764 bytes / 74.63 MB
- SHA256: `F59EC0DCBA9293E50A584845893EDCE12D67291B58FF3A5FE4D78CAB7CB0070B`
- LastWriteTime: `2026-05-29 14:50:04`

## 2026-05-29 - 播放记忆与断点恢�?
本轮新增播放器记忆功能：用户听到一半退�?App、清理后台后，再次进�?App 时，迷你播放器和播放器页面会显示上次播放的歌曲以及上次播放到的时间点�?
### 实现内容

- `lib/features/player/data/player_playback_memory_store.dart`
  - 新增 `PlayerPlaybackMemory`，保存当前歌曲、播放列表、当前索引、播放进度、歌曲时长、当前音质和保存时间�?  - 新增 `HivePlayerPlaybackMemoryStore`，使�?Hive �?`player_memory/last_playback` 单键覆盖保存，不会持续追加日志或无限增长�?- `lib/features/player/presentation/providers/player_provider.dart`
  - 播放歌曲、拖动进度、音频进度流更新、切换音质、队列变化时节流保存播放记忆，默�?5 秒最多写入一次�?  - `PlayerNotifier` 初始化时异步读取播放记忆，恢�?`currentSong`、`position`、`duration`、`playlist` �?`currentQuality`�?  - 恢复后不会自动播放，避免打开 App 突然出声；用户点击播放时会重新获取播�?URL，seek 到上次进度，再开始播放�?  - 对恢复态拖动进度做保护：音源尚未重新加载前只更�?UI 和记忆，不向空播放器执行 seek�?- `lib/app.dart`
  - 接入 App 生命周期，在进入后台、失焦或 detached 时主�?flush 播放记忆，降低被系统清理后台前丢失进度的概率�?- `test/player_provider_test.dart`
  - 新增回归测试覆盖保存播放记忆、冷启动恢复显示、恢复后点击播放从保存进度继续�?
### 验证

- `flutter test --no-pub test\player_provider_test.dart --reporter expanded` 通过�?1/11�?- `flutter test --no-pub test\player_provider_test.dart test\widget_test.dart --reporter expanded` 通过�?2/22�?- `flutter test --no-pub --reporter expanded` 通过�?8/98�?- `flutter analyze --no-pub` 统计：`ERROR_WARNING_COUNT=0`，`INFO_COUNT=418`，均为项目既�?info �?lint�?
## 2026-05-29 - 酷狗用户歌单读取与新建失败修�?
本轮继续处理“酷狗歌单还是没有、新建歌单显示失败”的问题。根因不是单一 UI 错误，而是酷狗用户歌单相关接口链路混用了公开歌单 ID、用户编�?listid 和旧收藏列表接口，导致真实账号下可能出现列表为空、新建后刷新消失、详情无法进入或详情为空�?
### 修复内容

- `lib/platform/kugou/kugou_api.dart`
  - 用户歌单列表改走酷狗云歌单接�?`gateway.kugou.com/v7/get_all_list`，带登录�?`userid/token`、Android 签名参数�?`x-router: cloudlist.service.kugou.com`�?  - 用户歌单歌曲改走 `gateway.kugou.com/v4/get_list_all_file`，使用可编辑 `listid` 拉取详情，避免把公开 `specialid` 当作用户歌单详情 ID�?- `lib/platform/kugou/kugou_platform.dart`
  - QR 登录成功后如果状态接口只返回 token，会从后续用户资料里同步 `userid` 到底�?API，保证歌单接口有完整登录态�?  - 手机号登录成功后同步保存 `token/userid`，避免登录成功但后续歌单接口仍按未登录处理�?  - 新建歌单成功判断兼容 `errcode: 0`、`code: 0` 等成功返回；新建后只接受刷新列表中同名且有稳定详�?ID 的歌单，不再把临�?`listid` 或旧歌单误判为新建成功�?  - 用户歌单解析递归兼容 `list_create_list`、`list_collect_list`、`list/info/lists/data` 等嵌套容器�?  - `collection_3_userid_listid_0` 公开详情为空时，解析其中�?`listid` 并回退到用户歌单歌曲接口，修复已有歌单外层可见但进入详情为空的问题�?- `lib/platform/kugou/kugou_endpoints.dart`
  - 新增酷狗云歌单列表和用户歌单歌曲端点常量�?- `test/kugou_login_test.dart`、`test/kugou_playlist_test.dart`
  - 新增回归测试覆盖登录态同步、云歌单端点、用�?listid 详情、新建歌单成功码、拒绝临�?ID/旧歌单、嵌套歌单容器、`collection_...` �?`listid` 的详情回退�?
### 验证

- `flutter test --no-pub test\kugou_login_test.dart test\kugou_playlist_test.dart test\platform_playlists_provider_test.dart --reporter expanded` 通过�?4/24�?- `flutter test --no-pub --reporter expanded` 通过�?5/95�?- `flutter analyze --no-pub` 统计：`ERROR_WARNING_COUNT=0`，`INFO_COUNT=418`，均为项目既�?info �?lint�?
## 2026-05-29 - 歌单修复�?Release APK 打包

本次按用户要求在歌单分页导入、我的歌单编辑和长列表滚动条修复后重新生�?release APK�?
### 验证结果

- `flutter build apk --release --no-pub` 构建通过�?- APK 路径: `D:\Code_Work\My_Projects\Mconnect\build\app\outputs\flutter-apk\app-release.apk`
- Size: 78,155,460 bytes / 74.53 MB
- SHA256: `33E51ED1D4BB277AB28034AD35CE84F247C1932BE5A74D6B9C525AF7B4DD4D12`
- LastWriteTime: `2026-05-29 13:34:19`

## 2026-05-29 - 歌单分页导入、我的歌单编辑与长列表滚动条落地

本轮按既定计划完成歌单导入截断、本地“我的歌单”编辑分享，以及长信息流滚动条改进�?
### 修复内容

- 网易云歌单详情不再只保留�?1000 首；通过 `trackIds` 补齐缺失歌曲详情，避免大歌单导入截断�?- QQ 音乐歌单详情�?`song_begin/song_num` 分页加载现代接口结果，修复超�?200 首只取第一页的问题�?- 酷狗歌单详情�?`page/pagesize` 分页加载 shared playlist 与用户歌�?fallback，修复超�?100 首只取第一页的问题�?- “我的歌单”导入改为批量读写，支持删除歌单、删除歌单内歌曲、导�?`mconnect://playlist?data=...` 分享链接，以及重新导�?Mconnect 分享链接�?- 新增 `AppScrollbar`，为搜索结果、歌单详情、平台歌单、我的歌单、导入结果、我喜欢、听歌历史、下载管理、本地音乐、每日推荐、排行榜、发现页推荐网格、播放器收藏到歌单弹窗等长列表接入可拖动滚动条�?- 同步 QQ 测试 fake 的分页签名，补齐网易云测�?fake �?`@override` 注解，避免全量测试编译遗漏�?
### 验证

- 新增滚动条测试先红测失败于缺�?`AppScrollbar`，实现后通过�?- `flutter test --no-pub test\app_scrollbar_test.dart test\netease_api_test.dart test\qq_platform_test.dart test\kugou_playlist_test.dart test\my_playlists_repository_test.dart test\platform_playlists_provider_test.dart test\playlist_picker_sheet_test.dart test\search_screen_test.dart --reporter expanded` 通过�?8/38�?- `flutter test --no-pub --reporter expanded` 通过�?6/86�?- `flutter analyze --no-pub`：`ERROR_WARNING_COUNT=0`，剩�?418 条为既有 info �?lint�?
## 2026-05-29 - 歌单导入编辑与长列表滚动条修复计�?
本次按用户要求将“三平台完整分页导入”正式加入当前修复计划，并新增计划文档：
`docs/superpowers/plans/2026-05-29-playlist-import-edit-scrollbar-plan.md`�?
计划范围包括�?
- 网易云移�?1000 首硬截断，使用完�?`trackIds` 与批量歌曲详情补全�?- QQ 音乐修复 `song_num: 200` 只取第一页的风险，按 `song_begin/song_num` 翻页�?- 酷狗音乐修复 `pagesize: 100` 只取第一页的风险，按 `page/pagesize` 翻页�?- 本地“我的歌单”改为批量写入，降低大歌单导入卡顿风险�?- 增加删除歌单、删除歌单内歌曲、导�?Mconnect 分享链接、导�?Mconnect 分享链接�?- 为搜索结果、歌单详情、导入结果、我喜欢、听歌历史、下载管理、本地音乐、每日推荐、排行榜等长信息流加入可拖动滚动条�?
## 2026-05-29 - APK 打包校验

本次按用户请求重新生�?release APK，并对输出产物做文件级校验�?
### 验证结果

- `flutter build apk --release --no-pub` 构建通过�?- APK 路径: `D:\Code_Work\My_Projects\Mconnect\build\app\outputs\flutter-apk\app-release.apk`
- Size: 77,876,856 bytes / 74.27 MB
- SHA256: `C4D320ECE5340473C55C691B10211D00300621A3EEB820C250C431799AC48C6E`
- LastWriteTime: `2026-05-29 12:50:46`

## 2026-05-29 - 歌单导入分享链接兼容修复

本轮修复用户提供的网易云、QQ 音乐、酷狗音乐歌单分享链接导入失败问题，并补充对应回归测试，避免之后再次退化为“无法识别该链接”或“导�?0 首歌”�?
### 根因分析

- 网易云音乐导入只识别 `/#/playlist?id=` �?`/playlist/<id>`，没有兼容移动端分享格式 `https://music.163.com/m/playlist?id=...`，因此正确链接在平台解析阶段就返�?`null`�?- QQ 音乐分享链接中的 `id=9333150211` 能被识别，但当前 `musicu` 歌单详情接口可能返回�?`songlist`。该歌单通过公开旧接�?`fcg_ucc_getcdinfo_byids_cp.fcg` 可以拿到 `cdlist[0].songlist` 和真�?`songnum`，旧逻辑没有 fallback�?- 酷狗音乐短链 `https://t1.kugou.com/...` �?302 跳转�?H5 活动页，真实歌单 ID �?`global_specialid=collection_...` 中。旧逻辑只识别长链中的数�?`specialid`，也没有接入 H5 公开歌单歌曲接口�?
### 修复内容

- `lib/platform/netease/netease_platform.dart`：新�?URI 级歌�?ID 提取，兼�?`/m/playlist?id=...`、`/playlist?id=...`、`/#/playlist?id=...` 和路径式歌单链接�?- `lib/platform/qq/qq_api.dart`：新�?`getLegacyPlaylistDetail()`，接�?QQ 音乐公开旧歌单详情接口，用于分享页需要登录或现代详情为空时兜底�?- `lib/platform/qq/qq_platform.dart`：`getPlaylistDetail()` 在现代接口返回空歌曲列表时自�?fallback �?legacy 接口；`parseShareLink()` �?legacy `cdlist` 补全歌单名、封面和真实歌曲数量�?- `lib/platform/kugou/kugou_api.dart`：新�?`resolveShareUrl()` 解析 `t1.kugou.com` 短链跳转；新�?`getSharedPlaylistSongs()`，使用酷�?H5 签名参数访问 `pubsongscdn.kugou.com/v2/get_other_list_file`�?- `lib/platform/kugou/kugou_platform.dart`：支持从跳转后的 `global_specialid/global_collection_id` 提取 `collection_...` 歌单 ID；`collection_...` 歌单详情�?H5 shared playlist 接口；歌曲解析兼�?H5 字段 `name/filename/singerinfo/timelen/cover`�?
### 测试

- 新增回归测试覆盖用户给出的三个链接：
  - `https://music.163.com/m/playlist?id=863541621&creatorId=556315981`
  - `https://y.qq.com/n3/other/pages/details/playlist.html?...&id=9333150211...`
  - `https://t1.kugou.com/9Y4aX8fG1V2`
- `flutter test --no-pub test\netease_api_test.dart test\qq_platform_test.dart test\kugou_playlist_test.dart --reporter expanded` 通过�?1/21�?- `flutter test --no-pub --reporter expanded` 通过�?8/78�?- `flutter analyze --no-pub` 过滤 error/warning 后：`ERROR_WARNING_COUNT=0`。剩余为项目既有 info �?lint�?
## 2026-05-29 - QQ/酷狗新建歌单�?ID 路由崩溃修复

本轮修复酷狗新建歌单后进入详情出�?`GoException: no routes for location: /playlist/kugou?name=12` 的崩溃。QQ 音乐新建歌单也使用同一类防护，避免平台只返回编�?ID 时生成不可访问的歌单入口�?
### 根因分析

- 崩溃路由 `/playlist/kugou?name=12` 缺少歌单详情 ID，说�?UI 层拿到的�?`Playlist.id == ''`�?- 酷狗新建接口在部分情况下只返回空 `global_collection_id/listid`，旧逻辑仍会把这个结果插入歌单列表，点击后生成无 ID 的路由�?- QQ 音乐新建接口常返�?`dirid`，但详情访问需要稳定的 `dissid/disstid`。如果刷新用户歌单后仍找不到稳定详情 ID，旧逻辑也有生成不可访问入口的风险�?
### 修复内容

- `lib/platform/kugou/kugou_platform.dart`
  - 新建歌单成功后优先刷新用户歌单，用刷新结果中的稳定详�?ID�?  - 如果平台没有返回可访�?ID，则返回 `null`，不再构造空 ID 歌单�?- `lib/platform/qq/qq_platform.dart`
  - 新建歌单后用 `dirid` 反查�?`dissid/disstid` 的用户歌单�?  - 如果只能拿到不稳定的 `dirid`，则返回 `null`，避免详情路由不可访问�?- `lib/features/library/presentation/providers/platform_playlists_provider.dart`
  - 加载歌单时过滤空 ID 歌单�?  - 新建歌单返回�?ID 时显示“平台未返回可访问的歌单ID”，不插入列表�?- `lib/features/library/presentation/pages/platform_playlists_page.dart`
  - 点击歌单前增加路由保护；缺少可访�?ID 时提示刷新，不调�?`context.push()`�?
### 验证

- 新增回归测试先失败，覆盖酷狗新建返回�?ID、QQ 新建只有 `dirid`、provider 拒绝不可路由歌单�?- `flutter test --no-pub test\platform_playlists_provider_test.dart test\kugou_playlist_test.dart test\qq_platform_test.dart --reporter expanded` 通过�?6/16�?- `flutter test --no-pub` 通过�?4/74�?- `flutter analyze --no-pub` 过滤 error/warning 后：`ERROR_WARNING_COUNT=0`；剩余为既有 info �?lint 提示�?- `flutter build apk --release --no-pub` 通过�?- APK: `D:\Code_Work\My_Projects\Mconnect\build\app\outputs\flutter-apk\app-release.apk`
  - Size: 77,794,936 bytes / 74.19 MB
  - SHA256: `7E8F11F56105F0549260FCC871FCD7F044A05C3FC5A714839DD1B905DF34A814`

### 备注

- 本轮没有删除 QQ/酷狗歌单入口，因为崩溃的根因可以在路由和平台数据层防住�?- 如果平台接口在真实账号下仍不返回稳定详情 ID，新建歌单会失败提示，但不会再生成点击即崩溃的歌单项。后续若确认 QQ/酷狗长期无法返回稳定歌单详情 ID，再考虑隐藏或删除对应平台歌单能力�?
## 2026-05-29 - 平台歌单访问修复与我的歌�?
本轮修复 QQ/酷狗用户歌单进入后无法访问、新建歌单刷新后丢失的问题，并新增独立的本地“我的歌单”能力�?
### 根因与修�?
- **QQ 音乐歌单外部可见但歌曲不可访�?*：QQ 详情接口存在 `req_0.data.songlist` 和旧�?`cdlist[0].songlist` 等不同结构，旧解析只认一种。现在详情解析兼容多种结构，并补�?`songmid/songname/albummid` 等字段�?- **QQ 音乐新建歌单不可�?*：新建接口返回的�?`dirid`，而详情访问需�?`dissid/disstid`。现在新建成功后会刷新用户歌单，�?`dirid` 反查真正详情 ID，并保留 `editId` 用于后续添加歌曲�?- **酷狗已有歌单无法访问/刷新后消�?*：酷狗用户歌单会分散在创建歌单、收藏歌单等多个容器；详情也可能需�?`global_collection_id` 或用�?`listid`。现在合�?`list_create_list` �?`list_collect_list` 等容器，�?ID 去重；详情先走公开歌单 ID，空结果�?fallback 到用�?`listid` 接口�?- **酷狗新建后刷新消�?*：新建接口返回的 ID 不能直接假定可用于详情。现在新建成功后刷新用户歌单，以刷新结果中的稳定 ID 作为 UI 和详情入口�?- **我的歌单**：新增本地持久化歌单，位�?`歌单 -> 我的歌单`。支持新建多个本地歌单；导入分享链接后可保存为一个新的本地歌单；每次导入都保留原歌单名并生成独立歌单，不会混在一起；播放器收藏到歌单时也会显示我的歌单�?
### 修改文件

- `lib/platform/qq/qq_platform.dart`
- `lib/platform/kugou/kugou_api.dart`
- `lib/platform/kugou/kugou_platform.dart`
- `lib/features/library/data/my_playlists_repository.dart`
- `lib/features/library/presentation/providers/my_playlists_provider.dart`
- `lib/features/library/presentation/pages/platform_playlists_page.dart`
- `lib/features/library/presentation/pages/playlist_detail_page.dart`
- `lib/features/library/presentation/pages/import_playlist_page.dart`
- `lib/features/player/presentation/widgets/playlist_picker_sheet.dart`
- `test/qq_platform_test.dart`
- `test/kugou_playlist_test.dart`
- `test/my_playlists_repository_test.dart`
- `test/playlist_picker_sheet_test.dart`

### 验证

- 新增回归测试先失败，覆盖 QQ `cdlist` 歌曲结构、QQ 新建�?`dirid -> dissid` 反查、酷�?created/collected 容器合并、酷�?`listid` 详情 fallback、我的歌单持久化与去重�?- `flutter test --no-pub` 通过�?1/71�?- `flutter analyze --no-pub` 过滤 error/warning 后：`ERROR_WARNING_COUNT=0`；剩余为既有 info �?lint 提示�?- `flutter build apk --release --no-pub` 通过�?- APK: `D:\Code_Work\My_Projects\Mconnect\build\app\outputs\flutter-apk\app-release.apk`
  - Size: 77,794,936 bytes / 74.19 MB
  - SHA256: `D213E879A36C05BF4CA4AEE068CD65B8CE33B306D86F1311EF4FD1847F2A4C56`

## 2026-05-29 - QQ/酷狗歌单详情修复�?APK 打包

本轮继续处理平台歌单数据不一致问题，并重新生�?release APK�?
### 修复内容

- **QQ 音乐歌单详情为空**：用户歌单列表外层能显示 780 首，但进入详情为空。根因是列表解析优先�?`tid/dirid` 当作详情 ID，导致详情接口没有使用真正的 `dissid/disstid`。现�?`Playlist.id` 优先保存 `disstid/dissid`，同时新�?`editId` 保留 `dirid/tid` 给添加歌曲等编辑接口使用�?- **酷狗音乐暂无歌单/歌单详情为空**：酷狗不同接口会把创建歌单、收藏歌单、歌曲列表放在不同字段中。现在用户歌单解析已兼容 `data.list`、`data.info`、`data.lists`、`data.list_create_list`、`data.list_collect_list` 等常见容器；歌单详情也兼�?`data.info`、`data.songs`、`data.list`、`data.data` 和根级列表字段�?- **添加到平台歌�?ID 选择**：播放器歌单选择器改为使�?`playlist.editableId`，避�?QQ 详情 ID 与编�?ID 混用�?
### 修改文件

- `lib/models/playlist.dart`
- `lib/platform/qq/qq_platform.dart`
- `lib/platform/kugou/kugou_platform.dart`
- `lib/features/player/presentation/widgets/playlist_picker_sheet.dart`
- `test/qq_platform_test.dart`
- `test/kugou_playlist_test.dart`

### 验证

- `flutter test --no-pub` 通过�?1/61�?- `flutter analyze --no-pub` 过滤 error/warning 后：`ERROR_WARNING_COUNT=0`；剩余为既有 info �?lint 提示�?- `flutter build apk --release --no-pub` 通过�?- APK: `D:\Code_Work\My_Projects\Mconnect\build\app\outputs\flutter-apk\app-release.apk`
  - Size: 77,680,200 bytes / 74.08 MB
  - SHA256: `862998528722FD7120706A7E9660BDD1207819AA040D6C4043E644388E3F56D5`

## 2026-05-29 - 日志容量上限复核�?APK 打包

本轮按用户要求复核诊断日志不会无限增长，并重新生�?release APK�?
### 复核结果

- `lib/core/diagnostics/diagnostics_service.dart` 已有日志大小上限：默�?`maxLogBytes = 1024 * 1024`，即 1MB�?- 日志写入后会执行 `_truncateIfNeeded()`；超过上限时保留尾部近期内容，并写入 `log_truncated` 标记，避免文件持续变大�?- App 内日志路径入口仍为：`设置 -> 诊断 -> 诊断日志`�?- Android 真机日志文件通常位于：`/data/user/0/com.mconnect.mconnect/app_flutter/logs/mconnect.log`�?
### 验证

- `flutter test --no-pub test\diagnostics_service_test.dart test\settings_page_test.dart` 通过�?/4�?- `flutter build apk --release --no-pub` 通过�?- APK: `D:\Code_Work\My_Projects\Mconnect\build\app\outputs\flutter-apk\app-release.apk`
  - Size: 77,680,200 bytes
  - SHA256: `5AC37FF934C87F54AB825C5D251AFE71951BF770B98606175E6F5BCC12A4888C`

## 2026-05-29 - Phase 22 全局诊断日志、慢操作与卡死监�?
本轮按改进建议先落地诊断基础设施，用于后续定位“随机卡死”、播放器长时间无响应、平台请求挂起和导航栈异常等问题�?
### 规划

1. 第一阶段：新增全局 `DiagnosticsService`，负责慢操作计时、错误记录、UI �?isolate 心跳卡顿检测、最近事件内存缓冲和文件日志�?2. 第二阶段：接入高风险路径，包括全局 Flutter error、`runZonedGuarded` 未捕获异常、播放器播放/暂停/seek/setUrl/音质切换、平台播�?URL 请求、播放器打开/关闭导航事件�?3. 第三阶段：在设置页暴露“诊断日志”入口，让用户可以看到日志实际路径、复制路径、清空日志�?4. 后续阶段：继续把平台 API、数据库、下载队列和歌单加载接入同一诊断层，形成完整卡死证据链�?
### 日志输出位置

- 日志文件：`<应用文档目录>/logs/mconnect.log`
- Android 真机通常类似：`/data/user/0/com.mconnect.mconnect/app_flutter/logs/mconnect.log`
- App 内路径：`设置 -> 诊断 -> 诊断日志`，该项会显示实际路径；右侧菜单可复制路径或清空日志�?- 日志大小上限：默�?1MB，超过后自动截断并保留尾部近期内容，避免无限增长�?
### 修改内容

- `lib/core/diagnostics/diagnostics_service.dart`
  - 新增诊断服务，支�?`record()`、`recordError()`、`measure()`、`startUiHeartbeat()`、`flush()`、`clear()`�?  - 异步串行写入日志，避免日志系统阻�?UI�?  - 保存最�?200 条事件在内存中，文件日志超过 1MB 后自动截断�?- `lib/main.dart`
  - App 启动时初始化诊断服务�?  - 接入 `FlutterError.onError` �?`runZonedGuarded`�?  - 启动 UI 心跳监控，主 isolate 长时间不响应会写�?`ui_freeze`�?- `lib/features/player/presentation/providers/player_provider.dart`
  - 接入播放器关键慢操作监控：`stop`、`seek`、`setUrl`、播�?URL 获取、音质切�?URL 获取、音频互斥等待�?  - 播放开始、播�?ready、播放失败、音质切换失败会写入诊断日志�?- `lib/features/player/presentation/widgets/mini_player_bar.dart` / `lib/features/player/presentation/screens/player_screen.dart`
  - 记录�?mini 播放器进入播放页、关闭播放页的导航事件�?- `lib/features/settings/presentation/pages/settings_page.dart`
  - 新增“诊断日志”设置项，显示日志路径，并支持复制路径与清空日志�?
### 验证

- `flutter test --no-pub test\diagnostics_service_test.dart test\settings_page_test.dart` 通过�?/4�?- `flutter test --no-pub` 通过�?8/58�?- `flutter analyze --no-pub` 过滤 error/warning 后：`ERROR_WARNING_COUNT=0`�?
## 2026-05-29 - Phase 21 播放器返回不破坏来源页面�?
本轮修复从“我喜欢”等非首页页面反复进入播放器后，来源页面左上角返回键消失、安卓返回键直接退到桌面的导航栈问题�?
### 根因分析

- `MiniPlayerBar` 进入播放器时使用 `context.push('/player?from=...')`，这一步会把播放器压到当前页面栈上�?- `PlayerScreen._returnToSource()` 旧逻辑优先执行 `context.go(from)`。`go()` 会替换整个路由栈，而不是弹出播放器�?- 因此�?`/likes` 返回时，视觉上回到了“我喜欢”，但这个页面已经变成根页面，`AppBar` 自动返回键消失；安卓系统返回键也会直接退出应用�?- 该问题不只影响“我喜欢”，所有通过 mini 播放器进入播放器的非首页页面都有同类风险，例如听歌历史、设置、歌单详情等�?
### 修改内容

- `lib/features/player/presentation/screens/player_screen.dart`
  - 播放器返回逻辑改为：如果当前导航栈�?`pop`，优�?`pop()`；只有直接打开播放器且没有可弹出页面时，才回退�?`from` 或首页�?  - 下滑收起播放器和左上角按钮共用同一修复逻辑�?- `test/widget_test.dart`
  - 新增回归测试覆盖 `/likes` �?`/history`：反复从 mini 播放器进�?返回播放器后，来源页面仍保持在导航栈中，继续返回能回到首页�?
### 验证

- 新增测试先失败，失败信息�?`There is nothing to pop`，确认旧逻辑已把来源页面替换成根页面�?- `flutter test --no-pub test\widget_test.dart --plain-name "player return keeps"` 通过�?/2�?- `flutter test --no-pub test\widget_test.dart` 通过�?1/11�?- `flutter test --no-pub` 通过�?4/54�?- `flutter analyze --no-pub` 过滤 error/warning 后：`ERROR_WARNING_COUNT=0`�?- `flutter build apk --release --no-pub` 通过�?- APK: `build/app/outputs/flutter-apk/app-release.apk`
  - Size: 77,663,548 bytes
  - SHA256: `C16B04C26F4115914733A792D7330F489B22EAD1C1115917321136BE23CF364B`

## 2026-05-29 - Phase 20 平台音质命名与映射补�?
本轮修复各平台音质名称和请求映射不完整的问题。此前统一 `AudioLevel` 只有 5 档，网易云缺少环�?母带类音质，QQ 把多个高阶音质挤到同一�?`999` 逻辑中，�?QQ API �?`quality` 参数没有真正参与 `filename` 构造�?
### 根因分析

- `AudioLevel` 只有 `low/medium/high/lossless/hires`，无法表达网易云 `jyeffect/sky/jymaster` �?QQ `RS01/Q000/Q001/AI00` 等高阶音质�?- QQ `QqPlatform.getSongUrl()` 虽然接收音质参数，但 `QqApi.getSongUrl()` 固定请求 `M500...mp3`，导致切换到高品质、无损或臻品音质时仍按标准音质文件名请求�?- 下载弹窗写死标准/高品/无损三档，即使平台层已有更多音质也不会展示�?
### 修改内容

- `lib/models/audio_quality.dart`
  - 扩展 `AudioLevel.spatial/dolby/master`�?  - 平台化显示：
    - 网易云：标准、较高、极高、无损、Hi-Res、高清环绕声、沉浸环绕声、超清母带�?    - QQ 音乐：标准音质、HQ高品质、SQ无损品质、Hi-Res、臻品全景声2.0、臻品音�?.0、臻品母�?.0�?    - 酷狗：标准音质、高品音质、超品音质、无损音质、Hi-Res、VIPER HiFi、DSD�?  - 增加 `isLossless/isVipOnly/isSvipOnly`，供下载和会员提示统一判断�?- `lib/platform/netease/netease_platform.dart`
  - 网易云音�?level 映射补齐�?`standard/higher/exhigh/lossless/hires/jyeffect/sky/jymaster`�?- `lib/platform/qq/qq_api.dart` / `lib/platform/qq/qq_platform.dart`
  - QQ 播放 URL 请求按音质生�?`filename`：`M500/M800/F000/RS01/Q000/Q001/AI00`�?  - QQ 可用音质列表增加 Hi-Res、臻品全景声2.0、臻品音�?.0、臻品母�?.0�?- `lib/platform/kugou/kugou_platform.dart`
  - 可用音质列表增加 Hi-Res �?VIPER HiFi 显示档位；播�?URL 仍沿用当前酷狗接口能力，不伪造未接入的专用高�?URL 参数�?- `lib/features/download/presentation/widgets/download_button.dart`
  - 下载音质弹窗改为动态读取平�?`getAvailableQualities()`，失败时回退标准/HQ/无损三档�?
### 参考核�?
- NeteaseCloudMusicApi `SoundQualityType` / `song_url_v1` 相关实现：`standard/higher/exhigh/lossless/hires/jyeffect/sky/jymaster`�?- QQ 音乐公开实现中的 CgiGetVkey 文件名前缀：`M500/M800/F000/RS01/Q000/Q001/AI00`，分别用于标准、HQ、SQ、Hi-Res、臻品全景声2.0、臻品音�?.0、臻品母�?.0�?- 酷狗当前公开项目和客户端命名中可见标�?高品/无损/Hi-Res/VIPER HiFi/DSD 等命名，但不同接口的实际 URL 参数稳定性较差，本轮只补齐展示和枚举，不冒进修改播放请求�?
### 验证

- 新增/更新测试先失败，确认覆盖枚举缺失、网易云 level 映射缺失、QQ filename 固定标准音质、下载弹窗缺少高级音质等问题�?- `flutter test --no-pub test\audio_quality_test.dart test\netease_api_test.dart test\qq_api_test.dart test\download_button_test.dart` 通过�?2/12�?- `flutter test --no-pub` 通过�?2/52�?- `flutter analyze --no-pub` 过滤 error/warning 后：`ERROR_WARNING_COUNT=0`�?- `flutter build apk --release --no-pub` 通过�?- APK: `build/app/outputs/flutter-apk/app-release.apk`
  - Size: 77,663,548 bytes
  - SHA256: `0F1869C04E7DD55A16258C29B782E602B0566257D92B54AACEE15D8D4E9D292E`

## 2026-05-29 - Phase 19 迷你播放器文字样式修�?
本轮修复进入非首页页面后，底�?mini 播放器歌曲标题变红并出现双下划线、歌手名变淡黄色并出现黄色双下划线的问题�?
### 根因分析

- `AppRouteShell` �?`/likes`、`/history`、`/settings` 等非首页路由下直接返回顶�?`Column`�?- 这些页面自身�?`Scaffold`，但 `MiniPlayerBar` 是页�?`Scaffold` 的兄弟节点，不在任何正常�?`Material`/`DefaultTextStyle` 文本环境内�?- Flutter 在缺少正常文本样式时会使�?fallback `DefaultTextStyle`，其典型表现就是红色/黄色文字和双下划线�?
### 修改内容

- `lib/core/router/app_router.dart`
  - 为非首页路由 shell 增加 `Material` 与主�?`DefaultTextStyle` 包裹�?  - 保持 mini 播放器在非播放器页面常驻，不改变 `/player` 全屏播放页的行为�?- `test/widget_test.dart`
  - 新增回归测试 `route shell gives mini player normal material text style`，检�?mini 播放器歌曲名和歌手名不再继承 Flutter fallback 双下划线样式�?
### 验证

- 新增回归测试先失败，确认覆盖�?fallback `DefaultTextStyle` 泄漏问题�?- `flutter test --no-pub test\widget_test.dart --plain-name "route shell gives mini player normal material text style"` 通过�?- `flutter test --no-pub test\widget_test.dart` 通过�?/9�?- `flutter test --no-pub` 通过�?8/48�?- `flutter analyze --no-pub` 过滤 error/warning 后：`ERROR_WARNING_COUNT=0`�?- `flutter build apk --release --no-pub` 通过�?- APK: `build/app/outputs/flutter-apk/app-release.apk`
  - Size: 77,647,164 bytes
  - SHA256: `0DE5D27B685AB84C12B464CDA64A314459E5A330FDD43F9F275EB2C754423100`

## 2026-05-29 - Phase 18 播放器稳定性、歌词交互、全局迷你播放器与本地音乐

本轮按计划处理播放器卡死根因、歌词显示入口、双语歌词、音质命名、每日推荐范围、迷你播放器常驻以及本地音乐扫描/播放�?
### 根因与修�?
1. 音质选择后卡死的直接根因�?`switchQuality()` 在播放器互斥队列内等待平�?URL 请求，且该请求没有超时。一旦平台请求挂起，后续暂停、播放、切歌都会排队等待。已为音�?URL 请求加入超时和请求序号保护，并让音质弹窗先关闭再异步切换�?2. 歌词入口从顶部按钮扩展为点击播放器中部封�?歌词区域切换，顶部按钮保留并复用同一状态切换方法�?3. LRC 同时间戳原文/译文不再拼进同一�?`text` 字段，改�?`LyricsLine.translation`。普通歌词和 QRC/KRC 逐字歌词都会在原文下方显示官方译文�?4. 音质标签改为按平台显示：网易云保留“标�?较高/极高/无损/Hi-Res”，QQ 使用 “HQ高品�?/ SQ无损品质 / 臻品母带”，酷狗使用 “高品音�?/ 无损音质 / VIPER HiFi�?等平台命名�?5. QQ/酷狗每日推荐仍无稳定可验证结果，因此默认每日推荐页面只加载网易云，避免继续显示空�?QQ/酷狗日推入口�?6. 新增路由壳层 `AppRouteShell`，让 `/likes`、`/history`、`/settings`、歌单详情等非播放器页面底部保持迷你播放器；`/player` 保持全屏独立，不显示迷你播放器�?7. 新增本地音乐功能�?   - 音乐库新增“本地音乐”入口�?   - 使用文件夹选择器扫描用户选定目录�?   - 支持常见音频扩展：mp3、flac、wav、m4a、aac、ogg、opus、mp4、alac、aiff、aif�?   - 匹配同目录或 `lyrics/` 子目录中的同�?lrc/krc/qrc/txt 歌词文件�?   - 本地歌曲使用 `PlatformType.local`，播放时直接使用本地 file URI，不经过远程平台解析�?
### 构建修复

- `file_picker` 11 使用 `FilePicker.getDirectoryPath()`，已按当�?API 接入�?- `flutter_native_splash` 2.4.7 声明 Android plugin，release 生成�?plugin registrant 会引用它。为避免 dev dependency 不在 release classpath 中导�?`compileReleaseJavaWithJavac` 失败，已将其移入�?dependencies�?
### 新增/更新测试

- `test/player_provider_test.dart`
  - 覆盖音质切换 URL 请求挂起时，播放/暂停控制不能被永久阻塞�?  - 覆盖本地文件播放不调用远程平�?resolver�?- `test/widget_test.dart`
  - 覆盖播放器中部区域点击切换歌词�?  - 覆盖非首页路由仍显示迷你播放器，播放器页不显示迷你播放器�?- `test/lyrics_line_test.dart`
  - 覆盖同时间戳 LRC 原文/译文结构化合并�?  - 覆盖逐字歌词显示官方译文�?- `test/audio_quality_test.dart`
  - 覆盖平台化音质命名�?- `test/recommendations_provider_test.dart`
  - 覆盖每日推荐只加载已验证的网易云平台�?- `test/local_music_repository_test.dart`
  - 覆盖本地目录扫描和同名歌词匹配�?
### 验证

- `flutter test --no-pub` 通过�?7/47�?- `flutter analyze --no-pub` 过滤 error/warning 后：`ERROR_WARNING_COUNT=0`。完�?analyze 仍有既有 info �?lint�?- `flutter build apk --release --no-pub` 通过�?- APK: `build/app/outputs/flutter-apk/app-release.apk`
  - Size: 77,647,164 bytes
  - SHA256: `8E7D088F7891E5CC40F4ADA2AE42BA2E4C3117027674B6E57B73DDCC4712D4D5`

## 2026-05-28 - Phase 17 QQ 日推可见性、酷�?QR 账号落地�?UI/性能小修

本轮处理用户反馈�?4 类问题：QQ 音乐每日推荐仍不出现、酷狗扫码确认后账号管理仍显示未登录、UI 动画还有可优化空间、运行性能可继续优化�?
### 根因分析

1. 酷狗 QR 登录的状态流在服务端返回 `status=4` 后会直接抛出 `QrLoginStatus.success`，但如果随后 `getUserInfoFromToken()` 失败，平台层 `_currentUser` 仍然�?`null`。同时登录页收到 success 后没有等�?`AuthNotifier.onQrLoginSuccess()` 完成，`onQrLoginSuccess()` 旧实现也只保�?session、不刷新 `AuthState`，所以会出现“页面提示登录成功，但账号管理仍是点击登录”�?2. 每日推荐页面只用 `songsByPlatform.keys` 生成 tab。QQ 已登录但接口返回空、超时或失败时，provider 旧逻辑不会�?QQ 放入 `songsByPlatform`，UI 就把 QQ tab 整个隐藏，因此看起来像“只有网易云，没�?QQ”�?3. QQ Music OAuth 完成后，`QQConnectLogin.LoginServer.QQLogin` 返回�?`musickey` / `musicid` �?QQ 音乐专用字段没有被写�?cookie。参�?QQMusicApi �?`/daily` 路由，QQ 每日 30 首依赖带登录 cookie 访问 `musicmac/v6/index.html` 上的“今日私享”歌单；缺少 `qqmusic_key` / `qm_keyst` / `qqmusic_uin` 时容易拿不到该歌单�?4. QQ cookie 解析还有一个隐患：旧正则查�?`skey` 时可能误命中 `p_skey` 的后半段，导致后�?cookie 合并不稳定�?5. 首页 PageView �?tab 页面缺少明确的懒加载缓存和绘制隔离。正常滑动能用，但频繁切 tab 时会增加不必要的页面实例创建和重绘压力�?
### 修改内容

- `lib/platform/kugou/kugou_platform.dart`
  - 酷狗 QR 成功后必须先建立 `_currentUser` 再上�?success�?  - �?profile 接口失败�?QR 响应已有 `token/userid` 时，创建“酷狗用户”兜底账号，避免登录状态丢失�?- `lib/features/auth/presentation/providers/auth_provider.dart`
  - `onQrLoginSuccess()` 改为刷新平台用户、更�?Riverpod 登录态，然后再保�?session�?- `lib/features/auth/presentation/pages/login_page.dart`
  - QR success 分支等待 `onQrLoginSuccess()` 完成后再提示和返回，避免账号管理页面读到旧状态�?- `lib/platform/qq/qq_api.dart`
  - QQ OAuth 成功后合�?`musickey/musicid/uin/openid/access_token/refresh_key` 等字段�?  - 写入 `qqmusic_key`、`qm_keyst`、`qqmusic_uin`、`loginUin`，提高“今日私�?/ 每日 30 首”接口能识别登录态的概率�?  - cookie 解析过滤 `Path/Domain/Expires/HttpOnly` �?Set-Cookie 属性，并修复精�?cookie 名匹配�?- `lib/features/discovery/presentation/providers/recommendations_provider.dart`
  - 已登录平台即使返回空列表或错误，也会保留�?`songsByPlatform`，不再从 UI 中消失�?- `lib/features/discovery/presentation/pages/recommendations_page.dart`
  - 每个平台 tab 内独立显示“暂无每日推荐”或加载失败原因；QQ 失败时能看到 QQ tab 和错误，而不是被隐藏成只有网易云�?- `lib/features/home/presentation/screens/home_screen.dart`
  - 首页 tab 页面改为懒加载缓存，切换回来时复用已创建页面�?  - 给页面加 `RepaintBoundary` �?`TickerMode`，减少非当前页动画和重绘负担�?- 新增/更新测试�?  - `test/auth_provider_test.dart`
  - `test/kugou_login_test.dart`
  - `test/qq_api_test.dart`
  - `test/recommendations_provider_test.dart`
  - `test/widget_test.dart`

### 参考接�?
- QQMusicApi `routes/recommend.js`：`/daily` 通过登录 cookie 读取 `musicmac/v6/index.html` 的“今日私享”歌单�?- KuGouMusicApi QR 登录相关模块用于核对酷狗 QR 状态字段和 token/userid 流程�?
### 验证

- 新增回归测试先失败，确认覆盖了酷�?QR 用户丢失、QR success 未刷�?AuthState、QQ Music token cookie 丢失、QQ 日推平台被隐藏、首�?tab 页面重复创建等问题�?- 定向测试通过：`flutter test --no-pub test\kugou_login_test.dart test\auth_provider_test.dart test\qq_api_test.dart test\recommendations_provider_test.dart test\widget_test.dart`
- 全量测试通过：`flutter test --no-pub`�?9/39�?- analyzer 过滤检查：`ERROR_WARNING_COUNT=0`；完�?`flutter analyze --no-pub` 仍因既有 info �?lint 返回 exit code 1�?- `flutter build apk --release --no-pub` 通过�?- APK: `build/app/outputs/flutter-apk/app-release.apk`
  - Size: 77,090,963 bytes
  - SHA256: `BAD8C4080B8595B4A701375D91B76ADCF0E760B0FCACFEB77186093E223A6EBC`

## 2026-05-28 - Phase 16 酷狗 QR、双语歌词、歌单卡死与 QQ 每日推荐稳定性修�?
本轮处理用户反馈�?4 个问题：酷狗扫码后提示确认失效、非中文歌缺少翻译歌词、点击歌单仍可能卡死、QQ 音乐每日 30 首仍不出现�?
### 根因分析

1. 酷狗 QR 登录不仅是二维码 URL 问题。对�?KuGouMusicApi 后发�?`/v2/qrcode` �?`/v2/get_userinfo_qrcode` �?web 签名必须包含 `dfid/mid/uuid/clientver/clienttime` 等默认参数；旧实现只签了业务参数，实�?`/v2/qrcode` 返回 `error_code=20010`。同时旧二维码展�?URL 没有携带生成 key 时绑定的 `appid=1005`�?2. 歌词接口实际会返回翻译字段：网易云是 `tlyric.lyric`，QQ �?`trans`；旧实现只返回原�?`lrc/lyric`，所以非中文歌曲无法同时显示翻译�?3. 歌单详情卡死的主要剩余风险在网易云：旧实现请�?`n=100000` 首，超大歌单会让 JSON 解码�?`Song` 对象构建占住 Flutter �?isolate，表现为点击歌单�?App 假死�?4. QQ 每日推荐依赖“今日私享”歌单。旧实现若其他已登录平台日推请求挂起，会串行拖住 QQ；同�?QQ 歌单详情里的歌曲行可能包�?`songInfo` 下，旧解析会得到空白歌曲�?
### 修改内容

- `lib/platform/kugou/kugou_api.dart`
  - `web` 签名参数补齐 `dfid/mid/uuid/clientver/clienttime`，与 KuGouMusicApi 的请求结构对齐�?- `lib/platform/kugou/kugou_platform.dart`
  - 二维�?URL 改为 `appid=1005&qrcode=...`�?  - 优先使用酷狗接口返回�?`qrcode_img` 图片字节展示二维码，URL 作为备用�?- `lib/platform/netease/netease_api.dart` / `lib/platform/netease/netease_platform.dart`
  - 歌单详情请求上限�?`100000` 降到 `1000`，并在平台层再次 `take(1000)` 防御接口忽略参数�?  - 歌词返回合并 `lrc` �?`tlyric`�?- `lib/platform/qq/qq_api.dart` / `lib/platform/qq/qq_platform.dart`
  - QQ 歌词返回合并 `lyric` �?`trans`�?  - QQ 每日推荐歌单详情兼容 `songInfo/song/musicData` 包装�?- `lib/lyrics/models/lyrics_line.dart`
  - LRC 解析器合并相同时间戳的原�?翻译行，UI 会在同一时间轴显示双语文本�?- `lib/features/discovery/presentation/providers/recommendations_provider.dart`
  - 每个平台每日推荐改为并行加载，并为单个平台加 12 秒超时，避免一个平台卡住导�?QQ 每日 30 首不出现�?- 新增/更新测试�?  - `test/kugou_login_test.dart`
  - `test/qq_api_test.dart`
  - `test/netease_api_test.dart`
  - `test/lyrics_line_test.dart`
  - `test/recommendations_provider_test.dart`

### 参考接�?
- KuGouMusicApi `login_qr_key.js` / `login_qr_check.js`
- QQMusicApi `recommend.js`：`/daily` 通过 `musicmac/v6/index.html` 的“今日私享”歌单获取每日推荐�?
### 验证

- 新增定向测试首次运行失败，确认覆盖了酷狗签名缺参、二维码 appid 缺失、翻译歌词丢失、网易云歌单请求过大、LRC 同时间轴不合并等问题�?- 修复后定向测试通过�?4/14�?- `flutter test --no-pub` 通过�?2/32�?- analyzer 过滤检查无 `error -` / `warning -`；完�?`flutter analyze --no-pub` 仍因既有 info �?lint 返回 exit code 1�?- `flutter build apk --release --no-pub` 通过�?- APK: `build/app/outputs/flutter-apk/app-release.apk`
  - Size: 76,992,603 bytes
  - SHA256: `8E656D632F94451647F2DD435E945D05869DD50EEBE2724FE04EC833633A0175`

## 2026-05-28 - Phase 15 播放器手势、歌单详情、队列播放与平台接口修复

本轮处理播放器、歌单、播放队列、酷�?QR 登录、QQ 每日 30 首相关问题�?
### 根因分析

1. 播放器页面此前只有左上角按钮返回，没有下滑手势�?2. “歌单没有封面”主要是歌单列表页固定使用图标，没有展示 `Playlist.coverUrl`；同时网易云解析缺少部分封面字段兼容�?3. 搜索歌单和我的歌单只有列表项，没有详情路由，因此点不进去，也无法播放歌单内歌曲�?4. 进度条拖动时 `Slider.onChanged` 会高频调�?`seek()`；旧实现把每�?seek 都放入播放器互斥锁，底层 seek 一旦卡住，后续暂停、播放其他歌、切歌都会排队等待�?5. 每日推荐、排行榜、喜欢、历史、导入歌单、搜索结果等列表页以前点击单曲只调用 `playSong(song)`，没有把当前列表写入播放队列，所以下一�?上一首在每日推荐里没有可用上下文�?6. 酷狗 QR 登录参�?KuGouMusicApi 当前实现后发�?key 生成接口�?appid 使用不一致：生成 key 应使�?1001，二维码页面/状态检查使�?1005；旧实现一直用 1014 生成 key，容易导致酷�?App 提示确认已失效�?7. QQ 每日 30 首参�?QQMusicApi 当前实现后确认应优先�?`musicmac/v6/index.html` 的“今日私享”歌单取 id，再走歌单详情；旧实现先�?musicu 日推接口�?HTML 解析窗口过窄，容易返回空�?
### 修改内容

- `lib/features/player/presentation/screens/player_screen.dart`
  - 增加下滑收起播放器页面�?  - 进度条改为拖动时只更新本地显示，松手后只发起一�?seek，避�?seek 风暴�?- `lib/features/player/presentation/providers/player_provider.dart`
  - `seek()` 不再占用全局音频互斥锁�?  - seek 超时缩短到最�?2 秒，底层 seek 异常时不会阻塞后续播放或切歌�?- `lib/features/library/presentation/pages/playlist_detail_page.dart`
  - 新增歌单详情页，支持加载歌单歌曲、播放全部、点击任意歌曲后以整张歌单作为播放队列�?- `lib/core/router/app_router.dart`
  - 新增 `/playlist/:platform/:id` 路由�?- `lib/features/search/presentation/screens/search_screen.dart`
  - 歌单搜索结果可点击进入详情�?  - 搜索歌曲结果点击后使用整页搜索结果作为播放队列�?- `lib/features/library/presentation/pages/platform_playlists_page.dart`
  - 我的平台歌单列表显示封面，并可点击进入详情�?- `lib/platform/netease/netease_platform.dart`
  - 网易云歌单封面字段增�?`picUrl` / `imgurl` 兼容�?- `lib/platform/qq/qq_platform.dart` / `lib/platform/qq/qq_api.dart`
  - QQ 每日推荐优先按“今日私享”歌单解析，返回最�?30 首�?  - “今日私享”歌�?id 解析扩大匹配范围并兼容更�?HTML 写法�?- `lib/platform/kugou/kugou_api.dart` / `lib/platform/kugou/kugou_platform.dart`
  - 酷狗 QR key 生成 appid 调整�?1001�?  - QR 状态码统一�?int，避免字符串状态不匹配�?- `lib/features/discovery/presentation/pages/recommendations_page.dart`
- `lib/features/discovery/presentation/pages/rankings_page.dart`
- `lib/features/discovery/presentation/screens/discovery_screen.dart`
- `lib/features/library/presentation/pages/likes_page.dart`
- `lib/features/library/presentation/pages/history_page.dart`
- `lib/features/library/presentation/pages/import_playlist_page.dart`
  - 列表项播放全部改为写入当前列表队列，修复上一�?下一首无反应的问题�?- `test/player_provider_test.dart`
  - 新增回归测试：底�?seek 挂起时仍能播放另一首歌�?- `test/widget_test.dart`
  - 新增回归测试：播放器页面可下滑收起�?
### 参考接�?
- QQMusicApi `recommend.js`：`/daily` 通过 `今日私享` 歌单获取每日推荐�?- KuGouMusicApi `login_qr_key.js` / `login_qr_check.js` / `login_qr_create.js`：QR key、状态检查、二维码 URL 生成流程�?
### 验证

- `flutter test --no-pub` 通过�?3/23�?- analyzer 过滤检查无 `error -` / `warning -`；完�?`flutter analyze --no-pub` 仍因项目既有 info �?lint 返回 exit code 1�?- `flutter build apk --release --no-pub` 通过�?- APK: `build/app/outputs/flutter-apk/app-release.apk`
  - Size: 76,992,603 bytes
  - SHA256: `E1D03203F4BF0F94BBD0586F194D084C906554D178FD4472A1323602341D038D`

## 2026-05-28 - Phase 14 中文文案与歌单入口卡死修�?
本轮处理两个问题：可�?UI 中遗留的英文/乱码文案，以及进入平台歌单界面时仍像卡死一样长时间不可用的问题�?
### 根因分析

1. 中文乱码并不是整个项目文档损坏。`PROJECT.md` 和旧 `CHANGELOG.md` �?`rg` 能读出正常中文，`Get-Content` 显示乱码主要�?PowerShell 输出编码问题�?2. 真正写进 Dart 源码并会显示�?App 里的乱码集中�?`lib/features/search/presentation/screens/search_screen.dart`，例如搜索框提示和加载失败文案�?3. 歌单页卡死的核心原因�?`platform_playlists_provider.dart` 旧实现串行等待所有平台：一个平台请求超时或挂起时，整个歌单页一直停在全局 loading，其他已经返回的平台也不会显示�?4. 播放器里的“添加到平台歌单”弹窗虽然有超时，但等待期间缺少明确关闭入口，用户感知上仍像被锁住�?
### 修改内容

- `lib/features/library/presentation/providers/platform_playlists_provider.dart`
  - 改为按平台并�?增量加载，哪个平台先返回就先显示哪个平台的数据�?  - 新增 `isLoadingFor(platform)` �?`isCreatingFor(platform)`，去掉“一个慢平台拖住整个页面”的全局阻塞体验�?  - 每个平台独立记录错误和超时，单个平台失败不会影响其他平台�?- `lib/features/library/presentation/pages/platform_playlists_page.dart`
  - 歌单页改为每�?tab 自己显示加载、错误、空状态�?  - 刷新按钮只刷新当前平台，新增歌单按钮在当前平台创建中会禁用并显示加载�?  - 全部新增 UI 文案改为中文�?- `lib/features/player/presentation/widgets/playlist_picker_sheet.dart`
  - 歌单选择弹窗增加关闭按钮�?  - 未登录平台直接返回空列表，不再发起无意义请求�?  - 弹窗加载失败、重试、空状态、添加失败等文案改为中文�?- `lib/features/player/presentation/screens/player_screen.dart`
  - 歌单弹窗启用可拖�?滚动弹出行为，避免小屏和长列表下交互受限�?- `lib/features/search/presentation/screens/search_screen.dart`
  - 修复搜索页真实源码乱码�?  - “Songs / Playlists / Playlist saved / Save failed”等新增英文文案改为中文�?- `lib/features/library/presentation/screens/library_screen.dart`
  - 音乐库入口文案从英文恢复为中文�?- `lib/features/home/presentation/screens/home_screen.dart`
  - 底部导航文案从英文恢复为中文�?- `lib/platform/base/platform_registry.dart`
  - 平台不支持错误信息改为中文�?- `test/platform_playlists_provider_test.dart`
  - 新增回归测试：一个平台挂起时，另一个快速返回的平台必须先显示数据�?- `test/playlist_picker_sheet_test.dart` / `test/search_screen_test.dart`
  - 更新断言为中�?UI 文案�?
### 验证

- `flutter test --no-pub` 通过�?1/21�?- analyzer 过滤检查无 `error -` / `warning -`；完�?`flutter analyze --no-pub` 仍因项目既有 info �?lint 返回 exit code 1�?- 乱码/英文 UI 扫描未发现剩余目标文案；唯一命中是代码字段名 `dailySongs`，不是界面文案�?- `flutter build apk --release --no-pub` 通过�?- APK: `build/app/outputs/flutter-apk/app-release.apk`
  - Size: 76,910,683 bytes
  - SHA256: `C8D5E53C8C70D610A1DB913840AB760CC0037208493F168C2076E1666DE92212`

## 2026-05-28 - Phase 13 Platform Playlists / Playlist Search / Swipe UI / Freeze Fixes

This phase addresses the latest account, playlist, recommendation, and UI requests, with special focus on preventing hard freezes when platform playlist operations hang or fail.

### Changes

- `lib/features/player/presentation/widgets/playlist_picker_sheet.dart`
  - Reworked platform playlist picker with bounded height, retry/error states, and 12-second timeouts for both playlist loading and add-to-playlist operations.
  - Fixed the severe freeze path where opening existing platform playlists could leave the app stuck behind an infinite operation.
- `lib/platform/base/music_platform.dart`
  - Added platform contracts for playlist search, playlist creation, and playlist collection.
- `lib/models/playlist.dart`
  - Added editable/collected metadata used by platform playlist management and search results.
- `lib/platform/qq/qq_api.dart` / `lib/platform/qq/qq_platform.dart`
  - Expanded QQ login username recovery from more cookie/profile fields.
  - Added QQ playlist search, user playlist loading, playlist creation, playlist collection, and daily recommendation fallback via the daily private playlist page.
- `lib/platform/kugou/kugou_api.dart` / `lib/platform/kugou/kugou_platform.dart` / `lib/platform/kugou/kugou_endpoints.dart`
  - Added best-effort Kugou QR login flow based on current public KuGouMusicApi-compatible routes.
  - Added Kugou playlist search, user playlist loading, playlist creation, and collection entry points.
- `lib/platform/netease/netease_api.dart` / `lib/platform/netease/netease_platform.dart`
  - Added Netease playlist search, playlist creation, and playlist subscription support.
- `lib/features/library/presentation/screens/library_screen.dart`
  - Added the Library -> Playlists entry.
- `lib/features/library/presentation/providers/platform_playlists_provider.dart`
  - Added cross-platform playlist loading and playlist creation state management with operation timeouts.
- `lib/features/library/presentation/pages/platform_playlists_page.dart`
  - Added platform tabs for user-created playlists and in-app playlist creation.
- `lib/core/router/app_router.dart`
  - Added `/platform-playlists` route.
- `lib/features/search/presentation/screens/search_screen.dart`
  - Added song/playlist search mode switching and playlist collection actions.
- `lib/features/home/presentation/screens/home_screen.dart`
  - Replaced fixed tab switching with a swipeable PageView and a layered page transition effect.
  - Prevents over-swiping past the leftmost/rightmost tabs by relying on bounded PageView navigation.
- `lib/features/auth/presentation/pages/login_page.dart`
  - Enabled QR login UI for Kugou.
- Tests added/updated:
  - `test/qq_platform_test.dart`
  - `test/playlist_picker_sheet_test.dart`
  - `test/search_screen_test.dart`
  - `test/widget_test.dart`
  - Updated platform fakes in existing provider/player tests.

### Verification

- `flutter test --no-pub` passed: 20/20 tests.
- Analyzer filtered check found no `error -` or `warning -`; full `flutter analyze --no-pub` still returns exit code 1 because of existing info-level lint items.
- `flutter build apk --release --no-pub` passed.
- APK: `build/app/outputs/flutter-apk/app-release.apk`
  - Size: 76,894,299 bytes
  - SHA256: `5D3E034F7699EB88E588B2B46B07253DBB9739B0DFA79AF578A003C1F1C4B8AF`

### Notes

- Kugou QR login and playlist write operations are implemented against public KuGouMusicApi-style references and may still be affected by Kugou server risk controls or signature changes.
- Some newly rewritten UI text is currently ASCII to avoid compounding the existing source encoding corruption; a dedicated UTF-8 normalization pass is recommended before restoring all Chinese copy.

## 2026-05-28 - Phase 12 Player / Account / Lyrics / Download Fixes

修复本轮反馈的播放器导航、账号信息、验证码、歌词同步、收藏、歌单添加入口和下载入口问题，并重新打包 release APK�?
### 修改内容

- `lib/features/player/presentation/widgets/mini_player_bar.dart`
  - 进入播放器时携带当前来源地址，避免返回时落到下载管理或丢失原 tab�?- `lib/features/player/presentation/screens/player_screen.dart`
  - 返回按钮优先回到进入播放器前的位置�?  - 新增收藏按钮、下载按钮、添加到平台歌单入口�?  - 播放器主体改为小屏自适应滚动布局，避免低高度设备底部溢出�?- `lib/features/player/presentation/providers/player_provider.dart`
  - `playSong()` 在音频开始播放请求发出后立即清除 loading 并同�?`isPlaying=true`，避免音乐已播放但暂停键长时间转圈�?- `lib/features/player/presentation/widgets/lyrics_display.dart`
  - 通过 500ms 定时读取播放器进度刷新歌词，提升歌词随播放时间轴滚动的稳定性�?- `lib/features/player/presentation/widgets/playlist_picker_sheet.dart`
  - 新增平台歌单选择底部弹窗，支持将当前歌曲添加到已登录平台的歌单�?- `lib/features/download/presentation/widgets/download_button.dart`
  - 补齐歌曲下载按钮的显式依赖导入，下载入口接入播放器、搜索、推荐和排行列表�?- `lib/features/auth/presentation/pages/login_page.dart`
  - 手机验证码输入框新增“获取验证码”按钮�?- `lib/features/auth/presentation/providers/auth_provider.dart`
  - 增加平台验证码发送调用�?- `lib/platform/base/music_platform.dart`
  - 增加 `sendPhoneCode()` �?`addSongToPlaylist()` 平台接口�?- `lib/platform/qq/qq_api.dart` / `lib/platform/qq/qq_platform.dart`
  - QQ 登录后改�?profile homepage 接口刷新真实昵称，避免一直显示“QQ用户”�?  - 增加 QQ 添加歌曲到歌单接口�?- `lib/platform/netease/netease_platform.dart`
  - 增加网易云发送验证码和添加歌曲到歌单实现�?- `lib/platform/kugou/kugou_api.dart` / `lib/platform/kugou/kugou_platform.dart`
  - 增加酷狗发送手机验证码入口�?  - 修复酷狗歌词下载解码：LRC base64 fallback、KRC 解压后不再错误丢弃第一个字节�?  - 酷狗添加歌曲到歌单仍受限：参�?MakcRe/KuGouMusicApi �?`/cloudlist.service/v6/add_song` 需�?Android signature/encryptType 链路，当前项目还未完整移植该加密请求层，因此 UI 会显示失败而不是伪装成功�?- `lib/lyrics/models/lyrics_line.dart`
  - KRC 解析跳过空文本行，避免无效歌词行干扰同步�?- `test/widget_test.dart`
  - 覆盖 tab URL 同步和播放器来源返回�?- `test/player_provider_test.dart`
  - 覆盖播放请求不阻塞、音频操作超时恢复、播�?ready �?loading 清除�?- `test/lyrics_line_test.dart`
  - 覆盖酷狗 LRC base64 �?KRC 完整解码�?- `test/qq_platform_test.dart`
  - 覆盖 QQ profile 昵称解析�?
### Verification

- `flutter test --no-pub` passed: 14/14 tests.
- Analyzer filtered check found no `error -` or `warning -`; full `flutter analyze --no-pub` still reports existing info-level lint items in the project/scripts.
- `flutter build apk --release` passed.
- APK: `build/app/outputs/flutter-apk/app-release.apk`
  - Size: 76,648,351 bytes
  - SHA256: `2A3F8748AAEF2BBDA941D3183085AF7BCCF0895CE672D3ADED38CDDFD96AECD7`

## 2026-05-28 - APK packaging config fix

- `android/app/proguard-rules.pro`
  - Added the R8-generated Play Core split-install `-dontwarn` rules.
  - Root cause: release builds enable minify/shrink, while this app does not use Flutter deferred components. Flutter Android embedding still references optional Play Core classes, so R8 treated them as missing classes.

### Verification

- `flutter build apk --release` initially failed at `:app:minifyReleaseWithR8`; the generated rule file was `build/app/outputs/mapping/release/missing_rules.txt`.
- After adding the rules, `flutter build apk --release` passed and produced `build/app/outputs/flutter-apk/app-release.apk` (76,271,203 bytes, SHA256 `41964FC884008F0A2694B7178831A6CEEB0B62BC027546908F47E8E964320FA4`).

## 2026-05-28 - Phase 11 Stability Hotfix

修复播放器和启动链路的高风险卡死点，并修复推荐登录态传播�?
### 修改文件

- `lib/features/player/presentation/providers/player_provider.dart`
  - 新增可测试的 `PlayerAudioController` 适配层�?  - `AudioPlayer.play()` 改为 fire-and-forget，不再占用音频互斥锁直到整首歌结束�?  - `stop` / `setUrl` / `seek` / `pause` 加超时保护；平台通道卡住时重建播放器�?  - 音频播放器改为懒加载，首页未播放歌曲时不创建原生播放器�?  - 增加 transition watchdog，避免暂停键/播放键永久转圈�?- `lib/main.dart` / `lib/core/theme/theme_provider.dart`
  - 启动时显式初始化 Hive�?  - 主题加载/保存失败时记录日志，不让持久化异常打崩首屏�?- `lib/features/library/presentation/providers/history_provider.dart`
  - 听歌历史从“切歌瞬间写库”改为“确认开始播放后延迟 3 秒写库”，减少播放准备阶段 DB 压力�?- `lib/features/discovery/presentation/providers/recommendations_provider.dart`
  - 推荐加载支持部分成功，记�?`errorsByPlatform`�?  - 区分未登录、全部接口失败、接口返回空列表�?- `lib/features/discovery/presentation/providers/playlist_recommendations_provider.dart`
  - 与每日推荐一致，避免已登录平台部分失败时整体退回“请登录”�?- `lib/features/auth/presentation/providers/auth_provider.dart`
  - 会话恢复改为调用平台 `restoreSession()`，确保平台内�?`isLoggedIn` �?`AuthState` 一致�?  - 会话保存改为调用平台 `saveSession()`�?- `lib/features/discovery/presentation/screens/discovery_screen.dart`
  - 登录态变化后自动刷新发现页推荐�?  - post-frame callback 增加 `mounted` 防护�?- `lib/features/discovery/presentation/pages/recommendations_page.dart`
  - 登录态变化后自动刷新每日推荐�?  - post-frame callback 增加 `mounted` 防护�?- `lib/features/auth/presentation/pages/login_page.dart`
  - 异步登录/二维码加载后增加 `mounted` 防护，避免页面退出后 `setState`�?- `lib/platform/kugou/kugou_api.dart` / `lib/platform/kugou/kugou_platform.dart`
  - 酷狗歌词下载增加 LRC fallback�?  - 搜索 fallback 增加 song-only 和秒/毫秒 duration 兼容�?- `lib/features/player/presentation/providers/lyrics_provider.dart`
  - 缓存解析为空时不再直接返回空文档，会重新请求歌词�?- `test/player_provider_test.dart`
  - 覆盖播放器懒加载、`play()` 非阻塞、有限音频操作超时恢复�?- `test/recommendations_provider_test.dart`
  - 覆盖多账号推荐部分成功和未登录空状态�?- `test/widget_test.dart`
  - 覆盖首页首帧不会急切创建原生音频播放器�?
### 验证

- `flutter test --no-pub test/player_provider_test.dart` 通过�?/4�?- `flutter test --no-pub test/recommendations_provider_test.dart` 通过�?/2�?- `flutter test --no-pub test/widget_test.dart` 通过�?/1�?- `flutter analyze --no-pub` 曾返回既�?info/warning；后续两�?analyze �?Flutter 工具层超时，未取得新的完整静态分析结果�?
## 2026-05-28 - Phase 10 Bug 修复 (第二�?

修复 4 个顽�?Bug：App 卡死、网易云无法播放、暂停按钮转圈、酷狗无歌词�?
### 修改文件

- `lib/features/download/data/repositories/download_manager.dart` �?下载进度 1 秒节�?- `lib/features/download/presentation/screens/download_page.dart` �?`.select()` 精细订阅替代全量 watch
- `lib/features/home/presentation/screens/home_screen.dart` �?IndexedStack + KeyedSubtree 保留 tab State
- `lib/features/library/presentation/providers/history_provider.dart` �?批量查询替代 N+1 (200�? �?
- `lib/features/library/presentation/providers/likes_provider.dart` �?批量查询替代 N+1 (500�? �?
- `lib/core/database/app_database.dart` �?新增 `SongsDao.getSongsByIds()` 批量查询
- `lib/features/player/presentation/screens/player_screen.dart` �?position/duration 改用 Timer + ref.read()
- `lib/platform/netease/netease_api.dart` �?restoreCookie 改为合并模式
- `lib/features/player/presentation/providers/player_provider.dart` �?play()/setUrl() 10 秒超时保�?- `lib/platform/kugou/kugou_api.dart` �?downloadKrc/searchLyricsByHash 错误日志

### 根因分析

1. **App 卡死 (4 叠加因素)**:
   - 下载进度风暴: `onReceiveProgress` 每秒 50+ 次状态更�?�?1 秒节�?   - Tab State 销�? `Map<int, Widget>` + `putIfAbsent` 无法保留 State �?IndexedStack + KeyedSubtree
   - N+1 数据库查�? history 200+ �? likes 500+ 次单条查�?�?批量 WHERE IN
   - Player position 重建: watch position 每秒触发 �?Timer + ref.read()

2. **网易云无法播�?*: `restoreCookie()` 硬替�?`_cookie`，覆盖了 `_initCookie()` 生成的新�?NMTID/_ntes_nuid/__csrf �?改为合并模式

3. **暂停按钮转圈**: `isTransitioning` 只在 `_audioPlayer.play()` 返回后清�?(line 232)，play()/setUrl() �?ExoPlayer 死锁可永久挂�?�?10 秒超�?+ 超时后重�?AudioPlayer

4. **酷狗无歌�?*: `downloadKrc` �?`catch (_) { return null; }` 吞掉所有异常，无法诊断 �?添加 debugPrint 错误日志

---

## 2026-05-28 - Phase 9 Bug 修复 (第二�?

深度修复 5 个关键问题：app 卡死真正根因、数据库写入阻塞、网易云播放、QQ 歌词、酷狗歌词�?
### 根因分析

- **App 卡死 (真正根因)**: just_audio 平台通道死锁。快�?`setUrl()`/`play()` 导致 `PlatformException("Platform player already exists")`，AudioPlayer 永久损坏
- **drift 写入卡死**: 缺少 WAL 模式，SQLite 写锁阻塞所有读�?- **网易云无法播�?(真正根因)**: Cookie 不完整。服务器需�?`NMTID`、`_ntes_nuid`、`__csrf`、`appver=3.0.18.203152` 等字�?- **QQ 歌词 (根因)**: API 返回 JSON 字符串而非 Map，`data is Map` 检查失�?- **酷狗歌词 (根因)**: keyword-based 搜索依赖 singerName/songName 精确匹配，不可靠

### 修改文件

- `lib/features/player/presentation/providers/player_provider.dart` �?完整重写:
  - 新增 `_AudioMutex` 异步互斥锁，序列化所有音频操�?  - 每次 `setUrl()` 前调�?`stop()` 释放平台播放�?  - 每个 just_audio 调用包裹 try-catch，捕�?`PlatformException` 后重�?AudioPlayer
  - 所�?`seek()`/`play()`/`pause()` �?`_safeXxx()` 包装
- `lib/core/database/app_database.dart` �?添加 WAL 模式 + busy_timeout:
  - `PRAGMA journal_mode=WAL`
  - `PRAGMA busy_timeout=5000`
- `lib/platform/netease/netease_api.dart` �?完整 cookie 构�?
  - 新增 `_initCookie()` 生成 NMTID、_ntes_nuid、deviceId、__csrf �?  - 更新 User-Agent �?appver �?3.0.18.203152
  - `_captureCookie` 改为合并所�?Set-Cookie
  - CSRF token �?cookie 中提取并用于 getSongUrl
- `lib/platform/qq/qq_api.dart` �?歌词 jsonDecode:
  - `getLyric` 添加 `if (data is String) data = jsonDecode(data)`
  - `getQrcLyric` 同样修复
- `lib/platform/kugou/kugou_platform.dart` �?hash-based 歌词搜索:
  - 优先使用 `krcs.kugou.com/search?hash=HASH`
  - keyword-based 作为 fallback
- `lib/platform/kugou/kugou_api.dart` �?新增 `searchLyricsByHash()` 方法
- `lib/platform/kugou/kugou_endpoints.dart` �?新增 `lyricsSearchByHash` 端点
- `lib/features/home/presentation/screens/home_screen.dart` �?tab 切换 100ms debounce

---

## 2026-05-28 - Phase 8 Bug 修复 (第四�?

修复整个 app 卡死、会话不保存、QQ 登录信息错误�?5 个问题�?
### 修改文件

- `lib/features/player/presentation/providers/player_provider.dart` �?添加 `_playRequestId` 计数器，防止快速点击导致多�?`setUrl()`/`play()` 并发调用
- `lib/features/player/presentation/widgets/mini_player_bar.dart` �?`position` watch 每秒触发重建，改�?`ref.read()` 直接读取
- `android/app/proguard-rules.pro` �?添加 `flutter_secure_storage` �?`androidx.security.crypto` �?keep 规则
- `lib/core/storage/session_storage.dart` �?超时�?3 秒延长到 8 �?- `lib/platform/qq/qq_platform.dart` �?`getUserInfo` 改为�?cookie 提取 `uin=oXXXXX` 作为用户 ID

### 根因分析

- **整个 app 卡死 (根因)**: `playSong()` 无并发锁，快速点击导致多�?`setUrl()`/`play()` 并发调用，AudioPlayer 状态损坏阻塞主线程
- **页面切换卡死**: MiniPlayerBar �?`position` watch 每秒触发重建，导致整�?Column + IndexedStack 重建
- **会话不保�?(根因1)**: ProGuard �?release 模式下剥�?`flutter_secure_storage` �?`androidx.security.crypto` �?- **会话不保�?(根因2)**: 3 秒超时太短，Android Keystore 初始化可能超�?3 �?- **QQ getUserInfo 返回收藏数据**: `SongFavRead.GetFav` 返回收藏列表而非用户资料

---

## 2026-05-28 - Phase 8 Bug 修复 (第三�?

修复网易云播放、QQ 登录、会话持久化�?7 个问题�?
### 修改文件

- `lib/platform/netease/netease_api.dart` �?`'ids': [songId]` �?`jsonEncode([songId])`（Dio form-encoded �?`ids[]=VALUE` �?`ids=["VALUE"]`�?- `lib/platform/netease/netease_api.dart` �?`_captureCookie` �?`MUSIC_U=VALUE` 完全替换 `_cookie` �?合并逻辑
- `lib/platform/qq/qq_api.dart` �?ptqrtoken 哈希: `_getQrHash(_cookie ?? '')` �?`_getQrHash(_extractCookie('qrsig') ?? '')`
- `lib/platform/qq/qq_api.dart` �?setCookie 覆盖 �?�?key 合并
- `lib/platform/qq/qq_platform.dart` �?completeOAuthLogin 失败�?yield success �?只有 `_currentUser != null` �?yield
- `lib/core/storage/session_storage.dart` �?**新文�?*，封�?`flutter_secure_storage`
- `lib/features/auth/presentation/providers/auth_provider.dart` �?集成 `SessionStorage`

### 根因分析

- **网易云无法播�?*: `'ids': [songId]` �?Dio form-encoded 模式下被编码�?`ids[]=VALUE`，API 期望 `ids=["VALUE"]`
- **网易�?cookie 丢失**: `_captureCookie` �?`MUSIC_U=VALUE` 完全替换 `_cookie`，丢�?`os=pc; appver=...`
- **QQ ptqrtoken 哈希错误**: 对整�?cookie 字符串哈希，服务器期望只�?qrsig value 哈希
- **QQ setCookie 覆盖**: checkQr 返回�?Set-Cookie 覆盖原始 qrsig
- **QQ 登录成功无条�?yield**: completeOAuthLogin 失败也显示成�?
---

## 2026-05-28 - Phase 8 Bug 修复 (第二�?

修复 QQ 登录 OAuth 流程、酷狗封�?歌词、网易云播放/封面/登录�?8 个问题�?
### 修改文件

- `lib/platform/qq/qq_api.dart` �?完整实现 6 �?OAuth: ptqrshow �?ptqrlogin �?check_sig �?graph.qq.com authorize �?QQConnectLogin code exchange。appid=716027609, pt_3rd_aid=100497308
- `lib/platform/qq/qq_platform.dart` �?调用 `completeOAuthLogin()`
- `lib/platform/kugou/kugou_platform.dart` �?封面�?`trans_param.union_cover` 提取，替�?`{size}` �?`480`
- `lib/platform/kugou/kugou_platform.dart` �?歌词先调 `getSongInfo()` 获取 singerName+songName，再�?`singer-songname` 格式搜索
- `lib/platform/netease/netease_endpoints.dart` �?播放端点更新�?`/api/song/enhance/player/url/v1`
- `android/app/src/main/AndroidManifest.xml` �?添加 `android:usesCleartextTraffic="true"` 允许 HTTP 图片
- `lib/platform/netease/netease_api.dart` �?`_captureCookie` 遍历所�?Set-Cookie 头（原来只读第一个）
- `lib/features/player/presentation/providers/player_provider.dart` �?PlayerState 添加 `isTransitioning` 标记，`playSong()` 立即更新 currentSong

---

## 2026-05-28 - Phase 8 API 修复

三个平台 API 端点修复，搜索全部验证可用�?
### 修改文件

- `lib/platform/netease/netease_api.dart` �?放弃 WeAPI 加密 (`/weapi/`)，改用无加密 `/api/` 端点
- `lib/platform/qq/qq_api.dart` �?搜索请求 key 改为 `req_0`（不�?`req`）；`comm` 字段改为 `ct: 19, cv: 1845`（不�?`ct: 24, cv: 0`�?
### 验证

- 网易云搜�? 272 �?- QQ 音乐搜索: 5 �?- 酷狗搜索: 480 �?
---

## 2026-05-27 - Phase 6 补全平台 Stub + UI 完善

补全 QQ 和酷�?7 �?stub 方法，使三平台功能对齐；完善播放器菜单和下载管理�?
### 新增文件

- `lib/features/discovery/presentation/providers/playlist_recommendations_provider.dart` �?歌单推荐状态管�?
### 修改文件

- `lib/platform/qq/qq_endpoints.dart` �?新增 8 �?module/method 常量
- `lib/platform/qq/qq_api.dart` �?新增 8 �?API 方法（歌单、喜欢、推荐、VIP、排行榜�?- `lib/platform/qq/qq_platform.dart` �?替换 8 �?stub 方法为真实实�?- `lib/platform/kugou/kugou_endpoints.dart` �?新增 8 个端点常量（QR 登录、歌单、收藏、排行）
- `lib/platform/kugou/kugou_api.dart` �?新增 10 �?API 方法（QR 登录、歌单、收藏、排行、VIP�?- `lib/platform/kugou/kugou_platform.dart` �?替换 8 �?stub 方法为真实实现（�?QR 登录流程�?- `lib/features/player/presentation/providers/player_provider.dart` �?新增 `addToQueue()` 方法
- `lib/features/player/presentation/screens/player_screen.dart` �?更多选项按钮改为 PopupMenuButton（加入队列、复制信息）
- `lib/features/download/presentation/screens/download_page.dart` �?实现打开文件功能（open_filex�?- `lib/features/discovery/presentation/screens/discovery_screen.dart` �?歌单推荐区域接入真实数据（网格展示）
- `pubspec.yaml` �?新增 open_filex 依赖

### 功能

- **QQ 歌单管理**: getUserPlaylists / getPlaylistDetail / getLikedSongs / likeSong 全部实现
- **QQ 推荐与排�?*: getDailyRecommendations / getVipStatus / getRankingList 使用真正 API
- **QQ 分享链接解析**: 增强正则 + 调用 getPlaylistDetail 获取真实歌名和歌曲数
- **酷狗 QR 登录**: getQrCode / pollQrStatus 完整实现（passport.kugou.com API�?- **酷狗歌单管理**: getUserPlaylists / getPlaylistDetail / getLikedSongs / likeSong 全部实现
- **酷狗 VIP 状�?*: 调用 getVipInfo() 映射�?VipLevel（修复之前硬编码 free�?- **酷狗排行�?*: 使用 getRankList() 替换原来�?recommend 调用
- **播放器更多选项**: 加入播放队列 + 复制歌曲信息到剪贴板
- **下载打开文件**: 使用 open_filex 打开已下载的文件
- **发现页歌单推�?*: 登录后展示每日推荐歌曲网格，支持点击播放

### Bug 修复

- `kugou_api.dart` 缺少 `import 'kugou_endpoints.dart'`（编译错误）
- `kugou_api.dart` 移除未使用的 `import 'dart:io'`

### 验证

- 代码审查确认所�?9 个文件编译正�?- `flutter analyze --no-pub` 需本地执行验证

## 2026-05-27 - Phase 5 功能完善

实现排行榜、循�?随机播放、go_router 路由迁移和多平台登录四大功能�?
### 新增文件

- `lib/features/discovery/presentation/providers/rankings_provider.dart` �?排行榜状态管理，多平台聚�?- `lib/features/discovery/presentation/pages/rankings_page.dart` �?排行榜页面，平台 Tab 切换 + 歌曲列表
- `lib/features/auth/presentation/providers/auth_provider.dart` �?登录状态管理，多平台用户信�?- `lib/features/auth/presentation/pages/login_page.dart` �?各平台独立登录页（QR�?+ 手机号）
- `lib/core/router/app_router.dart` �?GoRouter 路由定义�? 个路�?+ 自定�?Player 过渡�?
### 修改文件

- `lib/platform/base/music_platform.dart` �?新增 `getRankingList()` 抽象方法
- `lib/platform/netease/netease_platform.dart` �?实现 `getRankingList()`（热歌榜 playlist 3778678�?- `lib/platform/qq/qq_platform.dart` �?实现 `getRankingList()`（搜�?API stub�?- `lib/platform/kugou/kugou_platform.dart` �?实现 `getRankingList()`（推�?API stub�?- `lib/features/player/presentation/providers/player_provider.dart` �?新增 `RepeatMode` 枚举 + `isShuffle`/`repeatMode` 字段 + `toggleShuffle()`/`cycleRepeatMode()` 方法
- `lib/features/player/presentation/screens/player_screen.dart` �?新增 shuffle/repeat 按钮
- `lib/features/discovery/presentation/screens/discovery_screen.dart` �?排行�?ListTile 接入 RankingsPage
- `lib/features/settings/presentation/pages/settings_page.dart` �?新增账号管理区域（三平台登录状态）
- `lib/features/library/presentation/screens/library_screen.dart` �?Navigator.push �?context.push
- `lib/features/player/presentation/widgets/mini_player_bar.dart` �?Navigator.push �?context.push('/player')
- `lib/features/home/presentation/screens/home_screen.dart` �?支持 ?tab= 查询参数切换 Tab
- `lib/app.dart` �?MaterialApp �?MaterialApp.router + 初始�?authProvider
- `lib/main.dart` �?清理未使�?import

### 功能

- **排行�?*: 各平台热歌榜聚合展示，按平台 Tab 切换，支持刷�?- **循环/随机播放**: PlayerState 新增 `RepeatMode`（off/all/one�? `isShuffle`，支持顺�?单曲循环/列表循环/随机播放
- **go_router 路由迁移**: MaterialApp �?MaterialApp.router�?0 个路由统一管理，Player 页自定义 slide-up 过渡
- **多平台登�?*: 各平台独立登录页，支�?QR 码扫描（网易�?QQ）和手机号登录（网易�?酷狗），设置页显示登录状�?
### 验证

- `flutter analyze --no-pub` 通过（需本地验证�?
## 2026-05-27 - Phase 4 Bug 修复

�?Phase 4 代码进行 3 轮审查，发现并修�?12 �?bug�?
### HIGH

- **RetryInterceptor 创建�?Dio() 绕过拦截�?*: 每次重试创建 `Dio()` 实例，绕过所有拦截器且丢失超时配置。改为引用父 `Dio` 实例，重试走完整拦截器链
- **main.dart 错误处理�?debugPrint**: `FlutterError.onError` �?`runZonedGuarded` 仅输出日志，release 构建中错误不可见。添�?`FlutterError.presentError` + `ErrorWidget.builder` 友好错误 UI
- **主题选择不持久化**: `StateProvider` 默认值每次重启恢复为"跟随系统"。改�?`StateNotifier` + Hive 持久�?
### MEDIUM

- **download_button ModalBottomSheet 使用错误 BuildContext**: `builder` 回调内使用外�?`context` 而非 `ctx`，主题颜色可能错误。改�?`ctx` �?`colorScheme`
- **硬编�?Colors.xxx 未适配深色模式**: quality_bottom_sheet (6�?、likes_page (6�?、history_page (5�?、import_playlist_page (3�?、recommendations_page (2�?、discovery_screen (5�?、download_page (4�? �?`Colors.grey`/`Colors.red`/`Colors.green` 等替换为 theme-aware `colorScheme.xxx`

### LOW

- **withAlpha 废弃 API**: 4 �?`withAlpha(30)` 替换�?`withValues(alpha: 0.12)`，与 SDK ^3.10.3 兼容
- **library_screen 下载管理 ListTile �?onTap**: 点击无响应，改为导航回首页下�?Tab
- **AppBar title 硬编�?fontSize**: 7 �?`TextStyle(fontSize: 18)` 移除，由主题 `appBarTheme.titleTextStyle` 统一处理
- **import_playlist OutlineInputBorder 覆盖主题**: 默认 4px 圆角覆盖主题 12px 圆角，改为显�?`borderRadius: BorderRadius.circular(12)`
- **AppTheme 每次 build 重建**: `AppTheme.light()`/`AppTheme.dark()` �?`build()` 中调用，改为 `static final` 缓存

### 修改文件

- `lib/core/network/retry_interceptor.dart` �?使用�?Dio 实例 + maxDelay 上限
- `lib/core/network/api_client.dart` �?设置 retryInterceptor.dio 引用
- `lib/main.dart` �?添加 ErrorWidget.builder + FlutterError.presentError
- `lib/core/theme/theme_provider.dart` �?StateProvider �?StateNotifier + Hive 持久�?- `lib/app.dart` �?ConsumerWidget + static final ThemeData 缓存
- `lib/features/settings/presentation/pages/settings_page.dart` �?使用 ThemeModeNotifier + package import
- `lib/features/download/presentation/widgets/download_button.dart` �?修复 BuildContext + 颜色
- `lib/features/download/presentation/screens/download_page.dart` �?颜色 + AppBar title
- `lib/features/player/presentation/widgets/quality_bottom_sheet.dart` �?6 处颜色修�?- `lib/features/player/presentation/widgets/mini_player_bar.dart` �?withAlpha �?withValues
- `lib/features/player/presentation/screens/player_screen.dart` �?AppBar title
- `lib/features/library/presentation/pages/likes_page.dart` �?6 处颜色修�?+ withAlpha + AppBar title
- `lib/features/library/presentation/pages/history_page.dart` �?5 处颜色修�?+ withAlpha + AppBar title
- `lib/features/library/presentation/pages/import_playlist_page.dart` �?3 处颜色修�?+ 边框圆角 + AppBar title
- `lib/features/library/presentation/screens/library_screen.dart` �?下载管理 onTap 导航
- `lib/features/discovery/presentation/screens/discovery_screen.dart` �?5 处颜色修�?- `lib/features/discovery/presentation/pages/recommendations_page.dart` �?3 处颜色修�?+ withAlpha + AppBar title

### 验证

- 手动代码审查确认所有编辑正�?
## 2026-05-27 - Phase 4 打磨发布

完成应用发布前的打磨工作，包括深色模式、动画过渡、错误处理、性能优化、App 图标/启动页配置和 APK 构建配置�?
### 新增文件

- `lib/core/theme/app_colors.dart` �?语义化颜色常量，替代硬编�?Colors.xxx
- `lib/core/theme/app_theme.dart` �?统一 light/dark ThemeData，含自定义子主题（AppBar/NavigationBar/Slider/Card/InputDecoration�?- `lib/core/theme/theme_provider.dart` �?Riverpod StateProvider<ThemeMode>，支持用户切换主�?- `lib/core/utils/snackbar_helper.dart` �?统一 SnackBar 工具类（showErrorSnackBar/showSuccessSnackBar�?- `lib/core/network/retry_interceptor.dart` �?Dio 重试拦截器，指数退避（最�?3 次），仅对超�?5xx 重试
- `lib/features/settings/presentation/pages/settings_page.dart` �?设置页，主题切换（跟随系�?浅色/深色�?- `android/app/proguard-rules.pro` �?R8 混淆规则（Flutter/ExoPlayer/SQLite 保留�?
### 修改文件

- `lib/app.dart` �?MaterialApp 改为 ConsumerWidget，接�?themeProvider，使�?AppTheme.light()/dark()
- `lib/main.dart` �?添加 FlutterError.onError + runZonedGuarded 全局错误处理
- `lib/features/home/presentation/screens/home_screen.dart` �?使用 IndexedStack 保留 Tab 状�?- `lib/features/player/presentation/screens/player_screen.dart` �?歌词/封面 AnimatedCrossFade、歌曲名 AnimatedSwitcher、播放按�?AnimatedScale、CachedNetworkImage
- `lib/features/player/presentation/widgets/mini_player_bar.dart` �?CachedNetworkImage + 播放器页向上滑动过渡
- `lib/features/player/presentation/widgets/lyrics_display.dart` �?硬编�?Colors.grey �?theme colorScheme.outline
- `lib/features/player/presentation/widgets/word_by_word_lyrics.dart` �?同上
- `lib/features/search/presentation/screens/search_screen.dart` �?CachedNetworkImage + 硬编码颜色修�?- `lib/features/download/presentation/screens/download_page.dart` �?硬编码颜色修�?- `lib/features/download/presentation/widgets/download_button.dart` �?硬编码颜色修�?- `lib/features/library/presentation/screens/library_screen.dart` �?新增设置入口
- `lib/core/network/api_client.dart` �?集成 RetryInterceptor
- `android/app/src/main/AndroidManifest.xml` �?android:label �?"Mconnect"，新�?POST_NOTIFICATIONS 权限
- `android/app/build.gradle.kts` �?release 签名配置 + R8 混淆启用
- `pubspec.yaml` �?新增 flutter_launcher_icons、flutter_native_splash dev_dependencies + 配置

### 功能

- **深色模式**：Material 3 主题系统，跟随系�?浅色/深色三种模式，设置页切换
- **硬编码颜色修�?*：~15 �?Colors.grey/Colors.black 替换�?theme-aware 颜色
- **动画过渡**：歌�?封面 AnimatedCrossFade、歌曲切�?AnimatedSwitcher、播放按�?AnimatedScale、迷你播放器→全屏滑动过�?- **图片缓存**�? �?Image.network �?CachedNetworkImage，带 placeholder �?errorWidget
- **首页状态保�?*：IndexedStack 替代直接切换，各 Tab 状态不丢失
- **全局错误处理**：FlutterError.onError + runZonedGuarded + ErrorWidget.builder
- **网络重试**：Dio RetryInterceptor，指数退避，仅超�?5xx 重试
- **App 图标/启动�?*：flutter_launcher_icons + flutter_native_splash 配置
- **APK 构建**：release 签名配置 + R8 混淆 + ProGuard 规则

### 验证

- `flutter analyze --no-pub` 通过，无新增编译错误

## 2026-05-27 - Phase 3 库管理功�?
实现了音乐库管理核心功能，包括本地持久化存储、跨平台聚合、听歌历史、每日推荐和歌单导入�?
### 新增文件

- `lib/core/database/app_database.dart` �?drift 数据库定义，5 张表（Songs, ListeningHistory, UserLikes, LyricsCache, Playlists�? 4 �?DAO
- `lib/core/database/app_database.g.dart` �?drift 生成代码（手动编写，build_runner �?Dart 3.10.3 不兼容）
- `lib/features/library/presentation/providers/likes_provider.dart` �?喜欢歌曲状态管理，支持跨平台聚合和平台筛�?- `lib/features/library/presentation/pages/likes_page.dart` �?我喜欢页面，显示所有平台的喜欢歌曲，支持平台筛�?- `lib/features/library/presentation/providers/history_provider.dart` �?听歌历史状态管理，自动记录播放历史
- `lib/features/library/presentation/pages/history_page.dart` �?听歌历史页面，按日期分组显示，支持清�?- `lib/features/library/presentation/pages/import_playlist_page.dart` �?歌单导入页面，支持粘贴分享链接解析导�?- `lib/features/discovery/presentation/providers/recommendations_provider.dart` �?每日推荐状态管理，多平台聚�?- `lib/features/discovery/presentation/pages/recommendations_page.dart` �?每日推荐页面，平�?Tab 切换

### 修改文件

- `lib/features/library/presentation/screens/library_screen.dart` �?接入导航：我喜欢、听歌历史、导入歌�?- `lib/features/discovery/presentation/screens/discovery_screen.dart` �?接入每日推荐导航
- `lib/features/player/presentation/providers/lyrics_provider.dart` �?集成歌词本地缓存（drift LyricsCache 表）
- `pubspec.yaml` �?新增 `path` 依赖

### 功能

- **本地数据�?*：drift (SQLite) 持久化存储，支持歌曲缓存、听歌历史、喜欢列表、歌词缓存、歌�?- **跨平台喜欢聚�?*：统一展示所有平台的喜欢歌曲，支持按平台筛�?- **听歌历史自动记录**：播放新歌曲时自动记录到本地数据库，按日期分组展�?- **每日推荐**：调用各平台推荐接口，按平台 Tab 切换展示
- **歌单导入**：支持粘贴网易云/QQ音乐/酷狗分享链接，解析并导入歌单歌曲
- **歌词离线缓存**：歌词获取后缓存到本地，切换歌曲秒加�?
### 技术细�?
- drift 2.33.0 手动生成代码（build_runner �?Dart 3.10.3 �?`dart compile` 不支�?build hooks�?- `@DataClassName('SongRecord')` 避免与模型层 `Song` 类命名冲�?- `InsertMode.insertOrReplace` 替代不存在的 `insertOnConflictUpdate`（drift 2.x API�?- `ref.listen` 监听播放器状态变化自动记录听歌历�?
### Phase 3 Bug 修复 (3 CRITICAL, 3 HIGH, 3 MEDIUM)

#### CRITICAL

- **TabController length=0 崩溃**: `recommendations_page.dart` initState 创建 `TabController(length: 0)` 触发断言失败。改为延迟创建，仅在有平台数据时初始�?- **TabController �?build() �?dispose**: `recommendations_page.dart` build 方法�?dispose+重建 TabController 导致 "used after disposed" 错误。改�?`_syncTabController` 方法，仅在长度变化时重建
- **recordListen 不更�?state**: `history_provider.dart` 写入数据库后未更新内存状态，UI 永远显示旧数据。改为在 DB 写入后直�?prepend 新条目到 state

#### HIGH �?第一�?
- **toggleLike 竞态条�?*: 快速双击爱心导致重复插入。添�?`_isToggling` 互斥�?+ 乐观更新
- **toggleLike 无错误处�?*: DAO 异常未捕获导致状态不一致。添�?try/catch + 失败�?re-sync
- **播放全部只播放第一�?*: `import_playlist_page.dart` �?`_playAll` 调用 `playSong` 而非 `playPlaylist`。改�?`ref.read(playerProvider.notifier).playPlaylist(_parsedSongs!)`
- **歌词缓存格式重新检�?*: 缓存命中时重新运�?`_formatForPlatform` 启发式检测，可能导致格式误判。改�?`getCachedLyricsWithFormat` 读取存储的格�?- **_lastListenedSongId 阻止重复收听**: 整个会话期间同一首歌只记录一次。改�?10 秒时间窗口冷�?
#### MEDIUM �?第一�?
- **likes 空状态筛选错�?*: 平台筛选无结果时显示空白而非提示。添�?`filteredSongs.isEmpty` 分支
- **history 空艺术家显示乱码**: `artistNames` 为空时显�?`· 3分钟前`。改为条件显示分隔符
- **history 错误被静默吞�?*: `loadHistory` 失败时无错误提示。添�?`error` 字段 + UI 错误状态展�?
### 验证

- `flutter analyze --no-pub` 通过，无新增编译错误

### Phase 3 Bug 修复 第二�?(1 HIGH, 2 MEDIUM, 3 LOW)

#### HIGH �?第二�?
- **import_playlist try-catch 包裹整个 for 循环**: 某平�?`parseShareLink` 抛异常后，后续平台不再尝试。改�?try-catch 移入循环内部，每个平台独立尝�?
#### MEDIUM �?第二�?
- **copyWith 静默清除 error**: `LikesState`、`HistoryState`、`RecommendationsState` �?copyWith 使用 `error: error`，调�?`copyWith(isLoading: false)` �?error 被清空。改�?`error: error ?? this.error`
- **likeSong �?insertSong 失败导致孤立记录**: `toggleLike` �?`likeSong` �?`insertSong`，后者失败时 UserLikes 表残留。改为先 insert �?like

#### LOW

- **recordListen duration 始终�?0**: `HistoryNotifier.recordListen` �?duration 参数，听歌时长永远记�?0。添加可�?`durationMs` 参数并传�?DAO �?state
- **TabController 切换�?index 重置�?0**: 平台数量变化时新�?TabController 导致选中标签丢失。改为保�?previousIndex（如果仍有效�?- **likes_page substring(0,2) 脆弱**: 新增平台 displayName 不足 2 字符时崩溃。改�?`clamp(0, 2)` 安全截取

### 修改文件

- `lib/features/library/presentation/pages/import_playlist_page.dart` �?try-catch 移入循环
- `lib/features/library/presentation/providers/likes_provider.dart` �?copyWith error 保留 + insert/like 顺序修正
- `lib/features/library/presentation/providers/history_provider.dart` �?copyWith error 保留 + duration 参数
- `lib/features/discovery/presentation/providers/recommendations_provider.dart` �?copyWith error 保留
- `lib/features/discovery/presentation/pages/recommendations_page.dart` �?TabController index 保留
- `lib/features/library/presentation/pages/likes_page.dart` �?substring 安全截取

### Phase 3 Bug 修复 第三�?(2 HIGH, 2 MEDIUM)

#### HIGH �?第三�?
- **copyWith 无法清除 error**: 第二轮修�?`error: error ?? this.error` 后，`error: null` 不再生效，错误消息永远残留。改�?`String? Function()?` 模式，清除时�?`error: () => null`
- **likes_page �?error 状�?UI**: `loadLikes()` 失败时页面显�?还没有喜欢的歌曲"而非错误提示。添�?error state + 重试按钮（与 history_page 一致）

#### MEDIUM �?第三�?
- **import_playlist 解析�?setState �?mounted 检�?*: 网络请求期间用户返回导致 `setState() called after dispose` 崩溃。添�?`if (!mounted) return` 检�?- **recommendations 重复加载**: `initState` 未检�?`isLoading`，快速进出页面触发重复网络请求。添�?`!state.isLoading` 守卫

### 修改文件

- `lib/features/library/presentation/providers/likes_provider.dart` �?copyWith Function() 模式 + error caller 更新
- `lib/features/library/presentation/providers/history_provider.dart` �?同上
- `lib/features/discovery/presentation/providers/recommendations_provider.dart` �?同上
- `lib/features/library/presentation/pages/likes_page.dart` �?新增 error state UI
- `lib/features/library/presentation/pages/import_playlist_page.dart` �?mounted 检�?- `lib/features/discovery/presentation/pages/recommendations_page.dart` �?isLoading 守卫

### 验证

- `flutter analyze --no-pub` 通过，无新增编译错误

### Phase 3 Bug 修复 第四�?(1 HIGH, 1 LOW)

#### HIGH �?第四�?
- **PlayerState.copyWith 同样无法清除 error**: `player_provider.dart` �?copyWith 使用 `String? error`，导�?position/duration/isPlaying 流更新时 error 被静默清除（每秒 5+ 次）。改�?`String? Function()?` 模式，与 Phase 3 State 类一�?
#### LOW �?第四�?
- **import_playlist getPlaylistDetail 失败显示误导信息**: `parseShareLink` 成功�?`getPlaylistDetail` 抛异常时，用户看�?无法识别该链�?。改为嵌�?try-catch，区�?链接不识�?�?获取详情失败"两种错误

### 修改文件

- `lib/features/player/presentation/providers/player_provider.dart` �?copyWith Function() 模式 + 3 �?caller 更新
- `lib/features/library/presentation/pages/import_playlist_page.dart` �?嵌套 try-catch 区分错误

### 验证

- `flutter analyze --no-pub` 通过，无新增编译错误

## 2026-05-27 - Phase 2 Bug Fixes

修复�?QQ 音乐、酷狗音乐和歌词解析器中�?15 个问题（2 CRITICAL, 4 HIGH, 5 MEDIUM, 4 LOW）�?
### CRITICAL
- **QQ _parseSong 空指针崩�?*: `s['id'].toString()` �?`s['id']` �?null 时崩溃，改为 `s['id']?.toString()` 并添加默认空字符�?- **QQ 二维码登录不保存 Cookie**: pollQrStatus 成功时不存储 cookie 也不获取用户信息，现已修�?
### HIGH
- **QQ 二维码状态匹配错�?*: API 返回 `ptuiCB(...)` 而非 `ptui_CB(...)`，现已同时匹配两种格�?- **酷狗 getLyrics 空关键词**: 传入空字符串搜索歌词导致无结果，改为传入 songId 作为关键�?- **QQ getSongUrl 忽略音质参数**: quality 参数未使用，现已映射�?API �?filename 参数
- **QQ getQrcLyric 缺少 nobase64**: QRC 歌词接口未传 `nobase64=1`，导致返回格式不正确

### MEDIUM
- **QQ parseShareLink 总是返回 null**: 正则匹配成功后仍返回 null，现已返�?Playlist 对象
- **酷狗 parseShareLink 总是返回 null**: 同上修复
- **二维码轮询无超时**: pollQrStatus 无限循环，添�?5 分钟超时�?50 �?× 2 秒）
- **�?midurlinfo 崩溃**: getSongUrl 未检�?midurlinfo 列表是否为空，现已添加检�?- **KRC 解密错误隐藏**: zlib 解压失败时静默吞掉异常，现使�?dart:developer 记录日志
- **ptqrtoken 哈希错误**: 使用了错误的 DJB2 初始值（5381），修正�?0

### LOW �?Phase 2 Bug 修复

- **酷狗未使用的 dart:async 导入**: 已移�?- **酷狗未使用的 _token 字段**: 保留（后续登录功能需要）

### 修改文件
- `lib/platform/qq/qq_platform.dart` �?4 项修�?- `lib/platform/qq/qq_api.dart` �?3 项修�?- `lib/platform/kugou/kugou_platform.dart` �?2 项修�?- `lib/platform/kugou/kugou_api.dart` �?1 项修�?
### 验证
- `flutter analyze --no-pub` 通过，无新增编译错误

## 2026-05-27 - 歌词显示组件

实现了播放器歌词同步显示功能，支持逐行高亮滚动和逐字变色�?
### 新增文件
- `lib/features/player/presentation/providers/lyrics_provider.dart` �?歌词数据 Provider，自动获�?解析当前歌曲歌词
- `lib/features/player/presentation/widgets/lyrics_display.dart` �?歌词主组件，支持自动滚动、行高亮、点击跳�?- `lib/features/player/presentation/widgets/word_by_word_lyrics.dart` �?逐字高亮组件，支�?QRC/KRC 格式

### 修改文件
- `lib/features/player/presentation/screens/player_screen.dart` �?改为 StatefulWidget，新增歌�?专辑封面切换按钮

### 功能
- 自动获取歌词：根据当前播放歌曲的平台自动调用对应 API 获取歌词
- 格式自动识别：根据平台类型判�?LRC/QRC/KRC 格式并调用对应解析器
- 逐行高亮：当前播放行高亮显示（颜�?字号+粗体�?- 自动滚动：歌词自动滚动到当前播放行（居中显示�?- 用户滚动暂停：用户手动滚动后暂停自动滚动 3 �?- 逐字变色：QRC/KRC 格式支持逐字颜色渐变（已播放=主题色，未播�?灰色�?- 点击跳转：点击任意歌词行跳转到对应时间点
- 切换按钮：AppBar 右上角按钮切换专辑封�?歌词视图

### 验证
- `flutter analyze --no-pub` 通过，无编译错误

## 2026-05-27 - 音质选择 UI

实现了播放器音质选择功能，支持实时切换音质�?
### 新增文件
- `lib/features/player/presentation/providers/quality_provider.dart` �?获取当前歌曲可用音质列表
- `lib/features/player/presentation/widgets/quality_bottom_sheet.dart` �?音质选择底部弹窗

### 修改文件
- `lib/features/player/presentation/providers/player_provider.dart` �?PlayerState 新增 `currentQuality` 字段，PlayerNotifier 新增 `switchQuality()` 方法
- `lib/features/player/presentation/screens/player_screen.dart` �?歌手名下方新增音质徽章（可点击打开选择面板�?
### 功能
- 音质徽章：歌手名下方显示当前音质（标�?较高/极高/无损/Hi-Res），点击打开选择面板
- 底部弹窗：列出当前歌曲可用的所有音质选项，显示比特率和格�?- 实时切换：选择新音质后自动重新获取播放 URL，保持当前播放进�?- 无损标识：无�?Hi-Res 音质旁显�?Hi-Fi 标签
- 切换状态：切换时保持播�?暂停状态，切换失败显示错误提示
- 歌曲切换重置：播放新歌曲时重置为标准音质

### 验证
- `flutter analyze --no-pub` 通过，无编译错误

## 2026-05-27 - 下载管理

实现了歌曲下载功能，支持多平台、音质选择、队列管理�?
### 新增文件
- `lib/features/download/domain/entities/download_task.dart` �?下载任务模型，包含状态、进度、文件信�?- `lib/features/download/data/repositories/download_manager.dart` �?下载管理器，支持并发控制、暂�?恢复、断点续�?- `lib/features/download/presentation/providers/download_provider.dart` �?下载状态管理，VIP 检�?- `lib/features/download/presentation/screens/download_page.dart` �?下载管理页面（下载中/已完�?失败三个 Tab�?- `lib/features/download/presentation/widgets/download_button.dart` �?播放器下载按钮，带音质选择弹窗

### 修改文件
- `lib/features/player/presentation/screens/player_screen.dart` �?控制栏新增下载按�?- `lib/features/home/presentation/screens/home_screen.dart` �?底部导航新增"下载"Tab

### 功能
- **下载按钮**：播放器控制栏左侧，点击弹出音质选择（标�?较高/无损�?- **VIP 检�?*：下载前检查平台会员状态，非会员提示所需等级
- **队列管理**：最�?3 个并发下载，超出自动排队
- **进度显示**：圆形进度条 + 百分�?+ 已下�?总大�?- **暂停/恢复**：支持单个任务暂停和恢复
- **取消下载**：支持取消正在下载的任务
- **下载管理�?*：三�?Tab（下载中/已完�?失败），支持批量暂停、重试、删�?- **存储路径**：`/下载目录/mconnect/{平台}/{音质}/`
- **文件命名**：`歌手 - 歌曲�?flac|mp3`

### 验证
- `flutter analyze --no-pub` 通过，无编译错误

## 2026-05-27 - Phase 2 全面 Bug 修复

对歌词、音质选择、下载管理三个模块进行代码审查，发现并修�?14 �?bug�?
### 歌词模块 (4 �?
- **CRITICAL**: lyrics_provider 每次 position 变化都重新请求歌�?API（每�?10+ 次网络请求）。改�?`ref.watch(playerProvider.select(...))` 仅监听歌曲变�?- **MODERATE**: 自动滚动使用硬编�?48px 行高，偏移不准。改�?`Scrollable.ensureVisible` + GlobalKey 精确定位
- **MODERATE**: 用户滚动检测计时器未防抖，多次快速滚动导致提前恢复自动滚动。改�?Timer + cancel 机制
- **MINOR**: 切歌�?`_currentLineIndex` 未重置，歌词不回顶部。新�?`_lastSongId` 跟踪，切歌时重置滚动位置

### 音质选择模块 (3 �?
- **HIGH**: `PlatformRegistry.get` �?try-catch 外调用，异常未捕获。移�?try 块内
- **MODERATE**: `switchQuality` 无互斥锁，快速点击导致音�?URL 状态不一致。新�?`_isSwitchingQuality` 标志
- **MODERATE**: `switchQuality` await 后歌曲可能已切换，setUrl 用旧歌曲 URL。await 后重新检�?`state.currentSong`

### 下载管理模块 (7 �?
- **MEDIUM**: `DownloadTask.copyWith` 未用 `?? this.error`，error 被意外清�?- **HIGH**: 重试按钮调用 `resumeDownload`，但该方法仅处理 paused 状态，failed 无效。改为同时处�?paused + failed
- **HIGH**: 恢复下载�?Dio.download 覆写文件而非追加，导致文件损坏。改为始终全量下�?- **MEDIUM**: 并发等待循环未检�?CancelToken，已取消的下载仍会启动。循环内添加取消检�?- **HIGH**: `resumeDownload` �?`firstWhere` + throw，任务被移除时崩溃。改�?`indexWhere` + 提前返回
- **MEDIUM**: 文件名未过滤 Windows 非法字符（`/\:*?"<>|`），�?AC/DC 等歌名时崩溃。新增正则替�?- **LOW**: `isDownloaded` 未检�?platform，跨平台�?ID 歌曲误判。新�?platform 参数

### 修改文件
- `lib/features/player/presentation/providers/lyrics_provider.dart`
- `lib/features/player/presentation/widgets/lyrics_display.dart`
- `lib/features/player/presentation/providers/player_provider.dart`
- `lib/features/download/domain/entities/download_task.dart`
- `lib/features/download/data/repositories/download_manager.dart`
- `lib/features/download/presentation/providers/download_provider.dart`

### 验证
- `flutter analyze --no-pub` 通过，无编译错误
