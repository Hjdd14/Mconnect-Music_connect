import '../../models/platform_type.dart';
import 'app_localizations.dart';

/// Localized platform names.
///
/// `PlatformType.displayName` is left untouched on purpose: it is the enum's own
/// label, it is not persisted anywhere, and dozens of call sites (including
/// platform-layer diagnostics) read it directly. Rewriting it would have been a
/// cross-cutting behavioural change hidden inside an i18n task.
///
/// Migrated pages use `platform.label(context.l10n)` instead; the remaining
/// pages keep `displayName` until they are migrated, at which point the ARB
/// bundle already carries the translation.
extension PlatformTypeLocalization on PlatformType {
  String label(AppLocalizations l) => switch (this) {
    PlatformType.local => l.platformLocal,
    PlatformType.netease => l.platformNetease,
    PlatformType.qq => l.platformQq,
    PlatformType.kugou => l.platformKugou,
  };
}
