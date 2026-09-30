import 'dart:async';

import 'package:flutter/services.dart';

import 'floating_lyrics_models.dart';

/// Overlay actions the native window can ask the app to perform when the user
/// taps the transport buttons drawn inside the floating lyrics.
enum FloatingLyricsControl { playPause, previous, next }

class FloatingLyricsService {
  FloatingLyricsService._({MethodChannel? channel})
    : _channel =
          channel ??
          const MethodChannel('com.mconnect.mconnect/floating_lyrics') {
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  static final instance = FloatingLyricsService._();

  final MethodChannel _channel;
  final _closedByUserController = StreamController<void>.broadcast();
  final _lockChangedController = StreamController<bool>.broadcast();
  final _windowResizedController =
      StreamController<({int width, int height})>.broadcast();
  final _styleChangedController =
      StreamController<({Color highlightColor, double fontSize})>.broadcast();
  final _controlRequestedController =
      StreamController<FloatingLyricsControl>.broadcast();
  final _positionChangedController = StreamController<double>.broadcast();

  Stream<void> get closedByUserStream => _closedByUserController.stream;

  Stream<bool> get lockChangedStream => _lockChangedController.stream;

  Stream<({int width, int height})> get windowResizedStream =>
      _windowResizedController.stream;

  /// Fired when the user picks a highlight swatch or changes the font size from
  /// the in-overlay settings row.
  Stream<({Color highlightColor, double fontSize})> get styleChangedStream =>
      _styleChangedController.stream;

  /// Fired when the user taps a transport button inside the overlay.
  Stream<FloatingLyricsControl> get controlRequestedStream =>
      _controlRequestedController.stream;

  /// Fired once per completed vertical drag, in physical pixels.
  Stream<double> get positionChangedStream => _positionChangedController.stream;

  Future<void> _handleNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'closedByUser':
        _closedByUserController.add(null);
        break;
      case 'lockChanged':
        final locked = call.arguments;
        if (locked is bool) {
          _lockChangedController.add(locked);
        }
        break;
      case 'windowResized':
        final args = call.arguments;
        if (args is Map) {
          final w = (args['width'] as num?)?.toInt();
          final h = (args['height'] as num?)?.toInt();
          if (w != null && h != null && w > 0 && h > 0) {
            _windowResizedController.add((width: w, height: h));
          }
        }
        break;
      case 'styleChanged':
        final args = call.arguments;
        if (args is Map) {
          final color = (args['highlightColor'] as num?)?.toInt();
          final fontSize = (args['fontSize'] as num?)?.toDouble();
          if (color != null && fontSize != null && fontSize > 0) {
            _styleChangedController.add((
              highlightColor: Color(color & 0xFFFFFFFF),
              fontSize: fontSize,
            ));
          }
        }
        break;
      case 'controlRequested':
        final args = call.arguments;
        if (args is Map) {
          final action = args['action'];
          final control = switch (action) {
            'playPause' => FloatingLyricsControl.playPause,
            'previous' => FloatingLyricsControl.previous,
            'next' => FloatingLyricsControl.next,
            _ => null,
          };
          if (control != null) {
            _controlRequestedController.add(control);
          }
        }
        break;
      case 'positionChanged':
        final value = call.arguments;
        if (value is num && value >= 0) {
          _positionChangedController.add(value.toDouble());
        }
        break;
    }
  }

  Future<T?> _invokeOptional<T>(String method, [Object? arguments]) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on MissingPluginException {
      return null;
    }
  }

  Future<bool> canDrawOverlays() async {
    return await _invokeOptional<bool>('canDrawOverlays') ?? false;
  }

  Future<bool> openOverlaySettings() async {
    return await _invokeOptional<bool>('openOverlaySettings') ?? false;
  }

  Future<bool> show(
    FloatingLyricsPayload payload,
    FloatingLyricsSettings settings,
  ) async {
    return await _invokeOptional<bool>('show', payload.toJson(settings)) ??
        false;
  }

  Future<bool> update(
    FloatingLyricsPayload payload,
    FloatingLyricsSettings settings,
  ) async {
    return await _invokeOptional<bool>('update', payload.toJson(settings)) ??
        false;
  }

  Future<bool> hide() async {
    return await _invokeOptional<bool>('hide') ?? false;
  }
}
