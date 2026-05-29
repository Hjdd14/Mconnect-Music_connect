import '../../models/platform_type.dart';
import 'music_platform.dart';

class PlatformRegistry {
  static final Map<PlatformType, MusicPlatform> _platforms = {};

  static void register(MusicPlatform platform) {
    _platforms[platform.platformType] = platform;
  }

  static MusicPlatform get(PlatformType type) {
    final platform = _platforms[type];
    if (platform == null) {
      throw PlatformNotSupportedException(type);
    }
    return platform;
  }

  static List<MusicPlatform> get all => _platforms.values.toList();

  static List<PlatformType> get supportedTypes => _platforms.keys.toList();
}

class PlatformNotSupportedException implements Exception {
  final PlatformType type;
  PlatformNotSupportedException(this.type);

  @override
  String toString() => '暂不支持${type.displayName}';
}
