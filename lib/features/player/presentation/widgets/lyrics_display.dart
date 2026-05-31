import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../lyrics/models/lyrics_line.dart';
import '../providers/lyrics_provider.dart';
import '../providers/player_provider.dart';
import 'word_by_word_lyrics.dart';

/// Full lyrics display with auto-scrolling and line/word highlighting.
class LyricsDisplay extends ConsumerStatefulWidget {
  const LyricsDisplay({super.key});

  @override
  ConsumerState<LyricsDisplay> createState() => _LyricsDisplayState();
}

class _LyricsDisplayState extends ConsumerState<LyricsDisplay> {
  final ScrollController _scrollController = ScrollController();
  final List<GlobalKey> _itemKeys = [];
  int _currentLineIndex = -1;
  bool _userScrolling = false;
  Timer? _scrollTimer;
  Timer? _positionTimer;
  Duration _position = Duration.zero;
  String? _lastSongId;

  @override
  void initState() {
    super.initState();
    _positionTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!mounted) return;
      final next = ref.read(playerProvider).position;
      if (next != _position) {
        setState(() => _position = next);
      }
    });
  }

  @override
  void dispose() {
    _scrollTimer?.cancel();
    _positionTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScrollNotification(ScrollNotification notification) {
    if (notification is UserScrollNotification) {
      _userScrolling = true;
      _scrollTimer?.cancel();
      _scrollTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) _userScrolling = false;
      });
    }
  }

  void _scrollToLine(int index) {
    if (_userScrolling || !_scrollController.hasClients) return;
    if (index < 0 || index >= _itemKeys.length) return;

    final key = _itemKeys[index];
    final context = key.currentContext;
    if (context == null) return;

    Scrollable.ensureVisible(
      context,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      alignment: 0.5, // center in viewport
    );
  }

  int _findCurrentLine(List<LyricsLine> lines, Duration position) {
    if (lines.isEmpty) return -1;

    int low = 0;
    int high = lines.length - 1;

    while (low <= high) {
      final mid = (low + high) ~/ 2;
      if (lines[mid].timestamp <= position) {
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }

    return high;
  }

  @override
  Widget build(BuildContext context) {
    final lyricsAsync = ref.watch(lyricsProvider);
    final position = _position;
    final currentSongId = ref.watch(
      playerProvider.select((s) => s.currentSong?.id),
    );

    return lyricsAsync.when(
      loading: () =>
          const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      error: (_, __) => Center(
        child: Text(
          '歌词加载失败',
          style: TextStyle(color: Theme.of(context).colorScheme.outline),
        ),
      ),
      data: (doc) {
        if (doc == null || doc.lines.isEmpty) {
          return Center(
            child: Text(
              '暂无歌词',
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
          );
        }

        // Reset scroll position when song changes
        final songId = currentSongId;
        if (songId != _lastSongId) {
          _lastSongId = songId;
          _currentLineIndex = -1;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            if (_scrollController.hasClients) {
              _scrollController.jumpTo(0);
            }
          });
        }

        // Rebuild item keys if line count changed
        if (_itemKeys.length != doc.lines.length) {
          _itemKeys.clear();
          _itemKeys.addAll(List.generate(doc.lines.length, (_) => GlobalKey()));
        }

        // Find current line
        final newIndex = _findCurrentLine(doc.lines, position);
        if (newIndex != _currentLineIndex) {
          _currentLineIndex = newIndex;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _scrollToLine(_currentLineIndex);
          });
        }

        final hasWordTiming =
            doc.format == LyricsFormat.qrc || doc.format == LyricsFormat.krc;

        return NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            _onScrollNotification(notification);
            return false;
          },
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.symmetric(vertical: 80),
            itemCount: doc.lines.length,
            itemBuilder: (context, index) {
              final line = doc.lines[index];
              final isCurrent = index == _currentLineIndex;

              return Padding(
                key: _itemKeys[index],
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                child: hasWordTiming
                    ? WordByWordLine(
                        line: line,
                        currentPosition: position,
                        isCurrentLine: isCurrent,
                        onTap: () => _seekToLine(line),
                      )
                    : _PlainLyricsLine(
                        line: line,
                        isCurrentLine: isCurrent,
                        onTap: () => _seekToLine(line),
                      ),
              );
            },
          ),
        );
      },
    );
  }

  void _seekToLine(LyricsLine line) {
    ref.read(playerProvider.notifier).seek(line.timestamp);
  }
}

class _PlainLyricsLine extends StatelessWidget {
  final LyricsLine line;
  final bool isCurrentLine;
  final VoidCallback? onTap;

  const _PlainLyricsLine({
    required this.line,
    required this.isCurrentLine,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedDefaultTextStyle(
        duration: const Duration(milliseconds: 200),
        style: TextStyle(
          fontSize: isCurrentLine ? 20 : 16,
          fontWeight: isCurrentLine ? FontWeight.bold : FontWeight.normal,
          color: isCurrentLine
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.outline,
          height: 1.5,
        ),
        textAlign: TextAlign.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(line.text),
            if (line.hasTranslation)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  line.translation!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: isCurrentLine ? 14 : 12,
                    color: Theme.of(context).colorScheme.outline,
                    height: 1.4,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
