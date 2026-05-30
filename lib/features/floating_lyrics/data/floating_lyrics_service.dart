import 'package:flutter/services.dart';

import 'floating_lyrics_models.dart';

class FloatingLyricsService {
  FloatingLyricsService._({MethodChannel? channel})
    : _channel =
          channel ?? const MethodChannel('com.mconnect.mconnect/floating_lyrics');

  static final instance = FloatingLyricsService._();

  final MethodChannel _channel;

  Future<bool> canDrawOverlays() async {
    return await _channel.invokeMethod<bool>('canDrawOverlays') ?? false;
  }

  Future<bool> openOverlaySettings() async {
    return await _channel.invokeMethod<bool>('openOverlaySettings') ?? false;
  }

  Future<bool> show(
    FloatingLyricsPayload payload,
    FloatingLyricsSettings settings,
  ) async {
    return await _channel.invokeMethod<bool>(
          'show',
          payload.toJson(settings),
        ) ??
        false;
  }

  Future<bool> update(
    FloatingLyricsPayload payload,
    FloatingLyricsSettings settings,
  ) async {
    return await _channel.invokeMethod<bool>(
          'update',
          payload.toJson(settings),
        ) ??
        false;
  }

  Future<bool> hide() async {
    return await _channel.invokeMethod<bool>('hide') ?? false;
  }
}
