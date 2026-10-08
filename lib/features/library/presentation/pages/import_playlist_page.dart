import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/transfer/playlist_codec.dart';
import '../../../../core/transfer/transfer_providers.dart';
import '../../../../core/transfer/transfer_report.dart';
import '../../../../core/widgets/app_scrollbar.dart';
import '../../../../models/song.dart';
import '../../../../platform/base/platform_registry.dart';
import '../../../player/presentation/providers/player_provider.dart';
import '../../data/my_playlists_repository.dart';
import '../providers/my_playlists_provider.dart';
import '../../../../core/utils/snackbar_helper.dart';

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

  /// Set when the pasted text was a transfer document rather than a link.
  TransferReport? _report;
  TransferDraft? _draft;

  /// The pending share payload already picked up, so a rebuild cannot parse the
  /// same document twice (the slot itself is cleared as soon as it is consumed,
  /// but two builds can happen inside one frame).
  String? _pendingInFlight;

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
      _report = null;
      _draft = null;
    });

    // A playlist *document* (m3u8 / our own JSON / `歌名 - 歌手` lines) is a
    // different problem from a share *link*: there is no platform to ask and no
    // id to look up, so every row has to be matched. `decodePlaylistTransfer`
    // returns null for anything that is not one of the three formats, which is
    // what keeps the link paths below untouched.
    if (await _parseTransferDocument(url)) return;

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
      showSuccessSnackBar(context, '已导入到我的歌单');
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
    showInfoSnackBar(context, playlist == null ? '保存失败' : '已保存到我的歌单');
  }

  /// Handles [text] when it is an m3u8 / JSON / `歌名 - 歌手` document.
  ///
  /// Returns false when it is not one of those, so the caller can carry on with
  /// the share-link paths. [text] is resolved row by row through the shared
  /// matcher; a row that resolves to nothing stays in the report rather than
  /// being dropped.
  Future<bool> _parseTransferDocument(String text) async {
    final document = decodePlaylistTransfer(text);
    if (document == null) return false;

    final report = await ref
        .read(transferMatcherProvider)
        .match(playlistName: document.name, entries: document.entries);
    if (!mounted) return true;

    setState(() {
      _report = report;
      _draft = TransferDraft(report);
      _isParsing = false;
    });
    return true;
  }

  Future<void> _saveTransferDraft(
    TransferReport report,
    TransferDraft draft,
  ) async {
    final songs = draft.songsToImport;
    if (songs.isEmpty || _isSaving) return;
    setState(() => _isSaving = true);
    final playlist = await ref
        .read(myPlaylistsProvider.notifier)
        .importPlaylist(name: report.playlistName, songs: songs);
    if (!mounted) return;
    setState(() => _isSaving = false);
    showInfoSnackBar(context, playlist == null ? '保存失败' : '已保存到我的歌单');
  }

  /// The three-bucket matching report.
  ///
  /// 未匹配 rows are rendered like the others, with the line the user actually
  /// pasted and the reason it failed: an import that silently dropped what it
  /// could not resolve is exactly the failure this report exists to prevent.
  Widget _buildTransferReport() {
    final report = _report!;
    final draft = _draft!;

    return Expanded(
      child: Column(
        children: [
          Expanded(
            // **Non-lazy on purpose.** This started as a `ListView(children:)`,
            // which builds only what the viewport reaches — and this area is only
            // ~283px tall on a phone (the header above it is tall), so the 未匹配
            // section, i.e. the answer to "what did *not* transfer", could sit
            // outside the build window entirely: measured, it was not mounted
            // until the user scrolled.
            //
            // Raising `cacheExtent` (later `scrollCacheExtent: ScrollCacheExtent
            // .pixels(2000)`) did **not** fix that — verified by probe: with a
            // 283px viewport the third section was still absent before scrolling
            // and appeared only after a 500px drag. So laziness itself is the
            // problem, not its size.
            //
            // A matching report is meant to be read as a unit — the three buckets
            // are one answer, and the user should not have to discover that it
            // scrolls. A very long playlist therefore builds all its rows in one
            // frame; import reports run to tens or hundreds of rows, which is an
            // accepted cost for never hiding a bucket.
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(top: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '匹配结果：${report.playlistName}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    '将导入 ${draft.songsToImport.length} 首',
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (report.exact.isNotEmpty) ...[
                    _reportSection(
                      '可入 (${report.exactCount})',
                      '自动加入，无需确认',
                    ),
                    for (final match in report.exact) _reportRow(match, draft),
                  ],
                  if (report.needsConfirmation.isNotEmpty) ...[
                    _reportSection(
                      '待确认 (${report.needsConfirmationCount})',
                      '点一下选择要导入的',
                    ),
                    for (final match in report.needsConfirmation)
                      _reportRow(match, draft),
                  ],
                  if (report.missing.isNotEmpty) ...[
                    _reportSection(
                      '未匹配 (${report.missingCount})',
                      '这些没能找到，已保留原文',
                    ),
                    for (final match in report.missing)
                      _reportRow(match, draft),
                  ],
                ],
              ),
            ),
          ),
          // Outside the scroll view on purpose: the primary action must stay
          // reachable however long the report gets.
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: draft.songsToImport.isEmpty || _isSaving
                    ? null
                    : () => _saveTransferDraft(report, draft),
                child: const Text('保存到我的歌单'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _reportSection(String title, String hint) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 16, 0, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          Text(
            hint,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _reportRow(TransferMatch match, TransferDraft draft) {
    final cs = Theme.of(context).colorScheme;
    final song = match.song;
    final subtitle = switch (match.kind) {
      TransferMatchKind.exact => song == null
          ? null
          : '→ ${song.name} - ${song.artistNames}',
      TransferMatchKind.needsConfirmation => song == null
          ? null
          : '待确认：${song.name} - ${song.artistNames}',
      TransferMatchKind.missing => match.reason ?? '未找到可播放版本',
    };
    final subtitleWidget = subtitle == null
        ? null
        : Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          );

    // Only 待确认 rows are selectable: 可入 is imported regardless and 未匹配 has
    // nothing to import.
    if (match.kind == TransferMatchKind.needsConfirmation) {
      return CheckboxListTile(
        dense: true,
        controlAffinity: ListTileControlAffinity.leading,
        value: draft.isAccepted(match),
        onChanged: (_) => setState(() => draft.toggle(match)),
        title: Text(
          match.entry.display,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: subtitleWidget,
      );
    }

    return ListTile(
      dense: true,
      title: Text(
        match.entry.display,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: subtitleWidget,
      leading: Icon(
        match.kind == TransferMatchKind.missing
            ? Icons.search_off
            : Icons.check_circle_outline,
        size: 20,
        color: match.kind == TransferMatchKind.missing
            ? cs.outline
            : cs.primary,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // A share that turned out to be a playlist document is parked in
    // `pendingPlaylistTransferProvider` by the deep-link wiring, because the
    // handler can only return a route name. Consume it once, then clear the slot
    // so a rebuild cannot import the same document again.
    final pending = ref.watch(pendingPlaylistTransferProvider);
    if (pending != null && pending != _pendingInFlight) {
      _pendingInFlight = pending;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(pendingPlaylistTransferProvider.notifier).state = null;
        _controller.text = pending;
        unawaited(_parseLink());
      });
    }

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
              '支持网易云、QQ音乐、酷狗音乐的分享链接；'
              '也可以粘贴 M3U8、Mconnect JSON 或「歌名 - 歌手」文本',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    // A pasted m3u8 / JSON / `歌名 - 歌手` list is inherently
                    // multi-line, and a single-line field is the wrong shape for
                    // it: the document is invisible (one line of it, at that) and
                    // a multi-line edit collapses at the newline. Grows with the
                    // content up to [maxLines], then scrolls internally.
                    minLines: 1,
                    maxLines: 6,
                    keyboardType: TextInputType.multiline,
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
            if (_report != null && _draft != null) _buildTransferReport(),
          ],
        ),
      ),
    );
  }
}
