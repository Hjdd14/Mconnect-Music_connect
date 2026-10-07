import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/features/download/data/saf_tree_store.dart';

/// Why this file exists: `Hive.openBox` before `Hive.initFlutter()` fails, and
/// the failure must not reach the caller — the SAF store is constructed by the
/// default `DownloadDirectoryService` even in tests that know nothing about SAF.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('reading the SAF store with Hive uninitialised degrades to "nothing saved"', (
    tester,
  ) async {
    final store = HiveSafTreeStore();

    expect(await store.read(), isNull);
    await store.save(
      SafTreeSelection(
        uri: 'content://tree/1',
        name: 'Music',
        grantedAt: DateTime(2026, 10, 8),
      ),
    );
    await store.clear();
    expect(await store.read(), isNull);
  });
}
