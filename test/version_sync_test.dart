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
}
