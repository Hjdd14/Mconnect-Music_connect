import 'dart:ui' show Locale, PlatformDispatcher;

import 'package:audio_service/audio_service.dart';

import '../../l10n/app_localizations.dart';

/// Android Auto / Android Automotive 的 **browse tree**（浏览树）。
///
/// # 为什么必须有它（Play 审核 EP-1 / EP-2 的根因）
/// `audio_service` 的 `BaseAudioHandler.getChildren` 默认实现是
///
///     Future<List<MediaItem>> getChildren(String parentMediaId, [options]) async => [];
///
/// 也就是"只有播放控制、没有任何可浏览内容"。Google Play 对车载媒体应用的审核正是
/// 按这一点拒的：
/// * **EP-1** Media content is not properly exposed to Android Auto
/// * **EP-2** App does not provide a compliant user interface for media browsing
/// （实证见 https://github.com/ryanheise/audio_service/issues/1119）
///
/// 所以必须自己提供"根 → 分组 → **可播放叶子**"三层结构：
/// * 根 id 必须是 `AudioService.browsableRootId`（audio_service 提供的公开静态常量，
///   对应原生 `onGetRoot`）；
/// * 分组 `playable: false`，叶子 `playable: true`；
/// * **只有分组没有叶子同样不合格**。
///
/// # 为什么只有一个分组
/// v1 只暴露"当前播放"（数据来自 `AudioHandler.queue`，是 audio_service 的公开 API，
/// 不需要碰 `lib/features/player/**`）。歌单/本地库分组需要读那些 feature 的 provider，
/// 属于后续工作。分组标题复用**已有**的 ARB 键 `playerNowPlaying`，因此本文件不新增
/// 硬编码中文（i18n 预算不被这条改动推高）。
///
/// ⚠️ 审核提醒：`audio_service` 作者本人声明 —— 加了这个包**不等于**自动过审，
/// AA 合规是应用自己的责任（原文见 issue #1119 维护者回复）。上线前必须用
/// Desktop Head Unit 或真车走一遍 `docs/v1.5-w2w3-implementation-specs.md` §C.3 的
/// 7 条自查（尤其是"内容非空""能点到并播放成功"）。
class AudioBrowseTree {
  const AudioBrowseTree._();

  /// "当前播放"分组的 media id。带 `mconnect.` 前缀，避免与队列里歌曲的 id 撞。
  static const String queueGroupId = 'mconnect.browse.queue';

  /// 当前 locale 下的文案。
  ///
  /// 只用 `zh`/`en` 两个分支：生成的 `lookupAppLocalizations` 对**不支持的 locale
  /// 会抛 FlutterError**（生成的 switch 没有 default 分支），而 App 目前只声明
  /// `[Locale('zh')]`，所以其它语言一律落到 zh。
  static AppLocalizations _l10n() {
    final code = PlatformDispatcher.instance.locale.languageCode;
    return lookupAppLocalizations(Locale(code == 'en' ? 'en' : 'zh'));
  }

  /// 根的直接子节点（车机打开 App 时看到的第一层）。
  static List<MediaItem> rootChildren() => <MediaItem>[
    MediaItem(
      id: queueGroupId,
      title: _l10n().playerNowPlaying,
      playable: false,
      extras: const <String, dynamic>{'mconnect.kind': 'group'},
    ),
  ];

  /// 任意父节点的子节点。**纯函数**（可单测）：不认识/不允许的 id 一律返回空列表，
  /// 绝不抛异常 —— 车机侧一次异常就会让整个 MediaBrowserService 断开。
  static List<MediaItem> childrenOf(
    String parentMediaId, {
    required List<MediaItem> queue,
  }) {
    if (parentMediaId == AudioService.browsableRootId) {
      return rootChildren();
    }
    if (parentMediaId == queueGroupId) {
      // 队列项本身就是可播放叶子（audio_service 的 QueueHandler 已经处理
      // playFromMediaId / skipToQueueItem，所以点进去就能播）。
      return List<MediaItem>.unmodifiable(queue);
    }
    return const <MediaItem>[];
  }
}

/// 把 [AudioBrowseTree] 接到任意 `BaseAudioHandler` 上。
///
/// **落地方式（这一步由 `lib/features/player/**` 的 owner 完成，不由本任务执行）**：
/// 在音频 handler 的 `with` 列表里追加一个 mixin 即可 —— 因为 Dart 的 mixin 会覆盖
/// 基类实现，而 `BaseAudioHandler` 的 `getChildren` 默认返回空列表：
///
/// ```dart
/// // lib/features/player/data/playback_notification_service.dart
/// class MconnectAudioHandler extends BaseAudioHandler
///     with QueueHandler, SeekHandler, AudioBrowseTreeMixin {
/// ```
///
/// 若该 handler 已经自己覆写了 `getChildren`，则把 `AudioBrowseTreeMixin` 放在
/// `with` 列表**最后**（mixin 覆盖先前的实现），或直接把
/// `AudioBrowseTree.childrenOf(parentMediaId, queue: queue.value)` 抄进它自己的
/// `getChildren`。
mixin AudioBrowseTreeMixin on BaseAudioHandler {
  @override
  Future<List<MediaItem>> getChildren(
    String parentMediaId, [
    Map<String, dynamic>? options,
  ]) async {
    try {
      // 注意：`queue` 是 ValueStream（rxdart BehaviorSubject 的别名）。理论上它被
      // 种子化过，但**没有值时 `.value` 会抛 StateError**，所以这里必须兜住：
      // 车机侧宁可看到空列表，也不能因为一次异常把 MediaBrowserService 拖断。
      final items = queue.value;
      return AudioBrowseTree.childrenOf(parentMediaId, queue: items);
    } catch (_) {
      return const <MediaItem>[];
    }
  }
}
