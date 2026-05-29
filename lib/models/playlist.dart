import 'platform_type.dart';

class Playlist {
  final String id;
  final String name;
  final PlatformType platform;
  final int songCount;
  final String? coverUrl;
  final String? creatorName;
  final bool editable;
  final bool collected;
  final String? editId;

  const Playlist({
    required this.id,
    required this.name,
    required this.platform,
    this.songCount = 0,
    this.coverUrl,
    this.creatorName,
    this.editable = false,
    this.collected = false,
    this.editId,
  });

  String get editableId => editId?.isNotEmpty == true ? editId! : id;
}
