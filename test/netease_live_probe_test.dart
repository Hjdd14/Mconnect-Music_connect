// ============================================================================
// ⚠️ 这不是普通单测 ⚠️
//
// 默认 **全部 skip**（`flutter test` 里显示为 `~10`，一次网络请求都不发），
// 只有显式设置环境变量才会真的打 https://music.163.com ：
//
//     PowerShell:  $env:NETEASE_LIVE='1'; flutter test --no-pub -j 1 test/netease_live_probe_test.dart
//     bash:        NETEASE_LIVE=1 flutter test --no-pub -j 1 test/netease_live_probe_test.dart
//
// 不设变量的输出是 `+0 ~10: All tests skipped.` —— 这是**预期行为**，
// 不是"测试被跳过 = 有问题"。请勿把它改造成默认出网的普通单测：
// 会污染 CI/离线门禁，并让 `flutter test` 依赖外网可用性。
//
// 为什么需要它：`scripts/test_netease_artist_album_toplist.dart` 只验证**端点**
// 可用（裸 Dio + 打印返回形状），而这里验证的是**实现**——`NeteasePlatform` 的
// 7 个新方法跑真实响应，解析出来的 name/排名/曲目号/地区差异是否真的对。
// 没有这一步，stub 单测只能证明"我按我以为的字段名解析"，不能证明字段名是对的。
//
// 结果记录在 `docs/netease-wave-b-report.md`（本文件所在的探针是"实现级"那一段）。
// ============================================================================
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/core/network/api_exception.dart';
import 'package:mconnect/platform/base/music_platform.dart';
import 'package:mconnect/platform/netease/netease_platform.dart';

/// 周杰伦（网易云艺人 id），探针里稳定存在。
const _artistId = '6452';

/// 热歌榜歌单 id（也在 getToplists 的返回里）。
const _hotChartId = '3778678';

final _live = Platform.environment['NETEASE_LIVE'] == '1';
const _skipReason =
    'live network probe: set NETEASE_LIVE=1 to run against music.163.com';

void _log(String line) {
  // ignore: avoid_print
  print(line);
}

void main() {
  final platform = NeteasePlatform();

  test('LIVE capabilities advertise artist/album/new-songs', () {
    expect(platform.supportsArtistPage, isTrue);
    expect(platform.supportsAlbumPage, isTrue);
    expect(platform.supportsNewSongs, isTrue);
    expect(platform.supportsDailyRecommendations, isTrue);
  }, skip: _live ? false : _skipReason);

  test('LIVE getToplists returns charts with real fields', () async {
    final toplists = await platform.getToplists();

    for (final t in toplists.take(3)) {
      _log(
        '  toplist id=${t.id} name=${t.name} freq=${t.updateFrequency} '
        'count=${t.songCount} cover=${t.coverUrl}',
      );
    }
    _log('  getToplists -> ${toplists.length} charts');
    expect(toplists, isNotEmpty);
    expect(toplists.where((t) => t.id == _hotChartId), isNotEmpty);
    expect(toplists.first.name, isNotEmpty);
    expect(toplists.first.updateFrequency, isNotNull);
    expect(toplists.first.songCount, isNotNull);
    expect(toplists.first.coverUrl, startsWith('http'));
  }, skip: _live ? false : _skipReason);

  test('LIVE getArtistDetail returns the real profile', () async {
    final artist = await platform.getArtistDetail(_artistId);

    _log(
      '  artist id=${artist?.id} name=${artist?.name} '
      'avatar=${artist?.avatarUrl} songs=${artist?.songCount} '
      'albums=${artist?.albumCount} fans=${artist?.fansCount} '
      'briefDesc=${artist?.briefDesc?.length} chars',
    );
    expect(artist, isNotNull);
    expect(artist!.name, '周杰伦');
    expect(artist.avatarUrl, startsWith('http'));
    expect(artist.songCount, greaterThan(0));
    expect(artist.albumCount, greaterThan(0));
    // head/info/get 的简介是完整的（旧接口那个是空字符串）。
    expect(artist.briefDesc, isNotEmpty);
    expect(artist.briefDesc!.length, greaterThan(50));
  }, skip: _live ? false : _skipReason);

  test('LIVE getArtistTopSongs parses real songs (dual field naming)', () async {
    final songs = await platform.getArtistTopSongs(_artistId);

    for (final s in songs.take(3)) {
      _log(
        '  topSong id=${s.id} name=${s.name} artists=${s.artistNames} '
        'album=${s.album?.name} cover=${s.coverUrl} dur=${s.duration.inSeconds}s',
      );
    }
    _log('  getArtistTopSongs -> ${songs.length} songs');
    expect(songs, hasLength(50));
    expect(songs.first.name, isNotEmpty);
    expect(songs.first.artists, isNotEmpty);
    expect(songs.first.artists.first.name, isNotEmpty);
    expect(songs.first.album?.name, isNotEmpty);
    expect(songs.first.coverUrl, startsWith('http'));
    expect(songs.first.duration.inSeconds, greaterThan(0));
  }, skip: _live ? false : _skipReason);

  test('LIVE getArtistAlbums pages with limit/offset', () async {
    final page1 = await platform.getArtistAlbums(_artistId, limit: 5);
    final page2 = await platform.getArtistAlbums(_artistId, page: 2, limit: 5);

    for (final a in page1) {
      _log(
        '  album id=${a.id} name=${a.name} artist=${a.artistName} '
        'tracks=${a.songCount} company=${a.company} date=${a.releaseDate} '
        'cover=${a.coverUrl}',
      );
    }
    _log(
      '  page2 first id=${page2.firstOrNull?.id} name=${page2.firstOrNull?.name}',
    );
    expect(page1, hasLength(5));
    expect(page1.first.name, isNotEmpty);
    expect(page1.first.artistName, '周杰伦');
    expect(page1.first.songCount, greaterThan(0));
    expect(page1.first.releaseDate, isNotNull);
    expect(page1.first.coverUrl, startsWith('http'));
    // offset 必须真的生效，否则分页会一直返回第一页。
    expect(page2.first.id, isNot(page1.first.id));
  }, skip: _live ? false : _skipReason);

  test('LIVE getAlbumDetail + getAlbumSongs agree and are ordered', () async {
    // 找一张曲目最多的专辑，才能真正验证 no -> trackNumber 的排序。
    final albums = await platform.getArtistAlbums(_artistId, limit: 30);
    final biggest = albums.reduce(
      (a, b) => (a.songCount ?? 0) >= (b.songCount ?? 0) ? a : b,
    );
    final detail = await platform.getAlbumDetail(biggest.id);
    final songs = await platform.getAlbumSongs(biggest.id);

    _log(
      '  albumDetail id=${detail?.id} name=${detail?.name} '
      'tracks=${detail?.songCount} company=${detail?.company} '
      'artist=${detail?.artistName} genre=${detail?.genre} '
      'desc=${detail?.description?.length} chars date=${detail?.releaseDate}',
    );
    _log(
      '  albumSongs -> ${songs.length}, trackNumbers='
      '${songs.map((s) => s.trackNumber).take(10).toList()}… first=${songs.firstOrNull?.name}',
    );
    expect(detail, isNotNull);
    expect(detail!.name, biggest.name);
    expect(detail.songCount, greaterThan(1));
    expect(detail.artistName, '周杰伦');
    expect(songs, hasLength(detail.songCount));
    // 曲目号实测 1..N 连续且与排序一致。
    expect(
      songs.map((s) => s.trackNumber),
      List.generate(songs.length, (i) => i + 1),
    );
    expect(songs.first.name, isNotEmpty);
    expect(songs.first.artists, isNotEmpty);
  }, skip: _live ? false : _skipReason);

  test('LIVE getNewSongs areaId really changes the list', () async {
    final byRegion = <NewSongRegion, List<String>>{};
    for (final region in NewSongRegion.values) {
      if (region == NewSongRegion.hongKongTaiwan) continue;
      final songs = await platform.getNewSongs(limit: 5, region: region);
      byRegion[region] = songs.map((s) => s.id).toList();
      _log(
        '  region=$region -> ${songs.length} songs, first=${songs.firstOrNull?.name} '
        'artists=${songs.firstOrNull?.artistNames} album=${songs.firstOrNull?.album?.name}',
      );
      expect(songs, hasLength(5));
      expect(songs.first.name, isNotEmpty);
      expect(songs.first.artists, isNotEmpty);
      expect(songs.first.duration.inSeconds, greaterThan(0));
    }
    // 五个地区的 id 集合必须两两不同，否则"地区筛选"就是个假承诺。
    final signatures = byRegion.values.map((ids) => ids.join(',')).toSet();
    _log('  distinct region result sets: ${signatures.length}/5');
    expect(signatures, hasLength(byRegion.length));
  }, skip: _live ? false : _skipReason);

  test('LIVE getNewSongs refuses the unsupported 港台 region', () async {
    await expectLater(
      platform.getNewSongs(region: NewSongRegion.hongKongTaiwan),
      throwsA(isA<UnsupportedActionException>()),
    );
  }, skip: _live ? false : _skipReason);

  test('LIVE getRankedSongs ranks by 1-based chart position', () async {
    final page1 = await platform.getRankedSongs(_hotChartId, offset: 0, num: 5);
    final page2 = await platform.getRankedSongs(_hotChartId, offset: 5, num: 5);

    for (final r in page1) {
      _log('  rank=${r.rank} name=${r.song.name} artists=${r.song.artistNames}');
    }
    _log('  page2 -> ${page2.map((r) => '${r.rank}:${r.song.name}').join(', ')}');
    expect(page1.map((r) => r.rank), [1, 2, 3, 4, 5]);
    expect(page2.map((r) => r.rank), [6, 7, 8, 9, 10]);
    expect(page1.first.song.name, isNotEmpty);
    expect(page1.first.song.artists, isNotEmpty);
    // 跨页不重复：offset 真的生效。
    expect(
      page1.map((r) => r.song.id).toSet().intersection(
            page2.map((r) => r.song.id).toSet(),
          ),
      isEmpty,
    );
  }, skip: _live ? false : _skipReason);

  test('LIVE getRankingList still returns 30 chart songs', () async {
    final songs = await platform.getRankingList();

    _log('  rankingList -> ${songs.length}, first=${songs.firstOrNull?.name}');
    expect(songs, hasLength(30));
    expect(songs.first.name, isNotEmpty);
  }, skip: _live ? false : _skipReason);
}
