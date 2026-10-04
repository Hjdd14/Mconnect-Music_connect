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

/// The scale and offset an editor `TransformationController` matrix encodes.
///
/// ## Why this exists
///
/// The editor used to let `InteractiveViewer` render its own matrix, and that is
/// **not** how this file renders a background: `Transform.scale` in
/// [AppBackgroundImageCanvas] anchors at the viewport *centre* — that is its
/// Flutter default `alignment` — while `InteractiveViewer` passes a null
/// alignment and therefore anchors at the child's top-left. The two differ by
/// `(1 - scale) * centre`, so a zoomed preview sat up-left of the picture the app
/// actually painted: the user had to drag up-left to compensate, and the saved
/// position then stayed wrong by that same amount.
///
/// The editor preview and the dialog's 保存 action both read the matrix through
/// this function, and the preview renders it with [AppBackgroundImageCanvas] —
/// the widget the app shell itself uses — so the two cannot drift apart again.
///
/// Read it as the inverse of [appBackgroundMatrixFromTransform].
({double scale, Offset offset}) appBackgroundTransformFromMatrix(
  Matrix4 matrix,
) {
  return (
    scale: matrix.getMaxScaleOnAxis().clamp(1, 4).toDouble(),
    offset: Offset(matrix.storage[12], matrix.storage[13]),
  );
}

/// Builds the matrix that [appBackgroundTransformFromMatrix] reads back.
Matrix4 appBackgroundMatrixFromTransform({
  required double scale,
  required Offset offset,
}) {
  return Matrix4.identity()
    ..translateByDouble(offset.dx, offset.dy, 0, 1)
    ..scaleByDouble(scale, scale, 1, 1);
}

/// The one viewport every layer that paints the user's picture must agree on.
///
/// ## Why this exists
///
/// The app-level shell paints the picture once, full screen. A secondary page
/// paints its own **frosted** copy of that same picture (see
/// [SecondaryGlassSurface]) and the two must land on exactly the same pixels —
/// otherwise the background visibly shrinks or grows black bars the moment a
/// page is pushed, which is the "重复 / 缩小 / 黑边" defect reported twice before.
///
/// They cannot be allowed to each measure themselves and hope they agree: a
/// routed page's box has historically been **smaller than the screen**
/// (`MiuixBottomStack` used to inset the routed content by the mini-player
/// clearance), and `appBackgroundImageGeometry` scales the picture to whichever
/// viewport it is handed — so a route-level measurement would silently shrink the
/// picture. That was the "重复 / 缩小 / 黑边" defect, reported twice.
///
/// So the app-level shell measures itself once and publishes it here, and every
/// other painter lays itself out at **this** size instead of at its own — see the
/// `OverflowBox` in [SecondaryGlassSurface]. One measurement, one geometry, so the
/// two copies cannot drift. Same principle 阶段 Q applied to the editor preview:
/// make it impossible to have two implementations of one transform.
///
/// The two sizes coincide today (the bottom clearance moved inside the routes —
/// `RouteBottomInset`), which makes the `OverflowBox` an identity. It stays as a
/// guard: the cheap thing to do is publish a measurement, the expensive thing is to
/// re-discover why an inset around a navigator breaks the background.
///
/// Only [AppBackgroundShell] with `drawImage: true` installs this. A route-level
/// shell wraps *inside* the app-level one, so if it published its own (inset)
/// measurements it would shrink every frosted plate to the routed content area.
class AppBackgroundViewport extends InheritedWidget {
  final Size size;

  const AppBackgroundViewport({
    super.key,
    required this.size,
    required super.child,
  });

  /// The published viewport, or `null` when there is no app-level shell above.
  static Size? maybeOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<AppBackgroundViewport>()
          ?.size;

  @override
  bool updateShouldNotify(AppBackgroundViewport oldWidget) =>
      oldWidget.size != size;
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

    final stack = Stack(
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
    );

    return ColoredBox(
      // The base is what masks the page below during a transition. With
      // `drawImage: false` there is no image layer on top of it, so it must be
      // semi-transparent for the app-level image to remain visible.
      color: theme.colorScheme.surface.withValues(alpha: baseOpacity),
      child: drawImage
          // Only the app-level shell publishes the viewport — see
          // [AppBackgroundViewport] for why a route-level shell must not.
          ? LayoutBuilder(
              builder: (context, constraints) {
                // Defensive: an unbounded shell (an unusual embedding, or a test
                // harness) has no meaningful "biggest", so fall back to the
                // window rather than publishing infinity to every plate.
                final size =
                    constraints.hasBoundedWidth &&
                        constraints.hasBoundedHeight
                    ? constraints.biggest
                    : MediaQuery.sizeOf(context);
                return AppBackgroundViewport(size: size, child: stack);
              },
            )
          : stack,
    );
  }
}

/// Frosted-sheet parameters for [SecondaryGlassSurface], as constants so a test
/// can assert them without reaching into a private widget.
///
/// ## The name describes the look, not the mechanism
///
/// This used to be a real acrylic: a `BackdropFilter` blurring the live scene.
/// It is not any more, and the name is kept only because "acrylic" is the visual
/// idiom the user asked for. The mechanism is now **self-contained** — see
/// [SecondaryGlassSurface]. Do not "restore" a `BackdropFilter` here without
/// re-reading that doc comment: it is exactly what caused the ghost.
abstract final class AcrylicSettings {
  /// Blur radius applied to the sheet's *own* copy of the picture.
  ///
  /// This, not the tint, is what keeps text legible over the picture.
  static const double sigma = 20;

  /// Fill opacity. Deliberately light so the user's background reads through —
  /// a heavy fill hides it, which is the whole point of setting one.
  ///
  /// No longer load-bearing for masking: masking is structural now (the sheet
  /// paints an opaque floor), so this can stay purely cosmetic. It used to be
  /// the only thing standing between the user and the previous page's text,
  /// which is why it could never be lowered.
  static const double fillAlpha = 0.13;
}

/// The frosted sheet laid over the background on secondary pages.
///
/// Sits **below** the page content, which works because the app's `Scaffold`s are
/// transparent (`app_theme.dart` sets `scaffoldBackgroundColor` to
/// `Colors.transparent`) — so the sheet reads as something the content sits on,
/// rather than something painted over it.
///
/// ## Why it is self-contained, and not a `BackdropFilter`
///
/// A `BackdropFilter` filters *the existing painted content* — "if there's no
/// clip, the filter will be applied to the full screen" — so its input is not
/// "the page underneath" but **the whole composited scene at that point in the
/// paint order**. During a route transition the outgoing route is still painted:
/// `TransitionRoute._handleStatusChanged` forces
/// `overlayEntries.first.opaque = false` for the entire `forward`/`reverse`
/// window and only restores it on `completed`, so the page below is
/// *deliberately* still in the scene while the new page slides in.
///
/// The result was the "白影": the previous page's white text landed inside the
/// blur and got smeared into a ghost that could be seen *through* the sheet. The
/// tint could not remove it — alpha compositing is linear, so one fill scales the
/// text's contrast and the picture's contrast by the same factor. Raising it far
/// enough to erase white text also flattens the picture. That is why the two
/// requirements were unsolvable while the sheet read the live scene.
///
/// So the sheet no longer reads the scene at all. It paints **its own copy of the
/// user's picture**, blurred, over an **opaque floor**:
///
/// ```text
/// ColoredBox(surface)                     <- opaque floor: nothing below can show
///   Stack
///     ClipRect > OverflowBox(appViewport) <- clip to this route; lay the picture
///       RepaintBoundary > ImageFiltered     out at the app-level size
///         AppBackgroundImageLayer
///     ColoredBox(surface @ fillAlpha)      <- the tint, unchanged
///     child                                <- page content
/// ```
///
/// Because no filter samples anything the framework painted, **no other route can
/// reach this sheet** — the ghost is impossible rather than merely faint. And
/// because the floor is opaque while the picture is still painted, "opaque" no
/// longer means "the background disappears": the sheet *is* the background.
///
/// Related: Flutter's own `FadeForwardsPageTransitionsBuilder` reaches the same
/// shape from the other side — for an opaque route it hides the outgoing page via
/// its `secondaryAnimation` and paints a plate behind it while the transition
/// runs (gated on `ModalRoute.opaqueOf` after flutter/flutter#167032). The plate
/// there is a flat colour, which is precisely why it loses the wallpaper and why
/// this sheet paints the picture instead.
///
/// ## The geometry is pinned, not hoped for
///
/// The sheet takes its size from [AppBackgroundViewport] — measured by the
/// app-level shell — and `OverflowBox` gives [AppBackgroundImageLayer] exactly
/// those constraints, so the app-level copy and this one compute identical
/// [appBackgroundImageGeometry] values from identical inputs.
///
/// Today those two sizes coincide: the sheet's own box *is* the screen, because
/// the bottom clearance now lives inside each route (`RouteBottomInset`) instead
/// of being a `Padding` around go_router's nested Navigator — see
/// `MiuixBottomStack.insetChild`. The `OverflowBox` is therefore currently an
/// identity. **Keep it anyway**: it is what makes the picture immune to a
/// re-introduced inset, and an inset around a navigator is exactly the bug this
/// round fixed (a band no route can paint into). The failure it guards against is
/// the "重复 / 缩小 / 黑边" that has been reported twice.
///
/// `test/secondary_plate_geometry_test.dart` asserts both halves: the sheet spans
/// the whole viewport, and the app-level and sheet copies land on the same `Rect`.
/// Keep that test green before trusting a change here.
///
/// ## Do not
///
/// * **Do not reintroduce a `BackdropFilter`** (or a `GlassContainer`, whose rim
///   could not be removed through the package API — see 阶段 M). Both make the
///   ghost possible again.
/// * **Do not drop the opaque floor.** It is what stops the page below from
///   compositing through, in both the push and the pop direction.
/// * **Do not weaken the fill expecting the blur to cover for it.** The blur is no
///   longer a mask; it is a look.
/// * **Do not put a `Padding` around the navigator that holds these pages.** It
///   creates a band no route can paint into, so this sheet cannot reach the bottom
///   edge and the capsule area stays sharp while the page slides away.
class SecondaryGlassSurface extends ConsumerWidget {
  final Widget child;

  /// Optional picture override, so tests can render the sheet without a real
  /// file on disk (`AppBackgroundShell` and `PlayerGlassRouteSurface` take the
  /// same hook).
  final Widget Function(File file)? imageBuilder;

  const SecondaryGlassSurface({
    super.key,
    required this.child,
    this.imageBuilder,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appBackgroundSettingsProvider);
    final theme = Theme.of(context);
    final file = settings.enabled ? File(settings.imagePath!) : null;
    final paintsPicture = file != null && file.existsSync();
    final viewport =
        AppBackgroundViewport.maybeOf(context) ?? MediaQuery.sizeOf(context);

    return ColoredBox(
      // The opaque floor. Masking is structural: whatever is painted below this
      // point — including the outgoing route for the whole push/pop window —
      // cannot contribute a single pixel to what the user sees.
      key: const Key('secondary-acrylic-base'),
      color: theme.colorScheme.surface,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (paintsPicture && !viewport.isEmpty)
            // `ClipRect` is required twice over: `OverflowBox` does **not** clip
            // (`RenderConstrainedOverflowBox` has no `clipBehavior`), and the
            // picture deliberately overflows this route's box because it is laid
            // out at the app-level viewport.
            ClipRect(
              child: OverflowBox(
                // The routed box starts at the screen's top-left — the player
                // inset is applied at the bottom only — so top-left alignment
                // puts the picture exactly where the app-level copy is.
                alignment: Alignment.topLeft,
                minWidth: viewport.width,
                maxWidth: viewport.width,
                minHeight: viewport.height,
                maxHeight: viewport.height,
                child: RepaintBoundary(
                  child: ImageFiltered(
                    key: const Key('secondary-acrylic-frosted-image'),
                    // `ImageFiltered` blurs its *own child's* buffer, so it can
                    // never sample another route. That is the fix.
                    //
                    // `TileMode.clamp` is required: without it the blur samples
                    // past the picture's edges and leaves a soft fade along the
                    // screen borders.
                    imageFilter: ImageFilter.blur(
                      sigmaX: AcrylicSettings.sigma,
                      sigmaY: AcrylicSettings.sigma,
                      tileMode: TileMode.clamp,
                    ),
                    child: AppBackgroundImageLayer(
                      settings: settings,
                      positioned: false,
                      imageBuilder: imageBuilder,
                    ),
                  ),
                ),
              ),
            ),
          IgnorePointer(
            child: ColoredBox(
              key: const Key('secondary-acrylic-surface'),
              color: theme.colorScheme.surface.withValues(
                alpha: AcrylicSettings.fillAlpha,
              ),
            ),
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
