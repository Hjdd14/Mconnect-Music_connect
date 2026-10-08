import 'package:flutter/widgets.dart';

import '../../l10n/l10n.dart';
import 'api_exception.dart';

/// The text a user should read for [error], in the **current** locale.
///
/// This is the "UI 翻译" half of `docs/i18n-migration-plan.md` §3.3 「模式 A」:
/// `lib/core/network` throws code-carrying [ApiException]s because it runs deep
/// in the data layer where there is no `BuildContext`, and every page that shows
/// an error maps the code here.
///
/// [ApiErrorCode.unknown] returns [ApiException.message] verbatim — that is the
/// exception's own text (built from the zh ARB, or supplied by a platform
/// adapter that has not been migrated yet), i.e. exactly what the UI showed
/// before this migration. So an unmapped error degrades to "Chinese text", never
/// to an empty or technical string.
String apiErrorText(BuildContext context, ApiException error) {
  final l = context.l10n;
  return switch (error.code) {
    ApiErrorCode.loginExpired => l.netLoginExpired,
    ApiErrorCode.songNotAvailable => l.netSongNotAvailable(
      error.platform ?? l.netCurrentPlatform,
    ),
    ApiErrorCode.qualityNotAvailable => error.suggestedQuality == null
        ? l.netQualityNotAvailable
        : l.netQualityDowngraded(error.suggestedQuality!),
    ApiErrorCode.lyricsNotFound => l.netLyricsNotFound,
    ApiErrorCode.noVipMembership => l.netNoVip(
      error.platform ?? l.netCurrentPlatform,
    ),
    ApiErrorCode.storagePermissionDenied => l.netStoragePermissionDenied,
    ApiErrorCode.network => l.netConnectionFailed,
    ApiErrorCode.notFound => l.netNotFound,
    ApiErrorCode.unsupportedAction => l.netUnsupported(
      error.platform ?? l.netCurrentPlatform,
    ),
    ApiErrorCode.storageFull => l.netStorageFull,
    ApiErrorCode.requestCancelled => l.netRequestCancelled,
    // Deliberately `?? ''` and not `netCurrentPlatform`: the pre-migration text
    // was `'$label请求超时'`, so an empty label produced `请求超时` with no prefix
    // (`test/platform_http_test.dart` pins the non-empty case).
    ApiErrorCode.requestTimeout => l.netRequestTimeout(error.platform ?? ''),
    ApiErrorCode.serverError => l.netServerError(error.platform ?? ''),
    ApiErrorCode.requestFailed => error.statusCode == null
        ? l.netRequestFailed
        : l.netRequestFailedWithCode(error.statusCode!),
    ApiErrorCode.unknown => error.message,
  };
}
