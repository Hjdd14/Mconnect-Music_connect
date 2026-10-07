import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mconnect/features/download/data/saf_document_tree.dart';
import 'package:mconnect/features/download/data/saf_tree_store.dart';

void main() {
  // Method-channel mocking and Hive both need a live test binding.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SafTreeSelection persistence', () {
    test('the in-memory store round-trips a selection', () async {
      final store = MemorySafTreeStore();
      expect(await store.read(), isNull);

      final selection = SafTreeSelection(
        uri: 'content://com.android.externalstorage.documents/tree/primary%3AMusic',
        name: 'Music',
        grantedAt: DateTime(2026, 10, 8, 9, 30),
      );
      await store.save(selection);

      final read = await store.read();
      expect(read, isNotNull);
      expect(read!.uri, selection.uri);
      expect(read.name, 'Music');

      await store.clear();
      expect(await store.read(), isNull);
    });

    test('the Hive store coexists with the legacy plain path', () async {
      final tempDir = await Directory.systemTemp.createTemp('mconnect_saf_box_');
      addTearDown(() async {
        await Hive.close();
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      Hive.init(tempDir.path);
      final box = await Hive.openBox<dynamic>(HiveSafTreeStore.boxName);

      // What an older build wrote: a bare filesystem path.
      await box.put('custom_root_path', 'D:/Music/Downloads');

      final store = HiveSafTreeStore();
      await store.save(
        SafTreeSelection(
          uri: 'content://tree/primary%3AMusic',
          name: 'Music',
          grantedAt: DateTime(2026, 10, 8),
        ),
      );

      final read = await store.read();
      expect(read!.uri, 'content://tree/primary%3AMusic');
      expect(read.name, 'Music');
      // The legacy key is untouched: choosing a SAF folder must not destroy the
      // directory an earlier build saved.
      expect(box.get('custom_root_path'), 'D:/Music/Downloads');

      await store.clear();
      expect(await store.read(), isNull);
      expect(box.get('custom_root_path'), 'D:/Music/Downloads');
    });

    test('the Hive store degrades to "nothing saved" when Hive is unavailable', () async {
      // No Hive.init() in this test: opening the box fails. The store must not
      // take the app down with it.
      final store = HiveSafTreeStore();
      expect(await store.read(), isNull);
      await store.save(
        SafTreeSelection(
          uri: 'content://x',
          name: 'x',
          grantedAt: DateTime(2026),
        ),
      );
      await store.clear();
      expect(await store.read(), isNull);
    });
  });

  group('MethodChannelSafDocumentTree', () {
    const channel = MethodChannel(MethodChannelSafDocumentTree.channelName);
    final calls = <MethodCall>[];

    setUp(() {
      calls.clear();
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    void mock(Object? Function(MethodCall call) respond) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return respond(call);
          });
    }

    test('pickDirectory parses the tree grant the Kotlin side returns', () async {
      mock(
        (call) => {
          'uri': 'content://com.android.externalstorage.documents/tree/primary%3AMusic',
          'name': 'Music',
          'canRead': true,
          'canWrite': true,
        },
      );

      final selection = await MethodChannelSafDocumentTree().pickDirectory();

      expect(calls.single.method, 'pickDirectory');
      expect(
        selection!.uri,
        'content://com.android.externalstorage.documents/tree/primary%3AMusic',
      );
      expect(selection.name, 'Music');
    });

    test('pickDirectory returns null when the user cancels', () async {
      mock((call) => null);
      expect(await MethodChannelSafDocumentTree().pickDirectory(), isNull);
    });

    test('isGranted sends the uri and reads the boolean back', () async {
      mock((call) => true);
      final granted = await MethodChannelSafDocumentTree().isGranted(
        'content://tree/1',
      );

      expect(granted, isTrue);
      expect(calls.single.method, 'isGranted');
      expect(calls.single.arguments, {'uri': 'content://tree/1'});
    });

    test('copyToTree sends the full copy request and parses the result', () async {
      mock(
        (call) => {
          'bytes': 4096,
          'uri': 'content://tree/1/document/song.mp3',
          'displayName': 'song.mp3',
        },
      );

      final result = await MethodChannelSafDocumentTree().copyToTree(
        treeUri: 'content://tree/1',
        relativePath: 'netease/mp3',
        fileName: 'song.mp3',
        sourcePath: 'C:/tmp/staging/song.mp3',
      );

      expect(calls.single.method, 'copyToTree');
      expect(calls.single.arguments, {
        'uri': 'content://tree/1',
        'relativePath': 'netease/mp3',
        'fileName': 'song.mp3',
        'sourcePath': 'C:/tmp/staging/song.mp3',
      });
      expect(result.bytes, 4096);
      expect(result.uri, 'content://tree/1/document/song.mp3');
      expect(result.displayName, 'song.mp3');
    });

    test('a PERMISSION_LOST platform error is classified as re-pickable', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            throw PlatformException(
              code: SafErrorCodes.permissionLost,
              message: '自定义目录的写入权限已失效，请重新选择目录',
            );
          });

      await expectLater(
        MethodChannelSafDocumentTree().copyToTree(
          treeUri: 'content://tree/1',
          relativePath: '',
          fileName: 'a.mp3',
          sourcePath: 'C:/tmp/a.mp3',
        ),
        throwsA(
          isA<SafDocumentTreeException>()
              .having((e) => e.code, 'code', SafErrorCodes.permissionLost)
              .having((e) => e.isPermissionProblem, 'isPermissionProblem', isTrue),
        ),
      );
    });

    test('a missing platform implementation is not a crash', () async {
      // No mock handler at all: this is what desktop and unit tests see.
      await expectLater(
        MethodChannelSafDocumentTree().isGranted('content://tree/1'),
        throwsA(
          isA<SafDocumentTreeException>().having(
            (e) => e.code,
            'code',
            SafErrorCodes.treeUnavailable,
          ),
        ),
      );
    });

    test('openTree reports whether a file manager accepted the folder', () async {
      mock((call) => true);
      expect(await MethodChannelSafDocumentTree().openTree('content://tree/1'), isTrue);
      expect(calls.single.method, 'openTree');
      expect(calls.single.arguments, {'uri': 'content://tree/1'});
    });
  });

  test('the platform error codes cover the Kotlin contract', () {
    // A guard against the two halves drifting apart: these strings are the
    // contract with SafDocumentTreeController.kt.
    expect(SafErrorCodes.permissionCodes, {
      'PERSIST_FAILED',
      'PERMISSION_LOST',
      'TREE_UNAVAILABLE',
    });
    expect(SafErrorCodes.sizeMismatch, 'SIZE_MISMATCH');
    expect(MethodChannelSafDocumentTree.channelName, 'com.mconnect.mconnect/saf_tree');
  });
}
