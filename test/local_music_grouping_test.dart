import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/features/local_music/data/local_track_store.dart';
import 'package:mconnect/features/local_music/domain/local_library_grouping.dart';
import 'package:path/path.dart' as p;

void main() {
  LocalTrackEntry track({
    required String path,
    String? title,
    String? artist,
    String? album,
    int? trackNumber,
    int durationMs = 180000,
    String? coverPath,
  }) {
    return LocalTrackEntry(
      path: path,
      mtime: 1,
      size: 1,
      title: title,
      artistName: artist,
      albumName: album,
      trackNumber: trackNumber,
      durationMs: durationMs,
      coverPath: coverPath,
    );
  }

  test('album view groups by album, orders by track number and keeps a cover', () {
    final tracks = [
      track(
        path: p.join('C:', 'music', 'b.flac'),
        title: 'B',
        artist: '歌手',
        album: '专辑一',
        trackNumber: 2,
      ),
      track(
        path: p.join('C:', 'music', 'a.flac'),
        title: 'A',
        artist: '歌手',
        album: '专辑一',
        trackNumber: 1,
        coverPath: '/covers/a.jpg',
      ),
      track(
        path: p.join('C:', 'music', 'c.flac'),
        title: 'C',
        artist: '别的歌手',
        album: '专辑二',
      ),
      track(path: p.join('C:', 'music', 'd.flac'), title: 'D', artist: '歌手'),
    ];

    final groups = LocalLibraryGrouping.byAlbum(tracks);

    expect(groups.map((g) => g.title), ['专辑一', '专辑二', '未知专辑']);
    final first = groups.first;
    expect(first.trackCount, 2);
    expect(first.tracks.map((t) => t.title), ['A', 'B']);
    expect(first.coverPath, '/covers/a.jpg');
    expect(first.subtitle, '歌手');
    expect(first.totalDuration, const Duration(milliseconds: 360000));
    expect(groups.last.tracks.single.title, 'D');
  });

  test('artist view groups by artist and reports the album count', () {
    final groups = LocalLibraryGrouping.byArtist([
      track(
        path: p.join('C:', 'music', '1.flac'),
        title: '一',
        artist: '甲',
        album: '专辑A',
      ),
      track(
        path: p.join('C:', 'music', '2.flac'),
        title: '二',
        artist: '甲',
        album: '专辑B',
      ),
      track(path: p.join('C:', 'music', '3.flac'), title: '三'),
    ]);

    expect(groups.map((g) => g.title), ['甲', '未知歌手']);
    expect(groups.first.trackCount, 2);
    expect(groups.first.subtitle, '2 张专辑');
    expect(groups.last.subtitle, '0 张专辑');
  });

  test('folder view groups by directory and shows the path as the subtitle', () {
    final firstDir = p.join('C:', 'music', 'rock');
    final secondDir = p.join('C:', 'music', 'jazz');
    final groups = LocalLibraryGrouping.byFolder([
      track(path: p.join(secondDir, 'b.flac'), title: 'B'),
      track(path: p.join(firstDir, 'z.flac'), title: 'Z'),
      track(path: p.join(firstDir, 'a.flac'), title: 'A'),
    ]);

    expect(groups.map((g) => g.title), ['jazz', 'rock']);
    final rock = groups.last;
    expect(rock.subtitle, firstDir);
    expect(rock.tracks.map((t) => p.basename(t.path)), ['a.flac', 'z.flac']);
  });

  test('an entry with no tags still gets a display name from its path', () {
    final entry = track(
      path: p.join('C:', 'music', 'unknown-song.mp3'),
    );

    expect(entry.displayTitle, 'unknown-song');
    expect(entry.displayArtist, '未知歌手');
    expect(entry.displayAlbum, '未知专辑');
    expect(entry.folderName, 'music');
    expect(entry.toSong().name, 'unknown-song');
    expect(entry.toSong().artistNames, '未知歌手');
  });

  test('a tagged entry is exposed through Song with the real tags', () {
    final entry = track(
      path: p.join('C:', 'music', 'tagged.flac'),
      title: '真标题',
      artist: '真歌手',
      album: '真专辑',
      trackNumber: 7,
      durationMs: 195000,
    );

    final song = entry.toSong();
    expect(song.name, '真标题');
    expect(song.artistNames, '真歌手');
    expect(song.album?.name, '真专辑');
    expect(song.trackNumber, 7);
    expect(song.duration, const Duration(milliseconds: 195000));
    expect(song.coverUrl, isNull, reason: '本地封面走 coverPath，不走网络图片');
  });
}
