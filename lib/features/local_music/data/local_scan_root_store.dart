import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Remembers the folder the user picked, so opening the local page again
/// rescans the *same* library (incrementally) instead of forcing another
/// folder-picker round trip.
///
/// On Android the value is the SAF **tree URI** — `MainActivity` already calls
/// `takePersistableUriPermission` (`MainActivity.kt:113`), but until now nothing
/// stored the URI, so that persisted grant was thrown away and the user had to
/// re-pick the folder after every restart (H-16).
abstract class LocalScanRootStore {
  Future<String?> read();

  Future<void> write(String root);

  Future<void> clear();
}

/// Hive-backed store. The main isolate opens the `settings` box at startup
/// (`main.dart:98`); this uses its own small box so a settings migration cannot
/// wipe the library root, and degrades to "no root remembered" when Hive is not
/// available (unit tests, desktop headless runs) rather than throwing.
class HiveLocalScanRootStore implements LocalScanRootStore {
  HiveLocalScanRootStore({this.boxName = 'local_music', this.key = 'scan_root'});

  final String boxName;
  final String key;

  Future<Box<dynamic>?> _box() async {
    try {
      if (Hive.isBoxOpen(boxName)) return Hive.box<dynamic>(boxName);
      return await Hive.openBox<dynamic>(boxName);
    } catch (error) {
      debugPrint('LocalScanRootStore: Hive unavailable ($error)');
      return null;
    }
  }

  @override
  Future<String?> read() async {
    final box = await _box();
    final value = box?.get(key);
    if (value is String && value.trim().isNotEmpty) return value;
    return null;
  }

  @override
  Future<void> write(String root) async {
    final box = await _box();
    if (box == null) return;
    try {
      await box.put(key, root);
    } catch (error) {
      debugPrint('LocalScanRootStore: write failed ($error)');
    }
  }

  @override
  Future<void> clear() async {
    final box = await _box();
    if (box == null) return;
    try {
      await box.delete(key);
    } catch (_) {}
  }
}

/// In-memory store for tests.
class MemoryLocalScanRootStore implements LocalScanRootStore {
  String? _root;

  MemoryLocalScanRootStore([this._root]);

  @override
  Future<String?> read() async => _root;

  @override
  Future<void> write(String root) async => _root = root;

  @override
  Future<void> clear() async => _root = null;
}
