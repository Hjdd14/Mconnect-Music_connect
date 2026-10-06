import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/l10n/app_localizations.dart';
import 'package:mconnect/l10n/l10n.dart';

/// Guards the ARB pipeline itself.
///
/// Three failure modes this catches, all of which look like "the app is fine"
/// until someone switches locale:
/// * a key added to one bundle only (the other locale silently falls back to the
///   template, so a translator never sees the gap);
/// * placeholders drifting between the two bundles (`{error}` vs `{message}`),
///   which throws at runtime in the generated code;
/// * editing the ARB and forgetting `flutter gen-l10n`, so the committed
///   generated code no longer matches the source of truth.
void main() {
  late Map<String, dynamic> zh;
  late Map<String, dynamic> en;

  Map<String, dynamic> readArb(String path) =>
      jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

  Set<String> messageKeys(Map<String, dynamic> arb) => arb.keys
      .where((key) => !key.startsWith('@'))
      .toSet();

  Set<String> placeholders(String value) => RegExp(r'\{(\w+)\}')
      .allMatches(value)
      .map((match) => match.group(1)!)
      .toSet();

  setUpAll(() {
    zh = readArb('lib/l10n/app_zh.arb');
    en = readArb('lib/l10n/app_en.arb');
  });

  test('both bundles expose exactly the same message keys', () {
    expect(
      messageKeys(en).difference(messageKeys(zh)),
      isEmpty,
      reason: 'keys present in en but missing from the zh template',
    );
    expect(
      messageKeys(zh).difference(messageKeys(en)),
      isEmpty,
      reason: 'keys present in zh but not translated into en',
    );
  });

  test('every key keeps the same placeholder set in both bundles', () {
    final mismatches = <String>[];
    for (final key in messageKeys(zh)) {
      final zhValue = zh[key]?.toString() ?? '';
      final enValue = en[key]?.toString() ?? '';
      if (!placeholders(zhValue).containsAll(placeholders(enValue)) ||
          !placeholders(enValue).containsAll(placeholders(zhValue))) {
        mismatches.add(
          '$key: zh=${placeholders(zhValue)} en=${placeholders(enValue)}',
        );
      }
    }
    expect(mismatches, isEmpty);
  });

  test('the committed generated code is up to date with the ARB', () {
    final generated = File('lib/l10n/app_localizations.dart').readAsStringSync();
    // Parameterised messages generate a method (`String audioMinutes(int ...)`),
    // the rest a getter (`String get settingsTitle;`).
    final missing = messageKeys(zh)
        .where(
          (key) =>
              !generated.contains('String get $key;') &&
              !generated.contains('String $key('),
        )
        .toList();
    expect(
      missing,
      isEmpty,
      reason: 'run `flutter gen-l10n` — these keys are in the ARB but not in the '
          'generated AppLocalizations',
    );
  });

  test('the Chinese bundle is the template and stays loadable', () {
    final l = lookupAppLocalizations(const Locale('zh'));
    expect(l.settingsTitle, '设置');
    expect(l.navLibrary, '音乐库');
    expect(l.appTitle, 'Mconnect');
  });

  test('the English bundle really renders English', () {
    final l = lookupAppLocalizations(const Locale('en'));
    expect(l.settingsTitle, 'Settings');
    expect(l.navLibrary, 'Library');
    expect(l.sessionExpired, isNotEmpty);
    expect(l.sessionExpired, isNot(zh['sessionExpired']));
  });

  testWidgets('a widget rendered with Locale(en) shows the English copy', (
    tester,
  ) async {
    // This is what makes the two bundles more than decoration: the app declares
    // only `zh` today (see `appSupportedLocales`), so this test is the proof that
    // flipping the declaration would actually switch the migrated pages.
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: const [Locale('en')],
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Builder(
          builder: (context) => Scaffold(
            body: Column(
              children: [
                Text(context.l10n.settingsTitle),
                Text(context.l10n.settingsBackup),
                Text(context.l10n.playerNowPlaying),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Backup & restore'), findsOneWidget);
    expect(find.text('Now playing'), findsOneWidget);
    expect(find.text('设置'), findsNothing);
  });

  testWidgets('without a delegate the accessor falls back to Chinese', (
    tester,
  ) async {
    // Several widget tests pump a single page into a bare MaterialApp; the
    // fallback is what keeps them asserting production copy.
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(body: Text(context.l10n.settingsTitle)),
        ),
      ),
    );

    expect(find.text('设置'), findsOneWidget);
  });

  test('expected placeholder values are rendered', () {
    final l = lookupAppLocalizations(const Locale('zh'));
    expect(l.audioMinutes(5), '5 分钟');
    expect(l.backgroundProcessFailed('boom'), contains('boom'));
    expect(l.accountLogoutConfirm('网易云音乐'), contains('网易云音乐'));
    expect(l.diagnosticsExportFailed('disk'), contains('disk'));
  });
}
