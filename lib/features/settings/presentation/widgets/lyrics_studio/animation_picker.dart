import 'package:flutter/material.dart';

import 'package:mconnect/core/lyrics/lyrics_animation_catalog.dart';

/// A wrapping chip picker for one animation family.
///
/// Pure presentation: it renders the catalog metadata (label plus the
/// "recommended for the taskbar" star) and reports the chosen value. The
/// surface filtering happens before it is built, so the same widget serves the
/// line, window and easing pickers.
class AnimationPicker<T> extends StatelessWidget {
  const AnimationPicker({
    super.key,
    required this.title,
    required this.idPrefix,
    required this.options,
    required this.selected,
    required this.onSelected,
    this.subtitle,
  });

  final String title;

  /// Prefix of the widget keys, so two pickers never collide on a shared id
  /// (none/fade exist in both the line and the window family).
  final String idPrefix;
  final List<LyricsAnimationOption<T>> options;
  final T selected;
  final ValueChanged<T> onSelected;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ordered = <LyricsAnimationOption<T>>[
      ...options.where((option) => option.recommendedForTaskbar),
      ...options.where((option) => !option.recommendedForTaskbar),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: theme.textTheme.titleSmall),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                subtitle!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: <Widget>[
              for (final option in ordered)
                ChoiceChip(
                  key: ValueKey<String>('$idPrefix-${option.id}'),
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      if (option.recommendedForTaskbar) ...<Widget>[
                        Icon(
                          Icons.star_rounded,
                          size: 14,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 2),
                      ],
                      Text(option.label),
                    ],
                  ),
                  selected: option.value == selected,
                  onSelected: (_) => onSelected(option.value),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
