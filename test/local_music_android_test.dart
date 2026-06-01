import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android native local music picker uses SAF tree scanning', () {
    final source = File(
      'android/app/src/main/kotlin/com/mconnect/mconnect/MainActivity.kt',
    ).readAsStringSync();

    expect(source, contains('localMusicChannel'));
    expect(source, contains('Intent.ACTION_OPEN_DOCUMENT_TREE'));
    expect(source, contains('takePersistableUriPermission'));
    expect(source, contains('DocumentFile.fromTreeUri'));
    expect(source, contains('scanDocumentTree'));
  });

  test('Android manifest uses scoped audio permissions', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    expect(manifest, contains('android.permission.READ_MEDIA_AUDIO'));
    expect(manifest, contains('android:maxSdkVersion="32"'));
    expect(manifest, contains('android.permission.READ_EXTERNAL_STORAGE'));
    expect(manifest, isNot(contains('MANAGE_EXTERNAL_STORAGE')));
  });

  test('Android build includes DocumentFile for SAF traversal', () {
    final buildFile = File('android/app/build.gradle.kts').readAsStringSync();

    expect(buildFile, contains('androidx.documentfile:documentfile'));
  });
}
