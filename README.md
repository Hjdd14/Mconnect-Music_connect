<!-- Mconnect · 三合一音乐客户端 -->
<p align="center">
  <img src="assets/icon/app_icon.png" width="104" alt="Mconnect" />
</p>

<h1 align="center">Mconnect</h1>

<p align="center">
  <b>网易云音乐 · QQ 音乐 · 酷狗音乐 —— 三合一第三方客户端</b><br/>
  <sub>一个应用，三个平台的搜索、播放、歌词、歌单、下载与本地音乐；Android 手机与 Windows 桌面同源同体验。</sub>
</p>

<p align="center">
  <a href="https://github.com/Hjdd14/Mconnect-Music_connect/releases/latest"><img alt="Release" src="https://img.shields.io/github/v/release/Hjdd14/Mconnect-Music_connect?style=flat-square&color=ff6b81&label=release"></a>
  <img alt="Platform" src="https://img.shields.io/badge/platform-Android%20%7C%20Windows-2ea44f?style=flat-square">
  <img alt="Flutter" src="https://img.shields.io/badge/Flutter-3.47-02569B?style=flat-square&logo=flutter&logoColor=white">
  <a href="https://github.com/Hjdd14/Mconnect-Music_connect/releases"><img alt="Downloads" src="https://img.shields.io/github/downloads/Hjdd14/Mconnect-Music_connect/total?style=flat-square&color=blue"></a>
  <a href="LICENSE"><img alt="License" src="https://img.shields.io/badge/license-MIT-lightgrey?style=flat-square"></a>
</p>

<p align="center">
  <a href="#-它能做什么">功能</a> ·
  <a href="#-windows-桌面端专属">桌面端</a> ·
  <a href="#-下载安装">下载安装</a> ·
  <a href="#-上手三步">上手</a> ·
  <a href="#-平台差异一览">平台差异</a> ·
  <a href="#-常见问题">常见问题</a> ·
  <a href="#-开发与构建">开发</a>
</p>

---

## 🎧 它是什么

Mconnect 把 **网易云音乐、QQ 音乐、酷狗音乐** 装进同一个界面。

不用在三个 App 之间来回切换：搜一次就能看到三个平台的歌，喜欢的歌可以跨平台聚合播放，歌单能互相导入，下载与本地音乐也在同一个库里管理。Android 与 Windows 使用同一套功能内核，桌面端额外提供任务栏歌词、系统媒体面板、全局快捷键等原生能力。

> 第三方客户端，与三家平台官方无关。接口由平台服务端决定，VIP 曲目与高音质播放仍受各平台账号权益限制。

---

## ✨ 它能做什么

<table>
<tr><td width="50%" valign="top">

### 🔍 搜索与发现
- **三平台聚合搜索**：歌曲、歌单一次搜全，结果按平台分组
- **每日推荐**：三平台并行加载，逐条标注来源（网易云个性化 / QQ 今日私享 / 酷狗首页推荐）
- **榜单中心**：热歌榜、飙升榜、新歌榜等，每行显示 **名次 + 封面 + 涨跌箭头**
- **新歌速递**：按华语 / 欧美 / 日本 / 韩国 / 港台分区
- **最近播放**：跨平台的播放历史

### 🎵 播放器
- 播放队列、上一首 / 下一首、随机与单曲循环
- 迷你播放器 + 全屏播放页（沉浸式封面背景）
- 进度记忆：下次打开接着上次的位置
- 音质选择：标准 / 高品 / 无损（受账号权益限制）
- 倍速播放、A-B 循环、淡入淡出、睡眠定时

</td><td width="50%" valign="top">

### 🎤 歌词
- 支持 **LRC / QRC / KRC / YRC**，逐字与翻译歌词尽最大努力同步
- 歌词工作室：字号、颜色、描边、动画、逐行 / 双行模式
- **悬浮歌词**（Android 悬浮窗 / Windows 独立窗口），可拖动、缩放、穿透点击
- **任务栏歌词**（Windows）：贴在任务栏里的歌词条，不遮挡任何窗口
- 减少动态效果开关

### 📚 音乐库与歌单
- 我喜欢的音乐：三平台收藏跨平台聚合
- 平台歌单浏览、**分享链接导入歌单**
- 本地「我的歌单」创建与管理
- 专辑页、歌手页（热门歌曲 / 专辑）
- 智能歌单：按平台、关键词、播放次数、最近播放、仅喜欢、仅缓存自动生成

</td></tr>
<tr><td valign="top">

### ⬇️ 下载与离线
- 多任务下载队列，自定义下载目录
- 整张歌单 / 整个榜单 **一键缓存**
- 离线缓存中心：容量上限、仅 Wi-Fi、自动清理
- 删除记录时可一并删除本地文件

### 💻 本地音乐
- 选择目录扫描本地歌曲，读取内嵌封面与标签
- 自动匹配同名歌词文件
- 与在线歌曲混合显示在同一个库中

</td><td valign="top">

### 📊 听歌统计
- 总播放次数、累计时长、最爱歌曲排行
- 按平台 / 时间维度的收听概览

### 🎛️ 个性化
- 主题模式：跟随系统 / 浅色 / 深色
- 强调色自选，设置即时生效
- 两套界面风格（Material / Miuix）
- 桌面背景自定义（Windows）
- 中文 / English 双语界面

</td></tr>
</table>

---

## 🖥️ Windows 桌面端专属

桌面版不是手机版的放大版：窗口、托盘、任务栏、系统媒体面板都是原生能力。

| 能力 | 说明 |
| --- | --- |
| 🗂️ 任务栏歌词 | 歌词条直接嵌入任务栏，可调宽度、锚点、偏移，也能直接拖动 |
| 🪟 悬浮歌词窗口 | 独立置顶窗口，逐字动画、可缩放，支持多显示器与高 DPI |
| 📌 托盘图标 | 右键菜单控制播放 / 切歌 / 开关歌词 / 退出；关闭到托盘而不是退出 |
| ⌨️ 全局快捷键 | 应用不在前台也能切换歌词、播放暂停 |
| 🎛️ 系统媒体面板 | 接入 Windows 媒体控制（SMTC），耳机按键与音量键生效 |
| 🪟 窗口记忆 | 记住窗口位置与大小，下次启动恢复 |
| 🔒 防休眠 | 播放期间阻止系统休眠，暂停后自动恢复 |
| 🔗 深链与单实例 | `mconnect://` 链接直达；再次双击 exe 只会唤回已运行的窗口 |
| 🖥️ 多显示器 | 歌词窗口可选择显示器，跟随 DPI 缩放 |

> 托盘图标依赖与资源管理器（Explorer）通信，因此 exe 以**管理员身份**启动（首次弹一次 UAC）。这是 Windows 完整性级别的限制，不是可选配置。

---

## 📦 下载安装

前往 [**Releases**](https://github.com/Hjdd14/Mconnect-Music_connect/releases) 下载最新版本 `v1.6.0`：

| 平台 | 文件 | 说明 |
| --- | --- | --- |
| Windows | `Mconnect-Setup-1.6.0.exe` | 安装包（推荐），自动创建开始菜单与卸载入口 |
| Windows | `Mconnect-1.6.0-win64-portable.zip` | 便携版，解压到任意目录双击 `mconnect.exe` 即用，不写注册表 |
| Android | `Mconnect-1.6.0-arm64-v8a.apk` | **绝大多数手机选这个**（2016 年后的真机） |
| Android | `Mconnect-1.6.0-armeabi-v7a.apk` | 更老的 32 位设备 |
| Android | `Mconnect-1.6.0-x86_64.apk` | 模拟器 / x86 平板 |

<details>
<summary><b>Android 分包安装注意事项</b></summary>

- 三个 APK 是**分架构**构建的，只装其中一个，不要混装。
- 分包后的 versionCode 会乘以架构权重（arm64 = 2000+，x86_64 = 4000+，v7a = 1000+）。装过分包版后再装通用包会被判为降级，需要先卸载。
- 当前使用 debug 签名分发（个人项目阶段），后续切换正式签名需卸载重装。
</details>

<details>
<summary><b>Windows 便携版怎么用</b></summary>

解压后保持目录结构完整，直接运行 `mconnect.exe`。数据保存在用户目录（`%LOCALAPPDATA%\com.mconnect`），不污染程序目录，整个文件夹可以随意移动或删除。
</details>

---

## 🚀 上手三步

1. **登录平台**：左侧「账号与平台」→ 选择网易云 / QQ 音乐 / 酷狗 → 扫码登录。三个平台互相独立，登录几个就用几个。
2. **听歌**：发现页自动加载每日推荐、榜单与新歌；搜歌时三平台结果一屏并列，点开即播。
3. **同步自己的库**：喜欢、平台歌单、分享链接导入、本地目录扫描都在「音乐库 / 本地音乐」里。

---

## 🧩 平台差异一览

| 能力 | 网易云音乐 | QQ 音乐 | 酷狗音乐 |
| --- | :---: | :---: | :---: |
| 搜索 / 播放 | ✅ | ✅ | ✅ |
| 每日推荐 | ✅ 个性化 | ✅ 登录后「今日私享」，未登录回退榜单 | ⚠️ 官方推荐已下线，取首页推荐模块 |
| 榜单 | ✅ | ✅ 含涨跌箭头 | ✅ |
| 逐字歌词 | ✅ | ✅ | ✅ |
| 收藏 / 歌单 | ✅ | ✅ | ✅ |
| 新歌速递 | ✅ | ✅ | ⚠️ 平台未开放该接口 |
| 高音质 / 无损 | 受权益限制 | 受权益限制 | 受权益限制 |

> 任一平台失败都不影响其他平台：失败原因按平台单独提示，不会静默变成空列表。

---

## ❓ 常见问题

<details>
<summary><b>Windows 托盘图标没出现？</b></summary>

Windows 11 默认把新出现的图标收进任务栏「^」溢出区。点开溢出区把 Mconnect 拖到任务栏上，或在「设置 → 个性化 → 任务栏 → 其他系统托盘图标」中打开。
若图标确实没有注册成功，应用内「设置 → 桌面行为 → 运行状态」会给出错误码与原因。
</details>

<details>
<summary><b>为什么 Windows 版需要管理员权限？</b></summary>

托盘图标通过窗口消息交给资源管理器，Windows 只允许同级或更高完整性级别的进程与 Explorer 通信。普通启动会拿到 `ERROR_ACCESS_DENIED`，图标永远不出现，因此 exe 声明了 `requireAdministrator`。
</details>

<details>
<summary><b>歌词不滚动 / 没有翻译？</b></summary>

优先使用平台提供的逐字歌词；平台只给了纯时间轴 LRC 时不会凭空生成逐字效果。翻译同理，仅当平台返回翻译行时展示。
</details>

<details>
<summary><b>VIP 歌曲播放失败或音质被降级？</b></summary>

播放与音质最终由平台服务端与账号权益决定，第三方客户端无法绕过版权与会员校验。
</details>

<details>
<summary><b>下载的歌在哪里？</b></summary>

设置里可指定下载目录；删除下载记录时可以选择是否连带删除本地文件。离线缓存与手动下载共用同一个目录配置。
</details>

---

## 🛠️ 开发与构建

```powershell
flutter pub get                     # 依赖
flutter analyze --no-pub            # 静态检查（要求 0 issue）
flutter test --no-pub -j 1          # 全量测试

# Android（务必分包，否则单包会为三套 ABI 多带约 50 MB）
flutter build apk --release --split-per-abi

# Windows
flutter build windows --release
# 安装器：用 Inno Setup 编译 installer/mconnect.iss
```

<details>
<summary><b>技术栈（简短版）</b></summary>

Flutter / Dart · Riverpod · GoRouter · Dio · media_kit 与 just_audio · drift + SQLite · Hive · Windows 原生 C++ 模块（托盘 / 任务栏歌词 / SMTC）· Inno Setup。

代码结构：`lib/core` 通用能力，`lib/features/*` 业务模块，`lib/platform/*` 三家平台适配层，`windows/runner` 桌面原生层，`test/` 单元与组件测试。
</details>

---

## 📄 说明

- 本项目为个人学习与自用开发的**第三方客户端**，与网易云音乐、QQ 音乐、酷狗音乐官方无任何关联。
- 不提供、不存储、不分发任何音乐内容；所有内容版权归各平台与版权方所有。
- 登录凭据只保存在本机（系统安全存储），仓库与日志中不含任何真实账号信息。
- 接口随时可能调整，功能以实际可用为准。使用产生的任何后果由使用者自行承担。

## 📜 License

[MIT](LICENSE)
