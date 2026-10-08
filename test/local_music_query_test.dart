import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/features/local_music/data/local_track_store.dart';
import 'package:mconnect/features/local_music/domain/local_library_query.dart';

/// The local library's search / sort / filter rules.
///
/// Pure functions, so these run without a widget tree, a database or Riverpod —
/// which is the point: the behaviour is asserted here once instead of being
/// re-derived by every page test.
///
/// Ordering assertions are written as **properties** ("each entry's key is >= the
/// previous one") rather than as hard-coded expected sequences: how the platform
/// orders CJK titles is not this test's subject, and pinning it would make the
/// suite fail on a different ICU/OS build for no reason.
void main() {
  LocalTrackEntry track(
    String path, {
    String? title,
    String? artist,
    String? album,
    int durationMs = 0,
    int? trackNumber,
    int? scannedAt,
    int? mtime,
  }) => LocalTrackEntry(
    path: path,
    mtime: mtime ?? 1000,
    size: 1,
    title: title,
    artistName: artist,
    albumName: album,
    durationMs: durationMs,
    trackNumber: trackNumber,
    scannedAt: scannedAt,
  );

  /// Asserts `result` is ordered by [key].
  void expectOrderedBy(
    List<LocalTrackEntry> result,
    Comparable<Object> Function(LocalTrackEntry) key, {
    bool descending = false,
    String? reason,
  }) {
    for (var index = 1; index < result.length; index++) {
      final comparison = key(result[index - 1]).compareTo(key(result[index]));
      expect(
        descending ? comparison >= 0 : comparison <= 0,
        isTrue,
        reason:
            reason ??
            'entry $index is out of order: '
                '${key(result[index - 1])} vs ${key(result[index])}',
      );
    }
  }

  final dawn = track(
    r'C:\music\稻香.mp3',
    title: '稻香',
    artist: '周杰伦',
    album: '魔杰座',
    durationMs: 223000,
    scannedAt: 300,
  );
  final blue = track(
    r'C:\music\青花瓷.mp3',
    title: '青花瓷',
    artist: '周杰伦',
    album: '我很忙',
    durationMs: 234000,
    scannedAt: 100,
  );
  // No tags at all: displayTitle falls back to the file name.
  final plain = track(
    r'C:\music\untagged.mp3',
    durationMs: 1000,
    scannedAt: 200,
  );

  group('keyword', () {
    test('matches the title, the artist and the album, case-insensitively', () {
      final tracks = [dawn, blue, plain];

      expect(LocalLibraryQuery(keyword: '稻香').apply(tracks), [dawn]);
      expect(LocalLibraryQuery(keyword: '周杰伦').apply(tracks).toSet(), {
        dawn,
        blue,
      });
      expect(LocalLibraryQuery(keyword: '我很忙').apply(tracks), [blue]);
      expect(
        LocalLibraryQuery(keyword: 'UNTAGGED').apply(tracks),
        [plain],
        reason: 'the match is case-insensitive',
      );
      expect(
        LocalLibraryQuery(keyword: '  稻香  ').apply(tracks),
        [dawn],
        reason: 'surrounding whitespace must not defeat the match',
      );
    });

    test('every token must match, so extra words narrow instead of widening',
        () {
      final tracks = [dawn, blue, plain];

      expect(
        LocalLibraryQuery(keyword: '周杰伦 稻香').apply(tracks),
        [dawn],
        reason: 'the second word must narrow the first',
      );
      expect(LocalLibraryQuery(keyword: '周杰伦 不存在').apply(tracks), isEmpty);
    });

    test('an unmatched keyword yields nothing rather than everything', () {
      expect(
        LocalLibraryQuery(keyword: 'zzzz').apply([dawn, blue, plain]),
        isEmpty,
      );
    });
  });

  group('filters', () {
    test('rated / unrated are driven by the ratings map', () {
      final ratings = {localTrackSongKey(dawn): 4};
      final tracks = [dawn, blue, plain];

      expect(
        LocalLibraryQuery(filters: const {LocalTrackFilter.rated}).apply(
          tracks,
          ratings: ratings,
        ),
        [dawn],
      );
      expect(
        LocalLibraryQuery(filters: const {LocalTrackFilter.unrated})
            .apply(tracks, ratings: ratings)
            .toSet(),
        {blue, plain},
        reason: 'an absent entry means unrated, not "unknown"',
      );
      expect(
        LocalLibraryQuery(filters: const {LocalTrackFilter.rated}).apply(
          tracks,
          ratings: {localTrackSongKey(dawn): 0},
        ),
        isEmpty,
        reason: 'a stored 0 is still unrated',
      );
    });

    test('missing metadata needs all three tags to pass', () {
      final tagged = track(
        r'C:\music\tag-and-title.mp3',
        title: '有标题',
        artist: '有歌手',
      );
      final tracks = [dawn, tagged, plain];

      expect(
        LocalLibraryQuery(
          filters: const {LocalTrackFilter.missingMetadata},
        ).apply(tracks).toSet(),
        {tagged, plain},
        reason: 'a row missing only the album still needs attention',
      );
    });

    test('two filters are ANDed, not ORed', () {
      final ratings = {localTrackSongKey(dawn): 5, localTrackSongKey(plain): 3};
      final tracks = [dawn, blue, plain];

      expect(
        LocalLibraryQuery(
          filters: const {
            LocalTrackFilter.rated,
            LocalTrackFilter.missingMetadata,
          },
        ).apply(tracks, ratings: ratings),
        [plain],
        reason: 'rated AND missing metadata',
      );
    });
  });

  group('sort', () {
    test('the default order is by title', () {
      final result = LocalLibraryQuery.none.apply([dawn, blue, plain]);

      expectOrderedBy(result, (entry) => entry.displayTitle.toLowerCase());
      expect(
        result.first,
        plain,
        reason: '"untagged" is ASCII, so it precedes any CJK title',
      );
    });

    test('artist orders by artist, with the title as the tie-break', () {
      final other = track(
        r'C:\music\aaa.mp3',
        title: 'AAA',
        artist: 'AAA',
        album: 'Z专辑',
        durationMs: 5000,
      );
      // `blue` shares 周杰伦 with `dawn`: both must survive the sort, and the one
      // with the smaller title has to come first inside that artist.
      final result = LocalLibraryQuery(
        sort: LocalSortField.artist,
      ).apply([dawn, blue, other, plain]);

      expectOrderedBy(result, (entry) => entry.displayArtist.toLowerCase());
      expect(
        result.first,
        other,
        reason: '"AAA" is ASCII, so it precedes any CJK artist',
      );
      expect(
        result
            .where((entry) => entry.displayArtist == '周杰伦')
            .map((entry) => entry.path)
            .toList(),
        hasLength(2),
        reason: '同一歌手的两首都必须在结果里——tie-break 只决定顺序，不能吞掉行',
      );
      final jayChou = result
          .where((entry) => entry.displayArtist == '周杰伦')
          .toList();
      expect(
        jayChou.first.displayTitle.toLowerCase().compareTo(
              jayChou.last.displayTitle.toLowerCase(),
            ) <=
            0,
        isTrue,
        reason: '同歌手内按标题升序（不断言具体码点，只断言这个性质）',
      );
    });

    test('album orders by album, then by track number', () {
      final first = track(
        r'C:\music\t1.mp3',
        title: '一',
        artist: '同人',
        album: '同专辑',
        trackNumber: 1,
      );
      final second = track(
        r'C:\music\t2.mp3',
        title: '二',
        artist: '同人',
        album: '同专辑',
        trackNumber: 2,
      );
      final result = LocalLibraryQuery(
        sort: LocalSortField.album,
      ).apply([second, dawn, first]);

      expectOrderedBy(result, (entry) => entry.displayAlbum.toLowerCase());
      expect(
        result.indexOf(first) < result.indexOf(second),
        isTrue,
        reason: 'inside one album the track number decides',
      );
    });

    test('duration orders by length', () {
      final tracks = [dawn, blue, plain];
      final result = LocalLibraryQuery(
        sort: LocalSortField.duration,
      ).apply(tracks);

      expectOrderedBy(result, (entry) => entry.durationMs);
      expect(result.first, plain, reason: '1000 ms is the shortest');
      expect(result.last, blue, reason: '234000 ms is the longest');
    });

    test('recently added uses the scan stamp and falls back to the mtime', () {
      final neverScanned = track(r'C:\music\never.mp3', title: 'Z', mtime: 50);
      final result = LocalLibraryQuery(
        sort: LocalSortField.recentlyAdded,
      ).apply([dawn, blue, neverScanned]);

      expectOrderedBy(result, (entry) => entry.scannedAt ?? entry.mtime);
      expect(
        result.first,
        neverScanned,
        reason: 'the row with no scan stamp falls back to its mtime (50)',
      );
      expect(result[1], blue);
      expect(result.last, dawn);
    });

    test('play count comes from the aggregate map', () {
      final counts = {localTrackSongKey(blue): 9};
      final result = LocalLibraryQuery(
        sort: LocalSortField.playCount,
      ).apply([dawn, blue, plain], playCounts: counts);

      expectOrderedBy(
        result,
        (entry) => counts[localTrackSongKey(entry)] ?? 0,
      );
      expect(result.last, blue, reason: 'the only played song sorts last');
    });

    test('descending reverses the primary field', () {
      final tracks = [dawn, blue, plain];

      final byDuration = LocalLibraryQuery(
        sort: LocalSortField.duration,
        descending: true,
      ).apply(tracks);
      expectOrderedBy(
        byDuration,
        (entry) => entry.durationMs,
        descending: true,
      );
      expect(byDuration.first, blue);

      final byTitle = LocalLibraryQuery(descending: true).apply(tracks);
      expectOrderedBy(
        byTitle,
        (entry) => entry.displayTitle.toLowerCase(),
        descending: true,
      );
      expect(byTitle.last, plain);
    });

    test('rows that tie on the primary field keep a stable, path-based order',
        () {
      // Same title, artist, album and duration: without a total order these two
      // would swap places on every rebuild, because `List.sort` is not stable.
      final b = track(r'C:\music\b.mp3', title: '同名', artist: '同人');
      final a = track(r'C:\music\a.mp3', title: '同名', artist: '同人');

      final first = LocalLibraryQuery.none.apply([b, a]);
      final second = LocalLibraryQuery.none.apply([a, b]);

      expect(
        first.map((entry) => entry.path).toList(),
        second.map((entry) => entry.path).toList(),
      );
      expect(first.first.path, r'C:\music\a.mp3');
    });

    test('an empty input stays empty for every sort field', () {
      for (final field in LocalSortField.values) {
        expect(LocalLibraryQuery(sort: field).apply(const []), isEmpty);
      }
    });
  });

  group('query object', () {
    test('withFilter returns a fresh set and drops the filter when disabled',
        () {
      const base = LocalLibraryQuery.none;
      final rated = base.withFilter(LocalTrackFilter.rated, true);
      expect(rated.filters, {LocalTrackFilter.rated});
      expect(base.filters, isEmpty, reason: 'the original is untouched');

      final cleared = rated.withFilter(LocalTrackFilter.rated, false);
      expect(cleared.filters, isEmpty);
      expect(cleared.isDefault, isTrue);
    });

    test('a keyword, a filter or a sort makes the query non-default', () {
      expect(const LocalLibraryQuery(keyword: '  ').isDefault, isTrue);
      expect(const LocalLibraryQuery(keyword: 'x').isDefault, isFalse);
      expect(
        const LocalLibraryQuery(filters: {LocalTrackFilter.rated}).isDefault,
        isFalse,
      );
      expect(
        const LocalLibraryQuery(sort: LocalSortField.playCount).isDefault,
        isFalse,
      );
      expect(const LocalLibraryQuery(descending: true).isDefault, isFalse);
    });

    test('the song key of a local track survives a Windows path', () {
      // The key splits at the FIRST colon, so a `C:\…` id must not lose its tail.
      expect(
        localTrackSongKey(track(r'C:\music\a.mp3')),
        r'local:C:\music\a.mp3',
      );
      expect(localTrackSongKey(track('/sdcard/a.mp3')), 'local:/sdcard/a.mp3');
    });
  });
}
