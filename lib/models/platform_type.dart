enum PlatformType {
  local('本地音乐'),
  netease('网易云音乐'),
  qq('QQ音乐'),
  kugou('酷狗音乐');

  final String displayName;
  const PlatformType(this.displayName);

  static const musicServices = [
    PlatformType.netease,
    PlatformType.qq,
    PlatformType.kugou,
  ];

  bool get isMusicService => this != PlatformType.local;

  /// Parses a platform name that came from **outside** the app: a route path
  /// segment, a persisted JSON field, a database column.
  ///
  /// Returns `null` for anything unrecognised. Eight call sites used to write
  /// `orElse: () => PlatformType.netease`, which silently re-attributed
  /// unknown — or since-removed — platform data to 网易云 instead of reporting
  /// it. Callers decide what an unknown value means in their context:
  /// navigation rejects it, persisted-data readers keep or drop the row.
  static PlatformType? tryParse(String? name) {
    if (name == null) return null;
    for (final type in PlatformType.values) {
      if (type.name == name) return type;
    }
    return null;
  }

  /// Like [tryParse], but for places where an unknown platform is a
  /// programming/navigation error rather than recoverable data.
  static PlatformType parse(String name) {
    final type = tryParse(name);
    if (type == null) {
      throw FormatException('Unknown platform name: $name');
    }
    return type;
  }
}
