import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Machine guard for the version sync points listed in `AGENTS.md` §2.
///
/// The repository's history is the reason this file exists: v1.3.2 shipped with
/// the app, the installer, the exe resources and the docs all reporting
/// different versions, because the seven places were kept in sync **by hand**.
/// `PROJECT.md` and `CHANGELOG.md` are the two of those seven that are not
/// tracked by git, which is exactly why nothing caught the drift before: a
/// reviewer cannot see an untracked file in a diff.
///
/// So this test checks **every** point, including the two untracked ones — it
/// reads them from disk when they are present and says so explicitly when they
/// are not, rather than silently passing.
///
/// When a release bumps the version, this test is what tells you which of the
/// seven you forgot. Do not "fix" a failure here by loosening the pattern; the
/// whole point is that the number must be identical everywhere.
void main() {
  final pubspec = File('pubspec.yaml').readAsStringSync();
  final versionMatch = RegExp(
    r'^version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)\s*$',
    multiLine: true,
  ).firstMatch(pubspec);

  // `pubspec.yaml` is the single source of truth; everything else must match it.
  final name = versionMatch == null
      ? null
      : '${versionMatch[1]}.${versionMatch[2]}.${versionMatch[3]}';
  final build = versionMatch?[4];

  test('pubspec.yaml carries a parseable <name>+<build> version', () {
    expect(
      versionMatch,
      isNotNull,
      reason: 'pubspec.yaml must declare `version: X.Y.Z+N`',
    );
  });

  test('the app constant matches pubspec', () {
    final source = File(
      'lib/core/constants/app_constants.dart',
    ).readAsStringSync();
    final match = RegExp(r"appVersion\s*=\s*'v([\d.]+)'").firstMatch(source);
    expect(match, isNotNull, reason: 'app_constants.dart must define appVersion');
    expect(
      match![1],
      name,
      reason:
          '设置页显示的就是 AppConstants.appVersion；它与 pubspec.yaml 必须一致',
    );
  });

  test('the settings page test pins the same literal', () {
    // Deliberately a literal (not derived): changing the version has to touch
    // this file too, which is what AGENTS.md §2 asks for.
    final source = File('test/settings_page_test.dart').readAsStringSync();
    expect(
      source,
      contains("find.text('v$name')"),
      reason: 'settings_page_test.dart 的版本断言必须同步（AGENTS.md §2）',
    );
  });

  test('the Inno Setup script matches pubspec', () {
    final source = File('installer/mconnect.iss').readAsStringSync();
    expect(
      source,
      contains('#define MyAppVersion "$name"'),
      reason: '安装器文件名 Mconnect-Setup-$name.exe 由它决定',
    );
  });

  test('the Windows runner resources match pubspec', () {
    final source = File('windows/runner/Runner.rc').readAsStringSync();
    // The mapped defines (FLUTTER_VERSION_*) are the template's own indirection;
    // the literal fallbacks below them are what the exe actually reports.
    expect(
      source,
      contains(
        '#define VERSION_AS_NUMBER ${versionMatch![1]},${versionMatch[2]},'
        '${versionMatch[3]},$build',
      ),
      reason: 'exe 属性里的 FileVersion 必须与 build number 一致',
    );
    expect(
      source,
      contains('#define VERSION_AS_STRING "$name"'),
      reason: 'exe 属性里的 ProductVersion 必须与版本名一致',
    );
  });

  test('the untracked docs are checked when present, and the gap is named', () {
    final project = File('PROJECT.md');
    final changelog = File('CHANGELOG.md');
    final checked = <String>[];

    if (project.existsSync()) {
      checked.add('PROJECT.md');
      expect(
        project.readAsStringSync(),
        contains('$name+$build'),
        reason: 'PROJECT.md「项目概览」的版本必须与 pubspec 一致',
      );
    }
    if (changelog.existsSync()) {
      checked.add('CHANGELOG.md');
      expect(
        changelog.readAsStringSync(),
        contains('v$name'),
        reason: 'CHANGELOG.md 必须有一条 v$name 的版本段落',
      );
    }

    // Both files exist in this working copy today. If one is ever deleted the
    // test still passes, but it prints the gap so the missing check is visible
    // instead of silently skipped (they are not tracked by git, so no diff would
    // ever show the loss).
    // ignore: avoid_print
    print(
      'version sync: checked ${checked.length + 5} of 7 points; '
      'untracked docs verified: ${checked.isEmpty ? 'none (absent)' : checked.join(', ')}',
    );
  });

  // ---------------------------------------------------------------------------
  // W3-C ④：文档与产物的漂移护栏
  //
  // 上面 7 条查的是"版本号"，这一组查的是**文档里的事实**。加它们的原因是真实的：
  // `PROJECT.md` 漂到过"出包命令写 universal（违反 AGENTS.md §1）、表 5 张、DAO 4 个、
  // 路由 9 条、Flutter 版本自相矛盾、列了一个根本不存在的依赖 `open_filex`、
  // 把已集成的 `audio_service` 标成'未集成'"，而**没有任何机器检查能发现**。
  // 这几条把"文档与代码/配置不一致"变成红灯，而不是靠人记得去核对。
  // ---------------------------------------------------------------------------
  group('文档与产物漂移护栏（W3-C）', () {
    final project = File('PROJECT.md').readAsStringSync();

    /// [start] 之后、[end] 之前的片段。
    String slice(String source, String start, String end) {
      final from = source.indexOf(start);
      if (from < 0) return '';
      final rest = source.substring(from + start.length);
      final to = rest.indexOf(end);
      return to < 0 ? rest : rest.substring(0, to);
    }

    test('PROJECT.md 的出包命令带 --split-per-abi（AGENTS.md §1）', () {
      final offenders = project
          .split('\n')
          .where((line) => line.contains('flutter build apk'))
          .where((line) => line.contains('--release'))
          // `--debug` 行不受这条约束：分包是 release 出包的规矩。
          .where((line) => !line.contains('--split-per-abi'))
          .toList();

      expect(
        offenders,
        isEmpty,
        reason:
            'universal APK 会让每个用户多下 ~50MB 用不到的架构；'
            'release 出包必须写 `--split-per-abi`（AGENTS.md §1）',
      );
    });

    test('PROJECT.md 的路由表与 app_router.dart 逐条一致', () {
      final router = File('lib/core/router/app_router.dart').readAsStringSync();
      final codePaths = RegExp(r"path:\s*'([^']+)'")
          .allMatches(router)
          .map((match) => match.group(1)!)
          .toSet();
      final documented = RegExp(r'^\|\s*`([^`]+)`', multiLine: true)
          .allMatches(slice(project, '## 9. 路由配置', '\n## 10.'))
          .map((match) => match.group(1)!)
          .toSet();

      expect(codePaths, isNotEmpty, reason: '解析 app_router.dart 失败，护栏会空转');
      expect(
        documented.difference(codePaths),
        isEmpty,
        reason: 'PROJECT.md 记了代码里不存在的路由（应删）',
      );
      expect(
        codePaths.difference(documented),
        isEmpty,
        reason:
            '这些路由没被文档记录：${(codePaths.difference(documented).toList()..sort())}',
      );
    });

    test('PROJECT.md 的表/DAO 数量与 app_database.dart 一致', () {
      final db = File('lib/core/database/app_database.dart').readAsStringSync();
      final block = RegExp(
        r'@DriftDatabase\((.*?)\n\)',
        dotAll: true,
      ).firstMatch(db);
      expect(block, isNotNull, reason: 'app_database.dart 必须有 @DriftDatabase(...)');

      List<String> entries(String key) {
        final match = RegExp(
          '$key:\\s*\\[(.*?)\\]',
          dotAll: true,
        ).firstMatch(block!.group(1)!);
        expect(match, isNotNull, reason: '$key: [...] 未找到');
        // `RegExpMatch.group(n)` / `operator [n]` 的类型是 `String?`，所以守卫断言
        // 之后还要显式 `!` —— 少了它整份测试文件连加载都过不去（编译错误），
        // 连带把上面 7 条版本同步用例一起停跑。
        return match![1]!
            .split(',')
            .map((entry) => entry.replaceAll(RegExp(r'//.*'), '').trim())
            .where((entry) => entry.isNotEmpty)
            .toList();
      }

      final tables = entries('tables');
      final daos = entries('daos');
      expect(tables.length, greaterThan(4), reason: 'schema v2 起不止 5 张表');
      expect(daos.length, greaterThan(4));

      expect(
        project,
        contains('**${tables.length} 张表:**'),
        reason: '§4.3 的表数量必须等于 @DriftDatabase 注册的数量',
      );
      expect(
        project,
        contains('**${daos.length} 个 DAO:**'),
        reason: '§4.3 的 DAO 数量必须等于 @DriftDatabase 注册的数量',
      );

      final section = slice(project, '### 4.3 数据库 (Drift)', '### 4.4');
      for (final table in tables) {
        expect(section, contains(table), reason: '$table 未在 §4.3 记录');
      }
    });

    test('PROJECT.md §8 列的每个包都真的在 pubspec.yaml 里', () {
      // pubspec 里所有 2 空格缩进的 `name:` 键（dependencies + dev_dependencies，
      // 以及 flutter/flutter_launcher_icons 等配置块的子键 —— 多出来的名字只会让
      // 这条护栏更宽松，不会造成误报）。
      final declared = RegExp(r'^\s{2}([a-z0-9_]+):', multiLine: true)
          .allMatches(pubspec)
          .map((match) => match.group(1)!)
          .toSet();
      expect(
        declared,
        containsAll(<String>['flutter_riverpod', 'drift', 'just_audio']),
        reason: '解析 pubspec.yaml 失败，护栏会空转',
      );

      final documented = <String>{};
      for (final line in slice(
        project,
        '## 8. 依赖清单',
        '\n## 9.',
      ).split('\n')) {
        if (!line.startsWith('|')) continue;
        final cells = line.split('|');
        if (cells.length < 3) continue;
        final first = cells[1].replaceAll('`', '').trim();
        if (first.isEmpty || first == '包名' || first.startsWith('-')) continue;
        for (final part in first.split('+')) {
          final package = part.trim().split(RegExp(r'\s+')).first;
          if (RegExp(r'^[a-z0-9_]+$').hasMatch(package)) documented.add(package);
        }
      }
      expect(documented, isNotEmpty, reason: '§8 的依赖表解析失败，护栏会空转');

      expect(
        documented.difference(declared),
        isEmpty,
        reason:
            'PROJECT.md §8 列了 pubspec.yaml 里不存在的包：'
            '${(documented.difference(declared).toList()..sort())}',
      );
    });

    test('audio_service 不再被标成"未集成"', () {
      final section = slice(project, '## 8. 依赖清单', '\n## 9.');
      final row = section
          .split('\n')
          .firstWhere(
            (line) => line.startsWith('|') && line.contains('audio_service'),
            orElse: () => '',
          );
      expect(row, isNotEmpty, reason: '§8 应该仍然列出 audio_service');
      expect(
        row,
        isNot(contains('未集成')),
        reason: 'audio_service 已经集成（AndroidManifest 里声明了 MediaBrowserService）',
      );
    });

    test('PROJECT.md 的 Flutter / Dart 版本自洽且与工具链一致', () {
      final env = slice(project, '### 6.1 环境要求', '### 6.2');
      final flutter = RegExp(r'Flutter\s+(\d+\.\d+\.\d+)').firstMatch(env)?[1];
      final dart = RegExp(r'Dart\s+(\d+\.\d+\.\d+)').firstMatch(env)?[1];
      expect(flutter, isNotNull, reason: '§6.1 必须写明 Flutter 版本');
      expect(dart, isNotNull, reason: '§6.1 必须写明 Dart 版本');

      // §1 的技术栈行不能与 §6.1 矛盾（"3.47.5 vs 3.38.4"就是这条抓的）。
      final overview = slice(project, '## 1.', '## 2.');
      expect(overview, contains('Flutter $flutter'));
      expect(overview, contains('Dart $dart'));

      // Flutter：与工作副本的 SDK 版本对齐（`.dart_tool/version` 由 flutter 工具写，
      // CI 在 `flutter pub get` 之后同样存在；不存在时只看上面的自洽性）。
      final sdkVersionFile = File('.dart_tool/version');
      if (sdkVersionFile.existsSync()) {
        expect(
          flutter,
          sdkVersionFile.readAsStringSync().trim(),
          reason: '§6.1 的 Flutter 版本必须等于实际使用的 SDK',
        );
      }

      // Dart：pubspec 的 `sdk: ^X.Y.Z` 是唯一来源，major.minor 必须一致。
      final constraint = RegExp(
        r'sdk:\s*\^(\d+)\.(\d+)\.',
      ).firstMatch(pubspec);
      expect(constraint, isNotNull, reason: 'pubspec.yaml 必须声明 sdk 约束');
      expect(
        dart,
        startsWith('${constraint![1]}.${constraint[2]}.'),
        reason: '§6.1 的 Dart 版本与 pubspec.yaml 的 sdk 约束不同源',
      );
    });

    test('.gitignore 不再忽略 PROJECT.md / CHANGELOG.md', () {
      final ignored = File(
        '.gitignore',
      ).readAsLinesSync().map((line) => line.trim()).toSet();

      // AGENTS.md §2 的 7 个版本同步点里有 2 个在这两个文件里；它们不在版本控制内
      // 时，CI 与 fresh clone 都看不到它们，而 `version_sync_test` 只能"存在才检查"。
      expect(ignored, isNot(contains('/PROJECT.md')));
      expect(ignored, isNot(contains('/CHANGELOG.md')));
      expect(File('PROJECT.md').existsSync(), isTrue);
      expect(File('CHANGELOG.md').existsSync(), isTrue);
    });

    test('installer 检测 VC++ 运行库、带简体中文、且不重复包含 exe', () {
      final iss = File('installer/mconnect.iss').readAsStringSync();

      expect(
        iss,
        contains('[Code]'),
        reason: '缺 [Code] 段就没法在安装前拦住"缺运行库 → 双击闪退"',
      );
      expect(
        iss,
        contains('msvcp140'),
        reason: 'Flutter Windows 产物依赖 msvcp140.dll / vcruntime140.dll',
      );
      expect(iss, contains('vcruntime140'));
      expect(iss, contains('ChineseSimplified.isl'));

      final filesSection = slice(iss, '[Files]', '[');
      final exeEntries = filesSection
          .split('\n')
          .where(
            (line) =>
                line.trimLeft().startsWith('Source:') &&
                line.contains('MyAppExeName'),
          )
          .length;
      expect(
        exeEntries,
        lessThan(2),
        reason: '[Files] 里的 exe 与 `*` 通配重复包含（会多打包一次）',
      );
    });
  });
}
