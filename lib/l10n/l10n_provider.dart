import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_localizations.dart';
import 'l10n.dart';

/// The current [AppLocalizations] for layers that have **no `BuildContext`** —
/// the "模式 B" half of `docs/i18n-migration-plan.md` §3.3.
///
/// Shape (agreed with the Lead, B4-3b step 1):
///
/// * It is a **leaf**: no `ref.watch`, no dependency on any other provider, so
///   it cannot take part in a provider cycle. The failure that cost three waves
///   on scrobble was a *self-dependency* (a refresh gate waiting on a value
///   only refresh could fill); that shape is structurally impossible here,
///   because an override always comes from a **higher** scope and consumers
///   only ever read.
/// * Its default is the Chinese bundle, which is exactly what the app publishes
///   today (`app.dart` declares only `Locale('zh')`). When `en` is enabled, the
///   override belongs in `MaterialApp.builder` (the `buildGlassShell` layer in
///   `lib/app.dart`), because *that* context sits below `Localizations` — the
///   `ProviderScope` in `lib/main.dart` does **not**, it is above `MaterialApp`
///   and therefore cannot read `AppLocalizations.of(context)`.
///
/// Two rules for consumers (project convention):
///
/// 1. read it with `ref.read` **inside async methods only** — never while a
///    provider is being built;
/// 2. **never `ref.watch` it** from a notifier: a locale change would rebuild
///    (and discard) the notifier, cancelling whatever request is in flight.
final l10nProvider = Provider<AppLocalizations>((_) => zhAppLocalizations);
