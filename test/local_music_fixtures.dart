import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:mconnect/features/local_music/data/local_metadata_reader.dart';

/// Real (if tiny) FLAC files for the local-music tests.
///
/// The scanner's contract is "read the tags, fall back to the file name only
/// when there is no tag container", and that cannot be asserted with a stub
/// parser: a fixture that is not a real FLAC would take the *fallback* path and
/// the test would pass while proving nothing. So this builds the smallest valid
/// FLAC the `audio_metadata_reader` parser accepts — `fLaC` marker, a STREAMINFO
/// block (sample rate / channels / bit depth / total samples → real duration)
/// and a VORBIS_COMMENT block with TITLE/ARTIST/ALBUM/TRACKNUMBER — optionally
/// followed by a PICTURE block.
Uint8List buildFlacFixture({
  required String title,
  required String artist,
  required String album,
  int? trackNumber,
  int durationMs = 3000,
  int sampleRate = 44100,
  int channels = 2,
  int bitsPerSample = 16,
  int paddingBytes = 4096,
  Uint8List? coverBytes,
  String coverMime = 'image/jpeg',
}) {
  final blocks = BytesBuilder();
  blocks.add(ascii.encode('fLaC'));

  final hasPicture = coverBytes != null && coverBytes.isNotEmpty;

  // --- STREAMINFO (block type 0, 34 bytes) ---
  blocks.add(_blockHeader(type: 0, length: 34));
  blocks.add(_uint16(4096)); // min block size
  blocks.add(_uint16(4096)); // max block size
  blocks.add(_uint24(0)); // min frame size
  blocks.add(_uint24(0)); // max frame size
  final totalSamples = (sampleRate * durationMs / 1000).round();
  final packed =
      (sampleRate << 44) |
      ((channels - 1) << 41) |
      ((bitsPerSample - 1) << 36) |
      totalSamples;
  blocks.add(_uint64(packed));
  blocks.add(Uint8List(16)); // MD5

  // --- PADDING (block type 1) so a "real" library has some bytes to walk ---
  if (paddingBytes > 0) {
    blocks.add(_blockHeader(type: 1, length: paddingBytes));
    blocks.add(Uint8List(paddingBytes));
  }

  // --- VORBIS_COMMENT (block type 4) ---
  final comments = <String, String>{
    'TITLE': title,
    'ARTIST': artist,
    'ALBUM': album,
    if (trackNumber != null) 'TRACKNUMBER': '$trackNumber',
  };
  final commentBytes = BytesBuilder();
  const vendor = 'mconnect-test';
  commentBytes.add(_uint32le(vendor.length));
  commentBytes.add(ascii.encode(vendor));
  commentBytes.add(_uint32le(comments.length));
  comments.forEach((key, value) {
    final entry = utf8.encode('$key=$value');
    commentBytes.add(_uint32le(entry.length));
    commentBytes.add(entry);
  });
  final comment = commentBytes.takeBytes();
  blocks.add(_blockHeader(type: 4, length: comment.length, isLast: !hasPicture));
  blocks.add(comment);

  // --- PICTURE (block type 6), last ---
  if (hasPicture) {
    final picture = BytesBuilder();
    final mime = ascii.encode(coverMime);
    picture.add(_uint32(3)); // picture type: front cover
    picture.add(_uint32(mime.length));
    picture.add(mime);
    picture.add(_uint32(0)); // empty description
    picture.add(_uint32(1)); // width
    picture.add(_uint32(1)); // height
    picture.add(_uint32(24)); // depth
    picture.add(_uint32(0)); // colors
    picture.add(_uint32(coverBytes.length));
    picture.add(coverBytes);
    final pictureBytes = picture.takeBytes();
    blocks.add(_blockHeader(type: 6, length: pictureBytes.length, isLast: true));
    blocks.add(pictureBytes);
  }

  return blocks.takeBytes();
}

/// Writes a [buildFlacFixture] file.
Future<File> writeFlacFixture(
  Directory directory,
  String fileName, {
  required String title,
  required String artist,
  required String album,
  int? trackNumber,
  int durationMs = 3000,
  int paddingBytes = 4096,
  Uint8List? coverBytes,
}) async {
  final file = File('${directory.path}${Platform.pathSeparator}$fileName');
  await file.parent.create(recursive: true);
  await file.writeAsBytes(
    buildFlacFixture(
      title: title,
      artist: artist,
      album: album,
      trackNumber: trackNumber,
      durationMs: durationMs,
      paddingBytes: paddingBytes,
      coverBytes: coverBytes,
    ),
  );
  return file;
}

/// A 1x1 PNG, small enough to inline but a real image container.
Uint8List tinyPngBytes() => Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
]);

/// Counts how often metadata is read, and which files were opened.
///
/// The incremental-scan assertions are about this counter, not about the
/// parser: "the second scan does not re-read metadata" is exactly
/// `reader.calls == 3` after two scans of a three-track library.
class CountingMetadataReader implements LocalMetadataReader {
  CountingMetadataReader({LocalMetadataReader? inner})
    : inner = inner ?? AudioMetadataReader();

  final LocalMetadataReader inner;
  int calls = 0;
  final List<String> readPaths = [];

  @override
  LocalAudioMetadata? read(String path, {bool coverArt = true}) {
    calls++;
    readPaths.add(path);
    return inner.read(path, coverArt: coverArt);
  }
}

/// Deterministic lyrics payload "encrypted" with the KRC container, so the
/// decoder can be checked against a known plaintext.
String krcFixture({
  int lines = 3,
  String textPrefix = '词',
}) {
  final buffer = StringBuffer();
  for (var i = 0; i < lines; i++) {
    final start = 1000 * (i + 1);
    buffer.write(
      '[$start,400]<0,200,0>$textPrefix$i<200,200,0>第二段\n',
    );
  }
  return buffer.toString();
}

Uint8List _uint16(int value) => Uint8List.fromList([
  (value >> 8) & 0xFF,
  value & 0xFF,
]);

Uint8List _uint24(int value) => Uint8List.fromList([
  (value >> 16) & 0xFF,
  (value >> 8) & 0xFF,
  value & 0xFF,
]);

Uint8List _uint32(int value) => Uint8List.fromList([
  (value >> 24) & 0xFF,
  (value >> 16) & 0xFF,
  (value >> 8) & 0xFF,
  value & 0xFF,
]);

Uint8List _uint32le(int value) => Uint8List.fromList([
  value & 0xFF,
  (value >> 8) & 0xFF,
  (value >> 16) & 0xFF,
  (value >> 24) & 0xFF,
]);

Uint8List _uint64(int value) {
  final data = ByteData(8)..setUint64(0, value);
  return data.buffer.asUint8List();
}

Uint8List _blockHeader({
  required int type,
  required int length,
  bool isLast = false,
}) {
  return Uint8List.fromList([
    (isLast ? 0x80 : 0x00) | (type & 0x7F),
    (length >> 16) & 0xFF,
    (length >> 8) & 0xFF,
    length & 0xFF,
  ]);
}
