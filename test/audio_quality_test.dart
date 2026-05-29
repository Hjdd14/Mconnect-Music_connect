import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/models/audio_quality.dart';
import 'package:mconnect/models/platform_type.dart';

void main() {
  test('audio quality labels follow each platform naming style', () {
    expect(AudioLevel.medium.displayNameFor(PlatformType.netease), '较高');
    expect(AudioLevel.lossless.displayNameFor(PlatformType.netease), '无损');
    expect(AudioLevel.spatial.displayNameFor(PlatformType.netease), '高清环绕声');
    expect(AudioLevel.dolby.displayNameFor(PlatformType.netease), '沉浸环绕声');
    expect(AudioLevel.master.displayNameFor(PlatformType.netease), '超清母带');

    expect(AudioLevel.medium.displayNameFor(PlatformType.qq), 'HQ高品质');
    expect(AudioLevel.lossless.displayNameFor(PlatformType.qq), 'SQ无损品质');
    expect(AudioLevel.hires.displayNameFor(PlatformType.qq), 'Hi-Res');
    expect(AudioLevel.spatial.displayNameFor(PlatformType.qq), '臻品全景声2.0');
    expect(AudioLevel.dolby.displayNameFor(PlatformType.qq), '臻品音质2.0');
    expect(AudioLevel.master.displayNameFor(PlatformType.qq), '臻品母带2.0');

    expect(AudioLevel.medium.displayNameFor(PlatformType.kugou), '高品音质');
    expect(AudioLevel.lossless.displayNameFor(PlatformType.kugou), '无损音质');
    expect(AudioLevel.hires.displayNameFor(PlatformType.kugou), 'Hi-Res');
    expect(AudioLevel.spatial.displayNameFor(PlatformType.kugou), 'VIPER HiFi');
    expect(AudioLevel.master.displayNameFor(PlatformType.kugou), 'DSD');
  });

  test('audio quality metadata marks advanced lossless levels', () {
    expect(
      const AudioQuality(
        level: AudioLevel.hires,
        bitrate: 2400000,
        format: 'flac',
      ).isLossless,
      isTrue,
    );
    expect(
      const AudioQuality(
        level: AudioLevel.master,
        bitrate: 999000,
        format: 'flac',
      ).isLossless,
      isTrue,
    );
    expect(
      const AudioQuality(
        level: AudioLevel.dolby,
        bitrate: 320000,
        format: 'mp3',
      ).isLossless,
      isFalse,
    );
  });
}
