import 'package:flutter/material.dart';

/// Centralized SnackBar helpers for consistent error/success messaging.
///
/// Every user-facing toast in the app goes through these three functions so the
/// behaviours that used to drift from call site to call site stay fixed in one
/// place:
/// * errors are painted with the theme's error colour (a bare `SnackBar` looked
///   identical to a success message, which is how "删除失败" could be mistaken
///   for "已删除");
/// * all toasts float above the bottom navigation / mini player instead of
///   being glued to the screen edge;
/// * durations come from here (`error` 3 s, success/info 2 s).
///
/// Pass a `SnackBarAction` for the rare toast that needs a button (e.g. the
/// global "session expired → 去登录" notice).
void showErrorSnackBar(
  BuildContext context,
  String message, {
  Duration? duration,
  SnackBarAction? action,
}) {
  _show(
    context,
    message,
    isError: true,
    duration: duration,
    action: action,
  );
}

void showSuccessSnackBar(
  BuildContext context,
  String message, {
  Duration? duration,
  SnackBarAction? action,
}) {
  _show(
    context,
    message,
    isError: false,
    duration: duration,
    action: action,
  );
}

/// Neutral toast (information that is neither a success nor a failure).
void showInfoSnackBar(
  BuildContext context,
  String message, {
  Duration? duration,
  SnackBarAction? action,
}) {
  _show(
    context,
    message,
    isError: false,
    duration: duration,
    action: action,
  );
}

void _show(
  BuildContext context,
  String message, {
  required bool isError,
  Duration? duration,
  SnackBarAction? action,
}) {
  // `maybeOf` instead of `of`: a toast must never be the thing that throws. A
  // message fired from a route that is already gone (or from a widget test
  // without a `Scaffold`) simply does not show.
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger.showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: isError
          ? Theme.of(context).colorScheme.error
          : null,
      behavior: SnackBarBehavior.floating,
      duration:
          duration ??
          (isError ? const Duration(seconds: 3) : const Duration(seconds: 2)),
      action: action,
    ),
  );
}
