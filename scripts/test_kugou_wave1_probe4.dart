// WS-D probe #4: live-check the *shipping* endpoint constants.
//
// This one imports `lib/platform/kugou/kugou_endpoints.dart` (pure Dart, no
// Flutter imports) so it validates the URLs the app actually uses — including
// the schemes changed to HTTPS — instead of a copy.
//
// Run: dart run scripts/test_kugou_wave1_probe4.dart
import 'dart:convert';
import 'dart:io';

import 'package:mconnect/platform/kugou/kugou_endpoints.dart';

const _ua = 'Mozilla/5.0 (Linux; Android 11) AppleWebKit/537.36';

final _client = HttpClient()
  ..connectionTimeout = const Duration(seconds: 12)
  ..userAgent = _ua;

Future<void> check(
  String label,
  String url, {
  int? firstItemIn,
  String? itemPath,
}) async {
  final stopwatch = Stopwatch()..start();
  try {
    final request = await _client.getUrl(Uri.parse(url));
    final response = await request.close().timeout(const Duration(seconds: 25));
    final body = await response.transform(utf8.decoder).join();
    stopwatch.stop();
    final cleaned = body
        .replaceAll('<!--KG_TAG_RES_START-->', '')
        .replaceAll('<!--KG_TAG_RES_END-->', '')
        .trim();
    dynamic decoded;
    try {
      decoded = jsonDecode(cleaned);
    } catch (_) {
      decoded = null;
    }
    final status = decoded is Map ? decoded['status'] : null;
    final verdict = decoded == null
        ? 'NON-JSON: ${cleaned.substring(0, cleaned.length.clamp(0, 40))}'
        : 'json status=$status';
    stdout.writeln(
      '${response.statusCode == 200 && decoded != null ? "[OK]  " : "[CHK] "}'
      '$label ${Uri.parse(url).scheme.toUpperCase()} '
      'http=${response.statusCode} len=${body.length} '
      '${stopwatch.elapsedMilliseconds}ms $verdict',
    );
    if (decoded is Map && itemPath != null) {
      dynamic current = decoded;
      for (final segment in itemPath.split('.')) {
        if (current is Map) {
          current = current[segment];
        } else if (current is List) {
          current = current[int.parse(segment)];
        } else {
          current = null;
          break;
        }
      }
      if (current is Map) {
        stdout.writeln('       item fields: ${current.keys.join(',')}');
      } else {
        stdout.writeln('       no item at $itemPath');
      }
    }
    if (firstItemIn != null) {
      stdout.writeln('       (see probe #1/#2 for full sample)');
    }
  } catch (e) {
    stopwatch.stop();
    stdout.writeln('${'[BAD] '}$label ${Uri.parse(url).scheme.toUpperCase()} '
        'ERROR ${e.runtimeType}: $e');
  }
}

Future<void> main() async {
  stdout.writeln('== 本次改动涉及 / 新增的酷狗端点（实跑 2026-10-06） ==\n');

  stdout.writeln('-- 内容接口（本次新增） --');
  await check(
    'rank/list → getToplists',
    '${KugouEndpoints.rankList}?format=json&withsong=0&plat=0&page=1&pagesize=2',
    itemPath: 'data.info.0',
  );
  await check(
    'rank/song → getRankedSongs',
    '${KugouEndpoints.rankSong}?rankid=8888&page=1&pagesize=2&plat=0&version=11309',
    itemPath: 'data.info.0',
  );
  await check(
    'singer/info → getArtistDetail',
    '${KugouEndpoints.singerInfo}?singerid=3060',
  );
  await check(
    'singer/song → getArtistTopSongs',
    '${KugouEndpoints.singerSongs}'
        '?sorttype=2&version=9108&identity=3&plat=0&pagesize=2'
        '&singerid=3060&area_code=1&page=1',
    itemPath: 'data.info.0',
  );
  await check(
    'singer/album → getArtistAlbums',
    '${KugouEndpoints.singerAlbums}?singerid=3060&page=1&pagesize=2&plat=0',
    itemPath: 'data.info.0',
  );
  await check(
    'album/info → getAlbumDetail',
    '${KugouEndpoints.albumInfo}?albumid=14456909&format=json',
  );
  await check(
    'album/song → getAlbumSongs',
    '${KugouEndpoints.albumSongs}'
        '?albumid=14456909&page=1&pagesize=2&plat=0&version=11309',
    itemPath: 'data.info.0',
  );

  stdout.writeln('\n-- 推荐换源 --');
  await check(
    'homepage → 酷狗推荐来源',
    KugouEndpoints.homepage,
    itemPath: 'data.0',
  );
  await check(
    'recommend（预期仍被服务端拒绝）',
    '${KugouEndpoints.recommend}?format=json',
  );

  stdout.writeln('\n-- 本次改为 HTTPS 的端点 --');
  await check(
    'songInfo（播放地址，MITM 落盘面）',
    '${KugouEndpoints.songInfo}'
        '?cmd=playInfo&hash=E2948B4513F34F7A4C7767EAD15BC4F8',
  );
  await check(
    'lyrics.kugou.com/search',
    '${KugouEndpoints.lyricsSearch}'
        '?ver=1&man=yes&client=pc&keyword=%E6%BC%94%E5%91%98&duration=261&hash=',
  );
  await check(
    'krcs.kugou.com/search',
    '${KugouEndpoints.lyricsSearchByHash}'
        '?ver=1&man=yes&client=mobi&keyword=&duration='
        '&hash=E2948B4513F34F7A4C7767EAD15BC4F8&album_audio_id=',
  );

  stdout.writeln('\n-- 仍为 HTTP（必须留在 cleartext 白名单） --');
  await check(
    'send_mobile_code（HTTPS 不可用）',
    KugouEndpoints.sendMobileCode,
  );
  await check(
    'search/song（仍为 http）',
    '${KugouEndpoints.searchBase}?format=json&keyword=test&page=1&pagesize=1',
    itemPath: 'data.info.0',
  );
  await check(
    'singer/info 走 http 主机（对照）',
    '${KugouEndpoints.singerInfo.replaceFirst('http://', 'http://')}?singerid=3060',
  );

  stdout.writeln(
    '\n-- 播放地址真实 host（cleartext 白名单依据，见 probe #3） --',
  );
  final body = await () async {
    final request = await _client.getUrl(
      Uri.parse(
        '${KugouEndpoints.songInfo}'
        '?cmd=playInfo&hash=E2948B4513F34F7A4C7767EAD15BC4F8',
      ),
    );
    final response = await request.close();
    return response.transform(utf8.decoder).join();
  }();
  final playUrl = (jsonDecode(body) as Map)['url']?.toString();
  if (playUrl != null) {
    final uri = Uri.parse(playUrl);
    stdout.writeln('playable: scheme=${uri.scheme} host=${uri.host}');
  }
  _client.close(force: true);
}
