import 'dart:async';

import 'package:hive_flutter/hive_flutter.dart';

/// A folder the user granted through SAF, as persisted by the app.
class SafTreeSelection {
  /// The tree URI (`content://com.android.externalstorage.documents/tree/…`).
  final String uri;

  /// Display name of the folder, for the settings row.
  final String name;

  /// When the grant was taken, for diagnostics.
  final DateTime grantedAt;

  const SafTreeSelection({
    required this.uri,
    required this.name,
    required this.grantedAt,
  });

  @override
  String toString() => 'SafTreeSelection($name, $uri)';
}

/// Persistence for the SAF tree URI.
///
/// Deliberately a **separate interface from `DownloadDirectoryStore`**, writing
/// its own keys in the same Hive box: the legacy `custom_root_path` (a plain
/// filesystem path) stays untouched, so a user who picked a folder with the old
/// build keeps it, and both can coexist while the app migrates.
abstract class SafTreeStore {
  Future<SafTreeSelection?> read();

  Future<void> save(SafTreeSelection selection);

  Future<void> clear();
}

class HiveSafTreeStore implements SafTreeStore {
  static const boxName = 'download_settings';
  static const uriKey = 'custom_tree_uri';
  static const nameKey = 'custom_tree_name';

  /// Failure-tolerant on purpose: the store is also constructed on desktop and
  /// inside unit tests, where Hive has not been initialised. Not being able to
  /// remember a folder must not throw at the caller — it reports "nothing
  /// saved", which the callers already handle as "no SAF folder".
  ///
  /// The guarded zone is not paranoia. Before `Hive.initFlutter()` runs,
  /// `Hive.openBox` fails in a way that reaches **both** the returned future and
  /// the ambient zone; `flutter_test` treats that zone copy as a test failure
  /// even when the future error is caught (verified with a probe), so a plain
  /// `try`/`catch` is not enough to keep an unrelated widget test green.
  Future<Box<dynamic>?> _box() async {
    if (Hive.isBoxOpen(boxName)) return Hive.box<dynamic>(boxName);
    Box<dynamic>? box;
    await runZonedGuarded(() async {
      try {
        box = await Hive.openBox<dynamic>(boxName);
      } catch (_) {
        box = null;
      }
    }, (error, stack) {
      box = null;
    });
    return box;
  }

  @override
  Future<SafTreeSelection?> read() async {
    final box = await _box();
    final uri = box?.get(uriKey);
    if (uri is! String || uri.trim().isEmpty) return null;
    final name = box!.get(nameKey);
    return SafTreeSelection(
      uri: uri,
      name: name is String && name.trim().isNotEmpty ? name : uri,
      grantedAt: DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  @override
  Future<void> save(SafTreeSelection selection) async {
    final box = await _box();
    if (box == null) return;
    await box.put(uriKey, selection.uri);
    await box.put(nameKey, selection.name);
  }

  @override
  Future<void> clear() async {
    final box = await _box();
    if (box == null) return;
    await box.delete(uriKey);
    await box.delete(nameKey);
  }
}

/// In-memory store for tests and for platforms without Hive.
class MemorySafTreeStore implements SafTreeStore {
  SafTreeSelection? _selection;

  MemorySafTreeStore([this._selection]);

  @override
  Future<SafTreeSelection?> read() async => _selection;

  @override
  Future<void> save(SafTreeSelection selection) async => _selection = selection;

  @override
  Future<void> clear() async => _selection = null;
}
