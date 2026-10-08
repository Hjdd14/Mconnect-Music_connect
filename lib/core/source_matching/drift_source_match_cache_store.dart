// drift 必须**整包**导入：`&`（以及 `|` / `not()`）是 drift 的扩展成员
// （`extension BooleanExpressionOperators on Expression<bool>`），只经 `show`
// 组合器或只从别的库间接带进来时，扩展不在作用域里 —— 报错只会说
// "The operator '&' isn't defined for the type 'Expression<bool>'"，很容易误判。
import 'package:drift/drift.dart';

import '../database/app_database.dart';
import 'source_match_cache.dart';

/// 用 W0-D 的 `SourceMatchCache`（drift 表 + [SourceMatchCacheDao]）实现
/// [SourceMatchCacheStore]（Wave 1-A）。
///
/// 取 DAO 用回调而不是直接持有实例：装配播放器时不该因为构造这个 store 就碰数据库
/// （`database` 与它的 DAO 都是懒的，保持这一点）。
///
/// TTL 由 DAO 的 `get(..., now:)` 负责（`expiresAt <= now` → 当作不存在），
/// 本类只做行 ↔ 领域对象的翻译，不复制过期判断。
class DriftSourceMatchCacheStore implements SourceMatchCacheStore {
  DriftSourceMatchCacheStore(this._daoOf);

  final SourceMatchCacheDao Function() _daoOf;

  @override
  Future<SourceMatchEntry?> get(
    String songKey,
    String targetPlatform, {
    required DateTime now,
  }) async {
    final row = await _daoOf().get(songKey, targetPlatform, now: now);
    if (row == null) return null;
    final fetchedAt = row.urlFetchedAt;
    return SourceMatchEntry(
      songKey: row.songKey,
      targetPlatform: row.targetPlatform,
      targetSongId: row.targetSongId,
      url: row.url,
      urlFetchedAt: fetchedAt == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(fetchedAt),
      score: row.score,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(row.expiresAt),
    );
  }

  @override
  Future<void> put(SourceMatchEntry entry) {
    return _daoOf().put(
      songKey: entry.songKey,
      targetPlatform: entry.targetPlatform,
      targetSongId: entry.targetSongId,
      expiresAt: entry.expiresAt,
      url: entry.url,
      urlFetchedAt: entry.urlFetchedAt,
      score: entry.score,
    );
  }

  @override
  Future<void> invalidate(String songKey, String targetPlatform) {
    final dao = _daoOf();
    // 只删一行（主键就是 (songKey, targetPlatform)）。DAO 没有单行删除方法，
    // 这里用 drift 的 delete 语句，与 DAO 内部 `clearAll` 的写法一致。
    return (dao.delete(dao.sourceMatchCaches)..where(
          (table) =>
              table.songKey.equals(songKey) &
              table.targetPlatform.equals(targetPlatform),
        ))
        .go();
  }

  @override
  Future<int> purgeExpired({required DateTime now}) {
    return _daoOf().purgeExpired(now: now);
  }
}
