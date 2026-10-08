import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/features/widget/widget_actions.dart';
import 'package:mconnect/features/widget/widget_bridge.dart';
import 'package:mconnect/features/widget/widget_state.dart';

/// `home_widget` 的 `platforms:` **只有 android 与 ios**（已核实 pub cache 里
/// `home_widget-0.10.0/pubspec.yaml`）。因此：
/// * Windows **不会编译失败**（插件不参与构建）；
/// * 但在 Windows 上调用任何 `HomeWidget.*` 会抛 `MissingPluginException`。
///
/// 本文件最重要的用例就是证明**非 Android 平台上是安全 no-op**，并且是**结构性**证明
/// （`pluginCallCount == 0`，即连一次插件 API 都没碰），而不是"看起来没报错"。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WidgetActions.parse', () {
    test('识别 5 个约定 URI', () {
      expect(
        WidgetActions.parse(Uri.parse(WidgetActions.openPlayerUri))?.kind,
        WidgetActionKind.openPlayer,
      );
      expect(
        WidgetActions.parse(Uri.parse(WidgetActions.togglePlayPauseUri))?.kind,
        WidgetActionKind.togglePlayPause,
      );
      expect(
        WidgetActions.parse(Uri.parse(WidgetActions.nextUri))?.kind,
        WidgetActionKind.next,
      );
      expect(
        WidgetActions.parse(Uri.parse(WidgetActions.previousUri))?.kind,
        WidgetActionKind.previous,
      );
      expect(
        WidgetActions.parse(Uri.parse(WidgetActions.queueUri))?.kind,
        WidgetActionKind.openQueue,
      );
    });

    test('只有 togglePlayPause/next/previous 算"传输类"', () {
      WidgetAction parse(String raw) =>
          WidgetActions.parse(Uri.parse(raw))!;
      expect(parse(WidgetActions.togglePlayPauseUri).isTransport, isTrue);
      expect(parse(WidgetActions.nextUri).isTransport, isTrue);
      expect(parse(WidgetActions.previousUri).isTransport, isTrue);
      expect(parse(WidgetActions.openPlayerUri).isTransport, isFalse);
      expect(parse(WidgetActions.queueUri).isTransport, isFalse);
    });

    test('绝不误吞分享深链：非 widget host / 其它 scheme / 未知路径一律 null', () {
      // 这些 URI 属于 ux-parity 的分享深链体系（lib/core/share/share_links.dart），
      // 由 InboundLinkHandler 处理；小组件桥必须原样放过它们。
      expect(WidgetActions.parse(Uri.parse('mconnect://song?id=1')), isNull);
      expect(WidgetActions.parse(Uri.parse('mconnect://share?text=x')), isNull);
      expect(WidgetActions.parse(Uri.parse('https://example.com/widget/open')), isNull);
      expect(WidgetActions.parse(Uri.parse('mconnect://widget/unknown')), isNull);
      expect(WidgetActions.parse(Uri.parse('mconnect://widget')), isNull);
      expect(WidgetActions.parse(null), isNull);
    });

    test('parseRaw 对空串/畸形输入返回 null（不抛）', () {
      expect(WidgetActions.parseRaw(null), isNull);
      expect(WidgetActions.parseRaw(''), isNull);
      expect(WidgetActions.parseRaw('   '), isNull);
      expect(WidgetActions.parseRaw('mconnect://widget/%'), isNull);
      expect(WidgetActions.parseRaw('not a uri at all'), isNull);
      expect(
        WidgetActions.parseRaw(WidgetActions.nextUri)?.kind,
        WidgetActionKind.next,
      );
    });
  });

  group('WidgetSnapshot / WidgetDataKeys', () {
    test('键名是与 Kotlin 的字面量契约，必须逐字一致', () {
      // 这份清单必须与 android/.../MconnectWidgetProvider.kt 的 companion object 相同。
      expect(WidgetDataKeys.title, 'title');
      expect(WidgetDataKeys.artist, 'artist');
      expect(WidgetDataKeys.isPlaying, 'isPlaying');
      expect(WidgetDataKeys.hasSong, 'hasSong');
      expect(WidgetDataKeys.coverPath, 'coverPath');
      expect(WidgetDataKeys.all, <String>[
        'title',
        'artist',
        'isPlaying',
        'hasSong',
        'coverPath',
      ]);
    });

    test('toWidgetData 覆盖全部契约键（不多不少）', () {
      final data = const WidgetSnapshot(
        songName: '歌',
        artistNames: '歌手',
        isPlaying: true,
      ).toWidgetData();
      expect(data.keys.toSet(), WidgetDataKeys.all.toSet());
      expect(data[WidgetDataKeys.title], '歌');
      expect(data[WidgetDataKeys.artist], '歌手');
      expect(data[WidgetDataKeys.isPlaying], isTrue);
      expect(data[WidgetDataKeys.hasSong], isTrue);
      expect(data[WidgetDataKeys.coverPath], isNull);
    });

    test('empty：hasSong=false、isPlaying=false、文案为空串（原生侧走资源兜底）', () {
      const snapshot = WidgetSnapshot.empty();
      expect(snapshot.hasSong, isFalse);
      expect(snapshot.isPlaying, isFalse);
      final data = snapshot.toWidgetData();
      expect(data[WidgetDataKeys.title], '');
      expect(data[WidgetDataKeys.artist], '');
      expect(data[WidgetDataKeys.hasSong], isFalse);
    });

    test('只有曲名/歌手/播放态/封面变化才算"变了"（挡住每秒的进度 tick）', () {
      const a = WidgetSnapshot(songName: 'A', isPlaying: true);
      const b = WidgetSnapshot(songName: 'A', isPlaying: true);
      const c = WidgetSnapshot(songName: 'A', isPlaying: false);
      // 快照里根本不含 progress 字段，所以"同曲同态"的两次 tick 必然相等 ——
      // 桥接层据此跳过一次 SharedPreferences 写入 + 一次桌面重绘。
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });

    test('copyWith 可以显式清掉封面（切歌且新封面落盘失败时用）', () {
      const withCover = WidgetSnapshot(songName: 'A', coverPath: 'https://x/y.jpg');
      expect(withCover.copyWith(clearCover: true).coverPath, isNull);
      expect(withCover.copyWith(songName: 'B').coverPath, 'https://x/y.jpg');
    });
  });

  group('WidgetBridge 平台守护（非 Android 必须安全 no-op）', () {
    setUp(() async {
      await WidgetBridge.resetForTest();
      // 本仓库的测试默认平台是 android，这里显式假装成桌面端。
      WidgetBridge.platformProbe = () => TargetPlatform.windows;
    });

    tearDown(() async {
      await WidgetBridge.resetForTest();
    });

    test('非 Android → isSupported == false', () {
      expect(WidgetBridge.isSupported, isFalse);
    });

    test('initialize/publish/dispatch 全部安全 no-op，且一次也没碰插件 API', () async {
      final errors = <String>[];
      await WidgetBridge.initialize(
        onError: (message, error, stack) => errors.add(message),
      );

      // 幂等：再调一次也不该有任何变化
      await WidgetBridge.initialize();

      expect(WidgetBridge.isInitialized, isTrue);
      // 没有平台通道 → 没有冷启动 URI（而不是抛 MissingPluginException）
      expect(WidgetBridge.takeInitialUri(), isNull);

      // 推状态：必须什么都不做
      await WidgetBridge.publish(
        const WidgetSnapshot(songName: '不应被写入', isPlaying: true),
      );
      await WidgetBridge.publish(const WidgetSnapshot.empty());

      // 点击派发：解析成功也不得触碰插件（只有导航/传输处理器，且此处都未安装）
      WidgetBridge.dispatchRaw(WidgetActions.togglePlayPauseUri);
      WidgetBridge.dispatchRaw(WidgetActions.nextUri);
      WidgetBridge.dispatch(Uri.parse(WidgetActions.openPlayerUri));
      WidgetBridge.dispatch(null);

      expect(
        WidgetBridge.pluginCallCount,
        0,
        reason: '非 Android 平台一次都不允许调用 HomeWidget.*，'
            '否则会抛 MissingPluginException 并把启动流程带崩',
      );
      expect(errors, isEmpty, reason: 'no-op 路径不该产生任何错误上报');
    });

    test('重复 resetForTest 后状态干净（用例之间不串味）', () async {
      expect(WidgetBridge.isInitialized, isFalse);
      expect(WidgetBridge.pluginCallCount, 0);
      expect(WidgetBridge.isSupported, isFalse);
    });

    test('Android 平台才认为"支持"（守护的另一半：不能把 Android 一起挡掉）', () {
      WidgetBridge.platformProbe = () => TargetPlatform.android;
      expect(WidgetBridge.isSupported, isTrue);
    });
  });
}
