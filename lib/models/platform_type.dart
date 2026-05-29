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
}
