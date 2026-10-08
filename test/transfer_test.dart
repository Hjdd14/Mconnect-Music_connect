import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/core/transfer/json_codec.dart';
import 'package:mconnect/core/transfer/m3u8_codec.dart';
import 'package:mconnect/core/transfer/playlist_codec.dart';
import 'package:mconnect/core/transfer/source_match_adapter.dart';
import 'package:mconnect/core/transfer/text_codec.dart';
import 'package:mconnect/core/transfer/transfer_format.dart';
import 'package:mconnect/core/transfer/transfer_report.dart';
import 'package:mconnect/core/transfer/transfer_runner.dart';
import 'package:mconnect/models/album.dart';
import 'package:mconnect/models/artist.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/song.dart';

import 'support/content_page_fakes.dart';

const _zhou = Song(
  id: '1974443814',
  platform: PlatformType.netease,
  name: '夜曲',
  artists: <Artist>[Artist(id: 'a1', name: '周杰伦')],
  duration: Duration(seconds: 227),
);

const _eason = Song(
  id: '0039MnYb0qxYhV',
  platform: PlatformType.qq,
  name: '富士山下',
  artists: <Artist>[Artist(id: 'a2', name: '陈奕迅')],
  duration: Duration(seconds: 258),
);

/// Carries an album + cover, which only our own JSON format preserves.
const _beyond = Song(
  id: 'k1',
  platform: PlatformType.kugou,
  name: '海阔天空',
  artists: <Artist>[Artist(id: 'a3', name: 'Beyond')],
  album: Album(id: 'al1', name: '乐与怒', coverUrl: 'https://cdn.test/y.jpg'),
  duration: Duration(seconds: 300),
  coverUrl: 'https://cdn.test/y.jpg',
);

const _playlist = <Song>[_zhou, _eason];

/// A fourth song, only ever produced by the matcher, so a report can be asserted
/// on names that differ from the document's own rows.
const _songD = Song(
  id: 'd1',
  platform: PlatformType.kugou,
  name: 'D',
  artists: <Artist>[Artist(id: 'a4', name: '歌手D')],
);

/// Two candidates from one search: the scorer below ranks the first high, the
/// second low.
const _candidateHigh = Song(
  id: 'high',
  platform: PlatformType.qq,
  name: '夜曲',
  artists: <Artist>[Artist(id: '', name: '周杰伦')],
);

const _candidateLow = Song(
  id: 'low',
  platform: PlatformType.qq,
  name: '夜曲 (Live)',
  artists: <Artist>[Artist(id: '', name: '周杰伦')],
);

/// A document row that already names its song, so no matching is needed.
const _exactEntry = TransferEntry(
  title: '夜曲',
  artists: <String>['周杰伦'],
  platform: PlatformType.netease,
  id: '1974443814',
);

List<TransferEntry> _entriesOf(String text) =>
    PlaylistTextCodec.decode(text)!.entries;

TransferReport _threeBucketReport() => const TransferReport(
  playlistName: 'p',
  matches: <TransferMatch>[
    TransferMatch(
      entryIndex: 0,
      entry: TransferEntry(title: '夜曲'),
      kind: TransferMatchKind.exact,
      song: _zhou,
    ),
    TransferMatch(
      entryIndex: 1,
      entry: TransferEntry(title: '富士山下'),
      kind: TransferMatchKind.needsConfirmation,
      song: _eason,
      candidates: <SourceMatchCandidate>[
        SourceMatchCandidate(song: _eason, confident: false),
      ],
    ),
    TransferMatch(
      entryIndex: 2,
      entry: TransferEntry(title: '找不到的歌'),
      kind: TransferMatchKind.missing,
      reason: '未找到可播放版本',
    ),
  ],
);

void main() {
  group('m3u8 编解码', () {
    test('导出→导入 往返保住 平台/id/歌名/歌手/时长', () {
      final text = M3u8Codec.encode(name: '我的最爱', songs: _playlist);
      final doc = M3u8Codec.decode(text);

      expect(doc, isNotNull);
      expect(doc!.format, PlaylistTransferFormat.m3u8);
      expect(doc.name, '我的最爱');
      expect(doc.entries, hasLength(2));

      final first = doc.entries.first;
      expect(first.hasExactIdentity, isTrue);
      expect(first.platform, PlatformType.netease);
      expect(first.id, '1974443814');
      expect(first.title, '夜曲');
      expect(first.artistNames, '周杰伦');
      expect(first.duration, const Duration(seconds: 227));

      // The identity is what makes the round trip exact without any network.
      final song = first.toSong()!;
      expect(song.id, '1974443814');
      expect(song.platform, PlatformType.netease);
      expect(song.artistNames, '周杰伦');
    });

    test('导出以 #EXTM3U 开头，含 #PLAYLIST 与每首一条 #EXTINF', () {
      final text = M3u8Codec.encode(name: '我的最爱', songs: _playlist);

      expect(text.split('\n').first, M3u8Codec.header);
      expect(text, contains('${M3u8Codec.playlistTag}我的最爱'));
      expect(
        text.split(M3u8Codec.infoTag).length - 1,
        2,
        reason: '每首歌一条 #EXTINF',
      );
    });

    test('给了 pathFor 时定位行是路径（交给第三方播放器/服务器）', () {
      final text = M3u8Codec.encode(
        name: 'p',
        songs: _playlist,
        options: M3u8ExportOptions(
          pathFor: (song) => '/music/${song.artistNames} - ${song.name}.mp3',
        ),
      );

      expect(text, contains('/music/周杰伦 - 夜曲.mp3'));
      expect(text, contains('/music/陈奕迅 - 富士山下.mp3'));
      expect(text, isNot(contains('mconnect://')));
    });

    test('导入第三方 m3u8：没有身份但一行都不丢', () {
      const thirdParty = '''
#EXTM3U
#EXTINF:227,周杰伦 - 夜曲
/music/zhou/ye.mp3
#EXTINF:-1,只有歌名
/music/only-title.mp3
/music/orphan-track.flac
''';
      final doc = M3u8Codec.decode(thirdParty)!;

      expect(doc.entries, hasLength(3), reason: '裸定位行也要成为一行');

      final first = doc.entries[0];
      expect(first.hasExactIdentity, isFalse);
      // `#EXTINF` is `Title`-first here (our own order); the VLC-style
      // `Artist - Title` reading is kept as the alternate.
      expect(first.title, '周杰伦');
      expect(first.artists, <String>['夜曲']);
      expect(first.alternate?.title, '夜曲');
      expect(first.alternate?.artists, <String>['周杰伦']);
      expect(first.duration, const Duration(seconds: 227));

      expect(doc.entries[1].title, '只有歌名');
      expect(doc.entries[1].artists, isEmpty);
      expect(
        doc.entries[1].duration,
        Duration.zero,
        reason: '#EXTINF:-1 表示时长未知，不是 -1 秒',
      );

      expect(
        doc.entries[2].title,
        'orphan-track',
        reason: '没有 #EXTINF 时用文件名兜底',
      );
    });

    test('不是 m3u8 的文本返回 null，交给别的编解码器', () {
      expect(M3u8Codec.decode('夜曲 - 周杰伦'), isNull);
      expect(M3u8Codec.decode(''), isNull);
    });
  });

  group('纯文本（歌名 - 歌手）', () {
    test('导出：每行 歌名 - 歌手', () {
      expect(
        PlaylistTextCodec.encode(songs: _playlist),
        '夜曲 - 周杰伦\n富士山下 - 陈奕迅',
      );
    });

    test('导出：没有歌手的歌曲只写歌名', () {
      const orphan = Song(
        id: 'x',
        platform: PlatformType.netease,
        name: '纯音乐',
        artists: <Artist>[],
      );

      expect(PlaylistTextCodec.encode(songs: const <Song>[orphan]), '纯音乐');
    });

    test('导入：歌名 - 歌手', () {
      final doc = PlaylistTextCodec.decode('夜曲 - 周杰伦\n富士山下 - 陈奕迅')!;

      expect(doc.format, PlaylistTransferFormat.text);
      expect(doc.entries, hasLength(2));
      expect(doc.entries.first.title, '夜曲');
      expect(doc.entries.first.artists, <String>['周杰伦']);
      expect(doc.entries.last.title, '富士山下');
    });

    test('导入：同样给出「歌手 - 歌名」的备用读法', () {
      final entry = PlaylistTextCodec.decode('周杰伦 - 夜曲')!.entries.single;

      expect(entry.title, '周杰伦');
      expect(entry.artists, <String>['夜曲']);
      expect(entry.hasAlternate, isTrue);
      expect(entry.alternate!.title, '夜曲');
      expect(entry.alternate!.artists, <String>['周杰伦']);
    });

    test('导入：没有分隔符的行只有歌名，且没有备用读法', () {
      final entry = PlaylistTextCodec.decode('夜曲')!.entries.single;

      expect(entry.title, '夜曲');
      expect(entry.artists, isEmpty);
      expect(entry.hasAlternate, isFalse);
      expect(entry.toSong(), isNull, reason: '没有身份就必须走匹配');
    });

    test('导入：跳过空行与 # 注释行', () {
      final doc = PlaylistTextCodec.decode(
        '\n# 我的清单\n夜曲 - 周杰伦\n\n   \n',
      )!;

      expect(doc.entries, hasLength(1));
      expect(doc.entries.single.title, '夜曲');
    });

    test('导入：没有可用行时返回 null', () {
      expect(PlaylistTextCodec.decode('   \n\n#只有注释\n'), isNull);
    });
  });

  group('自有 JSON', () {
    test('往返：平台/id/歌手/专辑/封面/时长全部保住', () {
      final text = PlaylistJsonCodec.encode(
        name: '备份',
        songs: const <Song>[_zhou, _beyond],
      );
      final doc = PlaylistJsonCodec.decode(text)!;

      expect(doc.format, PlaylistTransferFormat.json);
      expect(doc.name, '备份');
      expect(doc.entries, hasLength(2));

      final first = doc.entries.first;
      expect(first.platform, PlatformType.netease);
      expect(first.id, '1974443814');
      expect(first.title, '夜曲');
      expect(first.artists, <String>['周杰伦']);
      expect(first.duration, const Duration(seconds: 227));

      final song = doc.entries.last.toSong()!;
      expect(song.name, '海阔天空');
      expect(song.album?.name, '乐与怒');
      expect(song.album?.coverUrl, 'https://cdn.test/y.jpg');
      expect(song.coverUrl, 'https://cdn.test/y.jpg');
    });

    test('带 format 标记，且是可读的 JSON', () {
      final text = PlaylistJsonCodec.encode(name: '备份', songs: _playlist);
      final decoded = jsonDecode(text) as Map<String, dynamic>;

      // Asserted structurally, not by string matching: the envelope keys are the
      // contract, the whitespace is not.
      expect(decoded[PlaylistJsonCodec.formatKey], PlaylistJsonCodec.formatTag);
      expect(decoded[PlaylistJsonCodec.versionKey], PlaylistJsonCodec.version);
      expect(decoded[PlaylistJsonCodec.nameKey], '备份');
      expect(decoded[PlaylistJsonCodec.songsKey], hasLength(2));
      expect(text, contains('夜曲'), reason: '不 base64 包装，人能直接看');
    });

    test('不是我们的 JSON 时返回 null，别的 .json 不被半解析', () {
      expect(PlaylistJsonCodec.decode('{"songs": []}'), isNull);
      expect(PlaylistJsonCodec.decode('{"foo": 1}'), isNull);
      expect(PlaylistJsonCodec.decode('[]'), isNull);
      expect(PlaylistJsonCodec.decode('夜曲 - 周杰伦'), isNull);
    });

    test('坏 JSON 返回 null 不抛', () {
      expect(PlaylistJsonCodec.decode('{ broken'), isNull);
      expect(
        PlaylistJsonCodec.decode('{"format": "mconnect.playlist"'),
        isNull,
      );
      expect(
        PlaylistJsonCodec.decode(
          '{"format": "${PlaylistJsonCodec.formatTag}", "songs": "not-a-list"}',
        ),
        isNull,
      );
    });
  });

  group('格式探测', () {
    test('m3u8 / JSON / 纯文本各自命中', () {
      expect(
        decodePlaylistTransfer(
          M3u8Codec.encode(name: 'x', songs: _playlist),
        )!.format,
        PlaylistTransferFormat.m3u8,
      );
      expect(
        decodePlaylistTransfer(
          PlaylistJsonCodec.encode(name: 'x', songs: _playlist),
        )!.format,
        PlaylistTransferFormat.json,
      );
      expect(
        decodePlaylistTransfer('夜曲 - 周杰伦\n富士山下 - 陈奕迅')!.format,
        PlaylistTransferFormat.text,
      );
    });

    test('m3u8 优先于纯文本，否则指令行会被当成歌名', () {
      final doc = decodePlaylistTransfer(
        M3u8Codec.encode(name: 'x', songs: const <Song>[_zhou]),
      )!;

      expect(doc.entries, hasLength(1));
      expect(doc.entries.single.title, '夜曲');
    });

    test('空白/垃圾输入返回 null', () {
      expect(decodePlaylistTransfer(''), isNull);
      expect(decodePlaylistTransfer('   \n\n'), isNull);
      expect(decodePlaylistTransfer('#EXTM3U\n'), isNull);
    });

    test('深链预判：只有真像歌单的文本才被路由到导入页', () {
      expect(looksLikePlaylistTransfer('夜曲 - 周杰伦\n富士山下 - 陈奕迅'), isTrue);
      expect(
        looksLikePlaylistTransfer('#EXTM3U\n#EXTINF:1,A - B'),
        isTrue,
      );
      expect(
        looksLikePlaylistTransfer(
          '{"format":"${PlaylistJsonCodec.formatTag}"}',
        ),
        isTrue,
      );
      expect(looksLikePlaylistTransfer('随便一句话'), isFalse);
      expect(looksLikePlaylistTransfer(''), isFalse);
      expect(
        looksLikePlaylistTransfer('https://music.163.com/playlist?id=1'),
        isFalse,
      );
    });
  });

  group('匹配报告', () {
    test('三类同时出现：有把握→可入，低置信→待确认，没候选→无', () async {
      final matcher = _FakeMatcher((entry) async {
        switch (entry.title) {
          case 'B':
            return const <SourceMatchCandidate>[];
          case 'C':
            return const <SourceMatchCandidate>[
              SourceMatchCandidate(song: _eason, confident: false),
            ];
          case 'D':
            return const <SourceMatchCandidate>[
              SourceMatchCandidate(song: _songD, confident: true),
            ];
          default:
            return const <SourceMatchCandidate>[];
        }
      });
      final runner = TransferMatcher(matcher: matcher);

      final report = await runner.match(
        playlistName: 'p',
        entries: const <TransferEntry>[
          _exactEntry,
          TransferEntry(title: 'B'),
          TransferEntry(title: 'C'),
          TransferEntry(title: 'D'),
        ],
      );

      expect(report.total, 4);
      expect(report.exactCount, 2, reason: '精确身份 + 高置信候选');
      expect(report.needsConfirmationCount, 1);
      expect(report.missingCount, 1);
      expect(report.isLossless, isFalse);

      // 「无」的行保留原文与原因，不静默丢歌。
      expect(report.missing.single.entry.title, 'B');
      expect(report.missing.single.reason, isNotNull);

      // 可入的行按文档顺序给出，供草稿直接导入。
      expect(report.autoSongs.map((s) => s.name), <String>['夜曲', 'D']);
    });

    test('文档里已有精确身份的条目根本不问 matcher', () async {
      final matcher = _FakeMatcher(
        (entry) async => const <SourceMatchCandidate>[],
      );

      await TransferMatcher(matcher: matcher).match(
        playlistName: 'p',
        entries: const <TransferEntry>[
          _exactEntry,
          TransferEntry(title: '富士山下', artists: <String>['陈奕迅']),
        ],
      );

      expect(matcher.calls, 1);
      expect(matcher.asked, <String>['富士山下 - 陈奕迅']);
    });

    test('matcher 抛异常时该行归入「无」，其余行照常', () async {
      final matcher = _FakeMatcher((entry) async {
        if (entry.title == '炸') throw StateError('platform exploded');
        return const <SourceMatchCandidate>[
          SourceMatchCandidate(song: _zhou, confident: true),
        ];
      });

      final report = await TransferMatcher(
        matcher: matcher,
        sleep: (duration) async {},
      ).match(
        playlistName: 'p',
        entries: const <TransferEntry>[
          TransferEntry(title: '好'),
          TransferEntry(title: '炸'),
          TransferEntry(title: '也好'),
        ],
      );

      expect(report.missingCount, 1);
      expect(report.missing.single.entry.title, '炸');
      expect(report.exactCount, 2, reason: '一行失败不能拖垮整份清单');
    });

    test('请求是串行的：并发峰值 = 1', () async {
      final matcher = _FakeMatcher(
        (entry) async => const <SourceMatchCandidate>[],
      );

      await TransferMatcher(matcher: matcher).match(
        playlistName: 'p',
        entries: const <TransferEntry>[
          TransferEntry(title: 'a'),
          TransferEntry(title: 'b'),
          TransferEntry(title: 'c'),
          TransferEntry(title: 'd'),
        ],
      );

      expect(matcher.peakInFlight, 1, reason: '批量并发会招来平台限流');
      expect(matcher.calls, 4);
    });

    test('失败按 maxAttempts 重试并线性退避', () async {
      final sleeps = <Duration>[];
      final matcher = _FakeMatcher(
        (entry) async => throw StateError('always fails'),
      );

      final report = await TransferMatcher(
        matcher: matcher,
        baseBackoff: const Duration(milliseconds: 10),
        maxAttempts: 3,
        sleep: (duration) async {
          sleeps.add(duration);
        },
      ).match(
        playlistName: 'p',
        entries: const <TransferEntry>[TransferEntry(title: 'a')],
      );

      expect(matcher.calls, 3);
      expect(sleeps, const <Duration>[
        Duration(milliseconds: 10),
        Duration(milliseconds: 20),
      ]);
      expect(report.missingCount, 1);
    });

    test('主读法有结果时不试备用读法', () async {
      final entries = _entriesOf('夜曲 - 周杰伦');
      final matcher = _FakeMatcher(
        (entry) async => const <SourceMatchCandidate>[
          SourceMatchCandidate(song: _zhou, confident: true),
        ],
      );

      final report = await TransferMatcher(
        matcher: matcher,
      ).match(playlistName: 'p', entries: entries);

      expect(matcher.calls, 1);
      expect(report.exactCount, 1);
    });

    test('主读法没结果时才试「歌手 - 歌名」备用读法', () async {
      final entries = _entriesOf('周杰伦 - 夜曲');
      final matcher = _FakeMatcher((entry) async {
        if (entry.title == '夜曲') {
          return const <SourceMatchCandidate>[
            SourceMatchCandidate(song: _zhou, confident: true),
          ];
        }
        return const <SourceMatchCandidate>[];
      });

      final report = await TransferMatcher(
        matcher: matcher,
      ).match(playlistName: 'p', entries: entries);

      expect(matcher.asked, <String>['周杰伦 - 夜曲', '夜曲 - 周杰伦']);
      expect(report.exactCount, 1);
      expect(report.exact.single.song!.name, '夜曲');
    });

    test('断点续传：已完成的行不重复请求', () async {
      final entries = _entriesOf(
        '夜曲 - 周杰伦\n富士山下 - 陈奕迅\n海阔天空 - Beyond',
      );

      final first = _FakeMatcher(
        (entry) async => const <SourceMatchCandidate>[
          SourceMatchCandidate(song: _zhou, confident: true),
        ],
      );
      final partial = await TransferMatcher(
        matcher: first,
      ).match(playlistName: 'p', entries: entries);
      expect(first.calls, 3);

      final second = _FakeMatcher(
        (entry) async => const <SourceMatchCandidate>[
          SourceMatchCandidate(song: _eason, confident: true),
        ],
      );
      final resumed = await TransferMatcher(matcher: second).match(
        playlistName: 'p',
        entries: entries,
        resumeFrom: <int, TransferMatch>{0: partial.matches.first},
      );

      expect(second.calls, 2, reason: '第 0 行已经解析过');
      expect(resumed.total, 3);
      expect(
        resumed.matches.first.song!.name,
        '夜曲',
        reason: '复用的是上一次的结果，不是重新匹配的',
      );
    });

    test('onProgress 每行回调一次', () async {
      final progress = <String>[];
      final matcher = _FakeMatcher(
        (entry) async => const <SourceMatchCandidate>[],
      );

      await TransferMatcher(matcher: matcher).match(
        playlistName: 'p',
        entries: const <TransferEntry>[
          TransferEntry(title: 'a'),
          TransferEntry(title: 'b'),
        ],
        onProgress: (done, total) => progress.add('$done/$total'),
      );

      expect(progress, <String>['1/2', '2/2']);
    });
  });

  group('W1-A 打分适配器', () {
    test('向已登录平台按标题取候选，并用注入的打分器排序与分档', () async {
      final qq = FakeContentPlatform(
        type: PlatformType.qq,
        loggedIn: true,
        searchPages: {1: const <Song>[_candidateLow, _candidateHigh]},
      );
      final finder = SourceMatchCandidateFinder(
        // W1-A 的 `scoreCandidate` 就是这样以 tear-off 注入的；这里用替身，
        // 所以这个文件测的是「排序 + 分档 + 搜索纪律」，不是打分公式本身。
        score: (identity, candidate) => candidate.id == 'high' ? 0.9 : 0.4,
        confidentAt: 0.8,
        platforms: () => [qq],
      );

      final candidates = await finder.candidatesFor(
        const TransferEntry(title: '夜曲', artists: <String>['周杰伦']),
      );

      expect(candidates, hasLength(2));
      expect(candidates.first.song.id, 'high');
      expect(candidates.first.score, 0.9);
      expect(candidates.first.confident, isTrue);
      expect(candidates.last.song.id, 'low');
      expect(candidates.last.confident, isFalse);
      expect(qq.searchCalls.single.query, '夜曲');
      expect(qq.searchCalls.single.limit, 10);
    });

    test('未登录的平台一个请求都不发', () async {
      final qq = FakeContentPlatform(
        type: PlatformType.qq,
        searchPages: {1: const <Song>[_candidateHigh]},
      );
      final finder = SourceMatchCandidateFinder(
        score: (identity, candidate) => 1.0,
        confidentAt: 0.8,
        platforms: () => [qq],
      );

      expect(
        await finder.candidatesFor(const TransferEntry(title: '夜曲')),
        isEmpty,
      );
      expect(qq.searchCalls, isEmpty, reason: '未登录平台取不到流，请求只是浪费');
    });

    test('一个平台抛错不影响其它平台，行不会因此丢', () async {
      final broken = FakeContentPlatform(
        type: PlatformType.netease,
        loggedIn: true,
        searchError: Exception('platform exploded'),
      );
      final working = FakeContentPlatform(
        type: PlatformType.qq,
        loggedIn: true,
        searchPages: {1: const <Song>[_candidateHigh]},
      );
      final finder = SourceMatchCandidateFinder(
        score: (identity, candidate) => 1.0,
        confidentAt: 0.8,
        platforms: () => [broken, working],
      );

      final candidates = await finder.candidatesFor(
        const TransferEntry(title: '夜曲'),
      );

      expect(candidates.single.song.id, 'high');
    });

    test('0 分的候选被丢掉；全是 0 分时返回空（于是归入「无」）', () async {
      final qq = FakeContentPlatform(
        type: PlatformType.qq,
        loggedIn: true,
        searchPages: {1: const <Song>[_candidateHigh, _candidateLow]},
      );
      final finder = SourceMatchCandidateFinder(
        score: (identity, candidate) => 0.0,
        confidentAt: 0.8,
        platforms: () => [qq],
      );

      expect(
        await finder.candidatesFor(const TransferEntry(title: '夜曲')),
        isEmpty,
        reason: '0 分是「不合格」（例如时长差超容差），不是「低置信候选」',
      );
    });

    test('候选数量有上限，长尾不淹没报告', () async {
      final qq = FakeContentPlatform(
        type: PlatformType.qq,
        loggedIn: true,
        searchPages: {1: const <Song>[_candidateHigh, _candidateLow, _songD]},
      );
      final finder = SourceMatchCandidateFinder(
        score: (identity, candidate) => 0.9,
        confidentAt: 0.8,
        platforms: () => [qq],
        maxCandidates: 2,
      );

      expect(
        await finder.candidatesFor(const TransferEntry(title: '夜曲')),
        hasLength(2),
      );
    });

    test('平台之间是串行的：共享并发峰值 = 1', () async {
      final probe = _ProbeState();
      final finder = SourceMatchCandidateFinder(
        score: (identity, candidate) => 1.0,
        confidentAt: 0.8,
        platforms: () => [
          _ProbePlatform(probe, PlatformType.netease),
          _ProbePlatform(probe, PlatformType.qq),
          _ProbePlatform(probe, PlatformType.kugou),
        ],
      );

      await finder.candidatesFor(const TransferEntry(title: '夜曲'));

      expect(probe.calls, 3);
      expect(probe.peak, 1, reason: '三家同时打会招来风控');
    });
  });

  group('导入草稿', () {
    test('只导入 可入 + 已接受的待确认，并保持文档顺序', () {
      final report = _threeBucketReport();
      final draft = TransferDraft(report);

      expect(draft.songsToImport.map((s) => s.name), <String>['夜曲']);

      draft.toggle(report.needsConfirmation.single);
      expect(draft.acceptedCount, 1);
      expect(draft.isAccepted(report.needsConfirmation.single), isTrue);
      expect(draft.songsToImport.map((s) => s.name), <String>['夜曲', '富士山下']);

      draft.acceptAllNeedsConfirmation();
      expect(draft.acceptedCount, 1);

      draft.clearAccepted();
      expect(draft.songsToImport.map((s) => s.name), <String>['夜曲']);
    });

    test('toggle 只作用于待确认行：可入与无都不可选', () {
      final report = _threeBucketReport();
      final draft = TransferDraft(report);

      draft.toggle(report.exact.single);
      draft.toggle(report.missing.single);

      expect(draft.acceptedCount, 0);
      expect(draft.isAccepted(report.exact.single), isFalse);
      expect(draft.isAccepted(report.missing.single), isFalse);
    });
  });

  group('二维码分享', () {
    test('正常链接可编码，空白与超长返回 null', () {
      expect(isQrShareable('mconnect://playlist?data=abc'), isTrue);
      expect(
        qrPayloadForPlaylistLink('  mconnect://playlist?data=abc  '),
        'mconnect://playlist?data=abc',
      );
      expect(qrPayloadForPlaylistLink(''), isNull);
      expect(qrPayloadForPlaylistLink('   '), isNull);

      final tooLong =
          'mconnect://playlist?data=${List<String>.filled(1300, 'a').join()}';
      expect(isQrShareable(tooLong), isFalse);
      expect(
        qrPayloadForPlaylistLink(tooLong),
        isNull,
        reason: '画不出来的二维码必须回落到文本分享，而不是画一个扫不动的',
      );
      expect(qrPayloadForPlaylistLink(tooLong, maxBytes: 5000), tooLong);
    });
  });

  group('健壮性', () {
    test('空输入 / 垃圾输入不崩', () {
      for (final input in <String>[
        '',
        '   ',
        '\n\n\n',
        '{ broken json',
        '#EXTM3U\n',
        'a',
      ]) {
        expect(() => decodePlaylistTransfer(input), returnsNormally);
        expect(() => looksLikePlaylistTransfer(input), returnsNormally);
      }
    });

    test('空歌单导出后再导入得到空文档而不是崩', () {
      expect(
        M3u8Codec.decode(
          M3u8Codec.encode(name: 'x', songs: const <Song>[]),
        )!.isEmpty,
        isTrue,
      );
      expect(PlaylistTextCodec.encode(songs: const <Song>[]), '');
      expect(PlaylistTextCodec.decode(''), isNull);
      expect(
        PlaylistJsonCodec.decode(
          PlaylistJsonCodec.encode(name: 'x', songs: const <Song>[]),
        )!.isEmpty,
        isTrue,
      );
    });
  });
}

/// How a fake matcher answers for one entry. A typedef rather than an inline
/// function type so the field declaration stays readable.
typedef _MatchAnswer =
    Future<List<SourceMatchCandidate>> Function(TransferEntry entry);

/// Drives matching from the test: answers per entry, and records how the runner
/// called it (order, count, concurrency peak).
class _FakeMatcher implements PlaylistSourceMatcher {
  _FakeMatcher(this._answer);

  final _MatchAnswer _answer;

  final List<String> asked = <String>[];
  int calls = 0;
  int peakInFlight = 0;
  int _inFlight = 0;

  @override
  Future<List<SourceMatchCandidate>> candidatesFor(TransferEntry entry) async {
    asked.add(entry.display);
    calls++;
    _inFlight++;
    if (_inFlight > peakInFlight) peakInFlight = _inFlight;
    try {
      // Yield, so a concurrent implementation would actually overlap here and
      // the peak assertion would catch it.
      await Future<void>.delayed(Duration.zero);
      return await _answer(entry);
    } finally {
      _inFlight--;
    }
  }
}

/// Counters shared by several platforms, so "are they queried one at a time?"
/// can be answered across all of them rather than per platform.
class _ProbeState {
  int calls = 0;
  int inFlight = 0;
  int peak = 0;
}

/// A platform that records the shared concurrency counters around its search.
class _ProbePlatform extends FakeContentPlatform {
  _ProbePlatform(this.state, PlatformType type)
    : super(type: type, loggedIn: true);

  final _ProbeState state;

  @override
  Future<List<Song>> search(
    String keyword, {
    int page = 1,
    int limit = 30,
  }) async {
    state.calls++;
    state.inFlight++;
    if (state.inFlight > state.peak) state.peak = state.inFlight;
    try {
      // Yield so a concurrent implementation would actually overlap.
      await Future<void>.delayed(Duration.zero);
      return const <Song>[];
    } finally {
      state.inFlight--;
    }
  }
}
