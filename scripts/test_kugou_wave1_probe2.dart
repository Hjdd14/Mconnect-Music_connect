// WS-D probe #2: field-level detail for the endpoints that responded, plus
// candidate paths for 歌手专辑 / 新歌, plus the real playback URL host.
//
// Run: dart run scripts/test_kugou_wave1_probe2.dart
import 'dart:convert';
import 'dart:io';

const _ua = 'Mozilla/5.0 (Linux; Android 11) AppleWebKit/537.36';

final _client = HttpClient()
  ..connectionTimeout = const Duration(seconds: 12)
  ..userAgent = _ua;

Future<void> probe(
  String label,
  String url, {
  String? itemPath,
  String? showPath,
  int trim = 700,
}) async {
  final stopwatch = Stopwatch()..start();
  try {
    final request = await _client.getUrl(Uri.parse(url));
    final response = await request.close().timeout(const Duration(seconds: 25));
    final body = await response.transform(utf8.decoder).join();
    stopwatch.stop();
    stdout.writeln('--- $label  [HTTP ${response.statusCode} len=${body.length} '
        '${stopwatch.elapsedMilliseconds}ms]');
    final cleaned = body
        .replaceAll('<!--KG_TAG_RES_START-->', '')
        .replaceAll('<!--KG_TAG_RES_END-->', '');
    dynamic decoded;
    try {
      decoded = jsonDecode(cleaned);
    } catch (_) {
      stdout.writeln('    NON-JSON: ${body.substring(0, body.length.clamp(0, 120))}');
      stdout.writeln('');
      return;
    }
    if (decoded is Map) {
      stdout.writeln('    status=${decoded['status']} errcode=${decoded['errcode']}');
    }
    if (showPath != null) {
      final value = _dig(decoded, showPath);
      final text = value is String ? value : jsonEncode(value);
      stdout.writeln(
        '    $showPath = ${text.length > trim ? '${text.substring(0, trim)}...(trimmed)' : text}',
      );
    }
    if (itemPath != null) {
      final item = _dig(decoded, itemPath);
      if (item is Map) {
        stdout.writeln('    fields: ${item.keys.join(',')}');
        stdout.writeln('    item = ${jsonEncode(item)}');
      } else {
        stdout.writeln('    no item at $itemPath (${item.runtimeType})');
      }
    }
  } catch (e) {
    stdout.writeln('--- $label  [ERROR ${e.runtimeType}: $e]');
  }
  stdout.writeln('');
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

void _section(String title) => stdout.writeln('\n============ $title ============\n');

Future<void> main() async {
  const artistId = 3060; // 薛之谦
  const albumId = 14456909; // 绅士

  _section('A. album/info 字段');
  await probe(
    'album/info',
    'http://mobilecdn.kugou.com/api/v3/album/info?albumid=$albumId&format=json',
    showPath: 'data',
  );

  _section('B. singer/info 去 res_tag + 字段');
  await probe(
    'singer/info 无 with_res_tag',
    'http://mobilecdnbj.kugou.com/api/v3/singer/info?singerid=$artistId',
    showPath: 'data',
  );
  await probe(
    'singer/info with_res_tag',
    'http://mobilecdnbj.kugou.com/api/v3/singer/info'
        '?singerid=$artistId&with_res_tag=1',
    showPath: 'data',
  );

  _section('C. 歌手专辑 候选路径');
  for (final url in [
    'http://mobilecdn.kugou.com/api/v3/singer/album?singerid=$artistId&page=1&pagesize=5&plat=0',
    'http://mobilecdnbj.kugou.com/api/v3/singer/album?singerid=$artistId&page=1&pagesize=5&plat=0',
    'http://mobilecdn.kugou.com/api/v5/singer/albumlist?singerid=$artistId&page=1&pagesize=5&plat=0',
    'http://mobilecdnbj.kugou.com/api/v5/singer/albumlist?singerid=$artistId&page=1&pagesize=5&plat=0',
    'http://m.kugou.com/singer/albumlist?singerid=$artistId&json=true',
    'http://m.kugou.com/singer/info/$artistId?json=true',
    'http://m.kugou.com/plist/list/$artistId?json=true',
    'http://mobilecdn.kugou.com/api/v3/search/album?keyword=%E8%96%9B%E4%B9%8B%E8%B0%A6&page=1&pagesize=5&format=json',
  ]) {
    await probe('candidate', url, itemPath: 'data.info.0');
  }

  _section('D. 新歌 候选路径');
  for (final url in [
    'http://mobilecdn.kugou.com/api/v3/newcd/list?page=1&pagesize=5&plat=0&type=1',
    'http://mobilecdnbj.kugou.com/api/v3/newcd/list?page=1&pagesize=5&plat=0&type=1',
    'http://mobilecdn.kugou.com/api/v3/album/list?page=1&pagesize=5&plat=0',
    'http://mobilecdnbj.kugou.com/api/v3/album/list?page=1&pagesize=5&plat=0',
    'http://m.kugou.com/newcd/index&json=true',
    'http://m.kugou.com/plist/index&json=true',
    'http://mobilecdn.kugou.com/api/v3/rank/song?rankid=6666&page=1&pagesize=5&plat=0&version=11309',
    'http://mobilecdn.kugou.com/api/v3/rank/song?rankid=52144&page=1&pagesize=5&plat=0&version=11309',
  ]) {
    await probe('candidate', url, itemPath: 'data.info.0');
  }

  _section('E. 播放地址真实 host');
  const hash = 'E2948B4513F34F7A4C7767EAD15BC4F8';
  await probe(
    'getSongInfo playInfo(rank hash)',
    'http://m.kugou.com/app/i/getSongInfo.php?cmd=playInfo&hash=$hash',
    showPath: 'url',
  );
  await probe(
    'getSongInfo playInfo 显示全部',
    'http://m.kugou.com/app/i/getSongInfo.php?cmd=playInfo&hash=$hash',
    trim: 2000,
  );
  await probe(
    'trackercdn v2 (android key)',
    'http://trackercdn.kugou.com/i/v2/'
        '?key=30919e29e6b4b3c4d0b0f0e0f0e0f0e0&hash=$hash'
        '&appid=1005&pid=2&cmd=25&behavior=play',
    showPath: 'url',
  );

  _section('F. 首页模块规模');
  await probe(
    '首页 data 数量',
    'http://m.kugou.com/?json=true',
    showPath: 'data.10.filename',
  );
  _client.close(force: true);
}
