import 'package:flutter/widgets.dart';

import 'app_localizations.dart';

/// The Chinese bundle: the app's single source for zh text.
///
/// Two callers, one source:
/// * [AppLocalizationsX.l10n] falls back to it when no delegate is installed
///   (which is what keeps every page test asserting production Chinese);
/// * layers with **no `BuildContext` at all** — `lib/core/network`'s exception
///   messages are the first of them — still have to produce a string, and
///   sourcing it from the ARB keeps `lib/core/**` free of hardcoded Chinese
///   (see `test/i18n_budget_test.dart`, `docs/i18n-migration-plan.md` §3.3).
final AppLocalizations zhAppLocalizations = lookupAppLocalizations(
  const Locale('zh'),
);

/// Locale-aware strings for a widget subtree.
///
/// `context.l10n.someKey` is the single accessor used by the migrated pages.
///
/// It falls back to the Chinese bundle when no [AppLocalizations] delegate is
/// installed above [context]. That is deliberate: several widget tests pump a
/// single page into a bare `MaterialApp` (without delegates), and the fallback
/// keeps those tests asserting the *production* copy instead of forcing every
/// test to install a delegate it does not care about.
extension AppLocalizationsX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this) ?? zhAppLocalizations;
}
