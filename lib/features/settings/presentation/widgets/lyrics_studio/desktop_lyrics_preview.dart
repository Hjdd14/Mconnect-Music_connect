import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:mconnect/core/lyrics/lyrics_animation_catalog.dart';
import 'package:mconnect/core/lyrics/lyrics_overlay_config.dart';
import 'package:mconnect/core/lyrics/lyrics_overlay_sink.dart';

/// Flutter-side preview of what the native window paints.
///
/// Semantics mirror docs/desktop-lyrics-protocol.md: the line changes with the
/// configured animation, the already-sung part of the line is highlighted, and
/// the window itself enters with the configured window animation. It is a
/// preview, not the renderer: Reduce Motion collapses every animation to a
/// no-op exactly like the native side does.
class DesktopLyricsPreview extends StatefulWidget {
  const DesktopLyricsPreview({
    super.key,
    required this.config,
    required this.lines,
    this.previewToken = 0,
    this.autoPlay = true,
    this.height = 150,
  });

  final LyricsOverlayConfig config;
  final List<LyricsPreviewLine> lines;

  /// Changing this replays the window animation.
  final int previewToken;

  /// Tests turn this off so no ticker keeps running.
  final bool autoPlay;

  final double height;

  @override
  State<DesktopLyricsPreview> createState() => _DesktopLyricsPreviewState();
}

class _DesktopLyricsPreviewState extends State<DesktopLyricsPreview>
    with SingleTickerProviderStateMixin {
  static const Duration _advanceInterval = Duration(milliseconds: 2400);

  late final AnimationController _advance = AnimationController(
    vsync: this,
    duration: _advanceInterval,
  )..addStatusListener(_onAdvanceStatus);

  int _index = 0;

  @override
  void initState() {
    super.initState();
    _syncPlayback();
  }

  @override
  void didUpdateWidget(covariant DesktopLyricsPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.previewToken != widget.previewToken ||
        oldWidget.config.surface != widget.config.surface) {
      _index = 0;
    }
    if (oldWidget.autoPlay != widget.autoPlay ||
        oldWidget.config.reduceMotion != widget.config.reduceMotion ||
        oldWidget.previewToken != widget.previewToken) {
      _syncPlayback();
    }
  }

  @override
  void dispose() {
    _advance.dispose();
    super.dispose();
  }

  void _onAdvanceStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || !mounted) return;
    setState(() {
      _index = (_index + 1) % math.max(1, widget.lines.length);
    });
    _syncPlayback();
  }

  void _syncPlayback() {
    if (!widget.autoPlay ||
        widget.config.reduceMotion ||
        widget.lines.length < 2) {
      _advance.stop();
      return;
    }
    _advance.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final lines = widget.lines;
    if (lines.isEmpty) return const SizedBox.shrink();
    final index = _index % lines.length;
    final current = lines[index];
    final next = lines[(index + 1) % lines.length];

    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: AnimatedSwitcher(
        duration: widget.config.reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 260),
        switchInCurve: LyricsAnimationCatalog.curveFor(widget.config.easing),
        transitionBuilder: (child, animation) =>
            _windowTransition(widget.config.windowAnimation, child, animation),
        child: KeyedSubtree(
          key: ValueKey<int>(widget.previewToken),
          child: _screenSurface(context, current, next),
        ),
      ),
    );
  }

  Widget _screenSurface(
    BuildContext context,
    LyricsPreviewLine current,
    LyricsPreviewLine next,
  ) {
    final config = widget.config;
    final radius = BorderRadius.circular(config.cornerRadius);
    final isTaskbar = config.surface == LyricsSurface.taskbar;
    return Container(
      key: const ValueKey<String>('desktop-lyrics-preview-surface'),
      alignment: Alignment.center,
      padding: EdgeInsets.symmetric(
        horizontal: config.padding,
        vertical: isTaskbar ? 4 : config.padding * 0.5,
      ),
      decoration: BoxDecoration(
        color: _backgroundColor(config),
        gradient: _backgroundGradient(config),
        borderRadius: radius,
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.12),
          width: 0.6,
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: isTaskbar
            ? _taskbarLines(context, current)
            : _floatingLines(context, current, next),
      ),
    );
  }

  Color _backgroundColor(LyricsOverlayConfig config) {
    if (config.backgroundMode == LyricsBackgroundMode.solid ||
        config.backgroundMode == LyricsBackgroundMode.gradient ||
        config.backgroundMode == LyricsBackgroundMode.cover) {
      return withPreviewOpacity(config.backgroundColor, config);
    }
    return Colors.transparent;
  }

  Gradient? _backgroundGradient(LyricsOverlayConfig config) {
    if (config.backgroundMode == LyricsBackgroundMode.gradient ||
        config.backgroundMode == LyricsBackgroundMode.cover) {
      return LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: <Color>[
          withPreviewOpacity(config.backgroundColor, config),
          withPreviewOpacity(config.backgroundColor2, config),
        ],
      );
    }
    return null;
  }

  Widget _floatingLines(
    BuildContext context,
    LyricsPreviewLine current,
    LyricsPreviewLine next,
  ) {
    final config = widget.config;
    final children = <Widget>[
      _highlightedLine(context, current.text, fontSize: config.fontSize),
    ];
    final translation = current.translation;
    final hasTranslation =
        translation != null &&
        translation.trim().isNotEmpty &&
        config.showTranslation != LyricsTranslationVisibility.never;

    switch (config.lineMode) {
      case LyricsLineMode.currentOnly:
        break;
      case LyricsLineMode.currentAndTranslation:
        if (hasTranslation) {
          children.add(_plainLine(context, translation, dim: true));
        }
      case LyricsLineMode.currentAndNext:
        children.add(_plainLine(context, next.text, dim: true));
      case LyricsLineMode.threeLines:
        if (hasTranslation) {
          children.add(_plainLine(context, translation, dim: true));
        }
        children.add(_plainLine(context, next.text, dim: true));
      case LyricsLineMode.auto:
        if (hasTranslation) {
          children.add(_plainLine(context, translation, dim: true));
        } else {
          children.add(_plainLine(context, next.text, dim: true));
        }
    }

    return AnimatedSwitcher(
      duration: _lineDuration(config),
      switchInCurve: LyricsAnimationCatalog.curveFor(config.easing),
      switchOutCurve: LyricsAnimationCatalog.curveFor(config.easing),
      transitionBuilder: (child, animation) => _lineTransition(
        LyricsAnimationCatalog.resolve(config.lineAnimation, seed: _index),
        child,
        animation,
      ),
      child: KeyedSubtree(
        key: ValueKey<int>(_index),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: _crossAxisAlignment(config.textAlign),
          children: children,
        ),
      ),
    );
  }

  Widget _taskbarLines(BuildContext context, LyricsPreviewLine current) {
    final config = widget.config;
    final line = _highlightedLine(
      context,
      current.text,
      fontSize: config.fontSize,
    );
    final translation = current.translation;
    final showTranslation =
        config.translationLayout != LyricsTranslationLayout.hidden &&
        translation != null &&
        translation.trim().isNotEmpty;
    if (!showTranslation) {
      return AnimatedSwitcher(
        duration: _lineDuration(config),
        transitionBuilder: (child, animation) => _lineTransition(
          LyricsAnimationCatalog.resolve(config.lineAnimation, seed: _index),
          child,
          animation,
        ),
        child: KeyedSubtree(key: ValueKey<int>(_index), child: line),
      );
    }
    final translationWidget = _plainLine(context, translation, dim: true);
    return AnimatedSwitcher(
      duration: _lineDuration(config),
      transitionBuilder: (child, animation) => _lineTransition(
        LyricsAnimationCatalog.resolve(config.lineAnimation, seed: _index),
        child,
        animation,
      ),
      child: KeyedSubtree(
        key: ValueKey<int>(_index),
        child: config.translationLayout == LyricsTranslationLayout.inline
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Flexible(child: line),
                  const SizedBox(width: 8),
                  Flexible(child: translationWidget),
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[line, translationWidget],
              ),
      ),
    );
  }

  Widget _highlightedLine(
    BuildContext context,
    String text, {
    required double fontSize,
  }) {
    final config = widget.config;
    final baseColor = Color(config.textColor);
    final style = _textStyle(config, fontSize: fontSize, color: baseColor);
    if (!config.wordHighlight ||
        config.highlightColor == config.textColor ||
        text.isEmpty) {
      return Text(text, style: style, textAlign: config.textAlign.textAlign);
    }
    // A fixed 55% sweep shows both halves of the gradient without a ticker;
    // the native window animates the same boundary from highlightProgress.
    const fraction = 0.55;
    final highlight = Color(config.highlightColor);
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (Rect bounds) {
        return LinearGradient(
          colors: <Color>[highlight, highlight, baseColor, baseColor],
          stops: const <double>[0, fraction, fraction, 1],
        ).createShader(bounds);
      },
      child: Text(text, style: style, textAlign: config.textAlign.textAlign),
    );
  }

  Widget _plainLine(BuildContext context, String text, {required bool dim}) {
    final config = widget.config;
    final color = Color(config.textColor).withValues(alpha: dim ? 0.62 : 1);
    return Text(
      text,
      style: _textStyle(config, fontSize: config.fontSize * 0.72, color: color),
      textAlign: config.textAlign.textAlign,
    );
  }

  TextStyle _textStyle(
    LyricsOverlayConfig config, {
    required double fontSize,
    required Color color,
  }) {
    return TextStyle(
      fontFamily: config.fontFamily.isEmpty ? null : config.fontFamily,
      fontSize: fontSize,
      fontWeight: _fontWeight(config.fontWeight),
      letterSpacing: config.letterSpacing,
      height: config.lineHeight,
      color: color,
      shadows: config.shadowOpacity <= 0
          ? null
          : <Shadow>[
              Shadow(
                color: Color(config.strokeColor)
                    .withValues(alpha: config.shadowOpacity),
                blurRadius: config.shadowBlur,
              ),
            ],
    );
  }

  Duration _lineDuration(LyricsOverlayConfig config) {
    if (config.reduceMotion) return Duration.zero;
    return Duration(milliseconds: config.animationDurationMs);
  }

  static CrossAxisAlignment _crossAxisAlignment(LyricsTextAlignment align) {
    return switch (align) {
      LyricsTextAlignment.left => CrossAxisAlignment.start,
      LyricsTextAlignment.center => CrossAxisAlignment.center,
      LyricsTextAlignment.right => CrossAxisAlignment.end,
    };
  }

  static FontWeight _fontWeight(int weight) {
    final index = (weight / 100).round().clamp(1, 9) - 1;
    return FontWeight.values[index];
  }

  static Color withPreviewOpacity(int argb, LyricsOverlayConfig config) {
    final base = Color(argb);
    return base.withValues(
      alpha: (base.a * config.backgroundOpacity).clamp(0.0, 1.0),
    );
  }

  Widget _lineTransition(
    LyricsLineTransition transition,
    Widget child,
    Animation<double> animation,
  ) {
    switch (transition) {
      case LyricsLineTransition.none:
        return child;
      case LyricsLineTransition.fade:
        return FadeTransition(opacity: animation, child: child);
      case LyricsLineTransition.fadeThrough:
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.92, end: 1).animate(animation),
            child: child,
          ),
        );
      case LyricsLineTransition.slideLeft:
        return _slide(child, animation, const Offset(0.35, 0));
      case LyricsLineTransition.slideRight:
        return _slide(child, animation, const Offset(-0.35, 0));
      case LyricsLineTransition.slideUp:
        return _slide(child, animation, const Offset(0, 0.6));
      case LyricsLineTransition.slideDown:
        return _slide(child, animation, const Offset(0, -0.6));
      case LyricsLineTransition.pushLeft:
        return _slide(child, animation, const Offset(1, 0));
      case LyricsLineTransition.pushRight:
        return _slide(child, animation, const Offset(-1, 0));
      case LyricsLineTransition.scaleIn:
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.55, end: 1).animate(animation),
            child: child,
          ),
        );
      case LyricsLineTransition.scaleOut:
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 1.35, end: 1).animate(animation),
            child: child,
          ),
        );
      case LyricsLineTransition.wipeLeft:
        return ClipRect(
          child: Align(
            alignment: Alignment.centerLeft,
            widthFactor: animation.value.clamp(0.0, 1.0),
            child: child,
          ),
        );
      case LyricsLineTransition.wipeRight:
        return ClipRect(
          child: Align(
            alignment: Alignment.centerRight,
            widthFactor: animation.value.clamp(0.0, 1.0),
            child: child,
          ),
        );
      case LyricsLineTransition.flipX:
        return FadeTransition(
          opacity: animation,
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.0015)
              ..rotateY((1 - animation.value) * math.pi / 2),
            child: child,
          ),
        );
      case LyricsLineTransition.flipY:
        return FadeTransition(
          opacity: animation,
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.0015)
              ..rotateX((1 - animation.value) * math.pi / 2),
            child: child,
          ),
        );
      case LyricsLineTransition.dropBounce:
        return SlideTransition(
          position:
              Tween<Offset>(
                begin: const Offset(0, -0.4),
                end: Offset.zero,
              ).animate(
                CurvedAnimation(parent: animation, curve: Curves.bounceOut),
              ),
          child: child,
        );
      case LyricsLineTransition.springUp:
        return SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 0.5), end: Offset.zero)
              .animate(
                CurvedAnimation(parent: animation, curve: Curves.elasticOut),
              ),
          child: child,
        );
      case LyricsLineTransition.glowSoft:
        return FadeTransition(
          opacity: animation,
          child: DecoratedBox(
            decoration: BoxDecoration(
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: Color(widget.config.highlightColor)
                      .withValues(alpha: 0.45 * animation.value),
                  blurRadius: 22 * animation.value,
                  spreadRadius: 2 * animation.value,
                ),
              ],
            ),
            child: child,
          ),
        );
      case LyricsLineTransition.random:
        return _lineTransition(
          LyricsAnimationCatalog.resolve(
            LyricsLineTransition.random,
            seed: _index,
          ),
          child,
          animation,
        );
    }
  }

  Widget _slide(Widget child, Animation<double> animation, Offset begin) {
    return SlideTransition(
      position: Tween<Offset>(
        begin: begin,
        end: Offset.zero,
      ).animate(animation),
      child: child,
    );
  }

  Widget _windowTransition(
    LyricsWindowTransition transition,
    Widget child,
    Animation<double> animation,
  ) {
    switch (transition) {
      case LyricsWindowTransition.none:
        return child;
      case LyricsWindowTransition.fade:
        return FadeTransition(opacity: animation, child: child);
      case LyricsWindowTransition.slideFromTop:
        return _slide(child, animation, const Offset(0, -1));
      case LyricsWindowTransition.slideFromBottom:
        return _slide(child, animation, const Offset(0, 1));
      case LyricsWindowTransition.slideFromLeft:
        return _slide(child, animation, const Offset(-1, 0));
      case LyricsWindowTransition.slideFromRight:
        return _slide(child, animation, const Offset(1, 0));
      case LyricsWindowTransition.pop:
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.85, end: 1).animate(animation),
            child: child,
          ),
        );
    }
  }
}
