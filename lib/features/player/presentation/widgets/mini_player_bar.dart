import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../../core/diagnostics/diagnostics_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/miuix_bottom_layout.dart';
import '../../../../models/song.dart';
import '../providers/player_provider.dart';

/// Identifies the capsule's perimeter progress painter in tests.
const Key capsuleProgressRingKey = Key('mini-player-capsule-progress-ring');

class MiniPlayerBar extends ConsumerWidget {
  /// Renders the player as a floating glass capsule instead of the full-width
  /// Material bar.
  ///
  /// Defaults to `false`, which is the pre-existing look: the Material path
  /// (and every test that pumps this widget without the Miuix style) must stay
  /// byte-for-byte identical (I-8).
  ///
  /// The capsule is shorter and wider than the Miuix nav capsule so the two
  /// floating layers stay distinguishable; its geometry lives in
  /// [MiuixBottomLayout] so the player and the nav bar cannot drift apart.
  final bool floating;

  const MiniPlayerBar({super.key, this.floating = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final song = ref.watch(playerProvider.select((s) => s.currentSong));
    final isPlaying = ref.watch(playerProvider.select((s) => s.isPlaying));

    if (song == null) return const SizedBox.shrink();

    final position = ref.watch(playerProvider.select((s) => s.position));
    final duration = ref.watch(playerProvider.select((s) => s.duration));

    return GestureDetector(
      onTap: () {
        final from = GoRouterState.of(context).uri.toString();
        DiagnosticsService.instance.record(
          'navigation',
          'open_player_from_mini',
          data: {
            'from': from,
            'song_id': song.id,
            'platform': song.platform.name,
          },
        );
        context.push(
          Uri(path: '/player', queryParameters: {'from': from}).toString(),
        );
      },
      child: floating
          ? _buildFloatingCapsule(context, ref, song, isPlaying, position, duration)
          : _buildMaterialBar(context, ref, song, isPlaying, position, duration),
    );
  }

  /// The pre-existing full-width bar. Do not change its geometry.
  Widget _buildMaterialBar(
    BuildContext context,
    WidgetRef ref,
    Song song,
    bool isPlaying,
    Duration position,
    Duration duration,
  ) {
    return Container(
      height: 64,
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.92),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).shadowColor.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        children: [
          _buildProgress(context, position, duration, minHeight: 2),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: _buildRow(context, ref, song, isPlaying, coverSize: 44),
            ),
          ),
        ],
      ),
    );
  }

  /// The Miuix floating capsule: shorter, inset from both edges, light glass.
  ///
  /// Uses a plain [BackdropFilter] rather than `liquid_glass_widgets` on
  /// purpose: the product spec calls for a *lighter* treatment than the nav
  /// capsule, and the package's shader path is the expensive one (Impeller
  /// processes the whole screen per backdrop — see the plan's E-21/E-22).
  Widget _buildFloatingCapsule(
    BuildContext context,
    WidgetRef ref,
    Song song,
    bool isPlaying,
    Duration position,
    Duration duration,
  ) {
    final scheme = Theme.of(context).colorScheme;
    const radius = BorderRadius.all(
      Radius.circular(MiuixBottomLayout.playerHeight / 2),
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.16),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      // The blur must be clipped to the capsule exactly: an unclipped
      // BackdropFilter bleeds across the whole parent (hard constraint 1).
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 7, sigmaY: 7),
          child: ColoredBox(
            // Semi-transparent fill sits *inside* the filter, never wrapped
            // around it: an outer Opacity would introduce a save layer and
            // break `BlendMode.srcOver` (hard constraint 2).
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
            // Pinned height: the row's content is shorter than the capsule, so
            // without this the capsule collapses to its intrinsic height
            // instead of the spec'd 48 dp.
            child: SizedBox(
              height: MiuixBottomLayout.playerHeight,
              child: _CapsuleProgressRing(
                position: position,
                duration: duration,
                isPlaying: isPlaying,
                trackColor: scheme.outlineVariant.withValues(alpha: 0.55),
                progressColor: scheme.primary,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 4, 0),
                  child: _buildRow(
                    context,
                    ref,
                    song,
                    isPlaying,
                    coverSize: 32,
                    compact: true,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProgress(
    BuildContext context,
    Duration position,
    Duration duration, {
    required double minHeight,
  }) {
    return LinearProgressIndicator(
      value: duration.inMilliseconds > 0
          ? position.inMilliseconds / duration.inMilliseconds
          : 0,
      minHeight: minHeight,
      backgroundColor: Colors.transparent,
    );
  }

  Widget _buildRow(
    BuildContext context,
    WidgetRef ref,
    Song song,
    bool isPlaying, {
    required double coverSize,
    bool compact = false,
  }) {
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: song.coverUrl != null
              ? CachedNetworkImage(
                  imageUrl: song.coverUrl!,
                  width: coverSize,
                  height: coverSize,
                  memCacheWidth: (coverSize * 2).round(),
                  fit: BoxFit.cover,
                  placeholder: (_, _) => _coverPlaceholder(context, coverSize),
                  errorWidget: (_, _, _) => _coverPlaceholder(context, coverSize),
                )
              : _coverPlaceholder(context, coverSize),
        ),
        SizedBox(width: compact ? 8 : 12),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                song.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: compact ? 13 : 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                song.artistNames,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: compact ? 11 : 12,
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          icon: Icon(Icons.skip_previous, size: compact ? 22 : 28),
          visualDensity: compact ? VisualDensity.compact : null,
          constraints: compact
              ? const BoxConstraints(minWidth: 36, minHeight: 36)
              : null,
          onPressed: ref.read(playerProvider.notifier).skipToPrevious,
        ),
        IconButton(
          icon: Icon(
            isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
            size: compact ? 30 : 36,
          ),
          visualDensity: compact ? VisualDensity.compact : null,
          constraints: compact
              ? const BoxConstraints(minWidth: 36, minHeight: 36)
              : null,
          onPressed: ref.read(playerProvider.notifier).togglePlay,
        ),
        IconButton(
          icon: Icon(Icons.skip_next, size: compact ? 22 : 28),
          visualDensity: compact ? VisualDensity.compact : null,
          constraints: compact
              ? const BoxConstraints(minWidth: 36, minHeight: 36)
              : null,
          onPressed: ref.read(playerProvider.notifier).skipToNext,
        ),
      ],
    );
  }

  Widget _coverPlaceholder(BuildContext context, double size) {
    return Container(
      width: size,
      height: size,
      color: AppColors.placeholder(context),
      child: Icon(Icons.music_note, size: size * 0.45),
    );
  }
}

/// Drives the capsule's perimeter progress and keeps it moving smoothly.
///
/// The player only publishes a new `position` when its **whole second** changes
/// (`player_provider.dart`, `sec != _lastPositionSecond`), so painting the raw
/// value would make the indicator jump once per second. This interpolates between
/// those updates on a frame ticker, and snaps instead of interpolating after a
/// seek or when the platform asks for reduced motion.
class _CapsuleProgressRing extends StatefulWidget {
  final Duration position;
  final Duration duration;
  final bool isPlaying;
  final Color trackColor;
  final Color progressColor;
  final Widget child;

  const _CapsuleProgressRing({
    required this.position,
    required this.duration,
    required this.isPlaying,
    required this.trackColor,
    required this.progressColor,
    required this.child,
  });

  @override
  State<_CapsuleProgressRing> createState() => _CapsuleProgressRingState();
}

class _CapsuleProgressRingState extends State<_CapsuleProgressRing>
    with SingleTickerProviderStateMixin {
  /// Wall-clock baseline captured whenever `position` changes.
  Duration _anchorPosition = Duration.zero;
  Duration _anchorElapsed = Duration.zero;

  /// A position jump larger than this is treated as a seek, not as playback.
  static const _seekThreshold = Duration(seconds: 3);

  late final AnimationController _ticker;

  @override
  void initState() {
    super.initState();
    _anchorPosition = widget.position;
    _ticker = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
    _syncTicker();
  }

  @override
  void didUpdateWidget(_CapsuleProgressRing oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.position != oldWidget.position) {
      final delta = widget.position - _anchorPosition;
      final isSeek = delta.isNegative || delta > _seekThreshold;
      _anchorElapsed = isSeek ? Duration.zero : _elapsed;
      _anchorPosition = widget.position;
    }
    _syncTicker();
  }

  void _syncTicker() {
    // A paused indicator must not keep repainting the (blurred) capsule.
    if (widget.isPlaying && !_ticker.isAnimating) {
      _ticker.repeat();
    } else if (!widget.isPlaying && _ticker.isAnimating) {
      _ticker.stop();
    }
  }

  Duration get _elapsed => Duration(
    microseconds: (_ticker.lastElapsedDuration ?? Duration.zero).inMicroseconds,
  );

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  double get _progress {
    final total = widget.duration.inMicroseconds;
    if (total <= 0) return 0;

    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    final effective = reducedMotion || !widget.isPlaying
        ? widget.position
        : _anchorPosition + (_elapsed - _anchorElapsed);

    return effective.inMicroseconds / total;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ticker,
      builder: (context, child) {
        return CustomPaint(
          key: capsuleProgressRingKey,
          // `foregroundPainter` so the ring stays above the glass fill but the
          // content row keeps its own layer.
          foregroundPainter: _CapsuleProgressPainter(
            progress: _progress,
            isPlaying: widget.isPlaying,
            trackColor: widget.trackColor,
            progressColor: widget.progressColor,
            radius: MiuixBottomLayout.playerHeight / 2,
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// Geometry for the capsule's perimeter progress.
///
/// Public and pure so the two things that are silently easy to get wrong can be
/// asserted directly: **where** the trace starts and **how long** the perimeter
/// is. A private painter cannot be reached from a test, which is how such a bug
/// would otherwise ship.
abstract final class CapsuleProgressGeometry {
  /// Arc-length offset of the **top centre** from the path's own start point.
  ///
  /// `StadiumBorder`'s path begins at the **left-most point** (`(0, height / 2)`)
  /// and runs clockwise, so reaching the top centre means traversing the top-left
  /// cap — a quarter circle, `π·r/2` — and then half of the straight top edge,
  /// `(width - 2r) / 2`.
  ///
  /// Every plausible shortcut is wrong, which is why a test probes the real path:
  /// * `width / 2` — off by `r - π·r/4` (the mistake that reached a build);
  /// * `(width - height) / 2` — off by `π·r/2 - r/2`;
  /// * half a *perimeter* — lands on the **bottom** centre;
  /// * `0` — lands on the left edge's midpoint.
  ///
  /// Measured for a 200 × 48 stadium: the top centre is at offset 113.46, and this
  /// formula gives 113.70 (the small gap is how `PathMetric` approximates the arc).
  static double startOffsetFor(double width, double height) {
    final radius = height / 2;
    final straight = math.max(0.0, width - 2 * radius);
    return math.pi * radius / 2 + straight / 2;
  }

  /// Perimeter of a stadium of [width] × [height].
  static double perimeterFor(double width, double height) {
    final radius = height / 2;
    final straight = (width - 2 * radius).clamp(0.0, double.infinity);
    return 2 * straight + 2 * math.pi * radius;
  }
}

/// Draws the playback progress around the capsule's **perimeter**.
///
/// The linear bar this replaces had to live *inside* the capsule's `ClipRRect`, so
/// its ends were clipped away by the 24 dp corner radius. A perimeter trace cannot
/// be clipped that way, because the path *is* the capsule outline.
///
/// Geometry: the start is the **top centre**, and progress advances clockwise
/// around the stadium. Note the perimeter of a 48 dp × ~300 dp capsule is roughly
/// 700 dp — 5–9× its width — so the indicator crosses the two short ends quickly
/// and spends most of the song along the long edges. That is inherent to tracing a
/// capsule, not a timing bug.
class _CapsuleProgressPainter extends CustomPainter {
  /// 0..1; values outside are clamped.
  final double progress;

  /// Whether playback is running. When paused the indicator holds still and dims.
  final bool isPlaying;

  /// Colour of the unplayed remainder of the outline.
  final Color trackColor;

  /// Colour of the played portion.
  final Color progressColor;

  final double radius;

  const _CapsuleProgressPainter({
    required this.progress,
    required this.isPlaying,
    required this.trackColor,
    required this.progressColor,
    required this.radius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // `StadiumBorder` is the same shape the `ClipRRect` uses, so the outline
    // cannot disagree with the clip.
    final path = const StadiumBorder().getOuterPath(
      Offset.zero & size,
      textDirection: TextDirection.ltr,
    );

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..isAntiAlias = true;

    // The outline is always drawn, so the capsule's shape stays readable even at
    // 0 % — the packaged glass edge alone was too faint to read as a boundary.
    paint.color = trackColor;
    canvas.drawPath(path, paint);

    final clamped = progress.clamp(0.0, 1.0);
    if (clamped <= 0) return;

    // A metric lets the arc be described in *arc length*, which is what makes the
    // indicator advance at a constant speed along the perimeter instead of
    // sweeping at a constant angle.
    final metric = path.computeMetrics().first;
    final perimeter = metric.length;
    if (perimeter <= 0) return;

    final start = CapsuleProgressGeometry.startOffsetFor(
      size.width,
      size.height,
    ) % perimeter;
    // Deliberately not wrapped: at progress == 1 the sweep ends exactly at `start`,
    // which would become an empty segment if it were modularised.
    final sweep = clamped * perimeter;

    paint
      ..color = progressColor
      ..strokeWidth = 3;

    if (start + sweep <= perimeter) {
      canvas.drawPath(metric.extractPath(start, start + sweep), paint);
    } else {
      // Split at the path end so a full lap is still drawn contiguously from the
      // top centre, rather than being clipped to the remaining length.
      canvas.drawPath(metric.extractPath(start, perimeter), paint);
      canvas.drawPath(metric.extractPath(0, start + sweep - perimeter), paint);
    }
  }

  @override
  bool shouldRepaint(_CapsuleProgressPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.isPlaying != isPlaying ||
      oldDelegate.trackColor != trackColor ||
      oldDelegate.progressColor != progressColor;
}
