import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/core/share/deep_link_service.dart';
import 'package:mconnect/core/share/share_links.dart';
import 'package:mconnect/features/library/data/my_playlists_repository.dart';
import 'package:mconnect/features/library/presentation/providers/my_playlists_provider.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/song.dart';

/// Link source driven by the test instead of by a platform channel.
class _FakeLinkSource implements LinkSource {
  _FakeLinkSource({this.initial});

  final Uri? initial;
  final StreamController<Uri> _controller = StreamController<Uri>.broadcast();

  void emit(Uri uri) => _controller.add(uri);

  @override
  Future<Uri?> initialLink() async => initial;

  @override
  Stream<Uri> links() => _controller.stream;

  Future<void> close() => _controller.close();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late MyPlaylistsRepository repository;
  late MyPlaylistsNotifier playlists;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('mconnect_deeplink_test');
    repository = MyPlaylistsRepository(storageDirectory: tempDir);
    playlists = MyPlaylistsNotifier(repository: repository);
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Future<String> seedPlaylistLink(String name) async {
    final playlist = await repository.createPlaylist(name);
    final link = await repository.exportPlaylistLink(playlist.id);
    expect(link, isNotNull);
    return link!;
  }

  Future<List<InboundLinkOutcome>> run(
    _FakeLinkSource source, {
    void Function()? afterStart,
    Duration wait = const Duration(milliseconds: 50),
  }) async {
    final outcomes = <InboundLinkOutcome>[];
    final service = DeepLinkService(
      source: source,
      handler: InboundLinkHandler(playlists: playlists),
      onOutcome: outcomes.add,
    );
    await service.start();
    afterStart?.call();
    await Future<void>.delayed(wait);
    await service.dispose();
    await source.close();
    return outcomes;
  }

  test('冷启动链接被处理一次', () async {
    final link = await seedPlaylistLink('分享来的歌单');
    final source = _FakeLinkSource(initial: Uri.parse(link));

    final outcomes = await run(source);

    expect(outcomes, hasLength(1));
    final outcome = outcomes.single as NavigateOutcome;
    expect(outcome.location, '/import-playlist');
    expect(outcome.message, contains('分享来的歌单'));
    // The import really happened, not just the navigation.
    expect(
      (await repository.getPlaylists()).map((p) => p.name),
      contains('分享来的歌单'),
    );
  });

  test('冷启动链接若被平台再次从 stream 重放，不重复导入', () async {
    final link = await seedPlaylistLink('只导入一次');
    final before = (await repository.getPlaylists()).length;
    final source = _FakeLinkSource(initial: Uri.parse(link));

    final outcomes = await run(
      source,
      afterStart: () => source.emit(Uri.parse(link)),
    );

    expect(outcomes, hasLength(1));
    expect(
      (await repository.getPlaylists()).length,
      before + 1,
      reason: '重放不能产生第二个歌单',
    );
  });

  test('运行中收到的链接会被处理', () async {
    final link = await seedPlaylistLink('运行中分享');
    final source = _FakeLinkSource();

    final outcomes = await run(
      source,
      afterStart: () => source.emit(Uri.parse(link)),
    );

    expect(outcomes, hasLength(1));
    expect((outcomes.single as NavigateOutcome).message, contains('运行中分享'));
  });

  test('歌曲链接 → PlaySongOutcome（携带可播放的 Song）', () async {
    final songLink = ShareLinks.songLink(
      const Song(id: '42', platform: PlatformType.qq, name: '歌名', artists: []),
    );
    final source = _FakeLinkSource(initial: Uri.parse(songLink));

    final outcomes = await run(source);

    final outcome = outcomes.single as PlaySongOutcome;
    expect(outcome.song.id, '42');
    expect(outcome.song.platform, PlatformType.qq);
  });

  test('平台歌单链接 → 交给 /import-playlist，且不做本地导入', () async {
    final source = _FakeLinkSource(
      initial: Uri.parse('https://y.qq.com/n/ryqq/playlist/123456'),
    );

    final outcomes = await run(source);

    expect((outcomes.single as NavigateOutcome).location, '/import-playlist');
    expect((outcomes.single as NavigateOutcome).message, isNull);
    expect(await repository.getPlaylists(), isEmpty);
  });

  test('无法解码的 mconnect 歌单链接 → 仍然进导入页并给出失败提示', () async {
    final source = _FakeLinkSource(
      initial: Uri.parse('mconnect://playlist?data=not-base64-json'),
    );

    final outcomes = await run(source);

    final outcome = outcomes.single as NavigateOutcome;
    expect(outcome.location, '/import-playlist');
    expect(outcome.message, contains('无法识别'));
  });

  test('未知的 mconnect 主机不产生导航（不把用户带去别处）', () async {
    final source = _FakeLinkSource(
      initial: Uri.parse('mconnect://unknown?x=1'),
    );

    final outcomes = await run(source);

    expect(outcomes, isEmpty);
  });

  test('无法解析的歌曲链接不产生结果', () async {
    final source = _FakeLinkSource();
    final outcomes = <InboundLinkOutcome>[];
    final service = DeepLinkService(
      source: source,
      handler: InboundLinkHandler(playlists: playlists),
      onOutcome: outcomes.add,
    );

    await service.start();
    source.emit(Uri.parse('mconnect://song?platform=spotify&id=1'));
    await Future<void>.delayed(const Duration(milliseconds: 30));
    await service.dispose();

    expect(outcomes, isEmpty);
    await source.close();
  });

  test('dispose 后不再处理新链接', () async {
    final source = _FakeLinkSource();
    final outcomes = <InboundLinkOutcome>[];
    final service = DeepLinkService(
      source: source,
      handler: InboundLinkHandler(playlists: playlists),
      onOutcome: outcomes.add,
    );
    await service.start();
    await service.dispose();

    source.emit(Uri.parse('mconnect://playlist?data=x'));
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(outcomes, isEmpty);
    await source.close();
  });

  test('start 幂等：重复调用不会建立第二条订阅', () async {
    final source = _FakeLinkSource();
    final outcomes = <InboundLinkOutcome>[];
    final service = DeepLinkService(
      source: source,
      handler: InboundLinkHandler(playlists: playlists),
      onOutcome: outcomes.add,
    );

    await service.start();
    await service.start();
    source.emit(Uri.parse('mconnect://song?platform=netease&id=7'));
    await Future<void>.delayed(const Duration(milliseconds: 30));
    await service.dispose();

    expect(outcomes, hasLength(1));
    await source.close();
  });
}
