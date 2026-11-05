import 'package:flutter/material.dart';

import 'desktop_tokens.dart';

/// Standard desktop page header plus a bounded content area.
///
/// The phone pages use [AppBar] and rely on the bottom capsule for spacing.
/// Desktop pages use this instead: a left-aligned title block, an action row on
/// the right, and content that starts below it. That single change is what
/// stops the desktop UI from reading as a stretched phone page.
class DesktopPageScaffold extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? leading;
  final List<Widget> actions;
  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool scrollable;
  final double maxContentWidth;

  const DesktopPageScaffold({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.actions = const <Widget>[],
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(
      DesktopSpacing.xxxl,
      DesktopSpacing.xxl,
      DesktopSpacing.xxxl,
      DesktopSpacing.xxl,
    ),
    this.scrollable = false,
    this.maxContentWidth = DesktopShellConstants.contentMaxWidth,
  });

  @override
  Widget build(BuildContext context) {
    final content = Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxContentWidth),
        child: child,
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DesktopPageHeader(
          title: title,
          subtitle: subtitle,
          leading: leading,
          actions: actions,
        ),
        Expanded(
          child: Padding(
            padding: padding,
            child: scrollable ? SingleChildScrollView(child: content) : content,
          ),
        ),
      ],
    );
  }
}

class DesktopPageHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? leading;
  final List<Widget> actions;

  const DesktopPageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.actions = const <Widget>[],
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        DesktopSpacing.xxxl,
        DesktopSpacing.xxl,
        DesktopSpacing.xxxl,
        DesktopSpacing.lg,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (leading != null) ...[
            leading!,
            const SizedBox(width: DesktopSpacing.md),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: DesktopText.headline.copyWith(color: scheme.onSurface),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                  const SizedBox(height: DesktopSpacing.xxs),
                  Text(
                    subtitle!,
                    style: DesktopText.caption.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(width: DesktopSpacing.lg),
            Wrap(
              spacing: DesktopSpacing.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: actions,
            ),
          ],
        ],
      ),
    );
  }
}

/// Bounded width used by the desktop pages. Kept here (rather than importing
/// the shell policy) so a page can be rendered in isolation in a widget test.
abstract final class DesktopShellConstants {
  DesktopShellConstants._();

  static const double contentMaxWidth = 1400;
}
