import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_background_provider.dart';

const int appBackgroundMaxDecodeSide = 4096;

@immutable
class AppBackgroundImageGeometry {
  final Size canvasSize;
  final Offset canvasOffset;
  final Offset contentOffset;
  final double scale;

  const AppBackgroundImageGeometry({
    required this.canvasSize,
    required this.canvasOffset,
    required this.contentOffset,
    required this.scale,
  });
}

({int? cacheWidth, int? cacheHeight}) appBackgroundImageDecodeSize({
  required AppBackgroundSettings settings,
  int maxSide = appBackgroundMaxDecodeSide,
}) {
  final imageWidth = settings.imageWidth.round();
  final imageHeight = settings.imageHeight.round();
  if (imageWidth <= 0 || imageHeight <= 0 || maxSide <= 0) {
    return (cacheWidth: null, cacheHeight: null);
  }

  final longestSide = math.max(imageWidth, imageHeight);
  if (longestSide <= maxSide) {
    return (cacheWidth: null, cacheHeight: null);
  }

  final resizeScale = maxSide / longestSide;
  return (
    cacheWidth: math.max(1, (imageWidth * resizeScale).round()),
    cacheHeight: math.max(1, (imageHeight * resizeScale).round()),
  );
}

AppBackgroundImageGeometry appBackgroundImageGeometry({
  required AppBackgroundSettings settings,
  required Size viewportSize,
}) {
  final imageSize = settings.imageWidth > 0 && settings.imageHeight > 0
      ? Size(settings.imageWidth, settings.imageHeight)
      : viewportSize;
  final containScale = math.min(
    viewportSize.width / imageSize.width,
    viewportSize.height / imageSize.height,
  );
  final canvasSize = Size(
    imageSize.width * containScale,
    imageSize.height * containScale,
  );
  final canvasOffset = Alignment.center.alongOffset(
    Offset(
      viewportSize.width - canvasSize.width,
      viewportSize.height - canvasSize.height,
    ),
  );
  final referenceWidth = settings.cropViewportWidth > 0
      ? settings.cropViewportWidth
      : viewportSize.width;
  final referenceHeight = settings.cropViewportHeight > 0
      ? settings.cropViewportHeight
      : viewportSize.height;
  final offsetScaleX = referenceWidth > 0
      ? viewportSize.width / referenceWidth
      : 1.0;
  final offsetScaleY = referenceHeight > 0
      ? viewportSize.height / referenceHeight
      : 1.0;

  return AppBackgroundImageGeometry(
    canvasSize: canvasSize,
    canvasOffset: canvasOffset,
    contentOffset: Offset(
      settings.offsetX * offsetScaleX,
      settings.offsetY * offsetScaleY,
    ),
    scale: settings.scale,
  );
}

class AppBackgroundShell extends ConsumerWidget {
  final Widget child;
  final Widget Function(File file)? imageBuilder;

  const AppBackgroundShell({super.key, required this.child, this.imageBuilder});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appBackgroundSettingsProvider);
    final theme = Theme.of(context);
    final scrim = theme.brightness == Brightness.dark
        ? Colors.black.withValues(alpha: 0.48)
        : theme.colorScheme.surface.withValues(alpha: 0.72);

    return ColoredBox(
      color: theme.colorScheme.surface,
      child: Stack(
        children: [
          AppBackgroundImageLayer(
            settings: settings,
            imageBuilder: imageBuilder,
          ),
          if (settings.enabled)
            Positioned.fill(
              child: IgnorePointer(child: ColoredBox(color: scrim)),
            ),
          child,
        ],
      ),
    );
  }
}

class AppBackgroundImageLayer extends StatelessWidget {
  final AppBackgroundSettings settings;
  final bool positioned;
  final Widget Function(File file)? imageBuilder;

  const AppBackgroundImageLayer({
    super.key,
    required this.settings,
    this.positioned = true,
    this.imageBuilder,
  });

  @override
  Widget build(BuildContext context) {
    final file = settings.enabled ? File(settings.imagePath!) : null;
    if (file == null || !file.existsSync()) {
      return const SizedBox.shrink();
    }

    final image = IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final viewportSize = Size(
            constraints.maxWidth,
            constraints.maxHeight,
          );

          return SizedBox.expand(
            child: AppBackgroundImageCanvas(
              settings: settings,
              viewportSize: viewportSize,
              file: file,
              imageBuilder: imageBuilder,
            ),
          );
        },
      ),
    );

    if (!positioned) return image;

    return Positioned.fill(child: image);
  }
}

class AppBackgroundImageCanvas extends StatelessWidget {
  final AppBackgroundSettings settings;
  final Size viewportSize;
  final File file;
  final Widget Function(File file)? imageBuilder;

  const AppBackgroundImageCanvas({
    super.key,
    required this.settings,
    required this.viewportSize,
    required this.file,
    this.imageBuilder,
  });

  @override
  Widget build(BuildContext context) {
    final geometry = appBackgroundImageGeometry(
      settings: settings,
      viewportSize: viewportSize,
    );
    final decodeSize = appBackgroundImageDecodeSize(settings: settings);
    final image =
        imageBuilder?.call(file) ??
        Image.file(
          file,
          width: geometry.canvasSize.width,
          height: geometry.canvasSize.height,
          fit: BoxFit.contain,
          cacheWidth: decodeSize.cacheWidth,
          cacheHeight: decodeSize.cacheHeight,
        );

    return ColoredBox(
      key: const Key('app-background-image-frame'),
      color: Colors.black,
      child: ClipRect(
        child: Transform.translate(
          offset: geometry.contentOffset,
          child: Transform.scale(
            scale: geometry.scale,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Positioned(
                  left: geometry.canvasOffset.dx,
                  top: geometry.canvasOffset.dy,
                  width: geometry.canvasSize.width,
                  height: geometry.canvasSize.height,
                  child: SizedBox(
                    key: const Key('app-background-image-canvas'),
                    width: geometry.canvasSize.width,
                    height: geometry.canvasSize.height,
                    child: image,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class PlayerGlassRouteSurface extends ConsumerWidget {
  final Widget child;
  final Widget Function(File file)? imageBuilder;

  const PlayerGlassRouteSurface({
    super.key,
    required this.child,
    this.imageBuilder,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appBackgroundSettingsProvider);
    final theme = Theme.of(context);
    final hasImage = settings.enabled && File(settings.imagePath!).existsSync();
    final scrim = theme.brightness == Brightness.dark
        ? Colors.black.withValues(alpha: 0.62)
        : theme.colorScheme.surface.withValues(alpha: 0.68);

    return ColoredBox(
      key: const Key('player-glass-route-base'),
      color: theme.colorScheme.surface,
      child: Stack(
        key: const Key('player-glass-route-surface'),
        fit: StackFit.expand,
        children: [
          if (hasImage)
            Positioned.fill(
              child: ImageFiltered(
                key: const Key('player-glass-background-blur'),
                imageFilter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                child: AppBackgroundImageLayer(
                  settings: settings,
                  positioned: false,
                  imageBuilder: imageBuilder,
                ),
              ),
            ),
          if (hasImage)
            IgnorePointer(
              child: ColoredBox(
                key: const Key('player-glass-route-scrim'),
                color: scrim,
              ),
            ),
          SizedBox.expand(child: child),
        ],
      ),
    );
  }
}
