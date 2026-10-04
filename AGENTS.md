# AGENTS.md — 本仓库的固定约定

给在此仓库工作的 AI agent / 协作者。这些是**项目约定**，除非用户明确要求，否则按此执行。

## 1. Android 出包：一律分包

```powershell
flutter build apk --release --split-per-abi
```

**不要**用 `flutter build apk --release`（那是 universal 包）。原因（v1.3.2 实测）：

| | |
|---|---|
| universal APK | 80.5 MB，其中 `lib/` 76.1 MB（95%） |
| 三套 ABI 各占 | `x86_64` 28.4 / `arm64-v8a` 25.7 / `armeabi-v7a` 22.0 MB |
| 后果 | 一台 arm64 真机要为它永远用不到的两套架构多下载约 50 MB |

分包产物（`build/app/outputs/flutter-apk/`）：

- `app-arm64-v8a-release.apk` —— 2016 年后的几乎所有真机，**发给别人基本都给这个**
- `app-armeabi-v7a-release.apk` —— 更老的 32 位机
- `app-x86_64-release.apk` —— 模拟器 / x86 平板

发版时**把三个文件都报出来**（或至少 arm64），不要只报一个路径。
打完分包后，`flutter-apk/` 里可能残留上一次的 universal `app-release.apk`，**当次构建没产生它时应当清掉**，避免误发。

**注意 `versionCode` 会被 ABI 加权。** 分包出包时 Flutter 会把 build number 乘上架构编号，v1.3.2（build `10`）实测装出来是：

| 产物 | 实际 versionCode |
|---|---|
| `app-armeabi-v7a-release.apk` | `1010` |
| `app-arm64-v8a-release.apk` | `2010` |
| `app-x86_64-release.apk` | `4010` |

后果：分包装过之后，**universal 包会被判为降级而装不上**（universal 的 versionCode 只有 `10`），必须先卸载。反方向（universal → 分包）是升级，正常。这是"订了分包就别再回头打 universal"的又一理由。

Windows 桌面端出包仍用 `flutter build windows --release`，再用 `installer/mconnect.iss`（Inno Setup）打安装器。

## 2. 版本号：一次改齐这几处

改 `pubspec.yaml` 的 `version: <name>+<build>` 时，**必须同步**下列位置，否则会出现 App 内显示、安装器、exe 资源、文档四处不一致（v1.3.2 之前就漂移过）：

| 文件 | 改什么 |
|---|---|
| `pubspec.yaml` | `version: 1.3.2+10`（`+` 后是 Android build number，必须**递增**才能覆盖安装） |
| `lib/core/constants/app_constants.dart` | `appVersion = 'v1.3.2'` —— **设置页「版本」显示的就是它** |
| `test/settings_page_test.dart` | `expect(find.text('v1.3.2'), ...)` —— 故意用字面量，让版本变更必须同时改这里 |
| `installer/mconnect.iss` | `#define MyAppVersion "1.3.2"`（决定安装器文件名 `Mconnect-Setup-1.3.2.exe`） |
| `windows/runner/Runner.rc` | `VERSION_AS_NUMBER 1,3,2,10` 与 `VERSION_AS_STRING "1.3.2"`（exe 属性里的版本） |
| `PROJECT.md` | 「项目概览」表里的 `版本` |
| `CHANGELOG.md` | 新增一条，含「版本与产物」小节 |

**不要动** `pubspec.lock` —— 里面的 `version:` 是依赖的版本，与本项目无关。（例：`cached_network_image_web` 恰好是 `1.3.1`。）
Android 侧无需改：`android/app/build.gradle.kts` 用的是 `flutter.versionCode` / `flutter.versionName`。

## 3. 签名：当前固定用 debug keystore

`android/app/build.gradle.kts` 中 release 的 `signingConfig` 指向 `debug`。这是**当前有意为之**（用户 2026-10-04 明确选择暂不切换正式签名）。

- **不要擅自改成正式签名**：签名一变，所有已安装设备都必须卸载重装，本地数据（drift 音乐库、Hive 设置、听歌统计、歌单、下载目录配置）会丢。
- 想切时必须先和用户确认，并提醒上面这条代价；步骤见 `docs/` 讨论记录（keytool 要用 `C:\Users\PC\flutter\jdk17\jdk-17.0.12+7\bin\keytool.exe`，PATH 上那个 JDK 8 的读不了现代 PKCS12 库）。
- `C:\Users\PC\.android\debug.keystore` **一旦丢失或重新生成，老用户将永远无法升级**——提醒用户备份。

## 4. 出包前必须过的门禁

```powershell
flutter analyze --no-pub      # 必须 0 issue
flutter test --no-pub -j 1    # 必须全绿
```

改动了 `lib/` 下任何与路由、背景、底部布局相关的文件时，除全量测试外，**必须对新增断言做红→绿验证**（先临时还原成旧结构确认断言会失败），否则不许声称修好——这是本仓库反复吃过亏的地方（见 `docs/mconnect-improvement-plan.md` 阶段 M / O / Q 的教训）。

## 5. 文档落点

- 每一轮修复的根因、方案、门禁、教训写入 `docs/mconnect-improvement-plan.md`（按「阶段 X」续写）
- 面向用户的版本变更写入 `CHANGELOG.md`
- 调研类产出放 `docs/`
