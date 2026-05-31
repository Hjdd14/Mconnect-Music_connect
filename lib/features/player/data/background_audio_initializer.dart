import 'package:flutter/foundation.dart';

import '../../../core/diagnostics/diagnostics_service.dart';
import '../../../core/platform/platform_utils.dart';
import 'playback_notification_service.dart';

class BackgroundAudioInitializer {
  static Future<void> initialize({DiagnosticsService? diagnostics}) async {
    if (!PlatformUtils.isAndroid) return;
    try {
      await AudioServicePlayerController.instance.initialize(
        diagnostics: diagnostics,
      );
    } catch (error, stack) {
      debugPrint('BackgroundAudioInitializer failed: $error');
      diagnostics?.recordError('background_audio.initialize', error, stack);
    }
  }
}
