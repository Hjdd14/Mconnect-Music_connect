import 'dart:convert';

/// Longest file name NTFS / exFAT / FAT32 accept, counted in UTF-8 bytes.
///
/// Deliberately not 260 (the classic MAX_PATH): the *name* limit and the *path*
/// limit are different limits, and the app cannot know how deep the user's
/// chosen download directory already is. Budgeting the name at 255 bytes keeps
/// root/platform/mp3-or-flac/name inside the path limit for every realistic
/// library root.
const int kMaxFileNameBytes = 255;

/// Characters Windows rejects in a file name. Kept identical on every platform
/// so a library synced between Windows and Android does not rename on sync.
const String _illegalCharacters = r'\/:*?"<>|';

/// DOS device names. A file called con / con.mp3 / CON.tar.gz cannot be created
/// on Windows: the name resolves to the device no matter the extension.
const Set<String> _reservedDeviceNames = {
  'con',
  'prn',
  'aux',
  'nul',
  'com1',
  'com2',
  'com3',
  'com4',
  'com5',
  'com6',
  'com7',
  'com8',
  'com9',
  'lpt1',
  'lpt2',
  'lpt3',
  'lpt4',
  'lpt5',
  'lpt6',
  'lpt7',
  'lpt8',
  'lpt9',
};

/// What an empty (or entirely illegal) name falls back to.
const String _fallbackStem = 'untitled';

/// Builds a file name that every target file system accepts.
///
/// The rules, and the failure each one prevents:
///
/// * **illegal characters** (backslash, slash, colon, star, question mark,
///   double quote, angle brackets, pipe) and control characters become `_.`
///   A song titled AC/DC - Back in Black used to be handed straight to
///   File.openWrite, which fails at *download* time rather than at name time.
/// * **reserved device names** get a `_ inserted in front. CON.mp3 fails to
///   open on Windows with a confusing "access denied" from CreateFile.
/// * **trailing dots and spaces** are trimmed: Windows silently strips them, so
///   the name the app records is not the name on disk, and the recorded path
///   then never matches: every resume re-downloads the file.
/// * **255 UTF-8 bytes** is enforced by dropping whole *runes* from the end, so
///   CJK titles and emoji are cut between characters, never inside one (a lone
///   surrogate is not a valid file name on any platform).
/// * **the extension is never truncated**: it is reserved from the budget first.
///
/// [prefix] is an identity token (song id + quality, say) that goes in **front**
/// of the human part. It belongs in front precisely because truncation eats the
/// tail: a suffix would be cut away for long names and two different songs would
/// silently collide onto one file again - the exact data-loss shape this
/// project's downloader had before (one task resuming from another task's
/// bytes, producing a file that passes the size check and plays as noise).
String safeFileName(
  String baseName, {
  String? prefix,
  required String extension,
  int maxBytes = kMaxFileNameBytes,
}) {
  final suffix = _normaliseExtension(extension);
  final budget = maxBytes - utf8.encode(suffix).length;

  final safePrefix = prefix == null ? '' : _sanitize(prefix);
  var stem = _sanitize(baseName);
  if (stem.isEmpty) stem = _fallbackStem;

  var assembled = safePrefix.isEmpty ? stem : '$safePrefix $stem';
  if (utf8.encode(assembled).length > budget) {
    assembled = _truncateToBytes(assembled, budget);
  }
  if (assembled.isEmpty) assembled = _fallbackStem;
  assembled = _disarmReservedName(assembled);
  return assembled + suffix;
}

/// Replaces every character a file system rejects, and trims the edges.
///
/// Idempotent: sanitising an already-sanitised name changes nothing, which is
/// what lets [safeFileName] be applied to an existing name (see the stability
/// test) without the name drifting on every download.
String _sanitize(String value) {
  final buffer = StringBuffer();
  for (final rune in value.runes) {
    final isControl = rune < 0x20 || rune == 0x7f;
    final isIllegal =
        rune < 0x80 && _illegalCharacters.contains(String.fromCharCode(rune));
    buffer.write(isControl || isIllegal ? '_' : String.fromCharCode(rune));
  }
  // Windows drops trailing dots/spaces on its own; doing it here keeps the name
  // the app records identical to the name on disk.
  return buffer.toString().trim().replaceFirst(RegExp(r'[. ]+$'), '');
}

/// The dotted, lower-case extension; empty for an empty extension.
String _normaliseExtension(String extension) {
  final trimmed = extension
      .trim()
      .replaceFirst(RegExp(r'^[.]+'), '')
      .replaceFirst(RegExp(r'[. ]+$'), '');
  if (trimmed.isEmpty) return '';
  return '.${trimmed.toLowerCase()}';
}

/// Cuts [value] to at most [maxBytes] UTF-8 bytes without splitting a rune.
String _truncateToBytes(String value, int maxBytes) {
  if (maxBytes <= 0) return '';
  final buffer = StringBuffer();
  var used = 0;
  for (final rune in value.runes) {
    final characters = String.fromCharCode(rune);
    final bytes = utf8.encode(characters).length;
    if (used + bytes > maxBytes) break;
    buffer.write(characters);
    used += bytes;
  }
  return _sanitize(buffer.toString());
}

/// Puts an underscore in front of a name Windows would resolve to a device.
///
/// The check is on the part before the first dot, because that is how Windows
/// reads it: CON.mp3 and CON.tar.gz are both the console device.
String _disarmReservedName(String value) {
  final firstSegment = value.split('.').first.trim().toLowerCase();
  if (!_reservedDeviceNames.contains(firstSegment)) return value;
  return '_$value';
}
