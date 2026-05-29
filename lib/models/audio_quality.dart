import 'platform_type.dart';

enum AudioLevel {
  low('标准'),
  medium('较高'),
  high('极高'),
  lossless('无损'),
  hires('Hi-Res'),
  spatial('高清环绕声'),
  dolby('沉浸环绕声'),
  master('超清母带');

  final String displayName;
  const AudioLevel(this.displayName);

  String displayNameFor(PlatformType platform) {
    switch (platform) {
      case PlatformType.local:
        return '本地';
      case PlatformType.netease:
        return displayName;
      case PlatformType.qq:
        return switch (this) {
          AudioLevel.low => '标准音质',
          AudioLevel.medium => 'HQ高品质',
          AudioLevel.high => 'HQ高品质',
          AudioLevel.lossless => 'SQ无损品质',
          AudioLevel.hires => 'Hi-Res',
          AudioLevel.spatial => '臻品全景声2.0',
          AudioLevel.dolby => '臻品音质2.0',
          AudioLevel.master => '臻品母带2.0',
        };
      case PlatformType.kugou:
        return switch (this) {
          AudioLevel.low => '标准音质',
          AudioLevel.medium => '高品音质',
          AudioLevel.high => '超品音质',
          AudioLevel.lossless => '无损音质',
          AudioLevel.hires => 'Hi-Res',
          AudioLevel.spatial => 'VIPER HiFi',
          AudioLevel.dolby => '臻品音质',
          AudioLevel.master => 'DSD',
        };
    }
  }

  bool get isLossless =>
      this == AudioLevel.lossless ||
      this == AudioLevel.hires ||
      this == AudioLevel.master;

  bool get isVipOnly =>
      this == AudioLevel.high ||
      this == AudioLevel.spatial ||
      this == AudioLevel.dolby;

  bool get isSvipOnly =>
      this == AudioLevel.lossless ||
      this == AudioLevel.hires ||
      this == AudioLevel.master;
}

class AudioQuality {
  final AudioLevel level;
  final int bitrate;
  final String format;
  final int? size;

  const AudioQuality({
    required this.level,
    required this.bitrate,
    required this.format,
    this.size,
  });

  bool get isLossless => level.isLossless;

  bool get isVipOnly => level.isVipOnly;

  bool get isSvipOnly => level.isSvipOnly;
}
