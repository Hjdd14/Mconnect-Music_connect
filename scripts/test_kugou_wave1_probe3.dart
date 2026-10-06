// WS-D probe #3: chart names, homepage module sizes, and the REAL playback CDN
// host returned by the signed v5 route (the cleartext whitelist depends on it).
//
// The v5 signing below is a byte-for-byte copy of `kugou_api.dart`
// `_signedAndroidParams` + `_songUrlKey` so this probe exercises the shipping
// parameter set instead of a guess.
//
// Run: dart run scripts/test_kugou_wave1_probe3.dart
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

const _ua = 'Mozilla/5.0 (Linux; Android 11) AppleWebKit/537.36';

final _client = HttpClient()
  ..connectionTimeout = const Duration(seconds: 12)
  ..userAgent = _ua;

Future<String> _get(String url) async {
  final request = await _client.getUrl(Uri.parse(url));
  final response = await request.close().timeout(const Duration(seconds: 25));
  final body = await response.transform(utf8.decoder).join();
  return body
      .replaceAll('<!--KG_TAG_RES_START-->', '')
      .replaceAll('<!--KG_TAG_RES_END-->', '');
}

String _androidSignature(Map<String, dynamic> params, {required bool lite}) {
  final secret = lite
      ? 'LnT6xpN3khm36zse0QzvmgTZ3waWdRSA'
      : 'OIlwieks28dk2k092lksi2UIkp';
  final keys = params.keys.toList()..sort();
  final body = keys
      .map(
        (key) =>
            '$key=${params[key] is Map || params[key] is List ? jsonEncode(params[key]) : params[key]}',
      )
      .join();
  return md5.convert(utf8.encode('$secret$body$secret')).toString();
}

String _songUrlKey(String hash, {required String userid, required bool lite}) {
  final secret = lite
      ? '185672dd44712f60bb1736df5a377e82'
      : '57ae12eb6890223e355ccfcb74edf70d';
  final appid = lite ? 3116 : 1005;
  return md5.convert(utf8.encode('$hash$secret$appid$mid$userid')).toString();
}

const mid = 'mid';

String _playbackQualityParam(String quality) => switch (quality) {
  '128' => '128',
  '320' => '320',
  'flac' => 'flac',
  _ => '128',
};

Map<String, dynamic> _playbackParams(
  String hash,
  String quality, {
  required bool lite,
  String albumId = '0',
  String albumAudioId = '0',
}) {
  final normalizedHash = hash.toLowerCase();
  final userid = '0';
  final appid = lite ? 3116 : 1005;
  final params = <String, dynamic>{
    'album_id': int.tryParse(albumId) ?? 0,
    'area_code': 1,
    'hash': normalizedHash,
    'ssa_flag': 'is_fromtrack',
    'version': 11430,
    'page_id': lite ? 967177915 : 151369488,
    'quality': _playbackQualityParam(quality),
    'album_audio_id': int.tryParse(albumAudioId) ?? 0,
    'behavior': 'play',
    'pid': lite ? 411 : 2,
    'cmd': 26,
    'pidversion': 3001,
    'IsFreePart': 0,
    'ppage_id': lite
        ? '356753938,823673182,967485191'
        : '463467626,350369493,788954147',
    'cdnBackup': 1,
    'module': '',
    'clientver': 11430,
    'key': _songUrlKey(normalizedHash, userid: userid, lite: lite),
  };
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final all = <String, dynamic>{
    'dfid': '-',
    'mid': mid,
    'uuid': '-',
    'appid': appid,
    'clientver': lite ? 11440 : 20489,
    'clienttime': now,
    ...params,
  };
  all['signature'] = _androidSignature(all, lite: lite);
  return all;
}

String _clip(String v, int n) => v.length > n ? '...' : v;

void _reportUrl(String label, Uri uri) {
  stdout.writeln('    $label -> scheme=${uri.scheme} host=${uri.host} '
      'port=${uri.hasPort ? uri.port : '-'}');
}

Uri? _firstPlayable(Map<String, dynamic> decoded) {
  for (final key in const ['url', 'play_url', 'playurl']) {
    final value = decoded[key];
    if (value is String && value.isNotEmpty && value != 'null') {
      return Uri.tryParse(value);
    }
  }
  for (final key in const ['backup_url', 'backup_urls']) {
    final value = decoded[key];
    if (value is List && value.isNotEmpty) {
      final uri = Uri.tryParse(value.first.toString());
      if (uri != null) return uri;
    }
    if (value is String) {
      final uri = Uri.tryParse(value.split(',').first);
      if (uri != null) return uri;
    }
  }
  return null;
}

Future<void> probePlayback(
  String label,
  String hash, {
  required bool lite,
  String quality = '128',
  String albumId = '0',
  String albumAudioId = '0',
}) async {
  final params = _playbackParams(
    hash,
    quality,
    lite: lite,
    albumId: albumId,
    albumAudioId: albumAudioId,
  );
  final uri = Uri.https('gateway.kugou.com', '/v5/url', {
    for (final entry in params.entries) entry.key: '${entry.value}',
  });
  stdout.writeln('--- $label');
  try {
    final request = await _client.getUrl(uri);
    request.headers.set('x-router', 'trackercdn.kugou.com');
    final response = await request.close().timeout(const Duration(seconds: 25));
    final body = await response.transform(utf8.decoder).join();
    stdout.writeln('    HTTP ${response.statusCode} len=${body.length}');
    final decoded = jsonDecode(body);
    if (decoded is Map) {
      stdout.writeln('    status=${decoded['status']} errcode=${decoded['errcode']} '
          'error=${decoded['error']}');
      final playable = _firstPlayable(decoded.cast<String, dynamic>());
      if (playable != null) {
        _reportUrl('playable', playable);
        stdout.writeln('    raw=${playable.toString()}');
      } else {
        stdout.writeln('    no playable url; body=${body.substring(0, body.length.clamp(0, 400))}');
      }
    }
  } catch (e) {
    stdout.writeln('    ERROR ${e.runtimeType}: $e');
  }
  stdout.writeln('');
}

Future<void> main() async {
  stdout.writeln('\n============ 榜单名称（全部） ============\n');
  final rankBody = await _get(
    'http://mobilecdn.kugou.com/api/v3/rank/list'
        '?format=json&withsong=0&plat=0&page=1&pagesize=40',
  );
  final rankJson = jsonDecode(rankBody) as Map<String, dynamic>;
  final info = (rankJson['data'] as Map)['info'] as List;
  stdout.writeln('total=${(rankJson['data'] as Map)['total']} count=${info.length}');
  for (final item in info) {
    final map = item as Map;
    final extra = map['extra'];
    Object? allTotal;
    if (extra is Map) {
      final resp = extra['resp'];
      if (resp is Map) allTotal = resp['all_total'];
    }
    stdout.writeln(
      '    rankid=${map['rankid']} name=${map['rankname']} '
      'update=${map['update_frequency']} all_total=$allTotal '
      'img=${map['imgurl']}',
    );
  }

  stdout.writeln('\n============ 首页模块规模 ============\n');
  final home = jsonDecode(await _get('http://m.kugou.com/?json=true'))
      as Map<String, dynamic>;
  int countOf(Object? value) => value is List
      ? value.length
      : value is Map
      ? value.length
      : -1;
  stdout.writeln('data(recommend) count=${countOf(home['data'])}');
  stdout.writeln('special count=${countOf(home['special'])} type=${home['special'].runtimeType}');
  stdout.writeln('rank count=${countOf(home['rank'])} type=${home['rank'].runtimeType}');
  stdout.writeln('singers count=${countOf(home['singers'])}');
  final special = home['special'];
  if (special is List && special.isNotEmpty) {
    stdout.writeln('special[0] fields=${(special.first as Map).keys.join(',')}');
    stdout.writeln('special[0]=${jsonEncode(special.first)}');
  } else if (special is Map && special.isNotEmpty) {
    final firstKey = special.keys.first;
    final first = special[firstKey];
    stdout.writeln('special keys=${special.keys.take(8).join(',')}');
    stdout.writeln('special[$firstKey]=${_clip(jsonEncode(first), 600)}');
  }
  final rank = home['rank'];
  if (rank is List && rank.isNotEmpty) {
    stdout.writeln('rank[0] fields=${(rank.first as Map).keys.join(',')}');
    stdout.writeln('rank[0]=${jsonEncode(rank.first)}');
  } else if (rank is Map && rank.isNotEmpty) {
    final firstKey = rank.keys.first;
    stdout.writeln('rank keys=${rank.keys.take(8).join(',')}');
    stdout.writeln('rank[$firstKey]=${_clip(jsonEncode(rank[firstKey]), 600)}');
  }
  stdout.writeln('data[0] keys=${((home['data'] as List).first as Map).keys.join(',')}');

  stdout.writeln('\n============ 播放 CDN 真实 host ============\n');
  const hash = 'E2948B4513F34F7A4C7767EAD15BC4F8'; // TOP500 第 1 首
  await probePlayback('v5 android 128', hash, lite: false);
  await probePlayback('v5 android 320', hash, lite: false, quality: '320');
  await probePlayback('v5 lite 128', hash, lite: true);
  await probePlayback(
    'v5 android 128 + album ids',
    hash,
    lite: false,
    albumId: '4012536',
    albumAudioId: '88079533',
  );

  stdout.writeln('\n============ getSongInfo 返回的 host ============\n');
  for (final h in [
    'E2948B4513F34F7A4C7767EAD15BC4F8',
    '097E777171F692855EAE98B6965F9477',
    'AB9F4F0054263A3521E83D50CB9DF818',
  ]) {
    final body = await _get(
      'http://m.kugou.com/app/i/getSongInfo.php?cmd=playInfo&hash=$h',
    );
    final decoded = jsonDecode(body);
    if (decoded is Map) {
      final url = decoded['url']?.toString();
      stdout.writeln('    $h status=${decoded['status']} url=$url');
      if (url != null && url.isNotEmpty) {
        final uri = Uri.tryParse(url);
        if (uri != null) _reportUrl('    playable', uri);
      }
      final backup = decoded['backup_url'];
      if (backup is List) {
        for (final item in backup) {
          final uri = Uri.tryParse(item.toString());
          if (uri != null) _reportUrl('    backup', uri);
        }
      }
    }
  }
  _client.close(force: true);
}
