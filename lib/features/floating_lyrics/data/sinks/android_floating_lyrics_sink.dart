import 'package:flutter/material.dart';

import '../../../../core/lyrics/lyrics_animation_catalog.dart';
import '../../../../core/lyrics/lyrics_overlay_config.dart';
import '../../../../core/lyrics/lyrics_overlay_frame.dart';
import '../../../../core/lyrics/lyrics_overlay_sink.dart';
import '../floating_lyrics_models.dart';
import '../floating_lyrics_service.dart';

/// The Android overlay, presented through the shared sink interface.
///
/// Deliberately frozen: it sends the same two methods (show/update) with the
/// same legacy map the Kotlin controller has always parsed, and it never calls
/// a desktop-only method. That is what keeps the Android behaviour untouched
/// while the two Windows windows move to frames
/// (docs/desktop-lyrics-protocol.md, section 5).
class AndroidFloatingLyricsSink extends LyricsOverlaySink {
  AndroidFloatingLyricsSink([FloatingLyricsService? service])
    : _service = service ?? FloatingLyricsService.instance;

  final FloatingLyricsService _service;

  @override
  LyricsSurface get surface => LyricsSurface.floating;

  @override
  bool get requiresOverlayPermission => true;

  /// No-op on purpose: Android has no style call, every style field rides along
  /// on show/update.
  @override
  Future<bool> configure(LyricsOverlayConfig config) async => true;

  @override
  Future<bool> show(LyricsOverlayFrame frame, LyricsOverlayConfig config) {
    return _service.show(payloadFromFrame(frame), settingsFromConfig(config));
  }

  @override
  Future<bool> update(LyricsOverlayFrame frame, LyricsOverlayConfig config) {
    return _service.update(payloadFromFrame(frame), settingsFromConfig(config));
  }

  @override
  Future<bool> hide() => _service.hide();

  @override
  Future<bool> ensureAvailable() => _service.canDrawOverlays();

  @override
  Future<bool> openOverlaySettings() => _service.openOverlaySettings();

  /// Rebuilds the legacy payload. Only the fields the Kotlin side reads are
  /// carried; the desktop extras stay out of the Android map by design.
  static FloatingLyricsPayload payloadFromFrame(LyricsOverlayFrame frame) {
    return FloatingLyricsPayload(
      text: frame.text,
      translation: frame.translation,
      progress: frame.progress,
      nextText: frame.nextText,
      highlightProgress: frame.highlightProgress,
      highlightRate: frame.highlightRate,
      isPlaying: frame.isPlaying,
      hasSong: frame.hasSong,
      lineIndex: frame.lineIndex,
      nextTranslation: frame.nextTranslation,
      wordSegments: frame.wordSegments,
      songTitle: frame.songTitle,
      artistName: frame.artistName,
      albumName: frame.albumName,
      coverUrl: frame.coverUrl,
    );
  }

  /// Rebuilds the legacy settings map from a surface-neutral config.
  static FloatingLyricsSettings settingsFromConfig(LyricsOverlayConfig config) {
    return FloatingLyricsSettings(
      enabled: config.enabled,
      textColor: Color(config.textColor),
      highlightColor: Color(config.highlightColor),
      backgroundColor: Color(config.backgroundColor),
      fontSize: config.fontSize,
      strokeWidth: config.strokeWidth,
      shadowOpacity: config.shadowOpacity,
      width: config.width,
      height: config.height,
      isLocked: config.isLocked,
      positionY: config.positionY,
    );
  }
}
