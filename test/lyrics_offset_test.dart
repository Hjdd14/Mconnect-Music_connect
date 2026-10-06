import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/features/player/presentation/providers/lyrics_offset_provider.dart';

/// 歌词偏移手动校准（WS-E 批次2）：范围钳制、步进、持久化。
void main() {
  test('clamps the offset to the calibration range', () {
    expect(
      clampLyricsOffset(const Duration(seconds: 30)),
      maxLyricsOffset,
    );
    expect(
      clampLyricsOffset(const Duration(seconds: -30)),
      minLyricsOffset,
    );
    expect(
      clampLyricsOffset(const Duration(milliseconds: 1200)),
      const Duration(milliseconds: 1200),
    );
  });

  test('starts at the persisted offset', () {
    final notifier = LyricsOffsetNotifier(
      initial: const Duration(milliseconds: 1500),
    );
    addTearDown(notifier.dispose);

    expect(notifier.state, const Duration(milliseconds: 1500));
  });

  test('a corrupt persisted value is clamped on load', () {
    final notifier = LyricsOffsetNotifier(
      initial: const Duration(hours: 2),
    );
    addTearDown(notifier.dispose);

    expect(notifier.state, maxLyricsOffset);
  });

  test('adjust steps by the calibration step and persists every change', () async {
    final persisted = <int>[];
    final notifier = LyricsOffsetNotifier(
      persist: (milliseconds) async => persisted.add(milliseconds),
    );
    addTearDown(notifier.dispose);

    await notifier.adjust(lyricsOffsetStep);
    expect(notifier.state, const Duration(milliseconds: 500));

    await notifier.adjust(lyricsOffsetStep);
    expect(notifier.state, const Duration(milliseconds: 1000));
    expect(persisted, [500, 1000]);

    await notifier.reset();
    expect(notifier.state, Duration.zero);
    expect(persisted.last, 0);
  });

  test('a failing persist keeps the in-memory offset', () async {
    final notifier = LyricsOffsetNotifier(
      persist: (milliseconds) async => throw StateError('disk full'),
    );
    addTearDown(notifier.dispose);

    await notifier.setOffset(const Duration(milliseconds: 750));

    expect(notifier.state, const Duration(milliseconds: 750));
  });
}
