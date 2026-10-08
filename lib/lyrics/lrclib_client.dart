import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/song.dart';
import 'models/lyrics_line.dart';

/// LRCLIB 兜底开关：只在**平台完全没给出可用歌词**或**时间轴明显不对**时才问。
///
/// 绝大多数歌曲平台自己就有词，每次都问会白等一个网络往返；LRCLIB 也不该被
/// 当成默认来源，它是兜底。
bool shouldAskLrclib(
  LyricsDocument? document, {
  required Duration songDuration,
}) {
  if (document == null || document.lines.isEmpty) return true;
  // 歌长未知时无法判断"明显错"，不要凭猜测去兜底。
  if (songDuration <= Duration.zero) return false;
  final lastLine = document.lines.last.timestamp;
  return lastLine > songDuration + const Duration(seconds: 30);
}

/// [LRCLIB](https://lrclib.net) 客户端：免费、无需 key，用来兜底没有词的歌。
///
/// 用 `/api/search`（模糊匹配，返回候选数组）而不是 `/api/get`：`get` 要求
/// track/artist/album/duration 全中，专辑名对不上就 404；`search` 之后按**时长
/// 就近**挑一个候选，命中率更高，也不必猜服务端对缺失参数的态度。
///
/// 实测响应形状（对象数组）：`duration`(秒, num) / `instrumental`(bool) /
/// `hasWordSync`(bool) / `plainLyrics`(String?) / `syncedLyrics`(String?，LRC)。
class LrclibClient {
  LrclibClient({Dio? dio, this.timeout = const Duration(seconds: 6)})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: 'https://lrclib.net',
              // LRCLIB 的文档要求客户端标识自己（他们的服务是免费公益的）。
              headers: {'User-Agent': 'Mconnect (lyrics fallback)'},
            ),
          );

  final Dio _dio;
  final Duration timeout;

  /// 同步歌词（LRC），没有就返回 null。
  ///
  /// **任何失败都返回 null**：一个兜底源没资格让端到端的歌词加载报错，也不该
  /// 掩盖平台自己的错误。
  Future<String?> fetchSyncedLyrics(Song song, {Duration? duration}) async {
    final wanted = duration ?? song.duration;
    try {
      final res = await _dio
          .get<dynamic>(
            '/api/search',
            queryParameters: {
              'track_name': song.name,
              'artist_name': song.artistNames,
            },
          )
          .timeout(timeout);
      return pickClosestSyncedLyrics(res.data, wanted);
    } catch (e) {
      debugPrint('LrclibClient failed: $e');
      return null;
    }
  }

  /// 从 `/api/search` 的响应里挑最合适的一条同步歌词。
  ///
  /// 解析与挑选是这条兜底的全部策略，所以单独可见以便钉住：跳过纯音乐与没有
  /// 同步歌词的条目，其余按 [wanted] 就近取；差太远（同名不同版本/现场版）宁可
  /// 返回 null，也不要把别的歌的歌词贴上来。
  @visibleForTesting
  static String? pickClosestSyncedLyrics(Object? data, Duration wanted) {
    final list = _asList(data);
    if (list.isEmpty) return null;

    final candidates = <({double duration, String lyrics})>[];
    for (final item in list) {
      if (item is! Map) continue;
      if (item['instrumental'] == true) continue;
      final synced = item['syncedLyrics'];
      if (synced is! String || synced.trim().isEmpty) continue;
      final rawDuration = item['duration'];
      candidates.add((
        duration: rawDuration is num ? rawDuration.toDouble() : 0.0,
        lyrics: synced,
      ));
    }
    if (candidates.isEmpty) return null;

    final wantedSeconds = wanted.inMilliseconds / 1000;
    if (wantedSeconds <= 0) return candidates.first.lyrics;

    candidates.sort(
      (a, b) => (a.duration - wantedSeconds).abs().compareTo(
        (b.duration - wantedSeconds).abs(),
      ),
    );
    final best = candidates.first;
    // 容差 = 5 秒或 5%（取大者）。
    final tolerance = wantedSeconds * 0.05 < 5 ? 5.0 : wantedSeconds * 0.05;
    if ((best.duration - wantedSeconds).abs() > tolerance) return null;
    return best.lyrics;
  }

  static List<Object?> _asList(Object? data) {
    if (data is List) return data;
    if (data is String) {
      try {
        final decoded = jsonDecode(data);
        if (decoded is List) return decoded;
      } catch (_) {
        // 不是 JSON 就当没有。
      }
    }
    return const [];
  }
}

/// 全局客户端；测试可覆盖它来避免真实网络。
final lrclibClientProvider = Provider<LrclibClient>((ref) => LrclibClient());
