import 'package:flutter/material.dart';

import 'app_theme.dart';

/// Corner radius Miuix uses for cards and input fields.
const double miuixCardRadius = 20;

/// Corner radius of the floating bottom navigation capsule (阶段 B/C).
const double miuixNavBarRadius = 28;

/// Corner radius for list tiles, buttons and chips.
const double miuixTileRadius = 16;

/// Corner radius for the dialog surface.
const double miuixDialogRadius = 32;

/// Corner radius for the top of a modal bottom sheet.
const double miuixSheetRadius = 28;

/// Corner radius for the tab indicator pill.
const double miuixTabIndicatorRadius = 12;

/// Minimum height for Miuix buttons.
const double miuixButtonMinHeight = 40;

const EdgeInsets _tilePadding = EdgeInsets.symmetric(horizontal: 16);
const EdgeInsets _buttonPadding = EdgeInsets.symmetric(
  horizontal: 20,
  vertical: 10,
);

/// Miuix-flavoured theme built *on top of* the existing Material theme.
///
/// The Miuix visual language is a **shape and surface** language rather than a
/// different colour system, so this stays a `.copyWith` overlay on [AppTheme]:
/// the colour scheme (and therefore the user's chosen seed colour), typography
/// and component behaviour are inherited verbatim. Only the slots that
/// materially change how a widget reads are overridden.
///
/// What is overridden and why:
/// * `cardTheme` / `listTileTheme` / `inputDecorationTheme` — flat surfaces with
///   a larger, consistent corner radius (16–20 dp) instead of Material's
///   elevation-driven cards.
/// * the four button themes — 16 dp corners and a 40 dp minimum height, with the
///   elevation removed from the filled/elevated variants.
/// * `switchTheme` / `sliderTheme` — thinner outline-driven switch and a sleeker
///   slider thumb, matching the flat-surface language.
/// * `chipTheme` / `segmentedButtonTheme` / `tabBarTheme` — pill shapes.
/// * `dialogTheme` / `bottomSheetTheme` — Miuix's larger sheet and dialog radii.
///
/// Everything else is inherited so that the Material path (I-8) is untouched:
/// this function is only ever consulted when the user selected [UiStyle.miuix].
///
/// [base] defaults to `AppTheme.light`/`AppTheme.dark` for [brightness], which
/// keeps call sites simple while still allowing a caller to pass an already
/// computed theme.
ThemeData miuixTheme({
  required Brightness brightness,
  required Color seedColor,
  ThemeData? base,
}) {
  final resolvedBase =
      base ??
      (brightness == Brightness.dark
          ? AppTheme.dark(seedColor: seedColor)
          : AppTheme.light(seedColor: seedColor));

  final scheme = resolvedBase.colorScheme;
  const tileShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(miuixTileRadius)),
  );
  final buttonStyle = ButtonStyle(
    shape: const WidgetStatePropertyAll(tileShape),
    minimumSize: const WidgetStatePropertyAll(
      Size(0, miuixButtonMinHeight),
    ),
    padding: const WidgetStatePropertyAll(_buttonPadding),
    visualDensity: VisualDensity.standard,
  );

  return resolvedBase.copyWith(
    // ── Surfaces ────────────────────────────────────────────────────────────
    cardTheme: resolvedBase.cardTheme.copyWith(
      elevation: 0,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(miuixCardRadius)),
      ),
    ),
    listTileTheme: resolvedBase.listTileTheme.copyWith(
      shape: tileShape,
      contentPadding: _tilePadding,
      minTileHeight: 56,
    ),
    inputDecorationTheme: resolvedBase.inputDecorationTheme.copyWith(
      border: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(miuixCardRadius)),
      ),
    ),
    dividerTheme: resolvedBase.dividerTheme.copyWith(
      thickness: 0.5,
      space: 0.5,
    ),
    dialogTheme: resolvedBase.dialogTheme.copyWith(
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(miuixDialogRadius)),
      ),
    ),
    bottomSheetTheme: resolvedBase.bottomSheetTheme.copyWith(
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(miuixSheetRadius),
        ),
      ),
      showDragHandle: true,
      dragHandleColor: scheme.onSurfaceVariant.withValues(alpha: 0.4),
    ),

    // ── Buttons ─────────────────────────────────────────────────────────────
    filledButtonTheme: FilledButtonThemeData(
      style: resolvedBase.filledButtonTheme.style?.merge(buttonStyle) ??
          buttonStyle,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: (resolvedBase.elevatedButtonTheme.style ?? const ButtonStyle())
          .merge(buttonStyle)
          .copyWith(elevation: const WidgetStatePropertyAll(0)),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: (resolvedBase.outlinedButtonTheme.style ?? const ButtonStyle())
          .merge(buttonStyle)
          .copyWith(
            side: WidgetStatePropertyAll(
              BorderSide(color: scheme.outlineVariant),
            ),
          ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: resolvedBase.textButtonTheme.style?.merge(buttonStyle) ??
          buttonStyle,
    ),

    // ── Selection controls ──────────────────────────────────────────────────
    //
    // The Miuix switch is an outlined track with a filled thumb rather than
    // Material's fully-filled track, so the outline carries the "on" state
    // colour and the track only fills while selected.
    switchTheme: SwitchThemeData(
      trackOutlineColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return Colors.transparent;
        }
        return scheme.outline;
      }),
      trackOutlineWidth: const WidgetStatePropertyAll(1.5),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return scheme.primary;
        }
        return scheme.surfaceContainerHighest;
      }),
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return scheme.onPrimary;
        }
        return scheme.outline;
      }),
    ),
    sliderTheme: resolvedBase.sliderTheme.copyWith(
      trackHeight: 4,
      activeTrackColor: scheme.primary,
      inactiveTrackColor: scheme.surfaceContainerHighest,
      thumbColor: scheme.primary,
      overlayColor: scheme.primary.withValues(alpha: 0.12),
      showValueIndicator: ShowValueIndicator.onlyForDiscrete,
    ),
    progressIndicatorTheme: resolvedBase.progressIndicatorTheme.copyWith(
      linearTrackColor: scheme.surfaceContainerHighest,
      linearMinHeight: 3,
    ),

    // ── Pills ───────────────────────────────────────────────────────────────
    chipTheme: resolvedBase.chipTheme.copyWith(
      shape: const StadiumBorder(),
      side: BorderSide(color: scheme.outlineVariant),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: (resolvedBase.segmentedButtonTheme.style ?? const ButtonStyle())
          .merge(
            ButtonStyle(
              shape: const WidgetStatePropertyAll(StadiumBorder()),
              minimumSize: const WidgetStatePropertyAll(
                Size(0, miuixButtonMinHeight),
              ),
            ),
          ),
    ),
    tabBarTheme: resolvedBase.tabBarTheme.copyWith(
      indicator: BoxDecoration(
        borderRadius: BorderRadius.circular(miuixTabIndicatorRadius),
        color: scheme.primary.withValues(alpha: 0.14),
      ),
      indicatorSize: TabBarIndicatorSize.tab,
      dividerColor: Colors.transparent,
      labelColor: scheme.primary,
      unselectedLabelColor: scheme.onSurfaceVariant,
    ),

    // ── Feedback ────────────────────────────────────────────────────────────
    snackBarTheme: resolvedBase.snackBarTheme.copyWith(
      behavior: SnackBarBehavior.floating,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(miuixTileRadius)),
      ),
    ),
    tooltipTheme: resolvedBase.tooltipTheme.copyWith(
      decoration: BoxDecoration(
        color: scheme.inverseSurface,
        borderRadius: BorderRadius.circular(12),
      ),
    ),
  );
}
