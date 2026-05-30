import 'package:flutter/services.dart';

import 'floating_lyrics_models.dart';

class FloatingLyricsService {
  FloatingLyricsService._({MethodChannel? channel})
    : _channel =
          channel ??
          const MethodChannel('com.mconnect.mconnect/floating_lyrics');

  static final instance = FloatingLyricsService._();

  final MethodChannel _channel;

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
