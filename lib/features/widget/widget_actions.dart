import 'package:flutter/foundation.dart';

/// 小组件点击产生的动作。
///
/// URI 约定（与原生 `MconnectWidgetProvider.OPEN_URI` 一致）：
///
///   mconnect://widget/open             → 打开 App 并落到播放页
///   mconnect://widget/togglePlayPause  → 播放/暂停
///   mconnect://widget/next             → 下一首
///   mconnect://widget/previous         → 上一首
///   mconnect://widget/queue            → 打开播放队列页
///
/// 注意 host 必须是 `widget`：本 App 还有 `mconnect://song` / `mconnect://share`
/// 等**分享深链**（`lib/core/share/share_links.dart`，由 ux-parity 持有）。这里只认
/// `widget` host，`parse` 对其它一切返回 null —— **未识别的链接绝不允许移动用户**
/// （和 `InboundLinkHandler` 的既有约定一致）。
enum WidgetActionKind {
  openPlayer,
  openQueue,
  togglePlayPause,
  next,
  previous,
}

/// 一个解析成功的小组件动作。
@immutable
class WidgetAction {
  const WidgetAction(this.kind, {required this.rawUri});

  final WidgetActionKind kind;

  /// 原始 URI 文本。仅用于日志/诊断（不含用户隐私）。
  final String rawUri;

  /// 是否是"控制播放"类动作（其余是"导航"类）。桥接层据此决定要不要碰播放器。
  bool get isTransport =>
      kind == WidgetActionKind.togglePlayPause ||
      kind == WidgetActionKind.next ||
      kind == WidgetActionKind.previous;

  @override
  String toString() => 'WidgetAction($kind, $rawUri)';

  @override
  bool operator ==(Object other) =>
      other is WidgetAction && other.kind == kind && other.rawUri == rawUri;

  @override
  int get hashCode => Object.hash(kind, rawUri);
}

/// 小组件 URI 的解析器（纯函数，可单测，不依赖任何插件）。
class WidgetActions {
  const WidgetActions._();

  static const String scheme = 'mconnect';
  static const String host = 'widget';

  static const String openPlayerUri = 'mconnect://widget/open';
  static const String togglePlayPauseUri = 'mconnect://widget/togglePlayPause';
  static const String nextUri = 'mconnect://widget/next';
  static const String previousUri = 'mconnect://widget/previous';
  static const String queueUri = 'mconnect://widget/queue';

  /// 解析一个来自小组件的 URI；不认识就返回 null（绝不抛异常）。
  static WidgetAction? parse(Uri? uri) {
    if (uri == null) return null;
    if (uri.scheme != scheme) return null;
    if (uri.host != host) return null;

    // `Uri.parse('mconnect://widget/open').path` == '/open'
    final segment = uri.path.replaceFirst('/', '').trim();
    final kind = switch (segment) {
      'open' => WidgetActionKind.openPlayer,
      'queue' => WidgetActionKind.openQueue,
      'togglePlayPause' => WidgetActionKind.togglePlayPause,
      'next' => WidgetActionKind.next,
      'previous' => WidgetActionKind.previous,
      // 也可能是 `mconnect://widget/togglePlayPause/` 这类带尾斜杠的写法
      _ => null,
    };
    if (kind == null) return null;
    return WidgetAction(kind, rawUri: uri.toString());
  }

  /// 便捷入口：直接从字符串解析（平台通道给的就是字符串）。
  static WidgetAction? parseRaw(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final Uri uri;
    try {
      uri = Uri.parse(raw);
    } on FormatException {
      return null;
    }
    return parse(uri);
  }
}
