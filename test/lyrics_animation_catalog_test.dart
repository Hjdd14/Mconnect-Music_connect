import 'dart:io';

import 'package:flutter/animation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/core/lyrics/lyrics_animation_catalog.dart';

/// Pins the animation vocabulary the Dart side and the Windows renderer share.
///
/// The ids are a wire format (docs/desktop-lyrics-protocol.md, section 3): a
/// rename on one side silently falls back to the default animation on the
/// other, so both the counts and the literal ids are asserted here.
void main() {
  List<LyricsAnimationOption<dynamic>> allOptions() {
    return <LyricsAnimationOption<dynamic>>[
      ...LyricsAnimationCatalog.lineOptions,
      LyricsAnimationCatalog.randomOption,
      ...LyricsAnimationCatalog.windowOptions,
      ...LyricsAnimationCatalog.easingOptions,
    ];
  }

  test('catalog has 18 line animations plus the random choice', () {
    expect(LyricsAnimationCatalog.lineOptions, hasLength(18));
    expect(
      LyricsAnimationCatalog.lineChoicesFor(LyricsSurface.floating),
      hasLength(19),
    );
    expect(
      LyricsAnimationCatalog.lineChoicesFor(LyricsSurface.taskbar),
      hasLength(10),
    );
    expect(
      LyricsAnimationCatalog.randomOption.value,
      LyricsLineTransition.random,
    );
  });

  test('catalog has 7 window animations and 4 easings', () {
    expect(LyricsAnimationCatalog.windowOptions, hasLength(7));
    expect(LyricsAnimationCatalog.easingOptions, hasLength(4));
    expect(LyricsWindowTransition.values, hasLength(7));
    expect(LyricsEasing.values, hasLength(4));
  });

  test('every catalog id appears in the protocol document', () {
    final document = File('docs/desktop-lyrics-protocol.md').readAsStringSync();
    final start = document.indexOf('## 3.');
    final end = document.indexOf('## 4.');
    expect(start, greaterThanOrEqualTo(0), reason: '协议文档结构变了');
    expect(end, greaterThan(start), reason: '协议文档结构变了');
    final section = document.substring(start, end);

    for (final option in allOptions()) {
      expect(
        section,
        contains(option.id),
        reason: '动画 id ${option.id} 必须出现在协议第 3 节',
      );
    }
  });

  test('labels are unique per animation family', () {
    void expectUniqueLabels(Iterable<LyricsAnimationOption<dynamic>> options) {
      final labels = options.map((option) => option.label).toList();
      for (final label in labels) {
        expect(label.trim(), isNotEmpty);
      }
      expect(labels.toSet(), hasLength(labels.length));
    }

    expectUniqueLabels(LyricsAnimationCatalog.lineOptions);
    expectUniqueLabels(LyricsAnimationCatalog.windowOptions);
    expectUniqueLabels(LyricsAnimationCatalog.easingOptions);
  });

  test('ids are unique within each family and offered on a surface', () {
    void expectUniqueIds(Iterable<LyricsAnimationOption<dynamic>> options) {
      final ids = options.map((option) => option.id).toList();
      expect(ids.toSet(), hasLength(ids.length));
    }

    expectUniqueIds(<LyricsAnimationOption<dynamic>>[
      ...LyricsAnimationCatalog.lineOptions,
      LyricsAnimationCatalog.randomOption,
    ]);
    expectUniqueIds(LyricsAnimationCatalog.windowOptions);
    expectUniqueIds(LyricsAnimationCatalog.easingOptions);
    for (final option in allOptions()) {
      expect(option.surfaces, isNotEmpty);
    }
  });

  test('only taskbar-friendly animations are recommended for the strip', () {
    for (final option in LyricsAnimationCatalog.lineOptions) {
      if (option.recommendedForTaskbar) {
        expect(option.supports(LyricsSurface.taskbar), isTrue);
      }
    }
    expect(
      LyricsAnimationCatalog.isRecommendedForTaskbar(
        LyricsLineTransition.slideLeft,
      ),
      isTrue,
    );
    expect(
      LyricsAnimationCatalog.isRecommendedForTaskbar(
        LyricsLineTransition.flipY,
      ),
      isFalse,
    );
  });

  test('vertical and flip animations stay floating-only', () {
    final taskbarIds = LyricsAnimationCatalog.lineChoicesFor(
      LyricsSurface.taskbar,
    ).map((option) => option.id).toSet();
    for (final transition in <LyricsLineTransition>[
      LyricsLineTransition.slideUp,
      LyricsLineTransition.slideDown,
      LyricsLineTransition.scaleIn,
      LyricsLineTransition.scaleOut,
      LyricsLineTransition.flipX,
      LyricsLineTransition.flipY,
      LyricsLineTransition.dropBounce,
      LyricsLineTransition.springUp,
      LyricsLineTransition.glowSoft,
    ]) {
      expect(taskbarIds, isNot(contains(transition.id)));
    }
    expect(
      LyricsAnimationCatalog.lineChoicesFor(LyricsSurface.floating)
          .map((option) => option.id),
      containsAll(taskbarIds),
    );
  });

  test('fromId round-trips and falls back for unknown values', () {
    for (final value in LyricsLineTransition.values) {
      expect(LyricsLineTransition.fromId(value.id), value);
    }
    expect(
      LyricsLineTransition.fromId('does-not-exist'),
      LyricsLineTransition.fade,
    );
    expect(
      LyricsLineTransition.fromId(
        'does-not-exist',
        fallback: LyricsLineTransition.none,
      ),
      LyricsLineTransition.none,
    );
    expect(LyricsLineTransition.fromId(null), LyricsLineTransition.fade);
    expect(LyricsLineTransition.fromId(7), LyricsLineTransition.fade);

    for (final value in LyricsWindowTransition.values) {
      expect(LyricsWindowTransition.fromId(value.id), value);
    }
    expect(LyricsWindowTransition.fromId('nope'), LyricsWindowTransition.fade);
    for (final value in LyricsEasing.values) {
      expect(LyricsEasing.fromId(value.id), value);
    }
    expect(LyricsEasing.fromId('nope'), LyricsEasing.easeOut);
  });

  test('snapDurationMs picks the nearest supported duration', () {
    for (final value in LyricsAnimationCatalog.supportedDurationsMs) {
      expect(LyricsAnimationCatalog.snapDurationMs(value), value);
    }
    expect(LyricsAnimationCatalog.snapDurationMs(0), 0);
    expect(LyricsAnimationCatalog.snapDurationMs(100), 120);
    expect(LyricsAnimationCatalog.snapDurationMs(159), 180);
    expect(LyricsAnimationCatalog.snapDurationMs(210), 220);
    // 260 sits between 220 and 300; a tie keeps the shorter one.
    expect(LyricsAnimationCatalog.snapDurationMs(260), 220);
    expect(LyricsAnimationCatalog.snapDurationMs(999), 420);
    expect(LyricsAnimationCatalog.snapDurationMs(-50), 0);
  });

  test('random resolves deterministically and never stays random', () {
    expect(
      LyricsAnimationCatalog.resolve(LyricsLineTransition.random, seed: 0),
      LyricsAnimationCatalog.lineOptions.first.value,
    );
    expect(
      LyricsAnimationCatalog.resolve(LyricsLineTransition.random, seed: 1),
      LyricsAnimationCatalog.lineOptions[1].value,
    );
    expect(
      LyricsAnimationCatalog.resolve(LyricsLineTransition.random, seed: 18),
      LyricsAnimationCatalog.lineOptions.first.value,
    );
    expect(
      LyricsAnimationCatalog.resolve(LyricsLineTransition.slideLeft, seed: 5),
      LyricsLineTransition.slideLeft,
    );
    for (var seed = 0; seed < 40; seed++) {
      expect(
        LyricsAnimationCatalog.resolve(LyricsLineTransition.random, seed: seed),
        isNot(LyricsLineTransition.random),
      );
    }
  });

  test('curves map one to one onto Flutter curves', () {
    expect(LyricsAnimationCatalog.curveFor(LyricsEasing.linear), Curves.linear);
    expect(
      LyricsAnimationCatalog.curveFor(LyricsEasing.easeOut),
      Curves.easeOutCubic,
    );
    expect(
      LyricsAnimationCatalog.curveFor(LyricsEasing.easeInOut),
      Curves.easeInOutCubic,
    );
    expect(
      LyricsAnimationCatalog.curveFor(LyricsEasing.overshoot),
      Curves.easeOutBack,
    );
  });
}
