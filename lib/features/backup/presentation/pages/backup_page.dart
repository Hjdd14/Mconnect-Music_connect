import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../data/backup_service.dart';
import '../../data/backup_store.dart';
import '../../domain/backup_models.dart';

final backupServiceProvider = Provider<BackupService>((ref) {
  return BackupService(store: AppBackupStore(database: database));
});

/// 数据备份与恢复 — single-file JSON export/import of likes, playlists,
/// smart-playlist rules, statistics and settings.
class BackupPage extends ConsumerStatefulWidget {
  const BackupPage({super.key});

  @override
  ConsumerState<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends ConsumerState<BackupPage> {
  bool _busy = false;
  String? _status;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('备份与恢复')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('导出备份', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            '把收藏、自建歌单、智能歌单规则、听歌统计明细与全部设置写入一个 JSON 文件。'
            '文件保存在应用文档目录，可自行复制到网盘或另一台设备。',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy ? null : _export,
            icon: const Icon(Icons.save_alt),
            label: const Text('导出为 JSON 文件'),
          ),
          const Divider(height: 40),
          Text('导入备份', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            '导入是合并操作：同（平台 + 歌曲 id）的收藏与歌曲不会重复，'
            '同名歌单按歌曲去重后合并，设置只覆盖备份里存在的项。'
            '导入前会先展示文件内容并二次确认。',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _busy ? null : _import,
            icon: const Icon(Icons.restore),
            label: const Text('从 JSON 文件导入'),
          ),
          if (_busy) ...[
            const SizedBox(height: 20),
            const LinearProgressIndicator(),
          ],
          if (_status != null) ...[
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(_status!),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                _error!,
                style: TextStyle(color: theme.colorScheme.onErrorContainer),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _export() async {
    setState(() {
      _busy = true;
      _error = null;
      _status = null;
    });
    try {
      final file = await ref.read(backupServiceProvider).exportToFile();
      final sizeKb = (await file.length()) / 1024;
      if (!mounted) return;
      setState(() {
        _status = '已导出：${file.path}\n'
            '大小：${sizeKb.toStringAsFixed(1)} KB';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '导出失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    setState(() {
      _busy = true;
      _error = null;
      _status = null;
    });
    try {
      final picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['json'],
        allowMultiple: false,
        withData: true,
      );
      if (picked == null || picked.files.isEmpty) {
        return;
      }
      final pickedFile = picked.files.single;
      final raw = pickedFile.bytes != null
          ? String.fromCharCodes(pickedFile.bytes!)
          : await File(pickedFile.path!).readAsString();
      if (!mounted) return;

      final service = ref.read(backupServiceProvider);
      final BackupFileSummary summary;
      try {
        summary = service.inspect(raw);
      } on BackupFormatException catch (e) {
        setState(() => _error = '无法解析备份文件：$e');
        return;
      }

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('确认导入'),
          content: Text('$summary\n\n导入为合并操作，不会删除本地已有数据。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('导入'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      if (!mounted) return;

      setState(() => _busy = true);
      final report = await service.importFromJson(raw);
      if (!mounted) return;
      setState(() => _status = '导入完成：$report');
    } on BackupFormatException catch (e) {
      if (mounted) setState(() => _error = '无法解析备份文件：$e');
    } catch (e) {
      if (mounted) setState(() => _error = '导入失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
