import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';

/// Which native overlay a style/frame is destined for.
///
/// Android only ever renders [floating] (its overlay is unchanged by the
/// desktop rewrite); Windows renders both.
enum LyricsSurface {
  floating('floating', '悬浮歌词'),
  taskbar('taskbar', '任务栏歌词');

  const LyricsSurface(this.id, this.label);

  /// Wire name shared with the native side.
  final String id;

  /// Chinese label used by the lyrics studio UI and diagnostics.
  final String label;

  bool get isDesktopOnly => this == LyricsSurface.taskbar;
}

/// Line-change animation ids shared with the Windows renderer.
///
/// The order and ids are part of the protocol
/// (docs/desktop-lyrics-protocol.md, section 3); the native side switches on
/// the id string, so renaming one is a breaking change.
enum LyricsLineTransition {
  none('none', '无动画'),
  fade('fade', '淡入'),
  fadeThrough('fadeThrough', '穿透淡入'),
  slideLeft('slideLeft', '左滑入'),
  slideRight('slideRight', '右滑入'),
  slideUp('slideUp', '上滑入'),
  slideDown('slideDown', '下滑入'),
  pushLeft('pushLeft', '左推挤'),
  pushRight('pushRight', '右推挤'),
  scaleIn('scaleIn', '缩放进入'),
  scaleOut('scaleOut', '缩放退出'),
  wipeLeft('wipeLeft', '左擦除'),
  wipeRight('wipeRight', '右擦除'),
  flipX('flipX', '横向翻转'),
  flipY('flipY', '纵向翻转'),
  dropBounce('dropBounce', '落下弹跳'),
  springUp('springUp', '弹性上浮'),
  glowSoft('glowSoft', '柔光'),
  random('random', '随机');

  const LyricsLineTransition(this.id, this.label);

  final String id;
  final String label;

  /// Resolves a persisted/native id, falling back to [fallback] for unknown
  /// values (a newer native build or a hand-edited Hive record).
  static LyricsLineTransition fromId(
    Object? id, {
    LyricsLineTransition fallback = LyricsLineTransition.fade,
  }) {
    if (id is! String) return fallback;
    for (final value in values) {
      if (value.id == id) return value;
    }
    return fallback;
  }
}

/// Window show/hide animation ids shared with the Windows renderer.
enum LyricsWindowTransition {
  none('none', '无动画'),
  fade('fade', '淡入'),
  slideFromTop('slideFromTop', '从上方滑入'),
  slideFromBottom('slideFromBottom', '从下方滑入'),
  slideFromLeft('slideFromLeft', '从左侧滑入'),
  slideFromRight('slideFromRight', '从右侧滑入'),
  pop('pop', '弹入');

  const LyricsWindowTransition(this.id, this.label);

  final String id;
  final String label;

  static LyricsWindowTransition fromId(
    Object? id, {
    LyricsWindowTransition fallback = LyricsWindowTransition.fade,
  }) {
    if (id is! String) return fallback;
    for (final value in values) {
      if (value.id == id) return value;
    }
    return fallback;
  }
}

/// Easing ids shared with the Windows renderer.
enum LyricsEasing {
  linear('linear', '线性'),
  easeOut('easeOut', '缓出'),
  easeInOut('easeInOut', '缓入缓出'),
  overshoot('overshoot', '过冲');

  const LyricsEasing(this.id, this.label);

  final String id;
  final String label;

  static LyricsEasing fromId(
    Object? id, {
    LyricsEasing fallback = LyricsEasing.easeOut,
  }) {
    if (id is! String) return fallback;
    for (final value in values) {
      if (value.id == id) return value;
    }
    return fallback;
  }
}

/// One pickable animation, with the metadata the lyrics studio needs.
@immutable
class LyricsAnimationOption<T> {
  const LyricsAnimationOption({
    required this.value,
    required this.surfaces,
    required this.recommendedForTaskbar,
  });

  final T value;

  /// Surfaces this animation is offered on. A taskbar is a thin strip, so the
  /// animations that need vertical room stay floating-only.
  final Set<LyricsSurface> surfaces;

  /// Whether the catalog suggests this animation for the taskbar. The picker
  /// uses it to group "recommended" before "all"; it never hides anything.
  final bool recommendedForTaskbar;

  bool get isRandom => value == LyricsLineTransition.random;

  String get id => switch (value) {
    LyricsLineTransition v => v.id,
    LyricsWindowTransition v => v.id,
    LyricsEasing v => v.id,
    _ => value.toString(),
  };

  String get label => switch (value) {
    LyricsLineTransition v => v.label,
    LyricsWindowTransition v => v.label,
    LyricsEasing v => v.label,
    _ => value.toString(),
  };

  bool supports(LyricsSurface surface) => surfaces.contains(surface);
}

/// The single source of truth for the animation ids/labels the two ends share.
///
/// 18 concrete line animations (the 19th, random, is an app-side choice rather
/// than a renderer state), 7 window animations and 4 easings - exactly the
/// lists in docs/desktop-lyrics-protocol.md, section 3.
abstract final class LyricsAnimationCatalog {
  /// Durations offered by the UI. 0 means "no animation" and is first on
  /// purpose: it is what reduceMotion degrades to.
  static const List<int> supportedDurationsMs = <int>[
    0,
    120,
    180,
    220,
    300,
    420,
  ];

  static const Set<LyricsSurface> bothSurfaces = <LyricsSurface>{
    LyricsSurface.floating,
    LyricsSurface.taskbar,
  };

  static const Set<LyricsSurface> floatingOnly = <LyricsSurface>{
    LyricsSurface.floating,
  };

  /// The 18 concrete line animations, in protocol order.
  static const List<LyricsAnimationOption<LyricsLineTransition>> lineOptions =
      <LyricsAnimationOption<LyricsLineTransition>>[
        LyricsAnimationOption(
          value: LyricsLineTransition.none,
          surfaces: bothSurfaces,
          recommendedForTaskbar: true,
        ),
        LyricsAnimationOption(
          value: LyricsLineTransition.fade,
          surfaces: bothSurfaces,
          recommendedForTaskbar: true,
        ),
        LyricsAnimationOption(
          value: LyricsLineTransition.fadeThrough,
          surfaces: bothSurfaces,
          recommendedForTaskbar: true,
        ),
        LyricsAnimationOption(
          value: LyricsLineTransition.slideLeft,
          surfaces: bothSurfaces,
          recommendedForTaskbar: true,
        ),
        LyricsAnimationOption(
          value: LyricsLineTransition.slideRight,
          surfaces: bothSurfaces,
          recommendedForTaskbar: true,
        ),
        LyricsAnimationOption(
          value: LyricsLineTransition.slideUp,
          surfaces: floatingOnly,
          recommendedForTaskbar: false,
        ),
        LyricsAnimationOption(
          value: LyricsLineTransition.slideDown,
          surfaces: floatingOnly,
          recommendedForTaskbar: false,
        ),
        LyricsAnimationOption(
          value: LyricsLineTransition.pushLeft,
          surfaces: bothSurfaces,
          recommendedForTaskbar: true,
        ),
        LyricsAnimationOption(
          value: LyricsLineTransition.pushRight,
          surfaces: bothSurfaces,
          recommendedForTaskbar: true,
        ),
        LyricsAnimationOption(
          value: LyricsLineTransition.scaleIn,
          surfaces: floatingOnly,
          recommendedForTaskbar: false,
        ),
        LyricsAnimationOption(
          value: LyricsLineTransition.scaleOut,
          surfaces: floatingOnly,
          recommendedForTaskbar: false,
        ),
        LyricsAnimationOption(
          value: LyricsLineTransition.wipeLeft,
          surfaces: bothSurfaces,
          recommendedForTaskbar: true,
        ),
        LyricsAnimationOption(
          value: LyricsLineTransition.wipeRight,
          surfaces: bothSurfaces,
          recommendedForTaskbar: true,
        ),
        LyricsAnimationOption(
          value: LyricsLineTransition.flipX,
          surfaces: floatingOnly,
          recommendedForTaskbar: false,
        ),
        LyricsAnimationOption(
          value: LyricsLineTransition.flipY,
          surfaces: floatingOnly,
          recommendedForTaskbar: false,
        ),
        LyricsAnimationOption(
          value: LyricsLineTransition.dropBounce,
          surfaces: floatingOnly,
          recommendedForTaskbar: false,
        ),
        LyricsAnimationOption(
          value: LyricsLineTransition.springUp,
          surfaces: floatingOnly,
          recommendedForTaskbar: false,
        ),
        LyricsAnimationOption(
          value: LyricsLineTransition.glowSoft,
          surfaces: floatingOnly,
          recommendedForTaskbar: false,
        ),
      ];

  /// random is offered next to the concrete 18; it is resolved to one of them
  /// before anything is sent to the native renderer.
  static const LyricsAnimationOption<LyricsLineTransition> randomOption =
      LyricsAnimationOption<LyricsLineTransition>(
        value: LyricsLineTransition.random,
        surfaces: bothSurfaces,
        recommendedForTaskbar: true,
      );

  static const List<LyricsAnimationOption<LyricsWindowTransition>>
  windowOptions = <LyricsAnimationOption<LyricsWindowTransition>>[
    LyricsAnimationOption(
      value: LyricsWindowTransition.none,
      surfaces: bothSurfaces,
      recommendedForTaskbar: true,
    ),
    LyricsAnimationOption(
      value: LyricsWindowTransition.fade,
      surfaces: bothSurfaces,
      recommendedForTaskbar: true,
    ),
    LyricsAnimationOption(
      value: LyricsWindowTransition.slideFromTop,
      surfaces: bothSurfaces,
      recommendedForTaskbar: false,
    ),
    LyricsAnimationOption(
      value: LyricsWindowTransition.slideFromBottom,
      surfaces: bothSurfaces,
      recommendedForTaskbar: true,
    ),
    LyricsAnimationOption(
      value: LyricsWindowTransition.slideFromLeft,
      surfaces: bothSurfaces,
      recommendedForTaskbar: false,
    ),
    LyricsAnimationOption(
      value: LyricsWindowTransition.slideFromRight,
      surfaces: bothSurfaces,
      recommendedForTaskbar: false,
    ),
    LyricsAnimationOption(
      value: LyricsWindowTransition.pop,
      surfaces: bothSurfaces,
      recommendedForTaskbar: false,
    ),
  ];

  static const List<LyricsAnimationOption<LyricsEasing>> easingOptions =
      <LyricsAnimationOption<LyricsEasing>>[
        LyricsAnimationOption(
          value: LyricsEasing.linear,
          surfaces: bothSurfaces,
          recommendedForTaskbar: false,
        ),
        LyricsAnimationOption(
          value: LyricsEasing.easeOut,
          surfaces: bothSurfaces,
          recommendedForTaskbar: true,
        ),
        LyricsAnimationOption(
          value: LyricsEasing.easeInOut,
          surfaces: bothSurfaces,
          recommendedForTaskbar: true,
        ),
        LyricsAnimationOption(
          value: LyricsEasing.overshoot,
          surfaces: bothSurfaces,
          recommendedForTaskbar: false,
        ),
      ];

  /// Every line animation a picker should offer for [surface], random included
  /// and last.
  static List<LyricsAnimationOption<LyricsLineTransition>> lineChoicesFor(
    LyricsSurface surface,
  ) {
    return <LyricsAnimationOption<LyricsLineTransition>>[
      ...lineOptions.where((option) => option.supports(surface)),
      if (randomOption.supports(surface)) randomOption,
    ];
  }

  static List<LyricsAnimationOption<LyricsWindowTransition>> windowChoicesFor(
    LyricsSurface surface,
  ) {
    return windowOptions
        .where((option) => option.supports(surface))
        .toList(growable: false);
  }

  static LyricsAnimationOption<LyricsLineTransition>? lineOptionFor(
    LyricsLineTransition transition,
  ) {
    for (final option in lineOptions) {
      if (option.value == transition) return option;
    }
    if (transition == LyricsLineTransition.random) return randomOption;
    return null;
  }

  static bool isRecommendedForTaskbar(LyricsLineTransition transition) {
    return lineOptionFor(transition)?.recommendedForTaskbar ?? false;
  }

  /// Clamps a duration to the nearest supported value, lowest on a tie.
  ///
  /// Used by both the setter and fromJson, so a hand-edited Hive record can
  /// never produce a duration the UI cannot represent.
  static int snapDurationMs(int value) {
    var best = supportedDurationsMs.first;
    var bestDistance = (value - best).abs();
    for (final candidate in supportedDurationsMs.skip(1)) {
      final distance = (value - candidate).abs();
      if (distance < bestDistance) {
        best = candidate;
        bestDistance = distance;
      }
    }
    return best;
  }

  /// random is resolved here and only here, so the native renderer never has
  /// to know the option exists.
  static LyricsLineTransition resolve(
    LyricsLineTransition transition, {
    int seed = 0,
  }) {
    if (transition != LyricsLineTransition.random) return transition;
    final pool = lineOptions;
    // Deterministic: the preview must not flicker between rebuilds.
    final index = seed.abs() % pool.length;
    return pool[index].value;
  }

  static Curve curveFor(LyricsEasing easing) {
    return switch (easing) {
      LyricsEasing.linear => Curves.linear,
      LyricsEasing.easeOut => Curves.easeOutCubic,
      LyricsEasing.easeInOut => Curves.easeInOutCubic,
      LyricsEasing.overshoot => Curves.easeOutBack,
    };
  }
}
