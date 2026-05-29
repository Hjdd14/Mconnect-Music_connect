import 'package:flutter/material.dart';

typedef ScrollableControllerBuilder =
    Widget Function(ScrollController controller);

class AppScrollbar extends StatefulWidget {
  final ScrollableControllerBuilder builder;
  final bool thumbVisibility;

  const AppScrollbar({
    super.key,
    required this.builder,
    this.thumbVisibility = true,
  });

  @override
  State<AppScrollbar> createState() => _AppScrollbarState();
}

class _AppScrollbarState extends State<AppScrollbar> {
  late final ScrollController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ScrollController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      controller: _controller,
      thumbVisibility: widget.thumbVisibility,
      interactive: true,
      child: widget.builder(_controller),
    );
  }
}
