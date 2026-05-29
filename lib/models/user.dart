import 'platform_type.dart';

enum VipLevel { free, vip, svip }

class User {
  final String id;
  final String nickname;
  final String? avatarUrl;
  final PlatformType platform;
  final VipLevel vipLevel;
  final DateTime? vipExpireTime;

  const User({
    required this.id,
    required this.nickname,
    this.avatarUrl,
    required this.platform,
    this.vipLevel = VipLevel.free,
    this.vipExpireTime,
  });

  bool get isVip => vipLevel != VipLevel.free;
  bool get isSvip => vipLevel == VipLevel.svip;

  Map<String, dynamic> toJson() => {
    'id': id,
    'nickname': nickname,
    'avatarUrl': avatarUrl,
    'platform': platform.name,
    'vipLevel': vipLevel.index,
  };

  factory User.fromJson(Map<String, dynamic> json) => User(
    id: json['id'] as String,
    nickname: json['nickname'] as String? ?? '',
    avatarUrl: json['avatarUrl'] as String?,
    platform: PlatformType.values.firstWhere(
      (p) => p.name == json['platform'],
      orElse: () => PlatformType.netease,
    ),
    vipLevel: VipLevel.values[json['vipLevel'] as int? ?? 0],
  );
}
