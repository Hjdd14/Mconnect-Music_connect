// v1.4.1-4 probe: does the cleartext Kugou hosts serve TLS on 443?
//
// `curl` cannot establish TLS to these hosts from this machine (it fails the
// handshake outright), but Dart's own stack can — so the probe is written in
// Dart on purpose. Result is copied into `docs/kugou-cleartext-probe.md`.
//
// Run: dart run scripts/test_kugou_tls_probe.dart
import 'dart:convert';
import 'dart:io';

const _ua = 'Mozilla/5.0 (Linux; Android 11) AppleWebKit/537.36';

Future<void> probe(
  String label,
  String httpsUrl, {
  String? httpUrl,
}) async {
  stdout.writeln('--- $label');
  stdout.writeln('    HTTPS $httpsUrl');
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 12)
    ..userAgent = _ua;
  final stopwatch = Stopwatch()..start();
  try {
    final request = await client.getUrl(Uri.parse(httpsUrl));
    final response = await request.close().timeout(const Duration(seconds: 20));
    final body = await response.transform(utf8.decoder).join();
    stopwatch.stop();
    var shape = '';
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        shape = 'json keys=${decoded.keys.take(6).join(',')}';
        if (decoded.containsKey('status')) {
          shape += ' status=${decoded['status']}';
        }
      }
    } catch (_) {
      shape = 'non-json: ${body.substring(0, body.length.clamp(0, 60))}';
    }
    stdout.writeln(
      '    => HTTPS OK  http=${response.statusCode} len=${body.length} '
      '${stopwatch.elapsedMilliseconds}ms $shape',
    );
  } catch (e) {
    stopwatch.stop();
    stdout.writeln('    => HTTPS FAIL ${e.runtimeType}: $e');
  } finally {
    client.close(force: true);
  }
  if (httpUrl != null) {
    final httpClient = HttpClient()
      ..connectionTimeout = const Duration(seconds: 12)
      ..userAgent = _ua;
    try {
      final request = await httpClient.getUrl(Uri.parse(httpUrl));
      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      final body = await response.transform(utf8.decoder).join();
      stdout.writeln(
        '    => HTTP  OK  http=${response.statusCode} len=${body.length} '
        '(对照)',
      );
    } catch (e) {
      stdout.writeln('    => HTTP  FAIL ${e.runtimeType}: $e');
    } finally {
      httpClient.close(force: true);
    }
  }
  stdout.writeln('');
}

Future<void> main() async {
  stdout.writeln('== 酷狗明文主机 443 可用性（Dart 栈，证书校验开启） ==\n');

  await probe(
    'tracker.kugou.com（私密取流地址 priv_url）',
    'https://tracker.kugou.com/v6/priv_url',
    httpUrl: 'http://tracker.kugou.com/v6/priv_url',
  );
  await probe(
    'mobilecdn.kugou.com/api/v2/user/vip（token 在 query）',
    'https://mobilecdn.kugou.com/api/v2/user/vip?format=json',
    httpUrl: 'http://mobilecdn.kugou.com/api/v2/user/vip?format=json',
  );
  await probe(
    'mobilecdn.kugou.com/api/v5/song/collect（token 在 query）',
    'https://mobilecdn.kugou.com/api/v5/song/collect?hash=E2948B4513F34F7A4C7767EAD15BC4F8',
    httpUrl:
        'http://mobilecdn.kugou.com/api/v5/song/collect?hash=E2948B4513F34F7A4C7767EAD15BC4F8',
  );
  await probe(
    'mobilecdn.kugou.com/api/v3/rank/list（对照：已确认走 http 的读接口）',
    'https://mobilecdn.kugou.com/api/v3/rank/list'
        '?format=json&withsong=0&plat=0&page=1&pagesize=1',
    httpUrl:
        'http://mobilecdn.kugou.com/api/v3/rank/list'
        '?format=json&withsong=0&plat=0&page=1&pagesize=1',
  );
  await probe(
    'mobilecdnbj.kugou.com/api/v3/singer/info（对照）',
    'https://mobilecdnbj.kugou.com/api/v3/singer/info?singerid=3060',
    httpUrl: 'http://mobilecdnbj.kugou.com/api/v3/singer/info?singerid=3060',
  );
  await probe(
    'login.user.kugou.com/v7/send_mobile_code（手机号，UI 即将不可达）',
    'https://login.user.kugou.com/v7/send_mobile_code',
    httpUrl: 'http://login.user.kugou.com/v7/send_mobile_code',
  );
  await probe(
    'm.kugou.com/app/i/getSongInfo.php（已改 HTTPS，回归对照）',
    'https://m.kugou.com/app/i/getSongInfo.php'
        '?cmd=playInfo&hash=E2948B4513F34F7A4C7767EAD15BC4F8',
  );
}
