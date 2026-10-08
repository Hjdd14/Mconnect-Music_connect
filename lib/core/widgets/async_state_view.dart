import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../../l10n/l10n.dart';
import '../theme/app_colors.dart';

/// Which of the three mutually exclusive page states a view represents.
enum AsyncStateKind { loading, error, empty }

/// The app's single loading / error / empty view.
///
/// Before this widget every page hand-rolled its own three-state block, and the
/// inconsistencies were visible: a bare `CircularProgressIndicator` on one page
/// and a `strokeWidth: 2` one on another; `ElevatedButton('重试')` on some pages
/// and `TextButton('重试')` on others; error text coloured with
/// `colorScheme.outline` (a colour meant for *borders*, not body copy).
///
/// Three rules are encoded here so no caller has to remember them:
///
/// 1. **Retry is always an [ElevatedButton].** A destructive-looking text button
///    next to a full-page failure reads as a link, not as "try again".
/// 2. **Body copy uses `onSurfaceVariant`**, never `outline` — see the M-73 note
///    in `docs/mconnect-improvement-plan.md`.
/// 3. **An error state must offer a way out.** [AsyncStateView.error] requires
///    `onRetry`; there is deliberately no error constructor without one.
///
/// Use [AsyncStateView.loading] with `skeleton: true` on list pages where a
/// spinner would make the layout jump; the skeleton is a generic shimmer list so
/// this file needs no knowledge of any feature's item widget.
class AsyncStateView extends StatelessWidget {
  /// A spinner, or a shimmer list when [skeleton] is true.
  const AsyncStateView.loading({super.key, this.title, this.skeleton = false})
    : kind = AsyncStateKind.loading,
      icon = null,
      message = null,
      onRetry = null;

  /// A failure with a mandatory retry affordance.
  const AsyncStateView.error({
    super.key,
    required this.title,
    this.message,
    required this.onRetry,
  }) : kind = AsyncStateKind.error,
       icon = Icons.error_outline,
       skeleton = false;

  /// "Nothing here yet" — not a failure, so no retry is offered.
  const AsyncStateView.empty({
    super.key,
    required this.title,
    this.message,
    this.icon = Icons.inbox_outlined,
  }) : kind = AsyncStateKind.empty,
       onRetry = null,
       skeleton = false;

  final AsyncStateKind kind;

  /// Primary line. May be null while loading.
  final String? title;

  /// Secondary line: the reason for a failure, or how to get content.
  final String? message;

  final IconData? icon;
  final VoidCallback? onRetry;
  final bool skeleton;

  /// Number of shimmer rows. A constant so the skeleton is identical everywhere
  /// (and could be asserted in tests).
  static const int skeletonRows = 6;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // `onSurfaceVariant` is the theme's own "secondary text" role. `outline` is
    // a border colour and fails contrast for body copy in both themes.
    final bodyStyle = TextStyle(
      color: scheme.onSurfaceVariant,
      fontSize: 16,
    );
    final captionStyle = TextStyle(
      color: scheme.onSurfaceVariant.withValues(alpha: 0.75),
      fontSize: 13,
    );

    switch (kind) {
      case AsyncStateKind.loading:
        if (skeleton) return const _AsyncSkeletonList();
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              if (title != null) ...[
                const SizedBox(height: 16),
                Text(title!, style: captionStyle),
              ],
            ],
          ),
        );

      case AsyncStateKind.error:
      case AsyncStateKind.empty:
        // **`outline` family = icons only; body copy is always
        // `onSurfaceVariant`** (rule 2 above). `scheme.outlineVariant` here is
        // deliberate and must not be "corrected" to a text colour: a 64dp
        // decorative glyph reads as a quiet mark, whereas the same low-contrast
        // colour on a paragraph fails contrast. The reverse mistake — using
        // `outline` for body copy — is the one the audit found on ~10 pages.
        //
        // The error glyph is the one icon that gets `scheme.error`, because it
        // carries meaning the sentence alone can miss at a glance.
        final iconColor = kind == AsyncStateKind.error
            ? scheme.error
            : scheme.outlineVariant;
        return Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 64, color: iconColor),
                const SizedBox(height: 16),
                Text(title!, style: bodyStyle, textAlign: TextAlign.center),
                if (message != null) ...[
                  const SizedBox(height: 8),
                  Text(message!, style: captionStyle, textAlign: TextAlign.center),
                ],
                if (onRetry != null) ...[
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: onRetry,
                    child: Text(context.l10n.commonRetry),
                  ),
                ],
              ],
            ),
          ),
        );
    }
  }
}

/// Wraps an [AsyncStateView] so it can be used as a sliver.
///
/// Pages built on `CustomScrollView` (top lists, downloads) previously had to
/// wrap their inline state in `SliverFillRemaining` themselves, which is why
/// some of them used a different spinner style than the box-based pages.
///
/// [padding] is applied *inside* the sliver, around the state view — the shape a
/// page needs when its scrollable already sits under a floating bottom stack and
/// the empty/error block has to stay above it.
class SliverAsyncStateView extends StatelessWidget {
  const SliverAsyncStateView({
    super.key,
    required this.child,
    this.hasScrollBody = false,
    this.padding,
  });

  final Widget child;
  final bool hasScrollBody;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) => SliverFillRemaining(
    hasScrollBody: hasScrollBody,
    child: padding == null
        ? child
        : Padding(padding: padding!, child: child),
  );
}

/// A feature-agnostic shimmer placeholder list.
class _AsyncSkeletonList extends StatelessWidget {
  const _AsyncSkeletonList();

  @override
  Widget build(BuildContext context) {
    final base = AppColors.placeholder(context);
    final scheme = Theme.of(context).colorScheme;
    return Shimmer.fromColors(
      baseColor: base,
      highlightColor: scheme.surfaceContainerHighest,
      child: ListView.builder(
        key: const Key('async-skeleton-list'),
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: AsyncStateView.skeletonRows,
        itemBuilder: (context, index) => const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              _SkeletonBox(width: 48, height: 48, radius: 8),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SkeletonBox(width: 180, height: 14, radius: 4),
                    SizedBox(height: 8),
                    _SkeletonBox(width: 110, height: 12, radius: 4),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SkeletonBox extends StatelessWidget {
  const _SkeletonBox({required this.width, required this.height, required this.radius});

  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      // Opaque on purpose: `Shimmer` masks the child and drives the moving
      // highlight itself, so the child's own colour is irrelevant as long as it
      // is opaque — which is why using the theme's placeholder colour (rather
      // than a hardcoded `Colors.white`) costs nothing and keeps AppColors the
      // single source of placeholder colour.
      color: AppColors.placeholder(context),
      borderRadius: BorderRadius.circular(radius),
    ),
  );
}
