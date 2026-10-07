import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the floating overlay's row order.
///
/// The overlay is a native (Kotlin) `LinearLayout`, so no widget test can reach
/// it — a source assertion is the only available guard, and this repository
/// already uses that approach for `MainActivity.kt`
/// (`test/local_music_android_test.dart`).
///
/// The bug this prevents: the payload's `translation` belongs to the line being
/// sung (`text`), while `nextText` is the *upcoming* line. Adding `nextText`
/// before `translationText` therefore rendered
///
/// ```text
/// line being sung
/// NEXT line            <-- between a line and its own translation
/// translation of the line being sung
/// ```
///
/// which reads as noise. The order must be: line → its translation → next line.
void main() {
  const controllerPath =
      'android/app/src/main/kotlin/com/mconnect/mconnect/FloatingLyricsController.kt';

  List<String> lyricsColumnChildren(String source) {
    // Only the lyrics column: the same view fields are also assigned, styled
    // and disposed elsewhere in the file, so the identifiers alone are not
    // enough to prove the order.
    final block = source.substring(
      source.indexOf('lyricsColumn.addView('),
      source.indexOf('lyricsBlock.addView('),
    );
    return RegExp(r'lyricsColumn\.addView\(\s*(\w+)')
        .allMatches(block)
        .map((m) => m.group(1)!)
        .toList();
  }

  test('the overlay stacks line, then its translation, then the next line', () {
    final source = File(controllerPath).readAsStringSync();

    expect(
      lyricsColumnChildren(source),
      ['lyricText', 'translationText', 'nextText'],
      reason:
          'the translation must sit directly under the line being sung; the '
          'next line goes last',
    );
  });

  test('the payload pairs the translation with the line being sung', () {
    final provider = File(
      'lib/features/floating_lyrics/presentation/providers/floating_lyrics_provider.dart',
    ).readAsStringSync();

    // If someone "fixes" the layout problem by swapping the payload fields
    // instead, the overlay would show the next line's translation as if it were
    // the current line's - a worse bug, and one the layout assertion above
    // cannot see.
    expect(provider, contains('translation: active.translation'));
    expect(provider, contains('nextText: next?.text'));
  });
}
