# 桌面歌词协议（Dart ↔ Windows 原生）

> 本文是 2026-11 桌面歌词重写的唯一接口约定。Dart 与 C++ 两端必须按此实现；新增字段采用“可选、带默认值”，旧客户端/旧原生不得因未知字段崩溃。

## 1. 通道

| 通道 | 用途 |
|---|---|
| com.mconnect.mconnect/floating_lyrics | Windows 悬浮歌词（保留旧方法，新增 configure/preview/getMonitors 等） |
| com.mconnect.mconnect/taskbar_lyrics | Windows 任务栏歌词 |
| com.mconnect.mconnect/desktop_integration | SMTC、托盘、窗口状态、单实例、深链、磁盘、快捷键 |

Android 仍只使用 floating_lyrics 通道，且忽略桌面专属字段；Android 原生实现不因本次协议改动而修改。

## 2. 共享数据结构

### 2.1 LyricsOverlayFrame（Dart → 原生，高频）

| 字段 | 类型 | 说明 |
|---|---|---|
| text | String | 当前行原文 |
| translation | String? | 当前行译文 |
| nextText | String | 下一行原文（可空串） |
| nextTranslation | String? | 下一行译文（可空） |
| lineIndex | int | 当前行索引；原生据此判断相邻切行/seek 跳行 |
| progress | double | 歌曲播放进度 0..1（预留） |
| highlightProgress | double | 当前行已唱比例 0..1 |
| highlightRate | double | 每毫秒进度增量，暂停/间奏为 0 |
| wordSegments | List<double>? | 可选的累计进度边界（最多 32 个，0..1 递增），用于 QRC/KRC/YRC 非匀速扫描 |
| isPlaying | bool | 是否正在播放 |
| hasSong | bool | 是否有歌曲 |
| revision | int | 递增帧序号；原生丢弃小于当前序号的帧 |
| songTitle / artistName / albumName | String? | 元数据（任务栏 hover / 诊断） |
| coverUrl | String? | 封面 URL（任务栏可选封面/氛围） |

### 2.2 FloatingLyricsStyle（Dart → 原生，低频）

在现有字段（enabled/textColor/highlightColor/backgroundColor/fontSize/strokeWidth/shadowOpacity/width/height/isLocked/positionY）基础上新增：

| 字段 | 类型 | 默认 | 说明 |
|---|---|---|---|
| positionX | double? | null | 归一化 X 0..1；null=居中 |
| positionYRatio | double? | null | 归一化 Y 0..1；旧 positionY 仍用于 Android |
| monitorDeviceName | String | "" | 空=主显示器 |
| lineAnimation | String | "fade" | 见第 3 节枚举 |
| animationDurationMs | int | 220 | 0/120/180/220/300/420 |
| easing | String | "easeOut" | linear/easeOut/easeInOut/overshoot |
| windowAnimation | String | "fade" | none/fade/slideFromTop/slideFromBottom/slideFromLeft/slideFromRight/pop |
| backgroundMode | String | "none" | none/solid/gradient/cover |
| backgroundColor2 | int | 0x00000000 | ARGB |
| backgroundOpacity | double | 0.55 | 0..1 |
| cornerRadius | double | 16 | 0..48 |
| fontFamily | String | "" | 空=Microsoft YaHei UI |
| fontWeight | int | 600 | 100..900 |
| textAlign | String | "center" | left/center/right |
| lineMode | String | "currentAndTranslation" | currentOnly/currentAndTranslation/currentAndNext/threeLines |
| showTranslation | String | "auto" | auto/always/never |
| letterSpacing | double | 0 | |
| lineHeight | double | 1.2 | |
| padding | double | 12 | |
| showControls | bool | true | |
| clickThrough | bool | false | 未锁定时文本区域是否穿透 |
| alwaysOnTop | bool | true | |
| hideInFullscreen | bool | true | |
| reduceMotion | bool | true | |
| strokeColor | int | 0xFF000000 | ARGB |
| shadowBlur | double | 8 | |
| wordHighlight | bool | true | |
| coverImagePath | String? | null | 预模糊封面临时文件（可选） |

### 2.3 TaskbarLyricsStyle（Dart → 原生，低频）

| 字段 | 类型 | 默认 |
|---|---|---|
| enabled | bool | false |
| monitorDeviceName | String | "primary" |
| anchor | String | "auto" |
| offsetX | double | 0 |
| width | double | 560 |
| height | double | 0 |
| fontSize | double | 16 |
| fontFamily / fontWeight | String / int | "" / 600 |
| textColor / highlightColor | int | 0xFFFFFFFF / 0xFFFFD44A |
| backgroundMode | String | "transparent" |
| backgroundColor / opacity | int / double | 0xFF000000 / 0.35 |
| lineMode | String | "auto" |
| translationLayout | String | "stacked" |
| lineAnimation | String | "slideLeft" |
| animationDurationMs | int | 200 |
| easing | String | "easeOut" |
| windowAnimation | String | "fade" |
| clickThrough | bool | true |
| followAutoHide | bool | true |
| hideInFullscreen | bool | true |
| marquee | bool | true |
| edgePadding | double | 8 |
| cornerRadius | double | 8 |
| debugGeometry | bool | false |

## 3. 动画枚举（两端必须一致）

行切换 LyricsLineTransition：
none, fade, fadeThrough, slideLeft, slideRight, slideUp, slideDown, pushLeft, pushRight, scaleIn, scaleOut, wipeLeft, wipeRight, flipX, flipY, dropBounce, springUp, glowSoft, random。

窗口出入 LyricsWindowTransition：
none, fade, slideFromTop, slideFromBottom, slideFromLeft, slideFromRight, pop。

缓动：linear, easeOut, easeInOut, overshoot。

## 4. 方法

### 4.1 floating_lyrics

| 方法 | 参数 | 返回 |
|---|---|---|
| canDrawOverlays | 无 | bool（Windows 恒 true） |
| openOverlaySettings | 无 | bool |
| configure | style JSON | bool |
| show | frame+style（兼容旧） | bool |
| update | frame（兼容旧） | bool |
| hide | 无 | bool |
| preview | {animation, sampleLines:[{text,translation}], durationMs} | bool |
| resetPosition | 无 | bool |
| getMonitors | 无 | List<{deviceName,left,top,right,bottom,dpi,isPrimary}> |
| setInteractive | bool | bool |

原生事件：closedByUser, lockChanged, windowResized{width,height}, styleChanged{highlightColor,fontSize}, controlRequested{action: playPause|previous|next}, positionChanged{positionY}, moveEnded{xRatio,yRatio,monitorDeviceName}, ready, rendererFallback{reason}。

### 4.2 taskbar_lyrics

| 方法 | 参数 | 返回 |
|---|---|---|
| configure | style JSON | bool |
| show | frame | bool |
| update | frame | bool |
| hide | 无 | bool |
| preview | {animation, sampleLines, durationMs} | bool |
| refreshGeometry | 无 | bool |
| getTaskbarInfo | 无 | List<{monitor,edge,thickness,taskbarRect,freeRect,trayRect,taskListRect,dpi,autoHide}> |

原生事件：geometryChanged, taskbarStateChanged{autoHide,edge,spaceInsufficient}, closedByUser, positionChanged{offsetX,width}。

### 4.3 desktop_integration

| 方法 | 参数 | 返回 |
|---|---|---|
| initialize | 无 | bool |
| setMediaMetadata | {title,artist,album,coverUrl,durationMs} | bool |
| setPlaybackState | {status: playing|paused|stopped} | bool |
| setTimeline | {positionMs,durationMs,seeking} | bool |
| setTrayState | {playing,hasSong,floatingLyrics,taskbarLyrics,liked,title,artist} | bool |
| setCloseBehavior | {minimizeToTray,firstRunHint} | bool |
| setHotkeys | {enabled,lyricsToggle,playPause} | bool |
| setPreventSleep | bool | bool |
| getWindowState / saveWindowState / resetWindowState | JSON / 无 | JSON / bool |
| freeSpaceBytes | path | int64 |
| takeInitialUri | 无 | String? |
| getMonitors | 无 | 同 floating |
| getAccentColor | 无 | int? |
| openFile / openFolder | path | bool（也可继续用 file_opener 通道） |

原生事件：smtcControl{action: play|pause|next|previous|stop|seek,positionMs?}, trayCommand{action}, uriReceived{uri}, windowCloseRequested, windowStateChanged{...}, trayReady, smtcUnavailable。

## 5. 兼容性

- 旧 Dart 调用 show/update/hide/canDrawOverlays/openOverlaySettings 必须继续工作。
- 新增字段缺失时原生使用默认值；未知字段忽略。
- Android 原生只读取它已知的字段；Dart 发送额外字段不得导致 Android 解析失败（Kotlin 用 opt* 读取）。
- 原生不得因 style/frame 字段类型异常而崩溃；类型不符时回退默认值并记录诊断。

## 6. 错误与诊断

- 原生方法失败返回 false 或错误码字符串；不向 Dart 抛未捕获异常。
- Dart 侧捕获 PlatformException/MissingPluginException，记录 DiagnosticsService，并在设置页显示“原生渲染回退/不可用”。
- D2D 初始化失败回退 GDI+ 逐像素；GDI+ 也失败则隐藏歌词窗口并上报 rendererFallback。
- 任务栏几何失败回退“任务栏上方悬浮条”并上报 spaceInsufficient。
