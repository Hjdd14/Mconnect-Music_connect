import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' show
    GlassContainer,
    GlassQuality,
    LiquidGlassSettings;

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

  /// Whether to dim the background image.
  ///
  /// Defaults to true, which is what the app-level shell wants. A *route-level*
  /// shell sets it to false: the app-level shell already paints the scrim, and
  /// applying it twice would make every secondary page darker than the home tab.
  final bool drawScrim;

  /// Whether this shell paints the background **image**.
  ///
  /// Defaults to true, which is the app-level shell. Route-level shells set it to
  /// false and contribute only an opaque base.
  ///
  /// The image used to be painted at every level — the app shell, each route page
  /// and the player surface — and `appBackgroundImageGeometry` scales it to fit
  /// whichever viewport it is given. Those viewports genuinely differ (the app
  /// shell covers the whole `MaterialApp.router`, including the Scaffold's bottom
  /// inset, while a route shell covers only the routed content), so the image was
  /// drawn several times at several scales: the "重复 / 缩小 / 黑边" the user
  /// reported. One image, painted once, at a known size, is the fix.
  final bool drawImage;

  /// Opacity of the opaque base below the content.
  ///
  /// 1.0 for the app-level shell. A route shell uses slightly less so the
  /// app-level image shows through it — that is what keeps the custom background
  /// visible on every page while still masking the page *below* during a
  /// transition. High enough (0.88) that the content underneath is not readable.
  final double baseOpacity;

  const AppBackgroundShell({
    super.key,
    required this.child,
    this.imageBuilder,
    this.drawScrim = true,
    this.drawImage = true,
    this.baseOpacity = 1,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appBackgroundSettingsProvider);
    final theme = Theme.of(context);
    final scrim = theme.brightness == Brightness.dark
        ? Colors.black.withValues(alpha: 0.48)
        : theme.colorScheme.surface.withValues(alpha: 0.72);
    final showImage = drawImage && settings.enabled;

    return ColoredBox(
      // The base is what masks the page below during a transition. With
      // `drawImage: false` there is no image layer on top of it, so it must be
      // semi-transparent for the app-level image to remain visible.
      color: theme.colorScheme.surface.withValues(alpha: baseOpacity),
      child: Stack(
        children: [
          if (drawImage)
            AppBackgroundImageLayer(
              settings: settings,
              imageBuilder: imageBuilder,
            ),
          if (showImage && drawScrim)
            Positioned.fill(
              child: IgnorePointer(child: ColoredBox(color: scrim)),
            ),
          child,
        ],
      ),
    );
  }
}

/// Acrylic parameters for [SecondaryGlassSurface], as constants so a test can
/// assert them without reaching into a private widget.
///
/// ## Why acrylic rather than liquid glass
///
/// The liquid-glass outline on this surface could **not** be removed through the
/// package's public API. Traced through `liquid_glass_widgets` 1.7.2:
///
/// * the rim is drawn from `GlassEffect`'s own fields — `rimThickness` (default
///   `0.5`), `rimSmoothing` (default `1.5`) and `edgeAlphaMultiplier` (default
///   `0.4`) — see `glass_effect.dart`, and for `GlassQuality.standard` the rim is
///   *forced* to `rimThickness * 0.35`;
/// * none of those are fields of `LiquidGlassSettings`, and `GlassContainer` does
///   not expose them either (no `rimThickness` anywhere in `glass_container.dart`);
///   neither does `LightweightLiquidGlass`.
///
/// So zeroing `lightIntensity`, `fresnelStrength` and `glowIntensity` — which is
/// what an earlier attempt did — leaves the rim untouched, because the rim is not
/// painted by those uniforms.
///
/// Acrylic removes the problem by construction: a [BackdropFilter] only blurs and
/// tints. There is **no edge-drawing code**, so there is nothing to disable.
///
/// Bonus: it needs no shader, so Windows behaves exactly like Android instead of
/// falling back.
abstract final class AcrylicSettings {
  /// Blur radius. This, not the tint, is what keeps text legible over the picture.
  static const double sigma = 20;

  /// Fill opacity. Deliberately light so the user's background reads through —
  /// the previous 0.9 fill was what made it invisible.
  static const double fillAlpha = 0.13;
}

/// An acrylic sheet laid over the background on secondary pages.
///
/// Sits **below** the page content, which works because the app's `Scaffold`s are
/// transparent (`app_theme.dart` sets `scaffoldBackgroundColor` to
/// `Colors.transparent`) — so the sheet reads as something the content sits on,
/// rather than something painted over it.
///
/// It blurs what is behind it. With a custom background that is the user's picture;
/// with a plain colour it is the app's opaque base layer, where the blur is a no-op
/// and the sheet is effectively a light scrim. **It is applied either way on
/// purpose**: the two cases used to diverge, and "no background configured" was the
/// only configuration where a page could still show through during a transition.
/// One path means one behaviour to reason about.
///
/// ## It also does the masking during a route transition
///
/// Because it sits above the route backing and is always on, whatever is left
/// un-covered while a page slides in is blurred and dimmed by this sheet rather than
/// showing the previous page. That is why the route backing does **not** need to
/// turn opaque mid-transition — and why an opaque backing was a mistake: being a flat
/// colour, it blanked the user's background for the whole animation and produced a
/// solid-colour flash.
///
/// **So this layer carries two jobs.** Weakening it — a smaller `fillAlpha`, a
/// smaller `sigma`, or making it conditional again — brings the leftover content
/// back. Change it with that in mind.
///
/// When there is nothing useful to blur — reduced motion — the layer falls back to a
/// plain scrim. Returning the child bare would leave text sitting directly on the
/// picture.
class SecondaryGlassSurface extends ConsumerWidget {
  final Widget child;

  const SecondaryGlassSurface({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reducedMotion = MediaQuery.disableAnimationsOf(context);

    if (reducedMotion) {
      // Nothing to blur for a user who asked for less motion, and a live backdrop
      // filter is real per-frame work — so dim instead.
      return ColoredBox(
        key: const Key('secondary-glass-surface-fallback'),
        color: Theme.of(
          context,
        ).colorScheme.surface.withValues(alpha: 0.6),
        child: child,
      );
    }

    return ClipRect(
      key: const Key('secondary-acrylic-surface'),
      // `ClipRect` is required: an unclipped `BackdropFilter` samples and paints
      // beyond its parent's bounds.
      child: BackdropFilter(
        // The whole point of acrylic: blur and a light tint, and nothing else. No
        // shader, no rim, no bevel, no shadow.
        filter: ImageFilter.blur(
          sigmaX: AcrylicSettings.sigma,
          sigmaY: AcrylicSettings.sigma,
        ),
        child: ColoredBox(
          color: Theme.of(
            context,
          ).colorScheme.surface.withValues(alpha: AcrylicSettings.fillAlpha),
          child: child,
        ),
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
      child: Material(
        // `liquid_glass_widgets` imports only `flutter/widgets.dart` and installs no
        // `Material` ancestor, while the app injects one only under
        // `UiStyle.miuix` (see `MconnectApp.buildGlassShell`). Installing it here,
        // locally, keeps any text under the glass from painting Flutter's yellow
        // double-underline debug decoration without wrapping the whole app — which
        // would change the Material element tree and break invariant I-8.
        type: MaterialType.transparency,
        child: Stack(
          key: const Key('player-glass-route-surface'),
          fit: StackFit.expand,
          children: [
            if (hasImage)
              Positioned.fill(
                child: ImageFiltered(
                  key: const Key('player-glass-background-blur'),
                  // Softer than the original 24: the liquid-glass layer above adds
                  // its own blur and refraction, and pre-blurring hard made the
                  // result read as a flat haze with no depth.
                  imageFilter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
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
            // Liquid glass over the whole route. The artwork stays *below* it, which
            // is what lets the package sample and refract the real backdrop instead
            // of a flat colour — the difference between this and the plain
            // `ImageFiltered` blur it replaces.
            //
            // Standalone-safe: `InheritedLiquidGlass.of` and `LiquidGlassScope.of`
            // both return null when no `LiquidGlassWidgets.wrap` ancestor exists, so
            // this works on the player route regardless of the app's UI style. Its
            // shader path also degrades internally when
            // `ImageFilter.isShaderFilterSupported` is false (Windows, and the test
            // environment), so no platform branch is needed here.
            Positioned.fill(
              child: IgnorePointer(
                child: GlassContainer(
                  key: const Key('player-glass-liquid-layer'),
                  // Explicit quality: `resolveQuality` falls back to `premium` when
                  // this is null, which would be far more expensive than the page
                  // needs (阶段 C 已确认该 fallback 行为).
                  quality: GlassQuality.standard,
                  useOwnLayer: true,
                  settings: const LiquidGlassSettings(
                    thickness: 18,
                    blur: 6,
                    chromaticAberration: 0.02,
                    lightIntensity: 0.5,
                    saturation: 1.1,
                  ),
                ),
              ),
            ),
            SizedBox.expand(child: child),
          ],
        ),
      ),
    );
  }
}
