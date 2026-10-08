import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/core/source_matching/source_match_cache.dart';
import 'package:mconnect/core/source_matching/source_match_service.dart';
import 'package:mconnect/core/source_matching/source_match_settings.dart';
import 'package:mconnect/core/source_matching/track_identity.dart';
import 'package:mconnect/features/player/data/next_track_prefetcher.dart';
import 'package:mconnect/features/player/data/playback_keep_alive_service.dart';
import 'package:mconnect/features/player/data/playback_notification_service.dart';
import 'package:mconnect/features/player/presentation/providers/player_provider.dart';
import 'package:mconnect/features/player/presentation/screens/player_screen.dart';
import 'package:mconnect/models/artist.dart';
import 'package:mconnect/models/audio_quality.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/song.dart';

import 'support/content_page_fakes.dart';

/// Wave 1-A 跨源换源（只在内置三平台之间）。
///
/// **红阶段形态**：这些 API 在实现前不存在，所以本文件在红阶段是**编译失败**
/// （而不是断言失败）——`SourceMatchService` / `TrackIdentity` /
/// `SourceMatchCacheStore` / `PlayerState.sourcePlatform` 都是本波新增的。
/// 编译通过之后，下面每条断言才是"换源行为"的可判别证据。
void main() {
  group('TrackIdentity 归一化', () {
    test('括号内容整体丢弃', () {
      expect(TrackIdentity.normalizeForMatch('夜曲 (Live)'), '夜曲');
      expect(TrackIdentity.normalizeForMatch('MIX（纯音乐）'), 'mix');
      expect(TrackIdentity.normalizeForMatch('Song [Explicit]'), 'song');
    });

    test('版本噪声词与 feat 之后的整段都丢弃', () {
      expect(TrackIdentity.normalizeForMatch('Hello - Remastered'), 'hello');
      expect(TrackIdentity.normalizeForMatch('Song feat. Other'), 'song');
      expect(TrackIdentity.normalizeForMatch('Song ft Other'), 'song');
      expect(TrackIdentity.normalizeForMatch('Song OST'), 'song');
    });

    test('大小写/标点/空白不影响 key，且只取主艺人', () {
      final song = _song('1', name: '  Hello, World!  ', artist: 'A/B', durationSeconds: 200);
      final identity = TrackIdentity.fromSong(song);
      expect(identity.titleKey, 'helloworld');
      expect(identity.artistKey, 'ab');
      expect(identity.duration, const Duration(seconds: 200));
    });
  });

  group('打分（阈值 0.8）', () {
    test('标题 + 主艺人 + 时长全对 → 满分', () {
      final service = _service(cache: _MemorySourceMatchCache(), platforms: const []);
      final identity = TrackIdentity.fromSong(
        _song('a', name: '夜曲', artist: '周杰伦', durationSeconds: 228),
      );
      final candidate = _song('b', platform: PlatformType.qq, name: '夜曲', artist: '周杰伦', durationSeconds: 228);
      // 不写 `isEqualTo(1.0)`：0.5+0.3+0.2 在 IEEE754 下不保证逐位等于 1.0。
      expect(service.scoreCandidate(identity, candidate), greaterThanOrEqualTo(0.99));
    });

    test('时长差超过 ±3s → 0 分（时长不符不换）', () {
      final service = _service(cache: _MemorySourceMatchCache(), platforms: const []);
      final identity = TrackIdentity.fromSong(_song('a', name: '夜曲', durationSeconds: 228));
      final candidate = _song('b', name: '夜曲', durationSeconds: 260);
      expect(service.scoreCandidate(identity, candidate), 0);
    });

    test('标题不同 → 低于阈值', () {
      final service = _service(cache: _MemorySourceMatchCache(), platforms: const []);
      final identity = TrackIdentity.fromSong(_song('a', name: '夜曲', durationSeconds: 228));
      final candidate = _song('b', name: '完全另一首歌', durationSeconds: 228);
      expect(service.scoreCandidate(identity, candidate), lessThan(0.8));
    });

    test('任一侧艺人缺失 → 给中性分，不把正常匹配压到阈值以下', () {
      final service = _service(cache: _MemorySourceMatchCache(), platforms: const []);
      final identity = TrackIdentity.fromSong(
        _song('a', name: '夜曲', artist: '', durationSeconds: 228),
      );
      final candidate = _song('b', name: '夜曲', artist: '周杰伦', durationSeconds: 228);
      expect(service.scoreCandidate(identity, candidate), greaterThanOrEqualTo(0.8));
    });
  });

  group('SourceMatchService 换源', () {
    test('未过期的缓存直接命中，且不再搜索任何平台', () async {
      final cache = _MemorySourceMatchCache();
      final qq = _MatchPlatform(type: PlatformType.qq);
      final kugou = _MatchPlatform(type: PlatformType.kugou);
      final song = _song('n-1', name: '夜曲');
      await cache.put(
        SourceMatchEntry(
          songKey: song.dedupeKey,
          targetPlatform: 'qq',
          targetSongId: 'qq-1',
          url: 'https://cached.test/x.mp3',
          urlFetchedAt: DateTime(2026),
          score: 0.92,
          // 远早于 safetyMargin（60s）之后，仍算有效
          expiresAt: DateTime(2026, 1, 1, 1),
        ),
      );
      final service = _service(cache: cache, platforms: [qq, kugou]);

      final resolution = await service.resolveDetailed(song, AudioLevel.low);

      expect(resolution.url, 'https://cached.test/x.mp3');
      expect(resolution.fromCache, isTrue);
      expect(resolution.platform, PlatformType.qq);
      expect(qq.searchInvocationCount, 0);
      expect(kugou.searchInvocationCount, 0);
      expect(cache.getCalls, 1);
    });

    test('缓存将在安全余量内过期 → 当作过期并重新解析', () async {
      final cache = _MemorySourceMatchCache();
      final qq = _MatchPlatform(
        type: PlatformType.qq,
        results: [_song('qq-9', platform: PlatformType.qq, name: '夜曲')],
      );
      final song = _song('n-2', name: '夜曲');
      await cache.put(
        SourceMatchEntry(
          songKey: song.dedupeKey,
          targetPlatform: 'qq',
          targetSongId: 'qq-old',
          url: 'https://cached.test/stale.mp3',
          urlFetchedAt: DateTime(2026),
          score: 0.9,
          // 距 now(2026-01-01) 只有 30s → 落在 60s 安全余量内 → 命中也当过期
          expiresAt: DateTime(2026, 1, 1, 0, 0, 30),
        ),
      );
      final service = _service(cache: cache, platforms: [qq]);

      final resolution = await service.resolveDetailed(song, AudioLevel.low);

      expect(resolution.fromCache, isFalse);
      expect(resolution.url, contains('qq-9'));
      expect(qq.searchInvocationCount, 1);
    });

    test('解析成功后写缓存，expiresAt = now + 20 分钟，并带上目标曲目', () async {
      final cache = _MemorySourceMatchCache();
      final qq = _MatchPlatform(
        type: PlatformType.qq,
        results: [_song('qq-2', platform: PlatformType.qq, name: '夜曲')],
      );
      final service = _service(cache: cache, platforms: [qq]);

      final resolution = await service.resolveDetailed(
        _song('n-3', name: '夜曲'),
        AudioLevel.lossless,
      );

      expect(resolution.isResolved, isTrue);
      expect(resolution.platform, PlatformType.qq);
      expect(resolution.targetSongId, 'qq-2');
      expect(cache.putCalls, 1);
      final stored = cache.entries.values.single;
      expect(stored.expiresAt, DateTime(2026).add(const Duration(minutes: 20)));
      expect(stored.url, contains('qq-2'));
      expect(qq.urlRequests.first.quality, AudioLevel.lossless);
    });

    test('目标平台没有请求档位时逐级降档取流', () async {
      final cache = _MemorySourceMatchCache();
      final qq = _MatchPlatform(
        type: PlatformType.qq,
        results: [_song('qq-4', platform: PlatformType.qq, name: '夜曲')],
        urlQualityFailures: const {AudioLevel.lossless},
      );
      final service = _service(cache: cache, platforms: [qq]);

      final resolution = await service.resolveDetailed(
        _song('n-4', name: '夜曲'),
        AudioLevel.lossless,
      );

      expect(resolution.isResolved, isTrue);
      expect(
        qq.urlRequests.map((request) => request.quality).toList(),
        [AudioLevel.lossless, AudioLevel.high],
      );
      expect(resolution.url, contains('-high.mp3'));
    });

    test('分不够就不采用，继续查下一个内置平台', () async {
      final cache = _MemorySourceMatchCache();
      final qq = _MatchPlatform(
        type: PlatformType.qq,
        results: [_song('qq-5', platform: PlatformType.qq, name: '完全另一首歌')],
      );
      final kugou = _MatchPlatform(
        type: PlatformType.kugou,
        results: [_song('kg-1', platform: PlatformType.kugou, name: '夜曲')],
      );
      final service = _service(cache: cache, platforms: [qq, kugou]);

      final resolution = await service.resolveDetailed(
        _song('n-5', name: '夜曲'),
        AudioLevel.low,
      );

      expect(resolution.platform, PlatformType.kugou);
      expect(resolution.url, contains('kg-1'));
      expect(qq.searchInvocationCount, 1);
      expect(kugou.searchInvocationCount, 1);
    });

    test('不会去查主平台自己，只查另外两个内置平台', () async {
      final cache = _MemorySourceMatchCache();
      final netease = _MatchPlatform(
        type: PlatformType.netease,
        results: [_song('ne-1', platform: PlatformType.netease, name: '夜曲')],
      );
      final qq = _MatchPlatform(
        type: PlatformType.qq,
        results: [_song('qq-6', platform: PlatformType.qq, name: '夜曲')],
      );
      final service = _service(cache: cache, platforms: [netease, qq]);

      final resolution = await service.resolveDetailed(
        _song('n-6', name: '夜曲'),
        AudioLevel.low,
      );

      expect(resolution.platform, PlatformType.qq);
      expect(netease.searchInvocationCount, 0);
    });

    test('未登录的平台不作为换源目标', () async {
      final cache = _MemorySourceMatchCache();
      final qq = _MatchPlatform(
        type: PlatformType.qq,
        loggedIn: false,
        results: [_song('qq-7', platform: PlatformType.qq, name: '夜曲')],
      );
      final kugou = _MatchPlatform(
        type: PlatformType.kugou,
        results: [_song('kg-2', platform: PlatformType.kugou, name: '夜曲')],
      );
      final service = _service(cache: cache, platforms: [qq, kugou]);

      final resolution = await service.resolveDetailed(
        _song('n-7', name: '夜曲'),
        AudioLevel.low,
      );

      expect(resolution.platform, PlatformType.kugou);
      expect(qq.searchInvocationCount, 0);
    });

    test('两个内置平台都换不到 → 返回失败，交给失败链跳过', () async {
      final cache = _MemorySourceMatchCache();
      final qq = _MatchPlatform(type: PlatformType.qq);
      final kugou = _MatchPlatform(type: PlatformType.kugou);
      final service = _service(cache: cache, platforms: [qq, kugou]);
      final song = _song('n-8', name: '夜曲');

      final resolution = await service.resolveDetailed(song, AudioLevel.low);

      expect(resolution.isResolved, isFalse);
      expect(resolution.failure, SourceMatchFailure.noCandidate);
      expect(await service.resolve(song, AudioLevel.low), isNull);
    });

    test('候选找到但取不到直链 → urlUnavailable，不写缓存', () async {
      final cache = _MemorySourceMatchCache();
      final qq = _MatchPlatform(
        type: PlatformType.qq,
        results: [_song('qq-8', platform: PlatformType.qq, name: '夜曲')],
        urlFailure: true,
      );
      final service = _service(cache: cache, platforms: [qq]);

      final resolution = await service.resolveDetailed(
        _song('n-9', name: '夜曲'),
        AudioLevel.low,
      );

      expect(resolution.failure, SourceMatchFailure.urlUnavailable);
      expect(cache.putCalls, 0);
    });

    // 复核 F1 的红→绿：老实现只用一个 bool，会把"有候选但全不及格"误报成
    // urlUnavailable；这里时长差 32s（> ±3s）→ 打分 0 → 应报 belowThreshold。
    test('有候选但时长差 >3s → belowThreshold（不是 urlUnavailable）', () async {
      final cache = _MemorySourceMatchCache();
      final qq = _MatchPlatform(
        type: PlatformType.qq,
        results: [
          _song(
            'qq-long',
            platform: PlatformType.qq,
            name: '夜曲',
            durationSeconds: 232,
          ),
        ],
      );
      final service = _service(cache: cache, platforms: [qq]);

      final resolution = await service.resolveDetailed(
        _song('n-13', name: '夜曲', durationSeconds: 200),
        AudioLevel.low,
      );

      expect(
        resolution.failure,
        SourceMatchFailure.belowThreshold,
        reason: '搜到了候选但时长差超容差 → 必须 belowThreshold；'
            '老实现（单个 sawCandidate）会误报 urlUnavailable',
      );
      expect(cache.putCalls, 0);
    });

    // 复核 F2 的红→绿：`SourceMatchEntry.isUsableAt` 以前是零引用死代码，TTL 全靠
    // "store 实现自觉遵守 get(now:) 契约"。这里用一个**违约的 store**（忽略 now、
    // 过期也照返）证明服务侧现在会自己复核，过期直链不会进播放。
    test('store 违约（忽略 now）时过期直链仍被拒（F2 纵深防御）', () async {
      final cache = _LyingSourceMatchCache();
      final qq = _MatchPlatform(
        type: PlatformType.qq,
        results: [_song('qq-fresh', platform: PlatformType.qq, name: '夜曲')],
      );
      final song = _song('n-14', name: '夜曲');
      cache.entries['${song.dedupeKey}|qq'] = SourceMatchEntry(
        songKey: song.dedupeKey,
        targetPlatform: 'qq',
        targetSongId: 'qq-stale',
        url: 'https://cached.test/stale.mp3',
        urlFetchedAt: DateTime(2025),
        score: 0.9,
        expiresAt: DateTime(2025), // 早已过期
      );
      final service = _service(cache: cache, platforms: [qq]);

      final resolution = await service.resolveDetailed(song, AudioLevel.low);

      expect(resolution.url, contains('qq-fresh'));
      expect(resolution.fromCache, isFalse);
      expect(
        qq.searchInvocationCount,
        1,
        reason: '违约 store 返回的过期直链必须被服务侧复核拦下并重解析',
      );
    });

    // 复核 F3 的核心判别断言：缓存直链播放失败 → 失效 → 下次必须重解析。
    // 之前这条路径完全零覆盖（一条"时间上还有效、服务端已失效"的直链会被复用满
    // 整个 20 分钟 TTL）。
    test('invalidateCache 之后必须重解析，不再复用同一条死链（F3）', () async {
      final cache = _MemorySourceMatchCache();
      final song = _song('inv-svc', name: '夜曲');
      await cache.put(
        SourceMatchEntry(
          songKey: song.dedupeKey,
          targetPlatform: 'qq',
          targetSongId: 'qq-dead',
          url: 'https://cached.test/dead.mp3',
          urlFetchedAt: DateTime(2026),
          score: 0.95,
          expiresAt: DateTime(2026, 1, 1, 1), // 仍"时间有效"
        ),
      );
      final qq = _MatchPlatform(
        type: PlatformType.qq,
        results: [_song('qq-new', platform: PlatformType.qq, name: '夜曲')],
      );
      final service = _service(cache: cache, platforms: [qq]);

      // ① 首次：命中缓存（死链），不搜索
      final first = await service.resolveDetailed(song, AudioLevel.low);
      expect(first.fromCache, isTrue);
      expect(first.url, 'https://cached.test/dead.mp3');
      expect(qq.searchInvocationCount, 0);

      // ② 播放失败 → 失效该 (歌曲, 平台)
      await service.invalidateCache(song, PlatformType.qq);
      expect(cache.invalidateCalls, 1);

      // ③ 下次必须重解析，拿到新直链
      final second = await service.resolveDetailed(song, AudioLevel.low);
      expect(second.fromCache, isFalse);
      expect(second.url, contains('qq-new'));
      expect(qq.searchInvocationCount, 1);
    });

    test('离线模式禁用换源，不发起任何搜索', () async {
      final cache = _MemorySourceMatchCache();
      final qq = _MatchPlatform(
        type: PlatformType.qq,
        results: [_song('qq-10', platform: PlatformType.qq, name: '夜曲')],
      );
      final service = _service(cache: cache, platforms: [qq], offline: true);

      final resolution = await service.resolveDetailed(
        _song('n-10', name: '夜曲'),
        AudioLevel.low,
      );

      expect(resolution.failure, SourceMatchFailure.offlineMode);
      expect(qq.searchInvocationCount, 0);
      expect(cache.getCalls, 0);
    });

    test('关闭「自动换源」→ disabled，不发起任何搜索', () async {
      final cache = _MemorySourceMatchCache();
      final qq = _MatchPlatform(
        type: PlatformType.qq,
        results: [_song('qq-11', platform: PlatformType.qq, name: '夜曲')],
      );
      final service = _service(cache: cache, platforms: [qq], autoSwitch: false);

      final resolution = await service.resolveDetailed(
        _song('n-11', name: '夜曲'),
        AudioLevel.low,
      );

      expect(resolution.failure, SourceMatchFailure.disabled);
      expect(qq.searchInvocationCount, 0);
    });

    test('本地文件不换源', () async {
      final cache = _MemorySourceMatchCache();
      final qq = _MatchPlatform(type: PlatformType.qq);
      final service = _service(cache: cache, platforms: [qq]);

      final resolution = await service.resolveDetailed(
        _song('C:\\Music\\a.mp3', platform: PlatformType.local, name: '夜曲'),
        AudioLevel.low,
      );

      expect(resolution.failure, SourceMatchFailure.localSource);
      expect(qq.searchInvocationCount, 0);
    });

    test('搜索失败按指数退避重试，且总次数有上限', () async {
      final cache = _MemorySourceMatchCache();
      final delays = <Duration>[];
      final qq = _MatchPlatform(
        type: PlatformType.qq,
        searchFailure: StateError('boom'),
      );
      final service = _service(
        cache: cache,
        platforms: [qq],
        sleep: (duration) async => delays.add(duration),
      );

      await service.resolveDetailed(_song('n-12', name: '夜曲'), AudioLevel.low);

      // 1 次首发 + maxRetriesPerPlatform(2) 次重试
      expect(qq.searchInvocationCount, 3);
      expect(delays, [
        const Duration(milliseconds: 300),
        const Duration(milliseconds: 600),
      ]);
    });
  });

  group('下一首预解析（步骤 3）', () {
    test('只预解析当前曲之后的 1~2 首：不含当前曲、不环绕', () async {
      final service = _CountingService(cache: _MemorySourceMatchCache());
      final prefetcher = NextTrackPrefetcher(service: service, lookahead: 2);
      final playlist = [_song('p-0'), _song('p-1'), _song('p-2'), _song('p-3')];

      prefetcher.schedule(
        playlist: playlist,
        currentIndex: 0,
        quality: AudioLevel.low,
      );
      await pumpEventQueue();
      expect(service.asked, ['p-1', 'p-2']);

      // 队尾没有"下一首"，不应环绕回队首
      service.asked.clear();
      prefetcher.schedule(
        playlist: playlist,
        currentIndex: 3,
        quality: AudioLevel.low,
      );
      await pumpEventQueue();
      expect(service.asked, isEmpty);
    });

    test('离线模式不预解析；退出离线后恢复', () async {
      final service = _CountingService(cache: _MemorySourceMatchCache());
      var offline = true;
      final prefetcher = NextTrackPrefetcher(
        service: service,
        isOfflineModeEnabled: () => offline,
      );
      final playlist = [_song('o-0'), _song('o-1')];

      prefetcher.schedule(
        playlist: playlist,
        currentIndex: 0,
        quality: AudioLevel.low,
      );
      await pumpEventQueue();
      expect(service.asked, isEmpty);

      offline = false;
      prefetcher.schedule(
        playlist: playlist,
        currentIndex: 0,
        quality: AudioLevel.low,
      );
      await pumpEventQueue();
      expect(service.asked, ['o-1']);
    });

    test('cancel() 之后不再解析后面的歌（在飞的那一次不撤回）', () async {
      final service = _CountingService(cache: _MemorySourceMatchCache());
      final prefetcher = NextTrackPrefetcher(service: service, lookahead: 3);

      prefetcher.schedule(
        playlist: [_song('c-0'), _song('c-1'), _song('c-2'), _song('c-3')],
        currentIndex: 0,
        quality: AudioLevel.low,
      );
      // 第一首的 resolveDetailed 在 schedule 里就已经同步进入请求，撤回不了；
      // 要保证的是"后面的不再发起"。
      prefetcher.cancel();
      await pumpEventQueue();

      expect(service.asked, ['c-1']);
      expect(prefetcher.isRunning, isFalse);
    });

    test('预解析把直链写进 SourceMatchCache（切歌才能零等待）', () async {
      final cache = _MemorySourceMatchCache();
      final qq = _MatchPlatform(
        type: PlatformType.qq,
        results: [_song('q-1', platform: PlatformType.qq, name: '夜曲')],
      );
      final service = SourceMatchService(
        cache: cache,
        platforms: () => [qq],
        now: () => DateTime(2026),
        sleep: (_) async {},
      );
      final prefetcher = NextTrackPrefetcher(service: service, lookahead: 1);

      prefetcher.schedule(
        playlist: [_song('n-0', name: '夜曲'), _song('n-1', name: '夜曲')],
        currentIndex: 0,
        quality: AudioLevel.low,
      );
      await pumpEventQueue();

      expect(
        cache.putCalls,
        1,
        reason: '预解析必须把直链落进缓存，否则切歌时还得现解析',
      );
    });
  });

  group('自动换源开关（计划 D-2）', () {
    test('读失败（无 Hive box）保持默认开；关掉后状态为 false', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // 用例环境里 Hive 没有 openBox('settings') → _load 抛并被捕获。
      // D-2 的硬要求：这条路径必须保持「开」。
      expect(
        container.read(autoSourceSwitchProvider).enabled,
        isTrue,
        reason: 'Hive 读失败必须保持默认值 true（默认开），不能变成 false',
      );

      // setEnabled 现在是**同步**的（内存状态立即翻转、落盘 fire-and-forget）：
      // 既不需要 await，也不会再有"Hive 未初始化"的异常从写盘路径逃逸。
      container.read(autoSourceSwitchProvider.notifier).setEnabled(false);

      expect(container.read(autoSourceSwitchProvider).enabled, isFalse);
    });
  });

  group('播放页来源角标', () {
    testWidgets('换源生效时显示「已换源 · 来自 QQ音乐」', (tester) async {
      final player = _BadgePlayer();
      addTearDown(player.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [playerProvider.overrideWith((ref) => player)],
          child: const MaterialApp(home: PlayerScreen()),
        ),
      );
      await tester.pump();

      expect(find.text('已换源 · 来自 QQ音乐'), findsOneWidget);
    });
  });
}

// ── 测试脚手架 ─────────────────────────────────────────────────────────────

const _badgeSong = Song(
  id: 'badge-1',
  platform: PlatformType.netease,
  name: '正在播放',
  artists: [Artist(id: 'ar', name: '歌手')],
);

/// 状态里已经带 `sourcePlatform` 的播放器（播放页角标的渲染输入）。
class _BadgePlayer extends PlayerNotifier {
  _BadgePlayer()
    : super(
        audioController: IdleAudioController(),
        audioControllerFactory: IdleAudioController.new,
        keepAliveController: const NoopPlaybackKeepAliveController(),
        notificationController: const NoopPlaybackNotificationController(),
        stuckWatchdogInterval: Duration.zero,
      ) {
    state = state.copyWith(
      currentSong: _badgeSong,
      playlist: const [_badgeSong],
      currentIndex: 0,
      sourcePlatform: () => PlatformType.qq,
    );
  }
}

Song _song(
  String id, {
  PlatformType platform = PlatformType.netease,
  String name = '夜曲',
  String artist = '歌手',
  int durationSeconds = 200,
}) {
  return Song(
    id: id,
    platform: platform,
    name: name,
    artists: [Artist(id: 'ar', name: artist)],
    duration: Duration(seconds: durationSeconds),
  );
}

SourceMatchService _service({
  required _MemorySourceMatchCache cache,
  required List<FakeContentPlatform> platforms,
  DateTime Function()? now,
  bool autoSwitch = true,
  bool offline = false,
  SourceMatchSleep? sleep,
}) {
  return SourceMatchService(
    cache: cache,
    platforms: () => platforms,
    isAutoSwitchEnabled: () => autoSwitch,
    isOfflineModeEnabled: () => offline,
    now: now ?? () => DateTime(2026),
    sleep: sleep ?? (_) async {},
  );
}

/// 记录"预解析问了哪几首"的服务（不改变解析行为）。
class _CountingService extends SourceMatchService {
  _CountingService({required super.cache})
    : super(
        platforms: () => const <FakeContentPlatform>[],
        now: () => DateTime(2026),
        sleep: (_) async {},
      );

  final asked = <String>[];

  @override
  Future<SourceMatchResolution> resolveDetailed(
    Song song,
    AudioLevel quality,
  ) {
    asked.add(song.id);
    return super.resolveDetailed(song, quality);
  }
}

/// 故意**违反** `get(now:)` 契约的 store：忽略 TTL，过期也照返。
///
/// 用来证明 `SourceMatchService._readCache` 的 `isUsableAt` 复核（F2）真的拦得住。
class _LyingSourceMatchCache extends _MemorySourceMatchCache {
  @override
  Future<SourceMatchEntry?> get(
    String songKey,
    String targetPlatform, {
    required DateTime now,
  }) async {
    getCalls++;
    return entries['$songKey|$targetPlatform'];
  }
}

/// 与 drift DAO 同一约定的内存缓存：`expiresAt <= now` 视为不存在。
class _MemorySourceMatchCache implements SourceMatchCacheStore {
  final entries = <String, SourceMatchEntry>{};
  int getCalls = 0;
  int putCalls = 0;
  int invalidateCalls = 0;

  static String _key(String songKey, String platform) => '$songKey|$platform';

  @override
  Future<SourceMatchEntry?> get(
    String songKey,
    String targetPlatform, {
    required DateTime now,
  }) async {
    getCalls++;
    final entry = entries[_key(songKey, targetPlatform)];
    if (entry == null) return null;
    return entry.expiresAt.isAfter(now) ? entry : null;
  }

  @override
  Future<void> put(SourceMatchEntry entry) async {
    putCalls++;
    entries[_key(entry.songKey, entry.targetPlatform)] = entry;
  }

  @override
  Future<void> invalidate(String songKey, String targetPlatform) async {
    invalidateCalls++;
    entries.remove(_key(songKey, targetPlatform));
  }

  @override
  Future<int> purgeExpired({required DateTime now}) async {
    final before = entries.length;
    entries.removeWhere((_, entry) => !entry.expiresAt.isAfter(now));
    return before - entries.length;
  }
}

/// 一个内置平台的替身：可控制搜索结果、取流失败与登录态。
class _MatchPlatform extends FakeContentPlatform {
  _MatchPlatform({
    required super.type,
    super.loggedIn = true,
    this.results = const [],
    this.searchFailure,
    this.urlFailure = false,
    this.urlQualityFailures = const {},
  });

  final List<Song> results;
  final Object? searchFailure;
  final bool urlFailure;
  final Set<AudioLevel> urlQualityFailures;
  int searchInvocationCount = 0;
  final urlRequests = <({String songId, AudioLevel quality})>[];

  @override
  Future<List<Song>> search(
    String keyword, {
    int page = 1,
    int limit = 30,
  }) async {
    searchInvocationCount++;
    final failure = searchFailure;
    if (failure != null) throw failure;
    return results;
  }

  @override
  Future<String> getSongUrl(
    String songId, {
    AudioLevel quality = AudioLevel.low,
  }) async {
    urlRequests.add((songId: songId, quality: quality));
    if (urlFailure || urlQualityFailures.contains(quality)) {
      throw StateError('url unavailable');
    }
    return 'https://alt.test/$songId-${quality.name}.mp3';
  }
}
