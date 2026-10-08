import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/core/android_auto/audio_browse_tree.dart';

/// 一个最小的音频 handler，只为验证 mixin 真的覆盖了 `BaseAudioHandler` 的默认实现。
/// `BaseAudioHandler.getChildren` 的默认返回值是**空列表** —— 那正是 Play 审核
/// EP-1/EP-2 的来源（见 `lib/core/android_auto/audio_browse_tree.dart` 的文档注释）。
class _FakeAudioHandler extends BaseAudioHandler with AudioBrowseTreeMixin {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AudioBrowseTree 结构（车载 browse tree 的最低要求）', () {
    test('根 id 就是 AudioService.browsableRootId，且返回非空分组', () {
      final roots = AudioBrowseTree.childrenOf(
        AudioService.browsableRootId,
        queue: const <MediaItem>[],
      );

      // 层级第一步：根不能是空的（空根 = 车机点进去什么都没有 = EP-1）
      expect(roots, isNotEmpty);
      // 根下必须是"分组"而不是曲目：分组 playable=false，曲目在第二层
      expect(roots.every((item) => item.playable == false), isTrue);
      expect(
        roots.map((item) => item.id),
        contains(AudioBrowseTree.queueGroupId),
      );
      // 分组必须有标题，否则车机上是一行空白
      expect(roots.every((item) => item.title.isNotEmpty), isTrue);
    });

    test('队列分组：有歌时给出可播放叶子（EP-1/EP-2 的硬要求）', () {
      // 注意：`MediaItem` 的构造函数**不是 const**（audio_service 0.18.x 在初始化
      // 列表里有 assert），所以这里用 final 而不是 const 列表。
      final queue = <MediaItem>[
        MediaItem(id: 'netease:1', title: '第一首', artist: '歌手甲'),
        MediaItem(id: 'qq:2', title: '第二首', artist: '歌手乙'),
      ];

      final leaves = AudioBrowseTree.childrenOf(
        AudioBrowseTree.queueGroupId,
        queue: queue,
      );

      expect(leaves.length, 2);
      // **至少一条 playable == true 的叶子**是审核里最关键的一条：
      // 只有分组、没有曲目，同样会被判 EP-2。
      expect(
        leaves.where((item) => item.playable ?? false).length,
        greaterThanOrEqualTo(1),
      );
      // id 必须是原样透传的队列项 id —— 车机点一次会带这个 id 回调
      // `playFromMediaId`，audio_service 的 QueueHandler 已经处理了那条链路。
      expect(leaves.map((item) => item.id), <String>['netease:1', 'qq:2']);
    });

    test('队列为空时：分组仍在、子树为空，且不抛异常', () {
      expect(
        AudioBrowseTree.childrenOf(
          AudioBrowseTree.queueGroupId,
          queue: const <MediaItem>[],
        ),
        isEmpty,
      );
    });

    test('未知 / 空 parentMediaId 一律返回空列表（绝不抛）', () {
      for (final id in <String>['', 'nope', 'mconnect.browse.unknown', '/']) {
        expect(
          AudioBrowseTree.childrenOf(id, queue: const <MediaItem>[]),
          isEmpty,
          reason: '车机侧一次异常就会让整个 MediaBrowserService 断开',
        );
      }
    });

    test('根列表与队列列表都是不可变视图（调用方改不动内部数据）', () {
      final leaves = AudioBrowseTree.childrenOf(
        AudioBrowseTree.queueGroupId,
        queue: <MediaItem>[MediaItem(id: 'a', title: 'a')],
      );
      expect(
        () => leaves.add(MediaItem(id: 'b', title: 'b')),
        throwsUnsupportedError,
      );
    });
  });

  group('AudioBrowseTreeMixin（mixin 必须覆盖 BaseAudioHandler 的空实现）', () {
    test('getChildren(browsableRootId) 非空 —— 这正是修 EP-1/EP-2 的那一行', () async {
      final handler = _FakeAudioHandler();

      final children = await handler.getChildren(AudioService.browsableRootId);

      expect(
        children,
        isNotEmpty,
        reason: 'BaseAudioHandler.getChildren 默认返回 []；若这里是空的，'
            '说明 mixin 没被应用（Play 审核会以 EP-1/EP-2 拒审）',
      );
      expect(children.first.id, AudioBrowseTree.queueGroupId);
    });

    test('getChildren 对任意 id 都返回列表而不是抛异常', () async {
      final handler = _FakeAudioHandler();

      for (final id in <String>[
        AudioService.browsableRootId,
        AudioBrowseTree.queueGroupId,
        'unknown',
        '',
      ]) {
        expect(await handler.getChildren(id), isA<List<MediaItem>>());
      }
    });

    test('队列为空时 getChildren(queueGroupId) 是空列表（不是异常）', () async {
      final handler = _FakeAudioHandler();
      expect(await handler.getChildren(AudioBrowseTree.queueGroupId), isEmpty);
    });
  });
}
