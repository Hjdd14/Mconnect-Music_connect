import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/core/constants/app_constants.dart';
import 'package:mconnect/core/diagnostics/diagnostics_export.dart';
import 'package:mconnect/core/diagnostics/diagnostics_redactor.dart';
import 'package:mconnect/core/diagnostics/diagnostics_service.dart';

/// Secrets that must never survive an export. Each one is a real shape from the
/// platform integrations: a NetEase cookie, a signed Kugou/QQ query string, a
/// JSON token, a QQ `skey`.
const _neteaseCookie = 'MUSIC_U=8f3a1c9d7e5b2a4fsecretcookievalue';
const _kugouToken = 'kugou-accesstoken-9f8e7d6c5b4a3210';
const _qqSkey = 'qq-skey-abcdef1234567890';
const _jsonToken = 'json-access-token-zyxwvu9876543210';
const _bearerToken = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.bearersecretpayload.signature';

/// Last.fm/Libre.fm scrobbling credentials: the session key parameter is
/// literally `sk`, and the request signature is `api_sig`. Both are written by a
/// scrobbler into its own request logs, so both must not survive an export.
const _lastfmSessionKey = 'lastfm-session-key-0123456789abcdef';
const _lastfmSignature = 'a1b2c3d4e5f60718293a4b5c6d7e8f90';

/// QQ's `g_tk` (`bkn`) token. It is an **int** — `qq_api.dart` derives it from
/// `p_skey` — so it reaches a log as an *unquoted* JSON scalar
/// (`{"comm":{"g_tk":1893349082,…}}`), not as a quoted string.
const _qqGtk = 1893349082;

void main() {
  group('DiagnosticsRedactor', () {
    test('masks a cookie header but keeps the header name', () {
      final result = DiagnosticsRedactor.redact(
        'request Cookie: $_neteaseCookie; __csrf=abcd1234',
      );

      expect(result.text, isNot(contains(_neteaseCookie)));
      expect(result.text, isNot(contains('abcd1234')));
      expect(result.text, contains('Cookie: <redacted>'));
      expect(result.rules, contains(DiagnosticsRedactor.ruleCookieHeader));
    });

    test('drops the whole query string of a URL but keeps scheme/host/path', () {
      final result = DiagnosticsRedactor.redact(
        'GET https://u.y.qq.com/cgi-bin/musicu.fcg?format=json&sign=$_qqSkey&data=%7B%7D',
      );

      expect(result.text, contains('https://u.y.qq.com/cgi-bin/musicu.fcg'));
      expect(result.text, isNot(contains(_qqSkey)));
      expect(result.text, isNot(contains('format=json')));
      expect(result.text, contains('https://u.y.qq.com/cgi-bin/musicu.fcg?<redacted>'));
      expect(result.rules, contains(DiagnosticsRedactor.ruleUrlQuery));
    });

    test('masks credential-like key/value pairs outside a URL too', () {
      final result = DiagnosticsRedactor.redact(
        'login body mobile=13800000000&token=$_kugouToken&clientver=1234',
      );

      expect(result.text, isNot(contains(_kugouToken)));
      expect(result.text, isNot(contains('13800000000')));
      expect(result.text, contains('token=<redacted>'));
      expect(result.text, contains('mobile=<redacted>'));
      // A non-sensitive parameter in the same line survives.
      expect(result.text, contains('clientver=1234'));
      expect(result.rules, contains(DiagnosticsRedactor.ruleSensitiveKey));
    });

    test('masks JSON-style secrets and bearer tokens', () {
      final json = DiagnosticsRedactor.redact(
        '{"access_token":"$_jsonToken","song_id":"42"}',
      );
      expect(json.text, isNot(contains(_jsonToken)));
      expect(json.text, contains('"access_token":"<redacted>"'));
      expect(json.text, contains('"song_id":"42"'));

      // A bare `Bearer <token>` (no credential-looking key in front of it).
      final bearer = DiagnosticsRedactor.redact(
        'retrying with Bearer $_bearerToken',
      );
      expect(bearer.text, isNot(contains(_bearerToken)));
      expect(bearer.text, contains('Bearer <redacted>'));
      expect(bearer.rules, contains(DiagnosticsRedactor.ruleBearer));

      // An `Authorization:` header masks its whole value — the strongest
      // outcome, because the scheme is not always `Bearer`.
      final header = DiagnosticsRedactor.redact(
        'Authorization: Bearer $_bearerToken',
      );
      expect(header.text, isNot(contains(_bearerToken)));
      expect(header.text, contains('Authorization: <redacted>'));
      expect(header.rules, contains(DiagnosticsRedactor.ruleCookieHeader));
    });

    test('is case-insensitive about the key names', () {
      final result = DiagnosticsRedactor.redact(
        'COOKIE: x=y\nTOKEN=$_kugouToken',
      );

      expect(result.text, isNot(contains(_kugouToken)));
      expect(result.text, isNot(contains('x=y')));
      expect(result.rules, contains(DiagnosticsRedactor.ruleCookieHeader));
      expect(result.rules, contains(DiagnosticsRedactor.ruleSensitiveKey));
    });

    test('masks the Last.fm session key and request signature', () {
      // `sk` is Last.fm/Libre.fm's session-key parameter and `api_sig` its
      // request signature. A scrobbler logs its own request parameters, so both
      // have to be redacted before the export leaves the device.
      final query = DiagnosticsRedactor.redact(
        'auth.getSession?method=auth.getSession&sk=$_lastfmSessionKey'
        '&api_sig=$_lastfmSignature',
      );

      expect(query.text, isNot(contains(_lastfmSessionKey)));
      expect(query.text, isNot(contains(_lastfmSignature)));
      expect(query.text, contains('sk=<redacted>'));
      expect(query.text, contains('api_sig=<redacted>'));
      // A non-sensitive parameter in the same query survives.
      expect(query.text, contains('method=auth.getSession'));
      expect(query.rules, contains(DiagnosticsRedactor.ruleSensitiveKey));

      // The suffix rule also has to cover the bare name and a platform that
      // prefixes it.
      final bare = DiagnosticsRedactor.redact(
        'track.scrobble?sig=$_lastfmSignature',
      );
      expect(bare.text, isNot(contains(_lastfmSignature)));
      expect(bare.text, contains('sig=<redacted>'));
    });

    test('masks a JSON-style sk too', () {
      final result = DiagnosticsRedactor.redact(
        '{"sk":"$_lastfmSessionKey","format":"json"}',
      );

      expect(result.text, isNot(contains(_lastfmSessionKey)));
      expect(result.text, contains('"sk":"<redacted>"'));
      expect(result.text, contains('"format":"json"'));
      expect(result.rules, contains(DiagnosticsRedactor.ruleSensitiveKey));
    });

    test('masks the QQ g_tk token in text and in a JSON map', () {
      // `g_tk` is derived from `p_skey` and is logged in three shapes, so it
      // needs the text rule **and** the unquoted-JSON rule: an int value never
      // reaches the quoted-value rule.
      final body = DiagnosticsRedactor.redact(
        'response_type=code&g_tk=$_qqGtk&from_ptlogin=1',
      );
      expect(body.text, isNot(contains('$_qqGtk')));
      expect(body.text, contains('g_tk=<redacted>'));
      // A non-sensitive parameter in the same body survives.
      expect(body.text, contains('from_ptlogin=1'));

      final map = DiagnosticsRedactor.redact(
        'musicu {"comm":{"g_tk":$_qqGtk,"platform":"yqq"}}',
      );
      expect(map.text, isNot(contains('$_qqGtk')));
      expect(map.text, contains('"g_tk":"<redacted>"'));
      expect(map.text, contains('"platform":"yqq"'));
      expect(map.rules, contains(DiagnosticsRedactor.ruleSensitiveKey));

      // The debug line that names the token next to the cookie it comes from.
      final line = DiagnosticsRedactor.redact(
        'QQ OAuth: p_skey=found, g_tk=$_qqGtk',
      );
      expect(line.text, isNot(contains('$_qqGtk')));
      expect(line.text, contains('p_skey=<redacted>'));
      expect(line.text, contains('g_tk=<redacted>'));
    });

    test('masks a credential key at the very start of a line', () {
      // A recorded message can begin with the credential itself: there is no
      // leading `?&;` or space for the pair rule to key off.
      final start = DiagnosticsRedactor.redactText('sk=$_lastfmSessionKey');
      expect(start, isNot(contains(_lastfmSessionKey)));
      expect(start, contains('sk=<redacted>'));

      final secondLine = DiagnosticsRedactor.redactText(
        'line one\ng_tk=$_qqGtk',
      );
      expect(secondLine, isNot(contains('$_qqGtk')));
      expect(secondLine, contains('g_tk=<redacted>'));
    });

    test('does not redact an ordinary key that merely ends with sk', () {
      // The counter-example that makes an *exact* `sk` rule necessary: `sk` is
      // too short and too common a suffix (`task`, `disk`, `mask`, `flask`) to
      // be matched positionally, and masking these values would destroy the very
      // debuggability the log exists for.
      const line = 'scan task=5&disk=1&mask=1&flask=on';
      final result = DiagnosticsRedactor.redact(line);

      expect(result.text, line);
      expect(result.rules, isEmpty);
      expect(result.changed, isFalse);

      // The same, at the very start of a line: `sk` would match here if it were
      // in the suffix list instead of the exact list, and the start-of-line
      // delimiter must not rescue it either.
      const atLineStart = 'task=5\ndisk=1\nmask=1\nflask=on';
      final started = DiagnosticsRedactor.redact(atLineStart);
      expect(started.text, atLineStart);
      expect(started.rules, isEmpty);
      expect(started.changed, isFalse);
    });

    test('leaves ordinary diagnostic lines untouched', () {
      const line =
          '2026-10-07T10:00:00.000 [slow_operation] player.load {"elapsed_ms":1200,"platform":"netease"}';
      final result = DiagnosticsRedactor.redact(line);

      expect(result.text, line);
      expect(result.rules, isEmpty);
      expect(result.changed, isFalse);
    });

    test('keeps a URL without a query intact, and hides any query there is', () {
      const plain = 'GET https://music.163.com/api/song/detail/1';
      final untouched = DiagnosticsRedactor.redact(plain);
      expect(untouched.text, plain);
      expect(untouched.rules, isEmpty);

      // Even a "harmless" query is dropped wholesale: the redactor cannot know
      // which parameter carries the signature, and a leaked one costs more than
      // a lost debug detail.
      final withQuery = DiagnosticsRedactor.redact(
        'GET https://music.163.com/api/song/detail?id=1',
      );
      expect(withQuery.text, 'GET https://music.163.com/api/song/detail?<redacted>');
      expect(withQuery.rules, contains(DiagnosticsRedactor.ruleUrlQuery));
    });

    test('an empty input is a no-op', () {
      final result = DiagnosticsRedactor.redact('');
      expect(result.text, isEmpty);
      expect(result.rules, isEmpty);
    });
  });

  group('DiagnosticsExporter', () {
    late Directory serviceDir;
    late Directory exportDir;
    late DiagnosticsService service;

    setUp(() async {
      serviceDir = await Directory.systemTemp.createTemp('mconnect_diag_src_');
      exportDir = await Directory.systemTemp.createTemp('mconnect_diag_out_');
      service = DiagnosticsService(directoryProvider: () async => serviceDir);
      await service.initialize();
    });

    tearDown(() async {
      // Let the write chain finish before the directory disappears, otherwise
      // the service logs a (harmless) PathAccessException from its own writer.
      await service.flush();
      service.dispose();
      for (final dir in [serviceDir, exportDir]) {
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      }
    });

    DiagnosticsExporter exporter({
      DiagnosticsRedactFn? redact,
      int maxLogBytes = 512 * 1024,
    }) {
      return DiagnosticsExporter(
        service: service,
        directoryProvider: () async => exportDir,
        redact: redact ?? DiagnosticsRedactor.redact,
        maxLogBytes: maxLogBytes,
      );
    }

    test('writes a real, readable file containing the recent events', () async {
      service.record('player', 'load_started song=song-1');
      service.record('network', 'request_finished status=200');
      service.recordError('player', StateError('broken'), StackTrace.fromString('stack line'));

      final result = await exporter().export(
        now: DateTime(2026, 10, 7, 12, 34, 56, 789),
      );

      expect(result.file.existsSync(), isTrue);
      expect(
        result.file.path,
        endsWith('mconnect-diagnostics-20261007-123456-789.txt'),
      );
      expect(result.byteSize, await result.file.length());
      expect(result.byteSize, greaterThan(0));
      // 3 recorded events + the initialize event.
      expect(result.eventCount, 4);

      final content = await result.file.readAsString();
      expect(content, contains('Mconnect 诊断日志'));
      expect(content, contains('应用版本: ${AppConstants.appVersion}'));
      expect(content, contains('平台: ${Platform.operatingSystem}'));
      expect(content, contains('===== 最近事件 ====='));
      expect(content, contains('===== 日志文件 ====='));
      expect(content, contains('load_started song=song-1'));
      expect(content, contains('request_finished status=200'));
      expect(content, contains('Bad state: broken'));
      expect(content, contains('[error] player'));
      // The on-disk log section is really the log file's content.
      expect(content, contains('diagnostics_initialized'));
      expect(result.logBytesIncluded, greaterThan(0));
      expect(result.logTruncated, isFalse);
      expect(result.redactions, isEmpty);
    });

    test('flushes pending writes so the newest event is not lost', () async {
      service.record('player', 'the_very_last_event');

      // No explicit flush here: the exporter is responsible for it.
      final result = await exporter().export();
      final content = await result.file.readAsString();

      expect(content, contains('the_very_last_event'));
    });

    test('maxEvents keeps only the newest events', () async {
      for (var i = 0; i < 20; i++) {
        service.record('event', 'line-$i');
      }

      final result = await exporter().export(maxEvents: 5);
      final content = await result.file.readAsString();
      // Only the event section is capped; the log section legitimately still
      // holds every line the log file has.
      final eventSection = content.split('===== 日志文件 =====').first;

      expect(result.eventCount, 5);
      expect(eventSection, contains('line-19'));
      expect(eventSection, contains('line-15'));
      expect(eventSection, isNot(contains('line-14')));
      expect(eventSection, isNot(contains('line-0')));
    });

    test('redacts secrets from events and from pre-existing log content', () async {
      // A pre-existing log line, as written by an older build that logged the
      // raw signed URL.
      await service.logFile.writeAsString(
        '2026-10-01T00:00:00.000 [network] get https://krcs.kugou.com/search?token=$_kugouToken\n',
        mode: FileMode.append,
      );
      service.record('network', 'request https://music.163.com/api/x?token=$_jsonToken');
      service.record('session', 'Cookie: $_neteaseCookie');
      service.record('qq', 'skey=$_qqSkey');
      service.record('auth', 'retrying with Bearer $_bearerToken');

      final result = await exporter().export();
      final content = await result.file.readAsString();

      for (final secret in [
        _kugouToken,
        _jsonToken,
        _neteaseCookie,
        _qqSkey,
        _bearerToken,
      ]) {
        expect(
          content,
          isNot(contains(secret)),
          reason: '导出文件不得包含 $secret',
        );
      }
      expect(content, contains(DiagnosticsRedactor.placeholder));
      expect(result.redactions, contains(DiagnosticsRedactor.ruleUrlQuery));
      expect(result.redactions, contains(DiagnosticsRedactor.ruleSensitiveKey));
      expect(result.redactions, contains(DiagnosticsRedactor.ruleCookieHeader));
      expect(result.redactions, contains(DiagnosticsRedactor.ruleBearer));
    });

    test('the secret really is present when redaction is disabled', () async {
      // The red→green companion: it proves the assertion above measures the
      // redactor and not some unrelated reason for the string being absent.
      service.record('network', 'request https://music.163.com/api/x?token=$_jsonToken');
      service.record('session', 'Cookie: $_neteaseCookie');

      final result = await exporter(
        redact: (input) => RedactionResult(text: input, rules: const {}),
      ).export();
      final content = await result.file.readAsString();

      expect(content, contains(_jsonToken));
      expect(content, contains(_neteaseCookie));
      expect(result.redactions, isEmpty);
    });

    test('truncates an oversized log file and says so', () async {
      await service.logFile.writeAsString(
        '${'x' * 400}OLDEST-MARKER\n${'y' * 400}NEWEST-MARKER\n',
        mode: FileMode.append,
      );

      final result = await exporter(maxLogBytes: 200).export();
      final content = await result.file.readAsString();

      expect(result.logTruncated, isTrue);
      expect(content, contains('日志文件超过 200 字节'));
      expect(content, contains('NEWEST-MARKER'));
      expect(content, isNot(contains('OLDEST-MARKER')));
      // The invariant that matters: at most `maxLogBytes` of log text is kept.
      expect(result.logBytesIncluded, lessThanOrEqualTo(200));
      expect(content, isNot(contains('y' * 300)));
    });

    test('an uninitialized service fails with a clear message', () async {
      final fresh = DiagnosticsService(
        directoryProvider: () async => serviceDir,
      );
      addTearDown(fresh.dispose);

      expect(fresh.isInitialized, isFalse);
      await expectLater(
        DiagnosticsExporter(
          service: fresh,
          directoryProvider: () async => exportDir,
        ).export(),
        throwsA(
          isA<DiagnosticsExportException>().having(
            (e) => e.message,
            'message',
            contains('尚未初始化'),
          ),
        ),
      );
    });

    test('an unusable output directory fails with a clear message', () async {
      // A *file* where the export wants a directory: `create(recursive: true)`
      // cannot succeed, and the caller must see why.
      final blocker = File('${serviceDir.path}${Platform.pathSeparator}not-a-dir');
      await blocker.writeAsString('x');

      await expectLater(
        DiagnosticsExporter(
          service: service,
          directoryProvider: () async => Directory(blocker.path),
        ).export(),
        throwsA(
          isA<DiagnosticsExportException>().having(
            (e) => e.message,
            'message',
            contains('无法创建导出目录'),
          ),
        ),
      );
    });

    test('a missing log file still exports the ring buffer', () async {
      service.record('player', 'event_before_log_deleted');
      await service.flush();
      // The log file can vanish (cleanup tool, another process) while the ring
      // buffer still holds the interesting events.
      await service.logFile.delete();

      final result = await exporter().export();
      final content = await result.file.readAsString();

      expect(content, contains('event_before_log_deleted'));
      expect(content, contains('(日志文件为空或不存在)'));
      expect(result.logBytesIncluded, 0);
    });

    test('the top-level exportDiagnosticsLog helper uses the injected service', () async {
      service.record('helper', 'via_top_level_function');

      final result = await exportDiagnosticsLog(
        service: service,
        directoryProvider: () async => exportDir,
      );

      expect(result.file.existsSync(), isTrue);
      expect(
        await result.file.readAsString(),
        contains('via_top_level_function'),
      );
    });

    test('the service-level exportToFile extension is wired to the same logic', () async {
      service.record('helper', 'via_service_extension');

      final result = await service.exportToFile(
        directoryProvider: () async => exportDir,
        now: DateTime(2026, 1, 2, 3, 4, 5),
      );

      expect(result.filePath, contains('mconnect-diagnostics-20260102-030405'));
      expect(
        await result.file.readAsString(),
        contains('via_service_extension'),
      );
    });

    test('exports non-ascii messages as valid UTF-8', () async {
      service.record('player', '播放失败：歌曲不存在（网络超时）');

      final result = await exporter().export();
      final bytes = await result.file.readAsBytes();

      expect(utf8.decode(bytes), contains('播放失败：歌曲不存在（网络超时）'));
      expect(result.byteSize, utf8.encode(await result.file.readAsString()).length);
    });
  });
}
