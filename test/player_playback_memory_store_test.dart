import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/features/player/data/player_playback_memory_store.dart';
import 'package:mconnect/models/platform_type.dart';

/// 播放记忆的静默平台回落回归：未知/已删除的平台名**不得**被改写成网易云，
/// 否则会恢复到错误平台（拿别家平台的歌去网易云取流）。
void main() {
  Map<String, dynamic> songJson(String id, String platform) => {
    'id': id,
    'platform': platform,
    'name': 'Song $id',
    'artists': [
      {'id': 'artist', 'name': 'Artist'},
    ],
    'durationMs': 180000,
  };

  test('restores a known platform unchanged', () {
    final memory = PlayerPlaybackMemory.fromJson({
      'currentSong': songJson('1', 'kugou'),
      'playlist': [songJson('1', 'kugou')],
      'currentIndex': 0,
    });

    expect(memory, isNotNull);
    expect(memory!.currentSong.platform, PlatformType.kugou);
  });

  test('an unknown current-song platform drops the snapshot', () {
    final memory = PlayerPlaybackMemory.fromJson({
      'currentSong': songJson('1', 'spotify'),
      'playlist': [songJson('1', 'spotify')],
      'currentIndex': 0,
    });

    expect(memory, isNull);
  });

  test('an unknown playlist platform is dropped, not re-attributed', () {
    final memory = PlayerPlaybackMemory.fromJson({
      'currentSong': songJson('1', 'netease'),
      'playlist': [
        songJson('1', 'netease'),
        songJson('2', 'spotify'),
      ],
      'currentIndex': 1,
    });

    expect(memory, isNotNull);
    expect(memory!.playlist.map((song) => song.id), ['1']);
    expect(memory.playlist.single.platform, PlatformType.netease);
    expect(memory.currentIndex, 0);
  });

  test('a null or missing platform is not turned into netease', () {
    final memory = PlayerPlaybackMemory.fromJson({
      'currentSong': {'id': '1', 'name': 'Song 1'},
      'currentIndex': 0,
    });

    expect(memory, isNull);
  });

  // Wave 0-A (A-2)：播放偏好（倍速/跳过静音/随机/循环/A-B）必须和"上次播到哪"
  // 一起落盘，否则杀进程后每次都要重设。
  test('round-trips the playback preferences next to the last song', () {
    final memory = PlayerPlaybackMemory.fromJson({
      'currentSong': songJson('1', 'kugou'),
      'playlist': [songJson('1', 'kugou')],
      'currentIndex': 0,
      'playbackSpeed': 1.5,
      'skipSilence': true,
      'isShuffle': true,
      'repeatMode': 'all',
      'abLoopStartMs': 12000,
      'abLoopEndMs': 34000,
    });

    expect(memory, isNotNull);
    final json = memory!.toJson();
    expect(json['playbackSpeed'], 1.5);
    expect(json['skipSilence'], true);
    expect(json['isShuffle'], true);
    expect(json['repeatMode'], 'all');
    expect(json['abLoopStartMs'], 12000);
    expect(json['abLoopEndMs'], 34000);
  });

  test('a snapshot without playback preferences keeps the safe defaults', () {
    final memory = PlayerPlaybackMemory.fromJson({
      'currentSong': songJson('1', 'kugou'),
      'playlist': [songJson('1', 'kugou')],
      'currentIndex': 0,
    });

    expect(memory, isNotNull);
    final json = memory!.toJson();
    expect(json['playbackSpeed'], 1.0);
    expect(json['skipSilence'], false);
    expect(json['isShuffle'], false);
    expect(json['repeatMode'], 'off');
    expect(json['abLoopStartMs'], isNull);
    expect(json['abLoopEndMs'], isNull);
  });
}
