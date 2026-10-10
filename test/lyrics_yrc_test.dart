import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/lyrics/models/lyrics_bundle.dart';
import 'package:mconnect/lyrics/models/lyrics_line.dart';

/// W2-A：网易云 `yrc`（逐字）与 `romalrc`（罗马音）。
///
/// 形状来自真实响应，已落成 `docs/netease-lyric-shapes.md`：**不是**推测。
/// 这里用自建的小样本（不含任何真实歌词正文）。
void main() {
  group('yrc parser', () {
    // `[行起始,行长](chunk 相对起始,chunk 时长,flags)文本`
    const yrc =
        '[0,232](0,232,0)制作人\n'
        '[232,232](232,232,0)作词\n'
        '[1000,1000](0,400,0)你(400,600,0)好\n'
        '[2500,1200](0,600,0)再(600,600,0)见\n';

    test('parses the line window and the per-chunk word timings', () {
      final document = LyricsDocument.parse(yrc, LyricsFormat.yrc);

      expect(document.format, LyricsFormat.yrc);
      expect(document.lines.map((line) => line.text), [
        '制作人',
        '作词',
        '你好',
        '再见',
      ]);
      expect(document.lines[2].timestamp, const Duration(milliseconds: 1000));
      final words = document.lines[2].words!;
      expect(words.map((word) => word.word), ['你', '好']);
      // chunk 起始是相对行首的：1000 + 0 / 1000 + 400。
      expect(words[0].start, const Duration(milliseconds: 1000));
      expect(words[0].duration, const Duration(milliseconds: 400));
      expect(words[1].start, const Duration(milliseconds: 1400));
      expect(words[1].duration, const Duration(milliseconds: 600));
    });

    test('keeps credit lines instead of assuming line 0 is the first lyric', () {
      final document = LyricsDocument.parse(yrc, LyricsFormat.yrc);

      // 真实 payload 头几行是制作人/作词/作曲，它们有时间戳、是可见文本。
      expect(document.lines.first.text, '制作人');
      expect(document.lines.first.timestamp, Duration.zero);
    });

    test('a chunk with an empty body is a gap, not a word', () {
      const withGap = '[0,900](0,300,0)前(300,300,0)(600,300,0)后';

      final document = LyricsDocument.parse(withGap, LyricsFormat.yrc);

      expect(document.lines.single.text, '前后');
      expect(document.lines.single.words, hasLength(2));
    });

    test('reports at least one line so format sniffing can rely on it', () {
      expect(LyricsDocument.parsesToLines(yrc, LyricsFormat.yrc), isTrue);
      // 反向守卫：LRC 内容绝不能冒充 yrc（否则嗅探会把 LRC 送进 yrc parser）。
      expect(
        LyricsDocument.parsesToLines('[00:01.00]普通歌词', LyricsFormat.yrc),
        isFalse,
      );
    });

    test('an LRC payload yields nothing as yrc', () {
      expect(
        LyricsDocument.parse('[00:01.00]普通歌词', LyricsFormat.yrc).lines,
        isEmpty,
      );
    });
  });

  group('LyricsBundle', () {
    const lrc = '[00:01.00]Hello\n[00:02.00]World';
    const translation = '[00:01.00]你好\n[00:02.00]世界';
    const yrc = '[1000,1000](0,500,0)Hello\n[2000,1000](0,500,0)World';

    test('prefers word-by-word when it parses', () {
      const bundle = LyricsBundle(lrc: lrc, yrc: yrc);

      final track = mainLyricsTrack(bundle)!;

      expect(track.format, LyricsFormat.yrc);
      expect(track.content, yrc);
    });

    test('falls back to lrc when the song has no yrc', () {
      // 八首里只有两首有 yrc：缺 yrc 是常态，不是错误。
      const bundle = LyricsBundle(lrc: lrc);

      final track = mainLyricsTrack(bundle)!;

      expect(track.format, LyricsFormat.lrc);
      expect(track.content, lrc);
    });

    test('falls back to lrc when the yrc payload is unusable', () {
      const bundle = LyricsBundle(lrc: lrc, yrc: 'garbage without timing');

      final track = mainLyricsTrack(bundle)!;

      expect(track.format, LyricsFormat.lrc);
      final document = buildLyricsDocument(bundle, source: LyricsSource.netease);
      expect(document.lines, hasLength(2));
      expect(document.lines.first.text, 'Hello');
    });

    test('a single-payload platform keeps the KRC sniffing', () {
      // 默认 getLyricsBundle 把「平台只有一份 payload」原样塞进 lrc。Kugou 解密后
      // 的 KRC 就长这样；若这里不做嗅探，LRC parser 看不到 [start,duration]，
      // 整首又变成「暂无歌词」——正是 W0-B 修掉的那个 bug。
      const krc = '[0,1200]<0,600,0>你<600,600,0>好';
      const bundle = LyricsBundle(lrc: krc);

      final track = mainLyricsTrack(bundle)!;

      expect(track.format, LyricsFormat.krc);
      expect(buildLyricsDocument(bundle).lines.single.text, '你好');
    });

    test('an ordinary LRC carrying markers still resolves to lrc', () {
      const bundle = LyricsBundle(lrc: '[00:01.00]你好 <3\n[00:03.00]a, b');

      expect(mainLyricsTrack(bundle)!.format, LyricsFormat.lrc);
      expect(buildLyricsDocument(bundle).lines, hasLength(2));
    });

    test('returns nothing usable for an empty bundle', () {      expect(mainLyricsTrack(const LyricsBundle()), isNull);
      expect(LyricsBundle(lrc: '   ').isEmpty, isTrue);
      expect(buildLyricsDocument(const LyricsBundle()).lines, isEmpty);
    });

    test('merges the ytlrc translation onto the word-by-word lines', () {
      // 真机 bug（2026-10-10）：yrc 主轨之前拿 `tlyric`（lrc 时间轴）配对，
      // 两者时间戳口径不同，几乎全配不上 ⇒ 有逐字歌词的歌全部丢译文。
      // yrc 主轨的翻译必须来自 `ytlrc`（它的时间戳 == yrc 行起始毫秒，
      // 实测：yrc `[14490,5880]` ↔ ytlrc `[00:14.490]`）。
      // 样本刻意让 tlyric 与 yrc 的时间戳不同（模拟真实数据），只有 ytlrc 能配上。
      const bundle = LyricsBundle(
        lrc: lrc,
        yrc: yrc,
        translation: '[00:01.90]错轴译文甲\n[00:02.90]错轴译文乙',
        yrcTranslation: '[00:01.00]你好\n[00:02.00]世界',
      );

      final document = buildLyricsDocument(
        bundle,
        source: LyricsSource.netease,
      );

      expect(document.format, LyricsFormat.yrc);
      expect(document.source, LyricsSource.netease);
      expect(document.lines.map((line) => line.text), ['Hello', 'World']);
      expect(
        document.lines.map((line) => line.translation),
        ['你好', '世界'],
        reason: 'yrc 主轨必须用 ytlrc 配对，而不是 lrc 时间轴的 tlyric',
      );
      expect(document.lines.first.words, isNotNull);
    });

    test('keeps using tlyric when the main track is plain lrc', () {
      // 无 yrc 的歌走 lrc 主轨，翻译仍来自 tlyric —— 图二那首（有译文）的路径。
      const bundle = LyricsBundle(
        lrc: lrc,
        translation: translation,
        yrcTranslation: '[00:09.00]不该被用上',
      );

      final document = buildLyricsDocument(bundle, source: LyricsSource.netease);

      expect(document.format, LyricsFormat.lrc);
      expect(document.lines.map((line) => line.translation), ['你好', '世界']);
    });

    test('an empty translation body never becomes a visible blank line', () {
      // 真实 romalrc/ytlrc 首行可能是「有时间戳、正文为空」。
      const bundle = LyricsBundle(
        lrc: lrc,
        translation: '[00:01.000]\n[00:01.00]你好\n[00:02.00]世界',
      );

      final document = buildLyricsDocument(bundle);

      expect(document.lines, hasLength(2));
      expect(document.lines.first.translation, '你好');
    });

    test('a translation line without a matching timestamp is ignored', () {
      const bundle = LyricsBundle(
        lrc: lrc,
        translation: '[00:09.00]无对应行',
      );

      final document = buildLyricsDocument(bundle);

      expect(document.lines.map((line) => line.translation), [null, null]);
    });

    test('keeps the source when the bundle is parsed', () {
      const bundle = LyricsBundle(lrc: lrc);

      expect(
        buildLyricsDocument(bundle, source: LyricsSource.qq).source,
        LyricsSource.qq,
      );
    });
  });

  group('LyricsSource', () {
    test('carries a badge label per source', () {
      expect(LyricsSource.netease.displayName, '网易云音乐');
      expect(LyricsSource.lrclib.displayName, 'LRCLIB');
      expect(LyricsSource.unknown.isKnown, isFalse);
      expect(LyricsSource.kugou.isKnown, isTrue);
    });
  });
}
