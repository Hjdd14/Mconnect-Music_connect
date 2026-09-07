import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../lyrics/models/lyrics_line.dart';
import '../providers/lyrics_provider.dart';
import '../providers/player_provider.dart';
import 'word_by_word_lyrics.dart';

/// Full lyrics display with auto-scrolling and line/word highlighting.
class LyricsDisplay extends ConsumerStatefulWidget {
  final bool isVisible;

  const LyricsDisplay({super.key, this.isVisible = true});

  @override
  ConsumerState<LyricsDisplay> createState() => _LyricsDisplayState();
}

class _LyricsDisplayState extends ConsumerState<LyricsDisplay> {
  static const double _listVerticalPadding = 80;
  static const double _estimatedLineExtent = 48;

  final ScrollController _scrollController = ScrollController();
  final List<GlobalKey> _itemKeys = [];
  final List<GlobalKey> _lineAnchorKeys = [];
  int _currentLineIndex = -1;
  bool _userScrolling = false;
  Timer? _scrollTimer;
  Timer? _positionTimer;
  Duration _position = Duration.zero;
  String? _lastSongId;
  LyricsDocument? _lastDocument;

  @override
  void didUpdateWidget(covariant LyricsDisplay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isVisible && widget.isVisible) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _scrollToLine(_currentLineIndex, force: true);
      });
    }
  }

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
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      _pauseAutoScrollForUser();
      return;
    }
    if (notification is ScrollUpdateNotification &&
        notification.dragDetails != null) {
      _pauseAutoScrollForUser();
    }
  }

  void _pauseAutoScrollForUser() {
    _userScrolling = true;
    _scrollTimer?.cancel();
    _scrollTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) _userScrolling = false;
    });
  }

  void _resetAutoScrollState() {
    _userScrolling = false;
    _scrollTimer?.cancel();
    _scrollTimer = null;
  }

  void _scrollToLine(
    int index, {
    bool force = false,
    bool allowEstimate = true,
  }) {
    if (!widget.isVisible) return;
    if (_userScrolling && !force) return;
    if (!_scrollController.hasClients) return;
    if (index < 0 || index >= _itemKeys.length) return;

    final key = _lineAnchorKeys[index];
    final context = key.currentContext;
    if (context == null) {
      if (allowEstimate) {
        _scrollToEstimatedLineOffset(index, force: force);
      }
      return;
    }

    final itemBox = context.findRenderObject();
    final scrollableContext = _scrollController.position.context.storageContext;
    final viewportBox = scrollableContext.findRenderObject();
    if (itemBox is! RenderBox || viewportBox is! RenderBox) {
      if (allowEstimate) {
        _scrollToEstimatedLineOffset(index, force: force);
      }
      return;
    }

    final itemCenter = itemBox.localToGlobal(
      itemBox.size.center(Offset.zero),
      ancestor: viewportBox,
    );
    final viewportCenter = viewportBox.size.center(Offset.zero);
    final target = _scrollController.offset + itemCenter.dy - viewportCenter.dy;
    final clamped = target.clamp(
      _scrollController.position.minScrollExtent,
      _scrollController.position.maxScrollExtent,
    );
    _scrollController.animateTo(
      clamped.toDouble(),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _scrollToEstimatedLineOffset(int index, {bool force = false}) {
    final position = _scrollController.position;
    final target = _estimateCenteredOffsetFor(index, position);
    final clamped = target.clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    _scrollController
        .animateTo(
          clamped.toDouble(),
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        )
        .whenComplete(() {
          if (!mounted || !widget.isVisible) return;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _scrollToLine(index, force: force, allowEstimate: false);
          });
        });
  }

  double _estimateCenteredOffsetFor(int index, ScrollPosition position) {
    final metrics = _visibleLineMetrics();
    if (metrics.length >= 2) {
      final first = metrics.first;
      final last = metrics.last;
      final lineSpan = last.index - first.index;
      if (lineSpan > 0) {
        final estimatedExtent =
            (last.contentCenter - first.contentCenter) / lineSpan;
        final targetCenter =
            first.contentCenter + ((index - first.index) * estimatedExtent);
        return targetCenter - (position.viewportDimension / 2);
      }
    }

    return _listVerticalPadding +
        (index * _estimatedLineExtent) -
        (position.viewportDimension / 2) +
        (_estimatedLineExtent / 2);
  }

  List<_LineMetric> _visibleLineMetrics() {
    final scrollableContext = _scrollController.position.context.storageContext;
    final viewportBox = scrollableContext.findRenderObject();
    if (viewportBox is! RenderBox) return const [];

    final metrics = <_LineMetric>[];
    for (var i = 0; i < _itemKeys.length; i++) {
      final context =
          _lineAnchorKeys[i].currentContext ?? _itemKeys[i].currentContext;
      final renderObject = context?.findRenderObject();
      if (renderObject is! RenderBox) continue;

      final center = renderObject.localToGlobal(
        renderObject.size.center(Offset.zero),
        ancestor: viewportBox,
      );
      metrics.add(
        _LineMetric(
          index: i,
          contentCenter: _scrollController.offset + center.dy,
        ),
      );
    }
    metrics.sort((a, b) => a.index.compareTo(b.index));
    return metrics;
  }

  int _findCurrentLine(List<LyricsLine> lines, Duration position) {
    if (lines.isEmpty) return -1;

    var active = -1;
    var firstVisible = -1;

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (!_hasVisibleText(line)) continue;
      if (firstVisible == -1) {
        firstVisible = i;
      }
      if (line.timestamp > position) break;
      active = i;
    }

    return active == -1 ? firstVisible : active;
  }

  bool _hasVisibleText(LyricsLine line) {
    return line.text.trim().isNotEmpty ||
        (line.translation?.trim().isNotEmpty ?? false);
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
      error: (error, stackTrace) => Center(
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
        if (songId != _lastSongId || !identical(doc, _lastDocument)) {
          _lastSongId = songId;
          _lastDocument = doc;
          _currentLineIndex = -1;
          _resetAutoScrollState();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            if (_scrollController.hasClients) {
              _scrollController.jumpTo(0);
            }
            if (widget.isVisible) {
              _scrollToLine(_currentLineIndex, force: true);
            }
          });
        }

        // Rebuild item keys if line count changed
        if (_itemKeys.length != doc.lines.length ||
            _lineAnchorKeys.length != doc.lines.length) {
          _itemKeys.clear();
          _lineAnchorKeys.clear();
          _itemKeys.addAll(List.generate(doc.lines.length, (_) => GlobalKey()));
          _lineAnchorKeys.addAll(
            List.generate(doc.lines.length, (_) => GlobalKey()),
          );
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
            padding: const EdgeInsets.symmetric(vertical: _listVerticalPadding),
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
                        primaryKey: _lineAnchorKeys[index],
                        onTap: () => _seekToLine(line),
                      )
                    : _PlainLyricsLine(
                        line: line,
                        isCurrentLine: isCurrent,
                        primaryKey: _lineAnchorKeys[index],
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

class _LineMetric {
  final int index;
  final double contentCenter;

  const _LineMetric({required this.index, required this.contentCenter});
}

class _PlainLyricsLine extends StatelessWidget {
  final LyricsLine line;
  final bool isCurrentLine;
  final Key primaryKey;
  final VoidCallback? onTap;

  const _PlainLyricsLine({
    required this.line,
    required this.isCurrentLine,
    required this.primaryKey,
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
            Text(
              line.text,
              key: line.text.trim().isNotEmpty ? primaryKey : null,
            ),
            if (line.hasTranslation)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  line.translation!,
                  key: line.text.trim().isEmpty ? primaryKey : null,
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
