# Mconnect 项目文档

> 多平台音乐聚合器 — 聚合网易云/QQ音乐/酷狗，统一搜索/播放/歌词/下载

---

## 1. 项目概览

| 项目 | 值 |
|------|-----|
| 名称 | Mconnect |
| 版本 | 1.4.4+15 |
| Application ID | com.mconnect.mconnect |
| 技术栈 | Flutter 3.47.5 / Dart 3.13.4 |
| 平台 | Android（主）+ Windows 桌面端口（`windows/`，含自研原生悬浮歌词窗口与 Inno Setup 安装器） |
| 架构 | Feature-first + 平台抽象层 |
| 状态管理 | Riverpod |
| 导航 | GoRouter |
| 网络 | Dio |
| 音频 | just_audio |
| 数据库 | drift (SQLite) |
| 持久化 | flutter_secure_storage + Hive |

---

## 2. 功能列表

### 2.1 三平台音乐源

| 平台 | 搜索 | 播放 | 歌词 | 登录 | 推荐 | 排行 | 歌单 | 收藏 | 下载 |
|------|------|------|------|------|------|------|------|------|------|
| 网易云 | ✅ | ✅ | LRC | QR+手机 | ✅ | ✅ | ✅ | ✅ | ✅ |
| QQ音乐 | ✅ | ✅ | LRC+QRC | QR | ✅ | ✅ | ✅ | ✅ | ✅ |
| 酷狗 | ✅ | ✅ | LRC+KRC | QR+手机 | ✅ | ✅ | ✅ | ✅ | ✅ |

### 2.2 搜索
- 平台选择器 (ChoiceChip)
- 输入 300ms 防抖自动搜索
- 清空输入立即清空结果
- 空状态区分“请输入关键词”和“未找到相关内容”
- 结果列表: 封面 + 歌名 + 歌手 + 专辑 + 平台标签 + 播放按钮
- 分页加载

### 2.3 播放器
- 全屏播放界面: 封面模式保持方形大封面，歌词模式使用独立更高面板
- 迷你播放器: 常驻底部，封面+歌名+进度条+控制按钮
- 播放控制: 上一首/播放暂停/下一首/随机/单曲循环/列表循环
- 音质切换: 底部弹窗选择，VIP 检测
- 播放队列管理
- 歌词显示:
  - 逐行高亮自动滚动 (二分搜索定位当前行)
  - QRC/KRC 逐字变色 (WordTiming)
  - 用户滚动暂停自动滚动 3 秒
  - 点击歌词跳转播放位置
  - 播放器歌词区域不再受专辑封面正方形尺寸限制

### 2.4 发现页
- 每日推荐 (三平台并行加载)
- 排行榜 (三平台)
- 歌单推荐网格

### 2.5 音乐库
- 我喜欢的音乐 (跨平台聚合，支持平台筛选)
- 听歌历史 (自动记录，10 秒去重，日期分组)
- 歌单导入 (粘贴分享链接解析)
- 下载管理
- 设置

### 2.6 下载
- 队列并发控制 (默认 3 个并发)
- 暂停/恢复/取消/重试
- 进度显示 (1 秒节流)
- 下载任务 Hive 持久化，启动时恢复记录
- 已完成任务恢复前校验本地文件是否仍存在
- 未完成任务启动恢复为暂停状态
- 删除已完成下载前弹出确认，并明确会删除本地文件
- VIP 音质门控
- 平台分目录存储
- 文件名安全字符处理

### 2.7 设置
- 设置首页 + 二级页结构，降低单页信息密度
- 账号管理 (每个平台独立登录/登出)
- 外观设置: 主题切换、主题色、自定义背景
- 悬浮歌词: 开关、颜色、字号、描边、阴影
- 音频增强: 淡入淡出、均衡器、睡眠定时
- 诊断与关于: 日志位置、版本信息

### 2.8 会话持久化
- flutter_secure_storage 存储 cookie + User JSON
- 启动时自动恢复 (8 秒超时)
- 登录成功后自动保存
- 登出时自动清除
- ProGuard keep 规则防止 release 模式剥离加密类

---

## 3. 目录结构

```
D:\Code_Work\My_Projects\Mconnect-Music_connect\
├── android/                          # Android 原生
│   └── app/
│       ├── build.gradle.kts          # 构建配置
│       ├── proguard-rules.pro        # 混淆规则
│       └── src/main/
│           ├── AndroidManifest.xml   # 权限声明
│           └── res/                  # 图标资源
├── lib/
│   ├── main.dart                     # 入口，注册 Platform
│   ├── app.dart                      # MaterialApp + GoRouter + Theme
│   ├── core/
│   │   ├── constants/
│   │   │   └── app_constants.dart    # 全局常量
│   │   ├── database/
│   │   │   ├── app_database.dart     # Drift 数据库定义
│   │   │   └── app_database.g.dart   # 生成代码
│   │   ├── network/
│   │   │   ├── api_client.dart       # Dio HTTP 客户端
│   │   │   ├── api_exception.dart    # 异常层级
│   │   │   └── retry_interceptor.dart # 指数退避重试
│   │   ├── router/
│   │   │   └── app_router.dart       # GoRouter 路由配置
│   │   ├── storage/
│   │   │   └── session_storage.dart  # 安全存储封装
│   │   ├── theme/
│   │   │   ├── app_colors.dart       # 语义颜色
│   │   │   ├── app_theme.dart        # Material 3 主题
│   │   │   └── theme_provider.dart   # 主题切换状态
│   │   └── utils/
│   │       └── snackbar_helper.dart  # Snackbar 工具
│   ├── features/
│   │   ├── auth/                     # 登录认证
│   │   │   └── presentation/
│   │   │       ├── pages/login_page.dart
│   │   │       └── providers/auth_provider.dart
│   │   ├── discovery/                # 发现页
│   │   │   └── presentation/
│   │   │       ├── screens/discovery_screen.dart
│   │   │       ├── pages/recommendations_page.dart
│   │   │       ├── pages/rankings_page.dart
│   │   │       └── providers/
│   │   ├── download/                 # 下载管理
│   │   │   ├── data/repositories/download_manager.dart
│   │   │   ├── data/download_task_store.dart
│   │   │   ├── domain/entities/download_task.dart
│   │   │   └── presentation/
│   │   │       ├── screens/download_page.dart
│   │   │       ├── providers/download_provider.dart
│   │   │       └── widgets/download_button.dart
│   │   ├── home/                     # 主页 (底部导航)
│   │   │   └── presentation/screens/home_screen.dart
│   │   ├── library/                  # 音乐库
│   │   │   └── presentation/
│   │   │       ├── screens/library_screen.dart
│   │   │       ├── pages/likes_page.dart
│   │   │       ├── pages/history_page.dart
│   │   │       ├── pages/import_playlist_page.dart
│   │   │       └── providers/
│   │   ├── player/                   # 播放器
│   │   │   └── presentation/
│   │   │       ├── screens/player_screen.dart
│   │   │       ├── providers/player_provider.dart
│   │   │       ├── providers/lyrics_provider.dart
│   │   │       ├── providers/quality_provider.dart
│   │   │       └── widgets/
│   │   ├── search/                   # 搜索
│   │   │   └── presentation/screens/search_screen.dart
│   │   └── settings/                 # 设置
│   │       └── presentation/pages/settings_page.dart
│   ├── lyrics/
│   │   └── models/lyrics_line.dart   # 歌词解析器
│   ├── models/                       # 领域模型
│   │   ├── song.dart
│   │   ├── artist.dart
│   │   ├── album.dart
│   │   ├── user.dart
│   │   ├── playlist.dart
│   │   ├── audio_quality.dart
│   │   └── platform_type.dart
│   ├── platform/                     # 平台抽象层
│   │   ├── base/
│   │   │   ├── music_platform.dart   # 抽象接口
│   │   │   ├── platform_enum.dart
│   │   │   └── platform_registry.dart # 静态注册表
│   │   ├── netease/
│   │   │   ├── netease_api.dart      # HTTP 客户端
│   │   │   ├── netease_crypto.dart   # WeAPI 加密 (未使用)
│   │   │   ├── netease_endpoints.dart
│   │   │   └── netease_platform.dart # 平台实现
│   │   ├── qq/
│   │   │   ├── qq_api.dart
│   │   │   ├── qq_endpoints.dart
│   │   │   └── qq_platform.dart
│   │   └── kugou/
│   │       ├── kugou_api.dart
│   │       ├── kugou_endpoints.dart
│   │       └── kugou_platform.dart
│   └── utils/
│       └── file_opener.dart
├── scripts/                          # 测试脚本
├── test/
│   └── widget_test.dart              # 冒烟测试
├── pubspec.yaml
├── CHANGELOG.md
├── PROJECT.md                        # 本文档
└── README.md
```

**2026-10 目录勘误**：上面的树是早期版本，实际仓库还包含以下模块（原文遗漏，容易让人以为"没有这个功能"）：

```text
lib/
├── core/
│   ├── diagnostics/        # DiagnosticsService：环形日志、UI 卡顿心跳、慢操作记录
│   ├── motion/             # 动效曲线与页面转场
│   ├── theme/              # app_background(自定义背景) / miuix_theme / ui_style / platform_accent
│   └── widgets/            # miuix_bottom_stack / floating_glass_nav_bar / app_scrollbar / song_actions_sheet
├── features/
│   ├── audio_effects/      # 均衡器、睡眠定时、淡入淡出
│   ├── floating_lyrics/    # Android 悬浮窗歌词 + Windows 原生歌词窗口桥接
│   ├── offline_cache/      # 离线缓存中心（策略设置）
│   ├── smart_playlists/    # 智能歌单（规则 + 生成器 + 编辑器）
│   ├── stats/              # 听歌统计
│   ├── toplist/            # 榜单中心（榜单列表 + 榜单详情）
│   ├── album/ artist/      # 专辑页 / 艺人页
│   ├── new_songs/          # 新歌速递
│   └── backup/             # 数据备份与恢复
windows/                    # 完整桌面端口：runner/floating_lyrics_window.cpp(655 行) +
                            # floating_lyrics_channel.cpp(197 行) 自研原生悬浮歌词窗口
installer/                  # Inno Setup 安装器脚本 (mconnect.iss)
.github/workflows/          # CI：analyze + test + 分包构建（2026-10 新增）
```


---

## 4. 核心架构

### 4.1 平台抽象层

```dart
abstract class MusicPlatform {
  PlatformType get platformType;
  String get platformName;
  bool get isLoggedIn;

  Future<QrLoginResult> getQrCode();
  Stream<QrLoginStatus> pollQrStatus(String key);
  Future<LoginResult> loginByPhone(String phone, String code);
  Future<User?> getUserInfo();
  Future<List<Song>> search(String keyword, {int page, int limit});
  Future<String> getSongUrl(String songId, {AudioLevel quality});
  Future<List<AudioQuality>> getAvailableQualities(String songId);
  Future<String?> getLyrics(String songId);
  Future<List<Playlist>> getUserPlaylists();
  Future<List<Song>> getPlaylistDetail(String playlistId);
  Future<List<Song>> getLikedSongs();
  Future<bool> likeSong(String songId, {bool like});
  Future<List<Song>> getDailyRecommendations();
  Future<List<Song>> getRankingList();
  Future<VipLevel> getVipStatus();
  Future<Playlist?> parseShareLink(String url);
}
```

启动时在 `main.dart` 中注册:
```dart
PlatformRegistry.register(NeteasePlatform());
PlatformRegistry.register(QQPlatform());
PlatformRegistry.register(KugouPlatform());
```

### 4.2 状态管理 (Riverpod)

| Provider | 类型 | 用途 |
|----------|------|------|
| `playerProvider` | StateNotifierProvider | 播放器核心状态 |
| `authProvider` | StateNotifierProvider | 多平台登录状态 |
| `downloadProvider` | StateNotifierProvider | 下载队列与记录恢复 |
| `lyricsProvider` | FutureProvider.autoDispose | 当前歌曲歌词 |
| `availableQualitiesProvider` | FutureProvider.autoDispose | 可用音质 |
| `searchResultsProvider` | FutureProvider.autoDispose | 搜索结果 |
| `likesProvider` | StateNotifierProvider | 喜欢的歌曲 |
| `historyProvider` | StateNotifierProvider | 听歌历史 |
| `themeProvider` | StateNotifierProvider | 主题模式 |
| `recommendationsProvider` | StateNotifierProvider | 每日推荐 |
| `rankingsProvider` | StateNotifierProvider | 排行榜 |

### 4.3 数据库 (Drift)

**13 张表:**

| 表名 | 主键 | 用途 |
|------|------|------|
| Songs | (id, platform) | 歌曲缓存 |
| ListeningHistory | id (auto) | 听歌记录 |
| UserLikes | id (auto) | 喜欢记录 |
| LyricsCache | (songId, platform) | 歌词缓存 |
| LocalTracks | path | 本地音乐索引 |
| ToplistsCache | (platform, toplistId) | 榜单目录缓存（离线先发） |
| PlayEvents | id (auto) | 播放事件明细（听歌统计的唯一真相） |
| DailyStats | (day, songId, platform) | 每日汇总 |
| SmartPlaylistSnapshots | ruleId | 智能歌单「已保存结果」 |
| LyricsOffsets | songKey | 歌词手动校准偏移 |
| SourceMatchCaches | (songKey, targetPlatform) | 跨平台同曲匹配缓存 |
| TrackRatings | songKey | 评分与播放次数（由 PlayEvents 重算） |
| ScrobbleQueue | id (auto) | 待上报的收听记录队列 |

> 注：`Playlists` 表在 schema v2 已删除（从未写入过），不要再按旧文档去查它。

**12 个 DAO:**
- `SongsDao` — 批量插入 (50 条/批)、批量查询
- `HistoryDao` — 记录听歌、获取最近记录、清空
- `LikesDao` — 收藏/取消收藏、判断是否收藏、获取全部
- `LyricsCacheDao` — 缓存/获取歌词 (含格式信息)
- `StatsDao` — 播放事件与每日汇总（听歌统计）
- `LocalTracksDao` — 本地曲目索引的增量写入与分组查询
- `LyricsOffsetDao` — 歌词校准偏移读写
- `SourceMatchCacheDao` — 跨平台同曲匹配缓存
- `ToplistsCacheDao` — 榜单目录缓存
- `SmartPlaylistSnapshotsDao` — 智能歌单结果的保存/读取
- `TrackRatingsDao` — 评分与播放次数（`syncPlayStats` 由 PlayEvents 重算）
- `ScrobbleQueueDao` — 收听记录上报队列（`claimNext` 领取待上报行）

**配置:**
- WAL 模式 (`PRAGMA journal_mode=WAL`)
- 忙等待超时 5 秒 (`PRAGMA busy_timeout=5000`)

### 4.4 音频播放引擎

```
PlayerNotifier
├── _AudioMutex — 异步互斥锁，序列化所有音频操作
├── _audioPlayer — just_audio AudioPlayer 实例
├── _playRequestId — 请求计数器，防止过期操作
├── _recreatePlayer() — 平台通道损坏时重建 AudioPlayer
├── _safeStop/Play/Seek — 异常静默忽略的包装方法
└── playSong() — 核心播放流程:
    1. 立即更新 UI (currentSong, isTransitioning=true)
    2. getSongUrl() [10s 超时]
    3. stop() 释放旧播放器
    4. setUrl() [10s 超时] — 捕获 PlatformException 后重建
    5. play() [10s 超时] — 捕获 PlatformException 后重建
    6. 清除 isTransitioning
```

### 4.5 歌词解析

```dart
class LyricsDocument {
  static LyricsDocument parse(String raw, String format) {
    // 自动检测格式: LRC / QRC (XML) / KRC (含方括号和逗号)
  }
}
```

- **LRC**: `[mm:ss.xx]歌词文本` 标准时间戳
- **QRC**: XML 格式，`<Lyric_1 LyricType="1" LyricText="...">` 带逐字时间
- **KRC**: Base64 → 跳过 4 字节头 → XOR 16 字节密钥 → zlib 解压 → 跳过 1 字节 → UTF-8

---

## 5. API 端点

### 5.1 网易云音乐

| 功能 | 方法 | 端点 |
|------|------|------|
| 搜索 | GET | `/api/cloudsearch/pc` |
| 歌曲URL | POST | `/api/song/enhance/player/url/v1` |
| 歌词 | GET | `/api/song/lyric` |
| QR Key | POST | `/api/login/qrcode/unikey` |
| QR 检查 | POST | `/api/login/qrcode/client/login` |
| 用户信息 | POST | `/api/nuser/account/get` |
| 用户歌单 | POST | `/api/user/playlist` |
| 歌单详情 | POST | `/api/v6/playlist/detail` |
| 每日推荐 | GET | `/api/v3/discovery/recommend/songs` |
| 喜欢 | POST | `/api/radio/like` |

**注意**: 使用无加密 `/api/` 端点 (非 `/weapi/`)。需要完整 cookie (NMTID, _ntes_nuid, __csrf, appver=3.0.18.203152)。

### 5.2 QQ 音乐

| 功能 | 模块 | 方法 |
|------|------|------|
| 搜索 | music.search.SearchCgiService | DoSearchForQQMusicDesktop |
| 歌曲URL | musicu.fcg | req_0 (vkey/getUrl) |
| 歌词 | music.musichallSong.PlayLyricInfo | GetPlayLyricInfo |
| QR 登录 | ptqrshow → ptqrlogin → check_sig → OAuth |
| 用户信息 | musicu.fcg | Cookie捷径 |
| 歌单 | musicu.fcg | diss (getDisslist) |

**注意**: `comm` 字段必须 `ct: 19, cv: 1845`。API 返回 JSON 字符串需要 `jsonDecode`。

### 5.3 酷狗音乐

| 功能 | 方法 | 端点 |
|------|------|------|
| 搜索 | GET | `mobilecdn.kugou.com/api/v3/search/song` |
| 歌曲信息 | GET | `m.kugou.com/app/i/getSongInfo.php` |
| 歌词搜索(哈希) | GET | `krcs.kugou.com/search` |
| 歌词下载 | GET | 歌词候选中的 `content` URL |
| QR 登录 | POST | `passport.kugou.com` |
| 每日推荐 | GET | `mobilecdn.kugou.com` |
| 排行榜 | GET | `mobilecdn.kugou.com` |

**注意**: 歌词搜索优先用 hash-based (`krcs.kugou.com/search?hash=HASH`)，比 keyword-based 更可靠。

---

## 6. 构建方式

### 6.1 环境要求

- Flutter 3.47.5 (路径: `C:\Users\PC\flutter\flutter`)
- Dart 3.13.4
- Android SDK
- Java 17

### 6.2 依赖安装

```bash
cd D:\Code_Work\My_Projects\Mconnect-Music_connect
flutter pub get
```

### 6.3 生成代码 (Drift)

```bash
# 用 build_runner 生成/重新生成。2026-10 实测：Dart 3.13.4 + drift_dev 2.33.0
# 下 `dart run build_runner build` 约 38 秒产出 343 个文件，可正常使用。
# （旧文档曾写"build_runner 与 Dart 3.10.3 不兼容、drift 代码手动生成"，已过期。）
dart run build_runner build
```

注意：新版 build_runner 已移除 `--delete-conflicting-outputs`（传了会被忽略并打印告警），不要再加。
**改动 schema（加表/加列）时必须同步 `schemaVersion` 与 `onUpgrade`**，并跑 `test/database_migration_test.dart`。

### 6.4 运行

```bash
# Android 调试
flutter run

# Web 调试 (端口 9092)
flutter run -d chrome --web-port 9092
```

### 6.5 构建 APK

```bash
# Debug APK
flutter build apk --debug

# Release APK —— **必须分包**（AGENTS.md §1）：universal 包 80.5MB，其中 76MB 是
# 三套 ABI 的 lib/，一台 arm64 真机要为用不到的架构白下约 50MB。
flutter build apk --release --split-per-abi
```

APK 输出目录: `build/app/outputs/flutter-apk/`

| 产物 | 用途 |
|------|------|
| `app-arm64-v8a-release.apk` | 2016 年后的几乎所有真机，**发给别人基本都给这个** |
| `app-armeabi-v7a-release.apk` | 更老的 32 位机 |
| `app-x86_64-release.apk` | 模拟器 / x86 平板 |
| `app-debug.apk` | 调试 |

注意：分包出包后 `flutter-apk/` 里可能残留上一次的 universal `app-release.apk`，**当次构建没产生它时应当清掉**，避免误发。（分包会把 versionCode 按 ABI 加权，所以 universal 包会被判为降级而装不上，详见 AGENTS.md §1。）

### 6.6 中国镜像

```bash
export PUB_HOSTED_URL=https://pub.flutter-io.cn
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
```

### 6.7 测试脚本

```bash
# 测试所有平台 API
dart run scripts/test_apis.dart

# 测试单个平台
dart run scripts/test_netease_anon.dart
dart run scripts/test_qq_lyrics.dart
dart run scripts/test_kugou_info.dart
```

---

## 7. 权限声明

```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK"/>
<uses-permission android:name="android.permission.WAKE_LOCK"/>
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"/>
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE"/>
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
```

- `usesCleartextTraffic="true"` — 允许 HTTP (酷狗 CDN 需要)
- `network_security_config` — 自定义网络安全配置

---

## 8. 依赖清单

### 8.1 运行时依赖

> 版本号以 `pubspec.yaml` 为唯一来源；`version_sync_test.dart` 有一条护栏会检查
> "这里列的每个包都真的在 pubspec 里"。改依赖时请两处一起改。

| 包名 | 版本 | 用途 |
|------|------|------|
| cupertino_icons | ^1.0.8 | Cupertino 图标字体 |
| flutter_riverpod | ^2.6.0 | 状态管理 |
| go_router | ^14.0.0 | 声明式路由 |
| dio | ^5.7.0 | HTTP 客户端 |
| crypto | ^3.0.0 | MD5/SHA |
| just_audio | ^0.9.42 | 音频播放 |
| audio_service | ^0.18.17 | 后台播放 / 媒体通知（**已集成**） |
| audio_session | ^0.1.25 | 音频焦点/会话（Android 后台播放） |
| just_audio_windows | ^0.2.3 | Windows 端 just_audio 支持 |
| media_kit | ^1.2.6 | Windows 桌面端播放引擎 |
| media_kit_libs_windows_audio | ^1.0.9 | 同上（Windows 音频库） |
| drift | ^2.22.0 | 类型安全 SQLite |
| sqlite3_flutter_libs | ^0.5.0 | SQLite 原生库 |
| path_provider | ^2.1.0 | 应用目录（日志/下载/背景图） |
| path | ^1.9.0 | 路径拼接 |
| hive_flutter | ^1.1.0 | 轻量键值存储（设置、播放记忆） |
| flutter_secure_storage | ^9.2.0 | 安全存储 (cookie/user) |
| cached_network_image | ^3.4.1 | 图片缓存 |
| shimmer | ^3.0.0 | 加载动画（骨架屏） |
| flutter_svg | ^2.0.10+1 | SVG 渲染 |
| liquid_glass_widgets | ^1.7.2 | 液态玻璃底栏与控件（1.0.0 起有破坏性重命名，底栏必须用 `GlassTabBar.bottom`） |
| mobile_scanner | ^5.2.0 | 二维码扫描 |
| qr_flutter | ^4.1.0 | 二维码生成 |
| pointycastle | ^3.9.1 | AES/RSA |
| encrypt | ^5.0.3 | AES 加密 |
| intl | 0.20.3 | 国际化（**精确锁定**，不带 `^`） |
| charset | ^2.0.1 | GBK/GB18030 解码（用户提供的 `.lrc` 常是 GBK，只按 UTF-8 解会乱码） |
| collection | ^1.19.0 | 集合工具 |
| json_annotation | ^4.9.0 | JSON 序列化注解 |
| permission_handler | ^11.0.0 | 权限请求 |
| uuid | ^4.0.0 | UUID 生成 |
| file_picker | 11.0.2 | 选择下载目录等（**精确锁定**） |
| flutter_native_splash | ^2.4.0 | 启动页生成（构建期工具，但 pubspec 把它归在运行时依赖） |
| connectivity_plus | ^7.3.1 | "仅 Wi-Fi" 等网络策略判定 |
| share_plus | ^12.0.2 | 分享歌曲/歌单/诊断日志 |
| app_links | ^7.2.1 | 深链（`mconnect://` 与分享链接回流） |
| audio_metadata_reader | ^1.4.1 | 读取本地音乐 ID3/FLAC 元数据与封面 |

两点说明：

- `flutter` / `flutter_localizations` 由 SDK 提供（`sdk: flutter`），不是带版本号的包。
- **打开文件/文件夹不需要额外依赖**：走仓库内的 `lib/utils/file_opener.dart`
  平台通道（`com.mconnect.mconnect/file_opener`）。**Android 已实现**
  （`MainActivity.kt`），Windows 侧未实现 —— 调用方要自己兜底（旧文档里那个
  `open_filex` 依赖**在本仓库并不存在**，已删）。

### 8.2 开发依赖

| 包名 | 版本 | 用途 |
|------|------|------|
| flutter_lints | ^6.0.0 | Lint 规则 |
| build_runner | ^2.4.0 | 代码生成 |
| drift_dev | ^2.22.0 | Drift 代码生成 |
| json_serializable | ^6.8.0 | JSON 序列化生成 |
| flutter_launcher_icons | ^0.14.0 | 应用图标生成 |

（`flutter_test` 同样是 SDK 提供。）

---

## 9. 路由配置

全部路由都声明在 `lib/core/router/app_router.dart`。除 `/player` 外都挂在
`ShellRoute` 内（迷你播放器与底部胶囊常驻、返回栈才正确）。
`version_sync_test.dart` 有一条护栏做**双向**核对：这里的每一条都必须在代码里存在，
代码里的每一条也必须在这里出现 —— 所以这份表不会再悄悄漂回 9 条。

| 路径 | 页面 | 转场 |
|------|------|------|
| `/` | HomeScreen (4 tab) | 默认 |
| `/player` | PlayerScreen | 上滑 |
| `/queue` | QueuePage（播放队列：重排/删除/清空/跳播） | 默认 |
| `/recommendations` | RecommendationsPage | 默认 |
| `/rankings` | RankingsPage（内容即 `ToplistsPage`，仅深链/历史兼容） | 默认 |
| `/likes` | LikesPage | 默认 |
| `/history` | HistoryPage | 默认 |
| `/import-playlist` | ImportPlaylistPage | 默认 |
| `/platform-playlists` | PlatformPlaylistsPage（含「我的歌单」Tab） | 默认 |
| `/local-music` | LocalMusicPage | 默认 |
| `/offline-cache` | OfflineCachePage | 默认 |
| `/listening-stats` | ListeningStatsPage | 默认 |
| `/smart-playlists` | SmartPlaylistsPage | 默认 |
| `/smart-playlists/editor` | SmartPlaylistEditorPage（`?id=` 编辑，缺省新建） | 默认 |
| `/playlist/:platform/:id` | PlaylistDetailPage（`?name=&cover=`） | 默认 |
| `/toplists` | ToplistsPage | 默认 |
| `/toplist/:platform/:id` | ToplistDetailPage（`?name=`） | 默认 |
| `/album/:platform/:id` | AlbumPage（`?name=`） | 默认 |
| `/artist/:platform/:id` | ArtistPage（`?name=`） | 默认 |
| `/new-songs` | NewSongsPage | 默认 |
| `/backup` | BackupPage | 默认 |
| `/settings` | SettingsPage | 默认 |
| `/settings/accounts` | SettingsAccountsPage | 默认 |
| `/settings/appearance` | SettingsAppearancePage | 默认 |
| `/settings/floating-lyrics` | SettingsFloatingLyricsPage | 默认 |
| `/settings/audio` | SettingsAudioPage | 默认 |
| `/settings/diagnostics` | SettingsDiagnosticsPage | 默认 |
| `/login/:platform` | LoginPage | 默认 |

---

## 10. 已知问题与注意事项

### 10.1 已修复的关键问题

| 问题 | 根因 | 修复 |
|------|------|------|
| App 卡死 | just_audio 平台通道死锁 | _AudioMutex + stop()前释放 + try-catch重建 |
| App 卡死 | 下载进度风暴 (50+/秒) | 1 秒节流 |
| App 卡死 | Tab State 销毁 | IndexedStack + KeyedSubtree |
| App 卡死 | N+1 数据库查询 (200-500次) | 批量 WHERE IN 查询 |
| 网易云播放失败 | ids 编码错误 | jsonEncode([songId]) |
| 网易云播放失败 | cookie 不完整 | 完整 cookie 构造 (NMTID, _ntes_nuid, __csrf) |
| 网易云播放失败 | restoreCookie 硬替换 | 改为合并模式 |
| QQ 登录失败 | ptqrtoken 哈希输入错误 | 只对 qrsig value 哈希 |
| QQ 登录失败 | setCookie 覆盖 | 按 key 合并 |
| QQ 歌词失败 | API 返回 JSON 字符串 | jsonDecode |
| 酷狗歌词失败 | keyword 搜索不可靠 | 改用 hash-based 搜索 |
| 暂停按钮转圈 | isTransitioning 永不清除 | play()/setUrl() 10 秒超时 |
| 数据库写入卡死 | 缺少 WAL 模式 | PRAGMA journal_mode=WAL |
| 会话不保存 | ProGuard 剥离加密类 | 添加 keep 规则 |

### 10.2 架构约束

- **just_audio 平台通道**: 快速 `setUrl()`/`play()` 会死锁，必须用互斥锁序列化
- **网易云 cookie**: 必须包含 NMTID、_ntes_nuid、__csrf、appver=3.0.18.203152 等字段
- **QQ 音乐 API**: `comm` 字段必须 `ct: 19, cv: 1845`；返回 JSON 字符串需要 jsonDecode
- **drift**: 必须 WAL 模式 + busy_timeout，否则写入阻塞主线程
- **酷狗歌词**: hash-based 搜索比 keyword-based 更可靠
- **网易云 restoreCookie**: 必须合并而非替换，否则覆盖新鲜的 NMTID/_ntes_nuid/__csrf

### 10.3 待完成功能

> 本表 2026-10 复核：原列表里有多项**已经完成**却仍标"待完成"，会让接手者重复劳动，已标注实际状态。

- ~~深色模式~~ —— **已完成**（`app_theme.dart` 双主题 + 语义色 `app_colors.dart`；仅剩 10 处硬编码黑白待收敛）
- ~~App 图标 + 启动页~~ —— **已完成**（`flutter_launcher_icons` / `flutter_native_splash` 已在 `pubspec.yaml` 配置并生成资源）
- ~~audio_service 后台播放集成~~ —— **已完成**（`AudioService` + `MediaButtonReceiver` 已在 `AndroidManifest.xml` 声明，播放通知/媒体按钮可用）
- ~~签名~~ —— **有意保留 debug keystore**（见 `AGENTS.md` §3，切换需用户确认，代价是已装设备必须卸载重装）
- 动画过渡 —— 已有 `app_motion`/`app_page_transition`，可按需细化
- 字体文件 (NotoSansSC) 包含 —— 仍未内置
- Web 模式 CORS 限制处理 —— 仍未处理（`web/` 目前只是模板残留）
- 国际化 —— **未做**（约 3091 处硬编码中文，跨 62 个文件，含 domain 层）
- Windows 桌面端体验补齐 —— 托盘 / 全局媒体键 / 窗口尺寸记忆 / 单实例 / 安装器语言与运行库检测


---

## 11. 测试脚本说明

| 脚本 | 用途 |
|------|------|
| `test_apis.dart` | 三平台搜索 API 集成测试 |
| `test_netease_anon.dart` | 网易云匿名 token 获取测试 |
| `test_netease_cookie.dart` | 网易云 cookie 处理测试 |
| `test_netease_dio.dart` | 网易云 Dio HTTP 配置测试 |
| `test_netease_url.dart` | 网易云歌曲 URL 获取测试 |
| `test_qq_lyrics.dart` | QQ 歌词端点测试 |
| `test_kugou_info.dart` | 酷狗歌曲信息测试 |
| `test_debug_all.dart` | 三平台调试汇总测试 |
| `generate_icon.py/v2/v3.py` | App 图标生成脚本 |

运行方式: `dart run scripts/<script_name>.dart`

---

## 12. 主题配置

- Material 3 设计语言
- Seed color: `#E91E63` (粉色)
- 浅色/深色主题自动适配
- 自定义组件: AppBar 居中标题、NavigationBar、Slider、Card (12px 圆角)、InputDecoration

**平台品牌颜色**（唯一来源：`lib/core/theme/platform_accent.dart`，2026-10 校正 —— 原文这三个值与代码不符）:
- 网易云: `#E60026` (红)
- QQ: `#31C27C` (绿)
- 酷狗: `#2CA2F9` (蓝)
- 本地音乐: 不品牌化，跟随主题（列表徽标场景用中性灰）

---

## 13. 版本历史

详见 [CHANGELOG.md](CHANGELOG.md)

当前版本: v1.4.4 悬浮歌词行序修复 (2026-10-07)
