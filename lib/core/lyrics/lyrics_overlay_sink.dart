import 'package:flutter/foundation.dart';

import 'lyrics_animation_catalog.dart';
import 'lyrics_overlay_config.dart';
import 'lyrics_overlay_frame.dart';

/// Platform channel names of the two desktop overlays
/// (docs/desktop-lyrics-protocol.md, section 1).
abstract final class LyricsChannels {
  static const String floating = 'com.mconnect.mconnect/floating_lyrics';
  static const String taskbar = 'com.mconnect.mconnect/taskbar_lyrics';
}

/// One line of the sample set an animation preview plays.
@immutable
class LyricsPreviewLine {
  const LyricsPreviewLine({required this.text, this.translation});

  final String text;
  final String? translation;

  Map<String, Object?> toJson() => <String, Object?>{
    'text': text,
    'translation': translation,
  };
}

/// Arguments of the configure/preview methods (protocol sections 4.1 and 4.2).
@immutable
class LyricsPreviewRequest {
  const LyricsPreviewRequest({
    required this.animation,
    required this.sampleLines,
    this.durationMs = 2400,
  });

  final LyricsLineTransition animation;
  final List<LyricsPreviewLine> sampleLines;
  final int durationMs;

  Map<String, Object?> toJson() => <String, Object?>{
    'animation': animation.id,
    'sampleLines': <Object?>[for (final line in sampleLines) line.toJson()],
    'durationMs': durationMs,
  };
}

/// An axis-aligned rectangle in physical pixels.
@immutable
class LyricsRect {
  const LyricsRect({
    this.left = 0,
    this.top = 0,
    this.right = 0,
    this.bottom = 0,
  });

  static const LyricsRect zero = LyricsRect();

  final double left;
  final double top;
  final double right;
  final double bottom;

  double get width => right - left;
  double get height => bottom - top;

  bool get isEmpty => width <= 0 || height <= 0;

  factory LyricsRect.fromJson(Object? json) {
    if (json is! Map) return zero;
    double read(String key) => (json[key] as num?)?.toDouble() ?? 0;
    return LyricsRect(
      left: read('left'),
      top: read('top'),
      right: read('right'),
      bottom: read('bottom'),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'left': left,
    'top': top,
    'right': right,
    'bottom': bottom,
  };
}

/// One monitor as reported by the native overlay (getMonitors).
@immutable
class LyricsMonitorInfo {
  const LyricsMonitorInfo({
    required this.deviceName,
    required this.bounds,
    this.dpi = 96,
    this.isPrimary = false,
  });

  final String deviceName;
  final LyricsRect bounds;
  final int dpi;
  final bool isPrimary;

  factory LyricsMonitorInfo.fromJson(Map<dynamic, dynamic> json) {
    return LyricsMonitorInfo(
      deviceName: json['deviceName'] as String? ?? '',
      bounds: LyricsRect(
        left: (json['left'] as num?)?.toDouble() ?? 0,
        top: (json['top'] as num?)?.toDouble() ?? 0,
        right: (json['right'] as num?)?.toDouble() ?? 0,
        bottom: (json['bottom'] as num?)?.toDouble() ?? 0,
      ),
      dpi: (json['dpi'] as num?)?.toInt() ?? 96,
      isPrimary: json['isPrimary'] as bool? ?? false,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'deviceName': deviceName,
    'left': bounds.left,
    'top': bounds.top,
    'right': bounds.right,
    'bottom': bounds.bottom,
    'dpi': dpi,
    'isPrimary': isPrimary,
  };
}

/// Taskbar geometry for one monitor (getTaskbarInfo, protocol section 4.2).
@immutable
class LyricsTaskbarInfo {
  const LyricsTaskbarInfo({
    required this.monitor,
    this.edge = 'bottom',
    this.thickness = 0,
    this.taskbarRect = LyricsRect.zero,
    this.freeRect = LyricsRect.zero,
    this.trayRect = LyricsRect.zero,
    this.taskListRect = LyricsRect.zero,
    this.dpi = 96,
    this.autoHide = false,
  });

  final String monitor;
  final String edge;
  final double thickness;
  final LyricsRect taskbarRect;
  final LyricsRect freeRect;
  final LyricsRect trayRect;
  final LyricsRect taskListRect;
  final int dpi;
  final bool autoHide;

  factory LyricsTaskbarInfo.fromJson(Map<dynamic, dynamic> json) {
    return LyricsTaskbarInfo(
      monitor: json['monitor'] as String? ?? '',
      edge: json['edge'] as String? ?? 'bottom',
      thickness: (json['thickness'] as num?)?.toDouble() ?? 0,
      taskbarRect: LyricsRect.fromJson(json['taskbarRect']),
      freeRect: LyricsRect.fromJson(json['freeRect']),
      trayRect: LyricsRect.fromJson(json['trayRect']),
      taskListRect: LyricsRect.fromJson(json['taskListRect']),
      dpi: (json['dpi'] as num?)?.toInt() ?? 96,
      autoHide: json['autoHide'] as bool? ?? false,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'monitor': monitor,
    'edge': edge,
    'thickness': thickness,
    'taskbarRect': taskbarRect.toJson(),
    'freeRect': freeRect.toJson(),
    'trayRect': trayRect.toJson(),
    'taskListRect': taskListRect.toJson(),
    'dpi': dpi,
    'autoHide': autoHide,
  };
}

/// One native overlay a frame can be pushed to.
///
/// The controller treats every sink identically and fans frames out to the
/// sinks whose surface is enabled. Desktop-only methods have no-op defaults,
/// which is what lets the Android sink implement just the legacy surface
/// without pretending to support a taskbar.
abstract class LyricsOverlaySink {
  const LyricsOverlaySink();

  /// Which surface this sink paints.
  LyricsSurface get surface;

  /// Whether [preview] is meaningful (the Windows sinks only).
  bool get supportsPreview => false;

  /// True when this sink can only draw with the system overlay permission
  /// (Android). Windows overlays are always allowed and answer true.
  bool get requiresOverlayPermission => false;

  /// Pushes the (low frequency) style.
  Future<bool> configure(LyricsOverlayConfig config) async => false;

  /// Creates/shows the overlay with [frame] and [config].
  Future<bool> show(
    LyricsOverlayFrame frame,
    LyricsOverlayConfig config,
  ) async => false;

  /// Pushes a frame to an existing overlay.
  Future<bool> update(
    LyricsOverlayFrame frame,
    LyricsOverlayConfig config,
  ) async => false;

  Future<bool> hide() async => false;

  Future<bool> preview(LyricsPreviewRequest request) async => false;

  Future<bool> resetPosition() async => false;

  Future<List<LyricsMonitorInfo>> getMonitors() async =>
      const <LyricsMonitorInfo>[];

  Future<List<LyricsTaskbarInfo>> getTaskbarInfo() async =>
      const <LyricsTaskbarInfo>[];

  /// Re-reads the taskbar geometry after a monitor/taskbar change.
  Future<bool> refreshGeometry() async => false;

  Future<bool> setInteractive(bool interactive) async => false;

  /// Whether the sink may draw right now. The controller asks before pushing a
  /// frame so it does not queue work the platform will reject.
  Future<bool> ensureAvailable() async => true;

  Future<bool> openOverlaySettings() async => false;

  Future<void> dispose() async {}
}
