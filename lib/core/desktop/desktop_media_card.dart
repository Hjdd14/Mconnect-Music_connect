import 'package:flutter/material.dart';

import 'desktop_network_image.dart';
import 'desktop_tokens.dart';

/// Cover-first card used for playlists, albums, artists and songs.
///
/// It is intentionally not a [Card]: the desktop look is a bare cover with a
/// label underneath, lifted on hover. That is how every desktop music client
/// (Spotify, Apple Music, NetEase PC) reads, and it keeps a grid calm.
class DesktopMediaCard extends StatefulWidget {
  final String title;
  final String? subtitle;
  final String? imageUrl;
  final double width;
  final VoidCallback? onTap;
  final VoidCallback? onPlay;
  final Widget? badge;

  /// The hover lift every card pays for inside its own layout box.
  ///
  /// Public so the surrounding scroll views can reserve the same amount of
  /// padding and the geometry test can assert it.
  static const double hoverLift = 3;

  const DesktopMediaCard({
    super.key,
    required this.title,
    this.subtitle,
    this.imageUrl,
    this.width = 180,
    this.onTap,
    this.onPlay,
    this.badge,
  });

  @override
  State<DesktopMediaCard> createState() => _DesktopMediaCardState();
}

class _DesktopMediaCardState extends State<DesktopMediaCard> {
  bool _hovered = false;

  /// Vertical lift of the cover on hover, in logical pixels.
  ///
  /// The lift is paid for **inside** the card: the cover always sits at
  /// `[DesktopMediaCard.hoverLift]` and the hover animation moves it back to 0.
  /// Translating outward instead used to push the top three pixels out of the
  /// card's own box, and every caller puts these cards inside a clipped scroll
  /// viewport (a horizontal `ListView` for the discovery rows, a `GridView` for
  /// the library), so the hovered cover lost its top strip.
  static const double _lift = DesktopMediaCard.hoverLift;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: widget.width,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onTap,
          onDoubleTap: widget.onPlay,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // The constant top padding is what makes the lift safe: the cover
              // never leaves the card's layout box, so no ancestor clip can cut
              // it, and the column below it does not move when the hover starts.
              Padding(
                padding: const EdgeInsets.only(top: _lift),
                child: AnimatedContainer(
                  duration: DesktopDurations.hover,
                  curve: Curves.easeOutCubic,
                  transform: Matrix4.translationValues(
                    0,
                    _hovered ? -_lift : 0,
                    0,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: DesktopRadii.lgAll,
                    boxShadow: _hovered
                        ? DesktopShadows.floating
                        : DesktopShadows.panel,
                  ),
                  child: ClipRRect(
                    borderRadius: DesktopRadii.lgAll,
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (widget.imageUrl != null)
                            DesktopNetworkImage(
                              url: widget.imageUrl!,
                              cacheWidth: (widget.width * 2).round(),
                              placeholder: _placeholder(scheme),
                              error: _placeholder(scheme),
                            )
                          else
                            _placeholder(scheme),
                          if (widget.badge != null)
                            Positioned(top: 8, left: 8, child: widget.badge!),
                          if (_hovered && widget.onPlay != null)
                            Positioned(
                              right: 10,
                              bottom: 10,
                              child: _PlayBubble(onTap: widget.onPlay!),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: DesktopSpacing.sm),
              Text(
                widget.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: DesktopText.bodyStrong.copyWith(
                  color: _hovered ? scheme.primary : scheme.onSurface,
                ),
              ),
              if (widget.subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  widget.subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DesktopText.caption.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _placeholder(ColorScheme scheme) {
    return ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: Icon(
        Icons.music_note,
        size: widget.width * 0.22,
        color: scheme.onSurfaceVariant,
      ),
    );
  }
}

class _PlayBubble extends StatelessWidget {
  final VoidCallback onTap;

  const _PlayBubble({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.primary,
      shape: const CircleBorder(),
      elevation: 4,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(Icons.play_arrow, size: 22, color: scheme.onPrimary),
        ),
      ),
    );
  }
}
