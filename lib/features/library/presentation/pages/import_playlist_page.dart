import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/widgets/app_scrollbar.dart';
import '../../../../models/song.dart';
import '../../../../platform/base/platform_registry.dart';
import '../../../player/presentation/providers/player_provider.dart';
import '../../data/my_playlists_repository.dart';
import '../providers/my_playlists_provider.dart';

class ImportPlaylistPage extends ConsumerStatefulWidget {
  const ImportPlaylistPage({super.key});

  @override
  ConsumerState<ImportPlaylistPage> createState() => _ImportPlaylistPageState();
}

class _ImportPlaylistPageState extends ConsumerState<ImportPlaylistPage> {
  final _controller = TextEditingController();
  bool _isParsing = false;
  String? _error;
  List<Song>? _parsedSongs;
  String? _playlistName;
  bool _isSaving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _parseLink() async {
    final url = _controller.text.trim();
    if (url.isEmpty) {
      setState(() => _error = '请输入分享链接');
      return;
    }

    setState(() {
      _isParsing = true;
      _error = null;
      _parsedSongs = null;
    });

    final decodedLocalShare = MyPlaylistsRepository.decodeShareLink(url);
    if (decodedLocalShare != null) {
      final localPlaylist = await ref
          .read(myPlaylistsProvider.notifier)
          .importShareLink(url);
      if (localPlaylist == null) {
        if (!mounted) return;
        setState(() {
          _error = '导入 Mconnect 歌单失败';
          _isParsing = false;
        });
        return;
      }
      final songs = await ref
          .read(myPlaylistsProvider.notifier)
          .getSongs(localPlaylist.id);
      if (!mounted) return;
      setState(() {
        _parsedSongs = songs;
        _playlistName = localPlaylist.name;
        _isParsing = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已导入到我的歌单')));
      return;
    }

    for (final platformType in PlatformRegistry.supportedTypes) {
      try {
        final platform = PlatformRegistry.get(platformType);
        final playlist = await platform.parseShareLink(url);
        if (playlist != null) {
          try {
            final songs = await platform.getPlaylistDetail(playlist.id);
            if (!mounted) return;
            setState(() {
              _parsedSongs = songs;
              _playlistName = playlist.name;
              _isParsing = false;
            });
            return;
          } catch (e) {
            if (!mounted) return;
            setState(() {
              _error = '获取歌单详情失败: $e';
              _isParsing = false;
            });
            return;
          }
        }
      } catch (e) {
        // parseShareLink failed for this platform, try next
      }
    }
    if (!mounted) return;
    setState(() {
      _error = '无法识别该链接，请检查链接格式';
      _isParsing = false;
    });
  }

  void _playAll() {
    if (_parsedSongs == null || _parsedSongs!.isEmpty) return;
    ref.read(playerProvider.notifier).playPlaylist(_parsedSongs!);
  }

  Future<void> _saveToMyPlaylist() async {
    final songs = _parsedSongs;
    final name = _playlistName;
    if (songs == null || songs.isEmpty || name == null || _isSaving) return;
    setState(() => _isSaving = true);
    final playlist = await ref
        .read(myPlaylistsProvider.notifier)
        .importPlaylist(name: name, songs: songs);
    if (!mounted) return;
    setState(() => _isSaving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(playlist == null ? '保存失败' : '已保存到我的歌单')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('导入歌单')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '粘贴分享链接',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              '支持网易云、QQ音乐、酷狗音乐的歌单分享链接',
              style: TextStyle(
                color: Theme.of(context).colorScheme.outline,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: InputDecoration(
                      hintText: 'https://music.163.com/...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.content_paste, size: 20),
                        tooltip: '粘贴',
                        onPressed: () async {
                          final data = await Clipboard.getData(
                            Clipboard.kTextPlain,
                          );
                          if (data?.text != null) {
                            _controller.text = data!.text!;
                          }
                        },
                      ),
                    ),
                    onSubmitted: (_) => _parseLink(),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _isParsing ? null : _parseLink,
                  child: _isParsing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('解析'),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 13,
                ),
              ),
            ],
            if (_parsedSongs != null) ...[
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '$_playlistName (${_parsedSongs!.length}首)',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _playAll,
                    icon: const Icon(Icons.play_circle_fill, size: 20),
                    label: const Text('播放全部'),
                  ),
                  TextButton.icon(
                    onPressed: _isSaving ? null : _saveToMyPlaylist,
                    icon: _isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.library_add, size: 20),
                    label: const Text('保存'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: AppScrollbar(
                  builder: (controller) => ListView.builder(
                    controller: controller,
                    itemCount: _parsedSongs!.length,
                    itemBuilder: (context, index) {
                      final song = _parsedSongs![index];
                      return ListTile(
                        dense: true,
                        leading: SizedBox(
                          width: 32,
                          child: Center(
                            child: Text(
                              '${index + 1}',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.outline,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                        title: Text(
                          song.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          song.artistNames,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.outline,
                            fontSize: 12,
                          ),
                        ),
                        onTap: () {
                          ref
                              .read(playerProvider.notifier)
                              .playPlaylist(_parsedSongs!, startIndex: index);
                        },
                      );
                    },
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
