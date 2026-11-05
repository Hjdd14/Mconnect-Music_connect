import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/features/download/domain/entities/download_task.dart';
import 'package:mconnect/models/artist.dart';
import 'package:mconnect/models/audio_quality.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/song.dart';
import 'package:mconnect/features/download/data/download_filename.dart';

/// The naming rule this change replaced, kept here as the regression pin.
///
/// It is exactly the old `DownloadTask.fileName` body: artist - name plus
/// quality, with nothing that identifies *which* song. Two releases that share
/// a title and an artist therefore resolved to one path.
String _legacyFileName(Song song, AudioLevel quality) =>
    '${song.artistNames} - ${song.name} [${quality.name}]'
    '.${quality.isLossless ? 'flac' : 'mp3'}';

void _downloadTaskNameTests() {
  const live = Song(
    id: '111',
    platform: PlatformType.netease,
    name: '稻香',
    artists: [Artist(id: 'a1', name: '周杰伦')],
  );
  const remaster = Song(
    id: '222',
    platform: PlatformType.netease,
    name: '稻香',
    artists: [Artist(id: 'a1', name: '周杰伦')],
  );

  test('two songs with one title and artist no longer share a file', () {
    DownloadTask taskOf(Song song) => DownloadTask(
      id: DownloadTask.buildId(song, AudioLevel.low),
      song: song,
      quality: AudioLevel.low,
      createdAt: DateTime(2026, 11, 3),
    );

    final first = taskOf(live).fileName;
    final second = taskOf(remaster).fileName;

    expect(
      _legacyFileName(live, AudioLevel.low),
      _legacyFileName(remaster, AudioLevel.low),
      reason: 'pins the bug: the old rule could not tell the two apart',
    );
    expect(first, isNot(second));
    expect(first, contains('111'));
    expect(second, contains('222'));
  });

  test('the quality still selects the file, and the extension follows it', () {
    String nameFor(AudioLevel level) => DownloadTask(
      id: DownloadTask.buildId(live, level),
      song: live,
      quality: level,
      createdAt: DateTime(2026, 11, 3),
    ).fileName;

    expect(nameFor(AudioLevel.low), endsWith('.mp3'));
    expect(nameFor(AudioLevel.lossless), endsWith('.flac'));
    expect(nameFor(AudioLevel.low), isNot(nameFor(AudioLevel.high)));
    expect(nameFor(AudioLevel.low), startsWith('[netease_111][low] '));
  });

  test('an offline-cache row points at the same file as the manual row', () {
    final manual = DownloadTask(
      id: DownloadTask.buildId(live, AudioLevel.low),
      song: live,
      quality: AudioLevel.low,
      createdAt: DateTime(2026, 11, 3),
    );
    final cache = DownloadTask(
      id: DownloadTask.buildCacheId(live, AudioLevel.low),
      song: live,
      quality: AudioLevel.low,
      isOfflineCache: true,
      createdAt: DateTime(2026, 11, 3),
    );

    expect(cache.fileName, manual.fileName);
  });
}

void main() {
  _downloadTaskNameTests();
  group('illegal characters', () {
    test('every Windows-rejected character becomes an underscore', () {
      final name = safeFileName(r'a/b\c:d*e?f"g<h>i|j', extension: 'mp3');

      for (final illegal in r'\/:*?"<>|'.split('')) {
        expect(
          name,
          isNot(contains(illegal)),
          reason: '"$illegal" must not survive in $name',
        );
      }
      expect(name, 'a_b_c_d_e_f_g_h_i_j.mp3');
    });

    test(
      'control characters are dropped, not carried into the file system',
      () {
        final name = safeFileName('a\u0001b\tc\u007fd', extension: 'mp3');

        expect(name, 'a_b_c_d.mp3');
        expect(name.codeUnits.any((unit) => unit < 0x20), isFalse);
      },
    );

    test(
      'a name that is nothing but illegal characters still yields a file',
      () {
        final name = safeFileName(r'\/:*?"<>|', extension: 'flac');

        expect(name, isNotEmpty);
        expect(name, isNot(startsWith('.')));
        expect(name, endsWith('.flac'));
      },
    );
  });

  group('Windows reserved device names', () {
    test('CON/PRN/AUX/NUL and the COM/LPT families are neutralised', () {
      const reserved = [
        'CON',
        'con',
        'PrN',
        'aux',
        'NUL',
        'COM1',
        'com9',
        'LPT1',
        'lpt9',
      ];

      for (final device in reserved) {
        final name = safeFileName(device, extension: 'mp3');
        final stem = name.substring(0, name.length - '.mp3'.length);
        expect(
          stem.toLowerCase(),
          isNot(device.toLowerCase()),
          reason: '"$device.mp3" cannot be created on Windows',
        );
        expect(
          name.toLowerCase().startsWith('${device.toLowerCase()}.'),
          isFalse,
          reason: 'a device name keeps its meaning with any extension',
        );
      }
    });

    test('a reserved name with a trailing dot is still reserved', () {
      final name = safeFileName('CON.', extension: 'mp3');

      expect(name.toLowerCase(), isNot(startsWith('con.mp3')));
    });

    test('a reserved word inside a longer name is left alone', () {
      expect(
        safeFileName('CONCERT - Live', extension: 'mp3'),
        'CONCERT - Live.mp3',
      );
      expect(safeFileName('Console', extension: 'mp3'), 'Console.mp3');
    });
  });

  group('trailing dots and spaces', () {
    test('trailing dots and spaces are trimmed', () {
      expect(safeFileName('name.', extension: 'mp3'), 'name.mp3');
      expect(safeFileName('name   ', extension: 'mp3'), 'name.mp3');
      expect(safeFileName('name. . ', extension: 'mp3'), 'name.mp3');
    });

    test('leading spaces are trimmed so the name does not look broken', () {
      expect(safeFileName('  name', extension: 'mp3'), 'name.mp3');
    });

    test('dots that are part of the name are kept', () {
      expect(
        safeFileName('Mr. Brightside', extension: 'mp3'),
        'Mr. Brightside.mp3',
      );
    });
  });

  group('byte budget', () {
    test('a long CJK name stays within 255 UTF-8 bytes', () {
      final name = safeFileName('稻' * 200, extension: 'mp3');

      expect(utf8.encode(name).length, lessThanOrEqualTo(255));
      expect(name, endsWith('.mp3'));
    });

    test('truncation never splits a rune', () {
      // An emoji is one rune but two UTF-16 code units; cutting either half
      // would produce a name with a lone surrogate that no file system accepts.
      final name = safeFileName('🎵' * 120, extension: 'mp3');
      final bytes = utf8.encode(name);

      expect(bytes.length, lessThanOrEqualTo(255));
      expect(
        utf8.decode(bytes),
        name,
        reason: 'the name must round-trip as UTF-8',
      );
      expect(
        name.runes.any((rune) => rune >= 0xD800 && rune <= 0xDFFF),
        isFalse,
      );
    });

    test('the prefix is counted against the budget too', () {
      final name = safeFileName(
        '稻' * 200,
        prefix: '[netease_123456][lossless]',
        extension: 'flac',
      );

      expect(utf8.encode(name).length, lessThanOrEqualTo(255));
      expect(name, startsWith('[netease_123456][lossless] '));
      expect(name, endsWith('.flac'));
    });

    test('a name already inside the budget is returned unchanged', () {
      expect(
        safeFileName('周杰伦 - 稻香', prefix: '[netease_1][high]', extension: 'mp3'),
        '[netease_1][high] 周杰伦 - 稻香.mp3',
      );
    });
  });

  group('extension', () {
    test(
      'the extension is kept verbatim (case normalised) and never truncated',
      () {
        expect(safeFileName('x', extension: '.MP3'), 'x.mp3');
        expect(safeFileName('稻' * 300, extension: '.FLAC'), endsWith('.flac'));
      },
    );

    test('an empty extension produces no trailing dot', () {
      expect(safeFileName('x', extension: ''), 'x');
    });
  });

  group('song id prefix', () {
    test('two songs sharing a name and artist stay distinct', () {
      final first = safeFileName(
        '周杰伦 - 稻香',
        prefix: '[netease_1][low]',
        extension: 'mp3',
      );
      final second = safeFileName(
        '周杰伦 - 稻香',
        prefix: '[netease_2][low]',
        extension: 'mp3',
      );

      expect(first, isNot(second));
    });

    test('the prefix survives truncation of a very long name', () {
      final first = safeFileName(
        '歌' * 200,
        prefix: '[netease_1][low]',
        extension: 'mp3',
      );
      final second = safeFileName(
        '歌' * 200,
        prefix: '[netease_2][low]',
        extension: 'mp3',
      );

      expect(first, startsWith('[netease_1][low]'));
      expect(second, startsWith('[netease_2][low]'));
      expect(first, isNot(second));
    });

    test('a prefix carrying illegal characters is sanitised as well', () {
      final name = safeFileName('song', prefix: '[a/b:c]', extension: 'mp3');

      expect(name, isNot(contains('/')));
      expect(name, isNot(contains(':')));
      expect(name, endsWith('song.mp3'));
    });
  });

  test('the result is idempotent', () {
    final cases = ['a/b\\c:d', 'CON', 'name. . ', '稻' * 200, '🎵' * 120, ''];

    for (final raw in cases) {
      final once = safeFileName(raw, extension: 'mp3');
      final twice = safeFileName(
        once.substring(0, once.length - '.mp3'.length),
        extension: 'mp3',
      );
      expect(twice, once, reason: 'safeFileName must be stable for "$raw"');
    }
  });
}
