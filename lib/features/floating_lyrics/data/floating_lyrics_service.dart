import 'dart:async';

import 'package:flutter/services.dart';

import 'floating_lyrics_models.dart';

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

  Stream<void> get closedByUserStream => _closedByUserController.stream;

  Stream<bool> get lockChangedStream => _lockChangedController.stream;

  Stream<({int width, int height})> get windowResizedStream =>
      _windowResizedController.stream;

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
