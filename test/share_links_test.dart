import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/core/share/share_links.dart';
import 'package:mconnect/core/share/share_service.dart';
import 'package:mconnect/models/artist.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/song.dart';

const _song = Song(
  id: '1974443814',
  platform: PlatformType.netease,
  name: '夜曲',
  artists: [Artist(id: 'a1', name: '周杰伦')],
);

void main() {
  group('歌曲链接格式', () {
    test('songLink → parseSongLink 往返保住 id/平台/名/歌手', () {
      final link = ShareLinks.songLink(_song);

      expect(link, startsWith('mconnect://song?'));
      final parsed = ShareLinks.parseSongLink(link);
      expect(parsed, isNotNull);
      expect(parsed!.id, '1974443814');
      expect(parsed.platform, PlatformType.netease);
      expect(parsed.name, '夜曲');
      expect(parsed.artistNames, '周杰伦');
    });

    test('多位歌手以逗号拼接，解析后逐个还原', () {
      const multi = Song(
        id: '9',
        platform: PlatformType.qq,
        name: '合唱',
        artists: [
          Artist(id: '1', name: 'A'),
          Artist(id: '2', name: 'B'),
        ],
      );
      final parsed = ShareLinks.parseSongLink(ShareLinks.songLink(multi))!;

      expect(parsed.artists.map((a) => a.name), ['A', 'B']);
      expect(parsed.artistNames, 'A, B');
    });

    test('缺名/缺歌手时给可用兜底而不是空字符串', () {
      const bare = Song(
        id: '1',
        platform: PlatformType.kugou,
        name: '',
        artists: [],
      );
      final parsed = ShareLinks.parseSongLink(ShareLinks.songLink(bare))!;

      expect(parsed.name, '未知歌曲');
      expect(parsed.artistNames, '未知歌手');
    });

    test('拒绝未知平台 / 缺 id / 本地歌曲 / 别人的链接', () {
      expect(
        ShareLinks.parseSongLink('mconnect://song?platform=spotify&id=1'),
        isNull,
      );
      expect(
        ShareLinks.parseSongLink('mconnect://song?platform=netease'),
        isNull,
      );
      expect(ShareLinks.parseSongLink('mconnect://song?id=1'), isNull);
      expect(
        ShareLinks.parseSongLink(
          'mconnect://song?platform=local&id=/sdcard/a.mp3',
        ),
        isNull,
      );
      expect(ShareLinks.parseSongLink('mconnect://playlist?data=abc'), isNull);
      expect(
        ShareLinks.parseSongLink('https://music.163.com/song?id=1'),
        isNull,
      );
      expect(ShareLinks.parseSongLink(''), isNull);
    });
  });

  group('分享文本', () {
    test('歌曲分享文本 = 歌名 - 歌手 + 链接', () {
      final text = buildSongShareText(_song);

      expect(text, contains('夜曲 - 周杰伦'));
      expect(text, contains(ShareLinks.songLink(_song)));
    });

    test('歌单分享文本 = 名称（N 首）+ 来源 + 链接', () {
      final text = buildPlaylistShareText(
        name: '我的最爱',
        songCount: 12,
        link: 'mconnect://playlist?data=xyz',
      );

      expect(text, contains('我的最爱（12 首）'));
      expect(text, contains('Mconnect'));
      expect(text, contains('mconnect://playlist?data=xyz'));
    });

    test('空歌单名回退占位名', () {
      expect(
        buildPlaylistShareText(name: '  ', songCount: 0, link: 'l'),
        contains('未命名歌单（0 首）'),
      );
    });
  });

  group('入站文本解析', () {
    test('从中文分享语里抽出链接并去掉尾随标点', () {
      expect(
        ShareLinks.extractLink(
          '这首歌不错 https://music.163.com/playlist?id=123。听听',
        ),
        'https://music.163.com/playlist?id=123',
      );
      expect(
        ShareLinks.extractLink('mconnect://playlist?data=abc'),
        'mconnect://playlist?data=abc',
      );
      expect(ShareLinks.extractLink('完全没有链接'), isNull);
      expect(ShareLinks.extractLink('   '), isNull);
    });

    test('ShareIntentHandler 的桥接链接会被拆包后继续解析', () {
      final bridge = ShareLinks.bridgeLink(
        '听听 https://music.163.com/playlist?id=9',
      );

      // Must stay byte-identical to `ShareIntentHandler.FORWARD_PREFIX` in
      // android/app/src/main/kotlin/com/mconnect/mconnect/ShareIntentHandler.kt.
      expect(bridge, startsWith('mconnect://share?text='));
      expect(
        ShareLinks.unwrapBridgeText(Uri.parse(bridge)),
        '听听 https://music.163.com/playlist?id=9',
      );
      final target = ShareLinks.classify(bridge);
      expect(target, isA<PlatformPlaylistLinkTarget>());
      expect(target!.link, 'https://music.163.com/playlist?id=9');
    });

    test('桥接链接嵌在散文里也能拆包', () {
      final inner = ShareLinks.bridgeLink('mconnect://song?platform=qq&id=42');
      final target = ShareLinks.classify('朋友分享的 $inner');

      expect(target, isA<SongLinkTarget>());
      expect((target! as SongLinkTarget).song.id, '42');
    });

    test('分类：歌曲 / 本地歌单 / 平台歌单链接', () {
      expect(
        ShareLinks.classify(ShareLinks.songLink(_song)),
        isA<SongLinkTarget>(),
      );
      expect(
        ShareLinks.classify('mconnect://playlist?data=abc'),
        isA<LocalPlaylistLinkTarget>(),
      );
      expect(
        ShareLinks.classify('https://y.qq.com/n/ryqq/playlist/123'),
        isA<PlatformPlaylistLinkTarget>(),
      );
      expect(ShareLinks.classify('随便一句话'), isNull);
      expect(ShareLinks.classify('mconnect://unknown?x=1'), isNull);
    });

    test('本地歌单链接判定与 OAuth 回调等其它 mconnect 主机不混淆', () {
      expect(
        ShareLinks.isLocalPlaylistLink('mconnect://playlist?data=1'),
        isTrue,
      );
      expect(ShareLinks.isLocalPlaylistLink('mconnect://song?id=1'), isFalse);
      expect(
        ShareLinks.isLocalPlaylistLink('https://mconnect.app/playlist'),
        isFalse,
      );
    });

    test('导入歌单落地路由指向 /import-playlist', () {
      expect(ShareLinks.importPlaylistLocation, '/import-playlist');
      expect(ShareLinks.playerLocation, '/player');
    });
  });

  group('ShareService（可注入通道，不碰平台通道）', () {
    test('shareSong 把文本与主题交给通道', () async {
      final channel = _RecordingChannel();
      final service = ShareService(channel);

      await service.shareSong(_song);

      expect(channel.texts.single, buildSongShareText(_song));
      expect(channel.subjects.single, '夜曲');
    });

    test('sharePlaylist 分享歌单链接', () async {
      final channel = _RecordingChannel();
      final service = ShareService(channel);

      await service.sharePlaylist(
        name: '我的最爱',
        songCount: 3,
        link: 'mconnect://playlist?data=1',
      );

      expect(channel.texts.single, contains('我的最爱（3 首）'));
      expect(channel.texts.single, contains('mconnect://playlist?data=1'));
      expect(channel.subjects.single, '我的最爱');
    });

    test('通道失败向上抛（由调用方决定提示，不静默吞掉）', () async {
      final service = ShareService(const _ThrowingChannel());

      await expectLater(service.shareSong(_song), throwsA(isA<StateError>()));
    });
  });
}

class _RecordingChannel implements ShareChannel {
  final List<String> texts = [];
  final List<String?> subjects = [];
  final List<List<String>> fileBatches = [];
  final List<String?> fileSubjects = [];

  @override
  Future<void> shareText(String text, {String? subject, Rect? origin}) async {
    texts.add(text);
    subjects.add(subject);
  }

  @override
  // 连带实现：`ShareChannel` 新增 `shareFiles`（歌词分享图用）后，假 channel 必须
  // 跟上；它只记录调用，不真分享 —— 不是写漏了。
  Future<void> shareFiles(
    List<String> paths, {
    String? subject,
    String? text,
    Rect? origin,
  }) async {
    fileBatches.add(List.of(paths));
    fileSubjects.add(subject);
  }
}

class _ThrowingChannel implements ShareChannel {
  const _ThrowingChannel();

  @override
  Future<void> shareText(String text, {String? subject, Rect? origin}) async {
    throw StateError('share unavailable');
  }

  @override
  // 同上：接口新增方法后的连带实现。
  Future<void> shareFiles(
    List<String> paths, {
    String? subject,
    String? text,
    Rect? origin,
  }) async {
    throw StateError('share unavailable');
  }
}
