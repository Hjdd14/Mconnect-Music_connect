import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';

import '../core/share/share_service.dart';

/// 歌词分享图：把卡片渲染成 PNG、落临时文件、交给系统分享面板。
///
/// 分三步各有单一职责，因此每一步都能单独测：挂载卡片 / 截图 / 写文件 / 分享。
/// 真实分享面板需要真机（本机没有），所以 `shareLyricsCard` 把"截图"做成可注入
/// 的（[LyricsCardCapture]），Dart 侧用真实 PNG 字节覆盖编排逻辑。

/// 屏幕外的挂载位置：Flutter 仍会布 局并绘制它，但它不会遮挡界面。
const Offset lyricsShareCardOffscreenOffset = Offset(-10000, 0);

/// 一张临时挂进 Overlay 的卡片，可以在调用方 pump 之后再截图。
class OffscreenCardHandle {
  OffscreenCardHandle._(this.key, this._entry);

  /// 卡片外面那层 `RepaintBoundary` 的 key，交给 [captureBoundaryPng]。
  final GlobalKey key;
  final OverlayEntry _entry;

  void remove() => _entry.remove();
}

/// 把 [card] 临时挂到当前 Overlay 的屏幕外。
///
/// 返回 null 表示当前 context 没有 Overlay（例如 widget 还没挂到树上）。
OffscreenCardHandle? mountOffscreenCard(BuildContext context, Widget card) {
  final overlay = Overlay.maybeOf(context);
  if (overlay == null) return null;
  final key = GlobalKey();
  final entry = OverlayEntry(
    builder: (_) => Positioned(
      left: lyricsShareCardOffscreenOffset.dx,
      top: lyricsShareCardOffscreenOffset.dy,
      child: RepaintBoundary(key: key, child: card),
    ),
  );
  overlay.insert(entry);
  return OffscreenCardHandle._(key, entry);
}

/// 把已经布局绘制过的 `RepaintBoundary` 截成 PNG 字节。
///
/// 调用方必须保证该 boundary 至少经历过一帧（否则 `toImage` 会抛）。
Future<Uint8List?> captureBoundaryPng(
  GlobalKey boundaryKey, {
  double pixelRatio = 2.5,
}) async {
  final boundary = boundaryKey.currentContext?.findRenderObject();
  if (boundary is! RenderRepaintBoundary) return null;
  ui.Image? image;
  try {
    image = await boundary.toImage(pixelRatio: pixelRatio);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  } catch (e) {
    debugPrint('captureBoundaryPng failed: $e');
    return null;
  } finally {
    image?.dispose();
  }
}

/// 把 PNG 写进临时目录，返回文件路径；失败返回 null。
///
/// [directory] 可注入，让测试不必依赖 `path_provider` 插件。
Future<String?> writeLyricsCardPng(
  Uint8List bytes, {
  String fileName = 'mconnect-lyrics.png',
  Future<Directory> Function()? directory,
}) async {
  if (bytes.isEmpty) return null;
  try {
    final dir = await (directory ?? getTemporaryDirectory)();
    final file = File('${dir.path}${Platform.pathSeparator}$fileName');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  } catch (e) {
    debugPrint('writeLyricsCardPng failed: $e');
    return null;
  }
}

/// 播放页用的截图入口：屏幕外挂载 → 等两帧 → 截图 → 摘除。
///
/// 等两帧是因为第一帧只完成布局，`RepaintBoundary` 的 layer 要到绘制之后才可用。
Future<Uint8List?> captureLyricsCardPng(
  BuildContext context, {
  required Widget card,
  double pixelRatio = 2.5,
}) async {
  final handle = mountOffscreenCard(context, card);
  if (handle == null) {
    debugPrint('captureLyricsCardPng: no Overlay in this context');
    return null;
  }
  try {
    await WidgetsBinding.instance.endOfFrame;
    await WidgetsBinding.instance.endOfFrame;
    return await captureBoundaryPng(handle.key, pixelRatio: pixelRatio);
  } finally {
    handle.remove();
  }
}

/// 截图实现（可注入，测试里用真实 boundary 截图代替 Overlay 流程）。
typedef LyricsCardCapture =
    Future<Uint8List?> Function(BuildContext context, Widget card);

/// 截图 → 落临时文件 → 交给分享通道；成功返回分享出去的文件路径。
///
/// 任何一步失败都返回 null（并 debugPrint）：分享是"能分享就分享"的功能，
/// 不该把异常抛进界面。
Future<String?> shareLyricsCard(
  BuildContext context, {
  required Widget card,
  required ShareService shareService,
  String? subject,
  String? text,
  Future<Directory> Function()? directory,
  double pixelRatio = 2.5,
  LyricsCardCapture? capture,
}) async {
  final captureCard =
      capture ?? (ctx, widget) => captureLyricsCardPng(ctx, card: widget, pixelRatio: pixelRatio);
  final bytes = await captureCard(context, card);
  if (bytes == null || bytes.isEmpty) return null;

  final path = await writeLyricsCardPng(bytes, directory: directory);
  if (path == null) return null;

  try {
    await shareService.shareFiles([path], subject: subject, text: text);
  } catch (e) {
    debugPrint('shareLyricsCard failed: $e');
    return null;
  }
  return path;
}
