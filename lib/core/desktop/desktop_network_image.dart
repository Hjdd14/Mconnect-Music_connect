import 'package:flutter/material.dart';

/// Desktop cover loader that bypasses flutter_cache_manager.
///
/// The desktop build can deny the temp directory that the default
/// CachedNetworkImage manager uses (the same environment that denied Hive's
/// profile path). CachedNetworkImage then answers its errorWidget for every
/// cover even though the URL is a perfectly valid HTTP image. The hero cards
/// already use Image.network and render, so desktop covers use the same path:
/// Flutter's in-memory image cache still applies, only the disk cache layer is
/// dropped.
class DesktopNetworkImage extends StatelessWidget {
  final String url;
  final BoxFit fit;
  final int? cacheWidth;
  final Widget placeholder;
  final Widget error;

  const DesktopNetworkImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.cacheWidth,
    required this.placeholder,
    required this.error,
  });

  @override
  Widget build(BuildContext context) {
    return Image.network(
      url,
      fit: fit,
      cacheWidth: cacheWidth,
      loadingBuilder: (context, child, progress) =>
          progress == null ? child : placeholder,
      errorBuilder: (_, _, _) => error,
    );
  }
}
