import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/player/presentation/providers/player_provider.dart';
import 'desktop_network_image.dart';

/// The desktop window's backdrop.
///
/// It blurs the *cover image itself* (with [ImageFiltered]) rather than the
/// live scene (with [BackdropFilter]). The latter is the expensive path on
/// Windows/Impeller and the project has already been burned by full-screen
/// backdrop filters; blurring a static image once per song is cheap and gives
/// the same "the whole window belongs to this track" effect.
class DesktopAmbientBackground extends ConsumerWidget {
  final Widget child;

  const DesktopAmbientBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final coverUrl = ref.watch(
      playerProvider.select((state) => state.currentSong?.coverUrl),
    );
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return ColoredBox(
      color: scheme.surface,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const Positioned.fill(child: _BrandGradient()),
          if (coverUrl != null && coverUrl.trim().isNotEmpty)
            Positioned.fill(
              child: AnimatedSwitcher(
                duration: reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 650),
                child: RepaintBoundary(
                  key: ValueKey<String>(coverUrl),
                  child: ImageFiltered(
                    imageFilter: ui.ImageFilter.blur(sigmaX: 46, sigmaY: 46),
                    child: DesktopNetworkImage(
                      url: coverUrl,
                      cacheWidth: 640,
                      placeholder: const SizedBox.shrink(),
                      error: const SizedBox.shrink(),
                    ),
                  ),
                ),
              ),
            ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    scheme.surface.withValues(alpha: 0.62),
                    scheme.surface.withValues(alpha: 0.86),
                    scheme.surface,
                  ],
                ),
              ),
            ),
          ),
          Positioned.fill(child: child),
        ],
      ),
    );
  }
}

class _BrandGradient extends StatelessWidget {
  const _BrandGradient();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primary.withValues(alpha: 0.14),
            scheme.surface,
            scheme.tertiary.withValues(alpha: 0.08),
          ],
          stops: const [0, 0.55, 1],
        ),
      ),
    );
  }
}
