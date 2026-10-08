import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../../core/diagnostics/diagnostics_service.dart';
import '../../../../core/source_matching/source_match_service.dart';
import '../../../../models/audio_quality.dart';
import '../../../../models/platform_type.dart';
import '../../../../models/song.dart';

/// 下一首预解析（Wave 1-A 步骤 3）。
///
/// 队列/下标/音质变化时，后台把**后面 1~2 首**的直链解析出来并写进
/// `SourceMatchCache`（由 [SourceMatchService] 负责写），真正切歌时
/// `resolveDetailed` 直接命中缓存 → 换源零等待。
///
/// **不做边下边播**：本仓库的 `just_audio` 版本没有接 `LockCachingAudioSource`
/// 所需的缓存目录/配额/清理管理，硬接会把"下载缓存"整套生命周期引进来（属后续
/// 波次）。这里只预解析 URL，不预下载音频字节。
///
/// 作废规则（每一条都有用例）：
/// * [schedule] 会推进 generation，在飞的那一轮在下一个检查点退出；
/// * 队列变更/换源/清空 → 调用方再 [schedule] 或 [cancel] 即可作废；
/// * 离线模式 → 直接不发起（也不推进正在跑的那一轮之后的工作）。
class NextTrackPrefetcher {
  NextTrackPrefetcher({
    required this._service,
    bool Function()? isOfflineModeEnabled,
    this._diagnostics,
    this.lookahead = 2,
  }) : assert(lookahead > 0, 'lookahead 至少要预解析 1 首'),
       _isOfflineModeEnabled = isOfflineModeEnabled ?? (() => false);

  final SourceMatchService _service;
  final bool Function() _isOfflineModeEnabled;
  final DiagnosticsService? _diagnostics;

  /// 预解析后面几首（1~2，默认 2）。
  final int lookahead;

  int _generation = 0;
  bool _running = false;
  _PrefetchRequest? _pending;

  @visibleForTesting
  int get generation => _generation;

  @visibleForTesting
  bool get isRunning => _running;

  /// 队列/下标/音质变化时调用。
  ///
  /// 只记录"最新一轮想要什么"，真正的执行由 [_drain] 串行完成：先前那一轮会在
  /// 下一个检查点看到 generation 变了就退出，新的一轮紧接着开始 —— 不会出现两轮
  /// 同时在请求平台（防风控）。
  void schedule({
    required List<Song> playlist,
    required int currentIndex,
    required AudioLevel quality,
  }) {
    _generation++;
    if (_isOfflineModeEnabled()) return;
    final targets = _targets(playlist, currentIndex);
    if (targets.isEmpty) return;
    _pending = _PrefetchRequest(
      generation: _generation,
      targets: targets,
      quality: quality,
    );
    unawaited(_drain());
  }

  /// 作废在飞的预取（清空队列 / 进离线模式 / 用户手动换源）。
  void cancel() {
    _generation++;
    _pending = null;
  }

  List<Song> _targets(List<Song> playlist, int currentIndex) {
    if (playlist.isEmpty || currentIndex < 0) return const <Song>[];
    final targets = <Song>[];
    for (var step = 1; step <= lookahead; step++) {
      final index = currentIndex + step;
      // 不环绕：队列末尾没有"下一首"，环绕预取会把队列开头重复算一遍。
      if (index >= playlist.length) break;
      targets.add(playlist[index]);
    }
    return targets;
  }

  Future<void> _drain() async {
    if (_running) return;
    _running = true;
    try {
      while (_pending != null) {
        final request = _pending!;
        _pending = null;
        for (final song in request.targets) {
          if (request.generation != _generation) break;
          if (_isOfflineModeEnabled()) break;
          if (song.platform == PlatformType.local) continue;
          try {
            final resolution = await _service.resolveDetailed(
              song,
              request.quality,
            );
            _diagnostics?.record(
              'source_match',
              'next_track_prefetched',
              data: {
                'song_id': song.id,
                'platform': song.platform.name,
                'hit': resolution.isResolved,
                'from_cache': resolution.fromCache,
              },
            );
          } catch (error, stack) {
            // 预解析失败绝不能影响正在播的那一首：只记诊断。
            _diagnostics?.recordError(
              'source_match.prefetch',
              error,
              stack,
              data: {'song_id': song.id},
            );
          }
        }
      }
    } finally {
      _running = false;
    }
  }
}

class _PrefetchRequest {
  const _PrefetchRequest({
    required this.generation,
    required this.targets,
    required this.quality,
  });

  final int generation;
  final List<Song> targets;
  final AudioLevel quality;
}
