/// 一条跨源匹配缓存（Wave 1-A）。
///
/// 对应 W0-D 建好的 `SourceMatchCaches` 表：一行 = `(歌曲, 目标平台)`。
class SourceMatchEntry {
  const SourceMatchEntry({
    required this.songKey,
    required this.targetPlatform,
    required this.targetSongId,
    required this.expiresAt,
    this.url,
    this.urlFetchedAt,
    this.score = 0,
  });

  /// 用 [Song.dedupeKey]（跨平台去重键）而不是 `(id, platform)`：缓存的价值正是
  /// "同一首歌在别家平台上是谁"，用主平台的 id 当键会让同一个录音写多份。
  final String songKey;

  /// 目标平台的 `PlatformType.name`（与本仓库其它持久化层同形）。
  final String targetPlatform;

  /// 命中曲目在目标平台上的 id。
  final String targetSongId;

  /// 上次解析出来的直链；平台直链是**签名短链**，必须配合 [expiresAt] 使用。
  final String? url;
  final DateTime? urlFetchedAt;

  /// 匹配置信度 `[0,1]`。
  final double score;

  /// 超过这个时刻就必须重新解析（命中缓存 ≠ 可直接播）。
  final DateTime expiresAt;

  /// [now] 时刻这条缓存还能不能直接拿去播。
  bool isUsableAt(DateTime now) {
    final url = this.url;
    return url != null && url.isNotEmpty && expiresAt.isAfter(now);
  }
}

/// 跨源匹配缓存的存储接缝。
///
/// 抽出来是为了让 [SourceMatchService] 能在没有 drift/Hive 的用例里跑：
/// 生产实现是 `DriftSourceMatchCacheStore`（包 W0-D 的 `sourceMatchCacheDao`）。
abstract class SourceMatchCacheStore {
  /// 取该 `(songKey, targetPlatform)` 的缓存。
  ///
  /// 约定：**`expiresAt <= now` 视为不存在**。调用方要额外留安全余量时，
  /// 把 `now` 往后挪（见 `SourceMatchService.urlSafetyMargin`）——TTL 判定只有
  /// 这一处，不做第二套。
  Future<SourceMatchEntry?> get(
    String songKey,
    String targetPlatform, {
    required DateTime now,
  });

  Future<void> put(SourceMatchEntry entry);

  /// 丢弃该 `(songKey, targetPlatform)` 的缓存（W2-B / 复核 F3）。
  ///
  /// 播放失败即调用：一条"时间上还有效、服务端已失效"的直链必须立刻作废，否则
  /// 下一次失败链还会命中它，把死链复用满整个 TTL。
  Future<void> invalidate(String songKey, String targetPlatform);

  /// 回收过期行；返回删掉几行。
  Future<int> purgeExpired({required DateTime now});
}
