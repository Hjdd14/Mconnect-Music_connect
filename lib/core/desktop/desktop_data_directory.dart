import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// Writable per-user data root for the Windows desktop build.
///
/// Release prefers %LOCALAPPDATA%\com.mconnect\mconnect; debug prefers a
/// workspace-local directory because the development sandbox can deny writes to
/// the real profile. MCONNECT_DATA_DIR overrides both. Mobile is not a consumer
/// of this helper (it keeps path_provider's app directories).
///
/// A candidate is accepted only after a real file probe. Creating the directory
/// is not enough: a profile can exist but still deny file creation (the DSH
/// sandbox does exactly that), and Hive/drift would then throw before the first
/// frame and leave a white window. If every candidate is denied we throw, and
/// main catches it to show an error screen instead of a blank window.
Future<Directory> desktopDataDirectory({String child = ''}) async {
  final override = Platform.environment['MCONNECT_DATA_DIR'];
  final localAppData = Platform.environment['LOCALAPPDATA'];
  final candidates = <String>[
    if (override != null && override.isNotEmpty) override,
    if (!kDebugMode && localAppData != null && localAppData.isNotEmpty)
      p.join(localAppData, 'com.mconnect', 'mconnect'),
    // Debug/QA first choice, and release fallback when the profile is locked.
    p.join(Directory.current.path, '.mconnect_data'),
    // Last resort: a writable per-user temp directory.
    p.join(Directory.systemTemp.path, 'mconnect_data'),
  ];

  Object? lastError;
  for (final base in candidates.toSet()) {
    try {
      final dir = Directory(p.join(base, child));
      await dir.create(recursive: true);
      final probe = File(p.join(dir.path, '.mconnect_write_probe'));
      await probe.writeAsBytes(const <int>[0], flush: true);
      try {
        await probe.delete();
      } on FileSystemException {
        // The probe proved write access; a failed cleanup is not fatal.
      }
      return dir;
    } catch (error) {
      lastError = error;
      debugPrint('desktopDataDirectory candidate rejected: $base: $error');
    }
  }
  throw FileSystemException(
    'No writable desktop data directory (tried ${candidates.join(', ')}); '
    'last error: $lastError',
  );
}
