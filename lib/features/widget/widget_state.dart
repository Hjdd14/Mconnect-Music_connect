import 'package:flutter/foundation.dart';

/// 小组件共享存储（Android 上就是 SharedPreferences）里的 key。
///
/// ⚠️ 这些字面量是**跨语言契约**：原生侧 `MconnectWidgetProvider` 的 companion object
/// 里有同名常量（`KEY_TITLE` / `KEY_ARTIST` / `KEY_IS_PLAYING` / `KEY_HAS_SONG` /
/// `KEY_COVER_PATH`）。改任意一侧都必须同时改另一侧，`test/widget_bridge_test.dart`
/// 会用字面量把它们钉住，改单侧就会红。
class WidgetDataKeys {
  const WidgetDataKeys._();

  /// 曲名。未播放时写空串（不是 null），保证原生 `getString(..., null)` 拿不到旧值。
  static const String title = 'title';

  /// 歌手（多歌手用 `, ` 连接，取自 `Song.artistNames`）。
  static const String artist = 'artist';

  /// 是否正在播放 → 原生据此切换 play/pause 图标。
  static const String isPlaying = 'isPlaying';

  /// 是否真的有一首歌（区分"暂停中的歌"和"从未播放过"）。
  static const String hasSong = 'hasSong';

  /// 封面图在**共享目录里的绝对路径**（由 `HomeWidget.saveImage`/`saveFile` 落盘）。
  /// 原生用 `BitmapFactory.decodeFile(path)` 读；拿不到就隐藏 ImageView，绝不留灰块。
  static const String coverPath = 'coverPath';

  /// 契约 key 的完整集合（测试用；顺序不影响语义）。
  static const List<String> all = <String>[
    title,
    artist,
    isPlaying,
    hasSong,
    coverPath,
  ];
}

/// 要推给小组件的一份快照。
///
/// 刻意**不含播放进度**：进度每秒都变，写一次 SharedPreferences 再让桌面重绘一次
/// 是纯浪费；而且 RemoteViews 上的进度条会闪。进度条留作后续（要走
/// `HomeWidget.scheduleWidgetUpdates` 而不是逐帧推送）。
///
/// 也刻意**不含歌手/曲名以外的歌曲身份字段**：原生只显示两行文本 + 一张图。
@immutable
class WidgetSnapshot {
  const WidgetSnapshot({
    this.songName,
    this.artistNames,
    this.isPlaying = false,
    this.coverPath,
  });

  /// "什么都没在播"的快照。原生侧据此显示 `@string/mconnect_widget_idle` 兜底文案。
  const WidgetSnapshot.empty()
    : songName = null,
      artistNames = null,
      isPlaying = false,
      coverPath = null;

  final String? songName;
  final String? artistNames;
  final bool isPlaying;
  final String? coverPath;

  /// 有歌可显示：曲名非空。注意"暂停中"仍然 hasSong == true（标题要留着）。
  bool get hasSong => songName != null && songName!.trim().isNotEmpty;

  /// 写进共享存储的键值对（键见 [WidgetDataKeys]）。
  ///
  /// `title`/`artist` 在无歌时写**空串**而不是 null：`saveWidgetData<String>(k, null)`
  /// 会删除键，而原生侧读不到键时会用 `hasSong=false` 走兜底 —— 两条路殊途同归，
  /// 但空串能让"上一次的歌名"一定不会残留（删键在某些 OEM 的 SharedPreferences
  /// 实现里需要 commit 才立刻可见，写值更稳）。
  Map<String, Object?> toWidgetData() => <String, Object?>{
    WidgetDataKeys.title: songName ?? '',
    WidgetDataKeys.artist: artistNames ?? '',
    WidgetDataKeys.isPlaying: isPlaying,
    WidgetDataKeys.hasSong: hasSong,
    WidgetDataKeys.coverPath: coverPath,
  };

  WidgetSnapshot copyWith({
    String? songName,
    String? artistNames,
    bool? isPlaying,
    String? coverPath,
    bool clearCover = false,
  }) {
    return WidgetSnapshot(
      songName: songName ?? this.songName,
      artistNames: artistNames ?? this.artistNames,
      isPlaying: isPlaying ?? this.isPlaying,
      coverPath: clearCover ? null : (coverPath ?? this.coverPath),
    );
  }

  /// 去重用的相等判断。
  ///
  /// 桥接层用它挡住"只变了播放进度"的更新：`PlayerState` 每次进度 tick 都会发通知，
  /// 若不过滤就会每秒写一次共享存储、并让桌面进程跟着重绘。
  @override
  bool operator ==(Object other) =>
      other is WidgetSnapshot &&
      other.songName == songName &&
      other.artistNames == artistNames &&
      other.isPlaying == isPlaying &&
      other.coverPath == coverPath;

  @override
  int get hashCode => Object.hash(songName, artistNames, isPlaying, coverPath);

  @override
  String toString() =>
      'WidgetSnapshot(songName: $songName, artistNames: $artistNames, '
      'isPlaying: $isPlaying, coverPath: $coverPath)';
}
