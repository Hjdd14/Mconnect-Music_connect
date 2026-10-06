import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/constants/app_constants.dart';
import '../domain/backup_models.dart';
import 'backup_store.dart';

/// Single-file JSON backup: `BackupManifest` + likes / playlists / smart rules /
/// settings / play events.
///
/// Design rules the implementation follows:
/// * **nothing is written before the whole file parses** — a truncated or
///   hand-edited file must not half-import;
/// * a **newer** format version is refused (downgrade safety);
/// * import **merges**, it never wipes first, so importing the same file twice is
///   idempotent and an import cannot destroy local data the file lacks.
class BackupService {
  BackupService({
    required this.store,
    this.appVersion = AppConstants.appVersion,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final BackupStore store;
  final String appVersion;
  final DateTime Function() _clock;

  static const String filePrefix = 'mconnect-backup-';

  Future<String> exportToJson() async {
    final data = await store.collect();
    final manifest = BackupManifest(
      version: backupFormatVersion,
      exportedAt: _clock(),
      appVersion: appVersion,
      schemaVersion: store.schemaVersion,
    );
    return const JsonEncoder.withIndent('  ').convert({
      'manifest': manifest.toJson(),
      ...data.toJson(),
    });
  }

  /// Writes the backup next to the app documents (or [directory] in tests).
  Future<File> exportToFile({Directory? directory}) async {
    final json = await exportToJson();
    final target = directory ?? await getApplicationDocumentsDirectory();
    if (!await target.exists()) {
      await target.create(recursive: true);
    }
    final stamp = _timestamp(_clock());
    final file = File(p.join(target.path, '$filePrefix$stamp.json'));
    await file.writeAsString(json, flush: true);
    return file;
  }

  Future<BackupImportReport> importFromJson(String raw) async {
    final parsed = _decode(raw);
    return store.restore(parsed.data);
  }

  /// Parses without touching storage — used by the UI to show what a file
  /// contains before the user confirms the import.
  BackupFileSummary inspect(String raw) {
    final parsed = _decode(raw);
    return BackupFileSummary(
      manifest: parsed.manifest,
      songCount: parsed.data.songs.length,
      likeCount: parsed.data.likes.length,
      playlistCount: parsed.data.playlists.length,
      smartRuleCount: parsed.data.smartRules.length,
      playEventCount: parsed.data.playEvents.length,
      settingsKeyCount: parsed.data.settings.length,
    );
  }

  ({BackupManifest manifest, BackupData data}) _decode(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      throw const BackupFormatException('备份文件为空');
    }
    final dynamic decoded;
    try {
      decoded = jsonDecode(trimmed);
    } catch (e) {
      throw const BackupFormatException('备份文件不是合法的 JSON');
    }
    if (decoded is! Map) {
      throw const BackupFormatException('备份文件顶层必须是一个 JSON 对象');
    }
    final json = Map<String, dynamic>.from(decoded);
    return (
      manifest: BackupManifest.fromJson(json['manifest']),
      data: BackupData.fromJson(json),
    );
  }

  static String _timestamp(DateTime value) {
    final local = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${local.year}${two(local.month)}${two(local.day)}-'
        '${two(local.hour)}${two(local.minute)}${two(local.second)}';
  }
}

/// Public view of a decoded backup file.
class BackupFileSummary {  final BackupManifest manifest;
  final int songCount;
  final int likeCount;
  final int playlistCount;
  final int smartRuleCount;
  final int playEventCount;
  final int settingsKeyCount;

  const BackupFileSummary({
    required this.manifest,
    this.songCount = 0,
    this.likeCount = 0,
    this.playlistCount = 0,
    this.smartRuleCount = 0,
    this.playEventCount = 0,
    this.settingsKeyCount = 0,
  });

  @override
  String toString() {
    return '导出于 ${manifest.exportedAt.toLocal()}（App ${manifest.appVersion}）\n'
        '歌曲 $songCount · 收藏 $likeCount · 自建歌单 $playlistCount · '
        '智能歌单 $smartRuleCount · 播放明细 $playEventCount · '
        '设置 $settingsKeyCount 项';
  }
}
