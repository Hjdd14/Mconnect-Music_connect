import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../../core/diagnostics/diagnostics_service.dart';
import '../../../core/platform/platform_utils.dart';

abstract class PlaybackKeepAliveController {
  Future<void> setPlaying(bool playing);

  Future<void> dispose();
}

class NoopPlaybackKeepAliveController implements PlaybackKeepAliveController {
  const NoopPlaybackKeepAliveController();

  @override
  Future<void> setPlaying(bool playing) async {}

  @override
  Future<void> dispose() async {}
}

class MethodChannelPlaybackKeepAliveController
    implements PlaybackKeepAliveController {
  MethodChannelPlaybackKeepAliveController._();

  static final MethodChannelPlaybackKeepAliveController instance =
      MethodChannelPlaybackKeepAliveController._();

  static const MethodChannel _channel = MethodChannel(
    'com.mconnect.mconnect/playback_keep_alive',
  );

  bool? _lastPlaying;

  @override
  Future<void> setPlaying(bool playing) async {
    await _setPlaying(playing);
  }

  Future<void> _setPlaying(bool playing, {bool force = false}) async {
    if (!PlatformUtils.isAndroid) return;
    if (!force && _lastPlaying == playing) return;
    try {
      await _channel.invokeMethod<void>('setPlaying', playing);
      _lastPlaying = playing;
    } catch (error, stack) {
      debugPrint('PlaybackKeepAlive setPlaying failed: $error');
      DiagnosticsService.instance.recordError(
        'playback_keep_alive.setPlaying',
        error,
        stack,
        data: {'playing': playing},
      );
    }
  }

  @override
  Future<void> dispose() async {
    await _setPlaying(false, force: true);
  }

  @visibleForTesting
  void resetForTest() {
    _lastPlaying = null;
  }
}
