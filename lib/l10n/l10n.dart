import 'package:flutter/widgets.dart';

import 'app_localizations.dart';

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
  AppLocalizations get l10n =>
      AppLocalizations.of(this) ?? lookupAppLocalizations(const Locale('zh'));
}
