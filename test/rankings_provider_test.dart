import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/features/discovery/presentation/providers/rankings_provider.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/song.dart';

import 'support/content_page_fakes.dart';

void main() {
  test('平台失败不再被静默吞掉：错误进 errorsByPlatform 且平台保留', () async {
    final netease = FakeContentPlatform(
      type: PlatformType.netease,
      rankingSongs: [song('n1', PlatformType.netease, name: '网易云热歌')],
    );
    final qq = FakeContentPlatform(
      type: PlatformType.qq,
      rankingError: Exception('网络连接失败'),
    );
    final kugou = FakeContentPlatform(
      type: PlatformType.kugou,
      rankingSongs: [song('k1', PlatformType.kugou, name: '酷狗热歌')],
    );
    final notifier = RankingsNotifier(
      supportedTypes: const [
        PlatformType.netease,
        PlatformType.qq,
        PlatformType.kugou,
      ],
      platformResolver: (platform) => switch (platform) {
        PlatformType.netease => netease,
        PlatformType.qq => qq,
        PlatformType.kugou => kugou,
        PlatformType.local => kugou,
      },
    );

    await notifier.loadRankings();

    expect(notifier.state.songsForPlatform(PlatformType.netease), hasLength(1));
    expect(notifier.state.songsForPlatform(PlatformType.kugou), hasLength(1));
    // QQ 保留在可见平台里，并带上错误信息 —— 这正是旧代码丢掉它的地方。
    expect(notifier.state.visiblePlatforms, contains(PlatformType.qq));
    expect(notifier.state.errorForPlatform(PlatformType.qq), contains('网络连接失败'));
    expect(notifier.state.totalCount, 2);
    // 页面级错误只在“什么都没拿到”时出现。
    expect(notifier.state.error, isNull);
  });

  test('全部平台都空时才给出页面级空态', () async {
    final netease = FakeContentPlatform(type: PlatformType.netease);
    final notifier = RankingsNotifier(
      supportedTypes: const [PlatformType.netease],
      platformResolver: (_) => netease,
    );

    await notifier.loadRankings();

    expect(notifier.state.visiblePlatforms, [PlatformType.netease]);
    expect(notifier.state.error, '暂无排行榜数据');
  });

  test('请求超时被记成「请求超时」而不是无声失败', () async {
    final slow = _SlowPlatform(type: PlatformType.qq);
    final notifier = RankingsNotifier(
      supportedTypes: const [PlatformType.qq],
      platformResolver: (_) => slow,
      operationTimeout: const Duration(milliseconds: 10),
    );

    await notifier.loadRankings();

    expect(notifier.state.errorForPlatform(PlatformType.qq), '请求超时');
    expect(notifier.state.isLoading, isFalse);
  });

  test('local 平台永远不会被查询', () async {
    final fake = FakeContentPlatform(type: PlatformType.netease);
    final queried = <PlatformType>[];
    final notifier = RankingsNotifier(
      supportedTypes: const [PlatformType.local, PlatformType.netease],
      platformResolver: (platform) {
        queried.add(platform);
        return fake;
      },
    );

    await notifier.loadRankings();

    expect(queried, [PlatformType.netease]);
  });
}

class _SlowPlatform extends FakeContentPlatform {
  _SlowPlatform({required super.type});

  @override
  Future<List<Song>> getRankingList() async {
    await Future<void>.delayed(const Duration(seconds: 5));
    return const [];
  }
}
