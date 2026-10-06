// WS-D probe: verify which Kugou endpoints/fields are actually alive.
//
// Run: dart run scripts/test_kugou_wave1_probe.dart
//
// Prints, for every candidate endpoint: HTTP status, payload length, the
// response `status` field and — for payloads with an item list — the field
// names of the first item. Also resolves the real playback URL host so the
// Android cleartext whitelist can be built from evidence instead of guesses.
import 'dart:convert';
import 'dart:io';

const _ua = 'Mozilla/5.0 (Linux; Android 11) AppleWebKit/537.36';

final _client = HttpClient()
  ..connectionTimeout = const Duration(seconds: 12)
  ..userAgent = _ua;

Future<void> probe(String label, String url, {String? itemPath}) async {
  final stopwatch = Stopwatch()..start();
  try {
    final request = await _client.getUrl(Uri.parse(url));
    final response = await request.close().timeout(const Duration(seconds: 20));
    final body = await response.transform(utf8.decoder).join();
    stopwatch.stop();
    stdout.writeln(
      '--- $label\n    $url\n    HTTP ${response.statusCode} '
      'len=${body.length} ${stopwatch.elapsedMilliseconds}ms',
    );
    dynamic decoded;
    try {
      decoded = jsonDecode(body);
    } catch (_) {
      stdout.writeln('    NON-JSON body: ${body.substring(0, body.length.clamp(0, 160))}');
      return;
    }
    if (decoded is! Map) {
      stdout.writeln('    JSON but not a Map: ${decoded.runtimeType}');
      return;
    }
    stdout.writeln(
      '    top-level keys: ${decoded.keys.take(14).join(',')}',
    );
    if (decoded.containsKey('status') || decoded.containsKey('error_code')) {
      stdout.writeln(
        '    status=${decoded['status']} error_code=${decoded['error_code']} '
        'errmsg=${decoded['error_msg'] ?? decoded['msg']}',
      );
    }
    if (itemPath != null) {
      final first = _dig(decoded, itemPath);
      if (first is Map) {
        stdout.writeln('    item fields: ${first.keys.join(',')}');
        stdout.writeln('    item[0] = ${jsonEncode(first)}');
      } else {
        stdout.writeln('    no item at $itemPath (got ${first.runtimeType})');
      }
    }
  } catch (e) {
    stopwatch.stop();
    stdout.writeln('--- $label\n    $url\n    ERROR ${e.runtimeType}: $e');
  } finally {
    stdout.writeln('');
  }
}

dynamic _dig(dynamic source, String path) {
  var current = source;
  for (final segment in path.split('.')) {
    if (current is Map) {
      current = current[segment];
    } else if (current is List) {
      final index = int.tryParse(segment);
      if (index == null || index >= current.length) return null;
      current = current[index];
    } else {
      return null;
    }
  }
  return current;
}

void _section(String title) {
  stdout.writeln('\n================ $title ================\n');
}

Future<void> main() async {
  _section('1. 榜单列表 rank/list');
  await probe(
    'rank/list',
    'http://mobilecdn.kugou.com/api/v3/rank/list'
        '?format=json&withsong=0&plat=0&page=1&pagesize=5',
    itemPath: 'data.info.0',
  );

  _section('2. 榜单歌曲 rank/song');
  await probe(
    'rank/song rankid=8888',
    'http://mobilecdn.kugou.com/api/v3/rank/song'
        '?rankid=8888&page=1&pagesize=5&plat=0&version=11309',
    itemPath: 'data.info.0',
  );

  _section('3. 歌手 singer/info + singer/song');
  await probe(
    'singer/info singerid=3060',
    'http://mobilecdnbj.kugou.com/api/v3/singer/info'
        '?singerid=3060&with_res_tag=1',
  );
  await probe(
    'singer/song sorttype=2 singerid=3060',
    'http://mobilecdnbj.kugou.com/api/v3/singer/song'
        '?sorttype=2&version=9108&identity=3&plat=0&pagesize=5'
        '&singerid=3060&area_code=1&page=1',
    itemPath: 'data.info.0',
  );

  _section('4. 歌手专辑 singer/albumlist (candidate paths)');
  await probe(
    'singer/albumlist (mobilecdnbj)',
    'http://mobilecdnbj.kugou.com/api/v3/singer/albumlist'
        '?singerid=3060&page=1&pagesize=5&plat=0&version=9108',
    itemPath: 'data.info.0',
  );
  await probe(
    'singer/albumlist (mobilecdn)',
    'http://mobilecdn.kugou.com/api/v3/singer/albumlist'
        '?singerid=3060&page=1&pagesize=5&plat=0&version=9108',
    itemPath: 'data.info.0',
  );

  _section('5. 专辑 album/info + album/song');
  await probe(
    'album/info albumid=1020619',
    'http://mobilecdn.kugou.com/api/v3/album/info'
        '?albumid=1020619&format=json',
  );
  await probe(
    'album/song albumid=1020619',
    'http://mobilecdn.kugou.com/api/v3/album/song'
        '?albumid=1020619&page=1&pagesize=5&plat=0&version=11309',
    itemPath: 'data.info.0',
  );

  _section('6. 新歌 newcd/list (candidate paths)');
  await probe(
    'newcd/list',
    'http://mobilecdn.kugou.com/api/v3/newcd/list'
        '?page=1&pagesize=5&plat=0&type=1&version=11309',
    itemPath: 'data.info.0',
  );
  await probe(
    'album/newsongs',
    'http://mobilecdn.kugou.com/api/v3/album/newsongs'
        '?page=1&pagesize=5&plat=0&version=11309',
    itemPath: 'data.info.0',
  );

  _section('7. 首页推荐 m.kugou.com/?json=true');
  await probe(
    'homepage json',
    'http://m.kugou.com/?json=true',
    itemPath: 'data.0',
  );

  _section('8. 官方推荐接口复核（预期已下线）');
  await probe(
    'recommend/song (plain)',
    'http://mobilecdn.kugou.com/api/v3/recommend/song?format=json',
  );
  await probe(
    'recommend/song (bj)',
    'http://mobilecdnbj.kugou.com/api/v3/recommend/song?format=json',
  );
  await probe(
    'everyday/recommend',
    'http://mobilecdn.kugou.com/api/v3/everyday/recommend?format=json',
  );

  _section('9. 播放地址真实 host（cleartext 白名单依据）');
  await probe(
    'getSongInfo playInfo',
    'http://m.kugou.com/app/i/getSongInfo.php'
        '?cmd=playInfo&hash=2c5e5f4c0c9d0c4c8c6f2f1b0a1e0f11',
  );
  _client.close(force: true);
}
