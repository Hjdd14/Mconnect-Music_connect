import 'dart:async';

import 'package:audio_session/audio_session.dart';

import '../../../core/diagnostics/diagnostics_service.dart';

/// 只记录音频焦点与拔耳机事件的诊断观察器，不改变任何播放行为。
///
/// just_audio 内部已开启 handleInterruptions 并负责打断暂停/自动恢复；
/// 这里仅把事件写进诊断日志，用于定位后台静音的故障来源
/// （例如焦点被抢占、duck 后音量未恢复、拔耳机等）。
class AudioFocusDiagnosticsObserver {
  AudioFocusDiagnosticsObserver({
    required this._interruptionStream,
    required this._becomingNoisyStream,
    DiagnosticsService? diagnostics,
  }) : _diagnostics = diagnostics ?? DiagnosticsService.instance;

  final Stream<AudioInterruptionEvent> _interruptionStream;
  final Stream<void> _becomingNoisyStream;
  final DiagnosticsService _diagnostics;
  StreamSubscription<AudioInterruptionEvent>? _interruptionSubscription;
  StreamSubscription<void>? _becomingNoisySubscription;

  void start() {
    _interruptionSubscription ??= _interruptionStream.listen((event) {
      _diagnostics.record(
        'audio_focus',
        event.begin ? 'interruption_begin' : 'interruption_end',
        data: {'type': event.type.name},
      );
    });
    _becomingNoisySubscription ??= _becomingNoisyStream.listen((_) {
      _diagnostics.record('audio_focus', 'becoming_noisy');
    });
  }

  Future<void> dispose() async {
    await _interruptionSubscription?.cancel();
    await _becomingNoisySubscription?.cancel();
    _interruptionSubscription = null;
    _becomingNoisySubscription = null;
  }
}