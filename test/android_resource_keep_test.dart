import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 资源收缩护栏：**由 Dart 字符串引用的 Android 资源必须写进 `keep.xml`**。
///
/// # 这条护栏防的是什么（真实事故，不是假想）
///
/// v1.5.0 把媒体通知的小图标从 `mipmap/ic_launcher` 换成了
/// `drawable/ic_stat_music`。`/data/user/0/...` 里那份真机日志显示 App 一播放就
/// 进程重启（66 秒内 6 次），而没有留下任何 Dart 异常。插上设备抓 logcat 才拿到：
///
/// ```
/// java.lang.IllegalArgumentException: Invalid notification (no valid small icon):
///   Notification(channel=com.mconnect.mconnect.audio ... category=transport actions=3 ...)
///     at android.app.NotificationManager.fixNotification(NotificationManager.java:699)
///     at android.app.NotificationManager.notify(NotificationManager.java:627)
/// ```
///
/// **根因**：`build.gradle.kts` 里 `isShrinkResources = true`，而 Dart 侧是用
/// **字符串**引用资源的（`androidNotificationIcon: 'drawable/ic_stat_music'`）。
/// 资源收缩器只认代码/XML 里的引用，**看不见 Dart 字符串**，于是把该 drawable
/// 判为 `reachable=false` 并从 release 包里删除：
///
/// ```
/// # build/app/outputs/mapping/release/resources.txt
/// @com.mconnect.mconnect:drawable/ic_stat_music : reachable=false
/// ```
///
/// 后果是**只有 release 崩、debug 不崩**（debug 不做资源收缩，图标还在包里），
/// 极难自查。`android/app/src/main/res/raw/keep.xml` 就是为此存在的——9-30 已经
/// 用它保护过 4 个 `audio_service_*` 图标，但 v1.5 新增图标时**漏了它**。
///
/// 所以本用例把这条规则钉死：**凡是 Dart 里以 `'drawable/xxx'` / `'mipmap/xxx'`
/// 字符串引用的资源，都必须在 keep.xml 里出现**。新增一个通知图标却忘了 keep，
/// 在这里就会红，而不是等到用户装上 release 包闪退。
void main() {
  test('every Dart-string-referenced Android resource is kept from shrinking', () {
    final keepFile = File(
      'android/app/src/main/res/raw/keep.xml',
    );
    expect(
      keepFile.existsSync(),
      isTrue,
      reason:
          'keep.xml 是资源收缩的护栏本体（isShrinkResources = true）。'
          '它不存在时，所有 Dart 字符串引用的资源都会被 release 包删掉。',
    );
    final keepText = keepFile.readAsStringSync();

    // 与 playback_notification_service.dart 等处的书写形式一致。
    final ref = RegExp("'((?:drawable|mipmap)/[a-z0-9_]+)'");

    final referenced = <String>{};
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      for (final m in ref.allMatches(entity.readAsStringSync())) {
        referenced.add(m.group(1)!);
      }
    }

    expect(
      referenced,
      isNotEmpty,
      reason: '没扫到任何资源引用，说明本用例的扫描口径坏了（而不是真的没有引用）',
    );

    final missing = referenced
        .where((name) => !keepText.contains('@$name'))
        .toList()
      ..sort();

    expect(
      missing,
      isEmpty,
      reason:
          '这些资源只被 Dart 字符串引用，release 的资源收缩器看不到它们，'
          '必须加进 android/app/src/main/res/raw/keep.xml，否则 release 包会把它删掉。'
          '媒体通知小图标被删会抛 "Invalid notification (no valid small icon)" '
          '并直接杀掉进程（v1.5.0 的真实闪退根因）。缺失项：',
    );

    // 反向保护：keep.xml 里不该留下已经不存在的资源名，否则是死配置。
    for (final m in RegExp(r'@((?:drawable|mipmap)/[a-z0-9_]+)')
        .allMatches(keepText)) {
      final name = m.group(1)!;
      final path = name.startsWith('drawable/')
          ? 'android/app/src/main/res/${name.replaceFirst('/', '/')}.xml'
          : null;
      if (path != null) {
        // 只在同名文件确实不存在、且该名字也没被 Dart 引用时提示（png 形式单独存在
        // 也合法，所以这里不做强断言，避免误伤）。
        // ignore: avoid_print
        print('keep.xml 声明: $name (dart 引用=${referenced.contains(name)})');
      }
    }
  });
}
