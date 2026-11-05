import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mconnect/core/lyrics/lyrics_animation_catalog.dart';

/// Which desktop window the lyrics studio is editing.
@immutable
class LyricsStudioState {
  const LyricsStudioState({
    this.surface = LyricsSurface.floating,
    this.previewToken = 0,
  });

  final LyricsSurface surface;

  /// Bumped to replay the window animation and the native preview.
  final int previewToken;

  LyricsStudioState copyWith({LyricsSurface? surface, int? previewToken}) {
    return LyricsStudioState(
      surface: surface ?? this.surface,
      previewToken: previewToken ?? this.previewToken,
    );
  }
}

class LyricsStudioController extends StateNotifier<LyricsStudioState> {
  LyricsStudioController() : super(const LyricsStudioState());

  void selectSurface(LyricsSurface surface) {
    if (surface == state.surface) return;
    state = state.copyWith(
      surface: surface,
      previewToken: state.previewToken + 1,
    );
  }

  void replay() {
    state = state.copyWith(previewToken: state.previewToken + 1);
  }
}

final lyricsStudioProvider =
    StateNotifierProvider<LyricsStudioController, LyricsStudioState>((ref) {
      return LyricsStudioController();
    });
