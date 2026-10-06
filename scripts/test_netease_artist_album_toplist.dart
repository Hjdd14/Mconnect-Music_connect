// WS-B probe: 网易云 艺人 / 专辑 / 新歌 / 榜单 明文端点实测
//
// 用法:
//   dart run scripts/test_netease_artist_album_toplist.dart
//
// 目的（Wave 1 硬性门禁）：本任务要实现的 7 个 MusicPlatform 方法全部依赖
// 网易云**明文** /api/ 端点。此脚本用与 NeteaseApi 完全相同的 BaseOptions
// （UA / Referer / Origin / 固定 cookie os=pc）实打实请求一次，把
//
//   * HTTP 状态码
//   * 顶层返回字段
//   * 业务字段的形状与样本值
//
// 打印出来并写入 docs/netease-wave-b-probe.md，作为"哪些端点真的可用"的证据。
// 绝不在此脚本里伪造/缓存任何数据：失败就如实打印失败。
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

const String _ua =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Safari/537.36 Chrome/125.0.0.0 '
    'NeteaseMusicDesktop/3.0.18.203152';

const String _cookie =
    'os=pc; appver=3.0.18.203152; osver=Microsoft-Windows-10-Professional-build-22631-64bit'
    '; deviceId=0123456789abcdef; channel=netease'
    '; NMTID=0123456789abcdef; _ntes_nuid=0123456789abcdef0123456789abcdef'
    '; __csrf=0123456789abcdef; __remember_me=true';

/// 周杰伦（网易云艺人 id），艺人/专辑探针用它，稳定存在。
const String kArtistId = '6452';

final _lines = <String>[];

void emit(String s) {
  // ignore: avoid_print
  print(s);
  _lines.add(s);
}

/// 把任意 JSON 压成一行并截断，避免刷屏。
String brief(Object? v, [int max = 420]) {
  if (v == null) return 'null';
  final s = v is String ? v : jsonEncode(v);
  if (s.length <= max) return s;
  return '${s.substring(0, max)}…(len=${s.length})';
}

/// 打印一个 JSON 对象的字段名（可选带样本值），用于核对契约。
String shapeOf(Object? map, {int maxFields = 40}) {
  if (map is! Map) return '<not a map: ${map.runtimeType}>';
  final keys = map.keys.map((k) => k.toString()).toList();
  final shown = keys.take(maxFields).join(', ');
  final suffix = keys.length > maxFields ? ', …(${keys.length} keys)' : '';
  return '$shown$suffix';
}

Map<String, dynamic>? asMap(Object? v) => v is Map ? v.map((k, x) => MapEntry(k.toString(), x)) : null;

List<dynamic>? asList(Object? v) => v is List ? v : null;

class Probe {
  Probe(this.label, this.method);

  final String label;

  /// Requested HTTP method, for the summary table.
  final String method;

  Map<String, dynamic>? body;
  int? status;
  Object? error;
  Duration elapsed = Duration.zero;

  bool get ok => error == null && status == 200 && body != null;

  String get verdict {
    if (error != null) return 'FAILED (transport): $error';
    if (status != 200) return 'FAILED (http $status)';
    if (body == null) return 'FAILED (non-JSON body)';
    return 'OK (http 200)';
  }

  Map<String, dynamic> report = {};
}

Future<Probe> run(
  Dio dio,
  String label, {
  required String method,
  required String path,
  Map<String, dynamic>? query,
  Map<String, dynamic>? form,
}) async {
  final p = Probe(label, method);
  final sw = Stopwatch()..start();
  try {
    late Response<dynamic> res;
    if (method == 'GET') {
      res = await dio.get(path, queryParameters: query);
    } else {
      res = await dio.post(
        path,
        data: form,
        options: Options(contentType: 'application/x-www-form-urlencoded'),
      );
    }
    p.status = res.statusCode;
    final data = res.data;
    if (data is Map) {
      p.body = data.map((k, v) => MapEntry(k.toString(), v));
    } else if (data is String) {
      final decoded = jsonDecode(data);
      if (decoded is Map) {
        p.body = decoded.map((k, v) => MapEntry(k.toString(), v));
      }
    }
  } catch (e) {
    p.error = e;
  }
  sw.stop();
  p.elapsed = sw.elapsed;
  track(p);
  return p;
}

Future<void> main() async {
  final startedAt = DateTime.now();
  final dio = Dio(
    BaseOptions(
      baseUrl: 'https://music.163.com',
      headers: {
        'User-Agent': _ua,
        'Referer': 'https://music.163.com/',
        'Origin': 'https://music.163.com',
        'cookie': _cookie,
      },
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 20),
      // 探针要看到 404/500 的**响应体**，不要让 Dio 直接抛。
      validateStatus: (_) => true,
      responseType: ResponseType.json,
    ),
  );

  emit('# 网易云 WS-B 端点实测（明文 /api/）');
  emit('');
  emit('- 运行时间: ${startedAt.toIso8601String()}');
  emit('- Dart: ${Platform.version}');
  emit('- 目标: https://music.163.com （明文 /api/，无 weapi/eapi 加密）');
  emit('- cookie: `os=pc; appver=3.0.18.203152; …`（与 NeteaseApi 一致）');
  emit('');

  // ---------------------------------------------------------------- 1. 所有榜单
  emit('## 1. getToplists — GET /api/toplist');
  final toplist = await run(dio, 'toplist', method: 'GET', path: '/api/toplist');
  emit('');
  emit('- ${toplist.verdict}, 耗时 ${toplist.elapsed.inMilliseconds}ms');
  if (toplist.ok) {
    final b = toplist.body!;
    emit('- 顶层字段: ${shapeOf(b)}');
    emit('- code=${b['code']}');
    final list = asList(b['list']);
    emit('- `list` 长度: ${list?.length}');
    if (list != null && list.isNotEmpty) {
      final first = asMap(list.first);
      emit('- `list[0]` 字段: ${shapeOf(first)}');
      emit('- `list[0]` 样本: ${brief(first, 500)}');
      // 契约要求字段
      for (final k in const [
        'id',
        'name',
        'coverImgUrl',
        'updateFrequency',
        'trackNumberUpdate',
      ]) {
        final present = first?.containsKey(k) ?? false;
        emit('  - 契约字段 `$k`: ${present ? '存在' : '**缺失**'}');
      }
      // 各字段实际类型（用于解析时定 int/String）
      emit('- 字段类型抽样(list[0..2]):');
      for (final key in const [
        'id',
        'name',
        'coverImgUrl',
        'updateFrequency',
        'trackNumberUpdate',
        'playCount',
        'description',
      ]) {
        final types = list
            .take(3)
            .map((e) => asMap(e)?[key])
            .map((v) => v == null ? 'null' : v.runtimeType.toString())
            .toSet()
            .join('/');
        emit('  - `$key`: $types');
      }
    }
  }

  // ------------------------------------------------------ 2. 榜单曲目（分页）
  emit('');
  emit('## 2. getRankedSongs — POST /api/v6/playlist/detail');
  final detail = await run(
    dio,
    'playlistDetail',
    method: 'POST',
    path: '/api/v6/playlist/detail',
    form: {'id': '3778678', 'n': 1000},
  );
  emit('');
  emit('- ${detail.verdict}, 耗时 ${detail.elapsed.inMilliseconds}ms');
  if (detail.ok) {
    final b = detail.body!;
    emit('- 顶层字段: ${shapeOf(b)}');
    emit('- code=${b['code']}');
    final playlist = asMap(b['playlist']);
    emit('- `playlist` 字段: ${shapeOf(playlist)}');
    emit('- `playlist.name` = ${brief(playlist?['name'], 80)}');
    emit('- `playlist.updateTime` = ${brief(playlist?['updateTime'], 80)}');
    final tracks = asList(playlist?['tracks']);
    final trackIds = asList(playlist?['trackIds']);
    emit('- `playlist.tracks` 长度: ${tracks?.length}');
    emit('- `playlist.trackIds` 长度: ${trackIds?.length}');
    emit('- `playlist.trackCount` = ${brief(playlist?['trackCount'], 40)}');
    if (tracks != null && tracks.isNotEmpty) {
      final t0 = asMap(tracks.first);
      emit('- `tracks[0]` 字段: ${shapeOf(t0)}');
      emit('- `tracks[0]` 样本: ${brief(t0, 500)}');
      emit(
        '- 结论: tracks 已含完整歌曲对象 = ${t0?.containsKey('name') == true && t0?.containsKey('ar') == true}',
      );
    }
    if (trackIds != null && trackIds.isNotEmpty) {
      emit('- `trackIds[0]` = ${brief(trackIds.first, 120)}');
    }
    emit(
      '- 分页判定: tracks(${tracks?.length}) vs trackIds(${trackIds?.length}) → 需要 trackIds 补齐 = ${(trackIds?.length ?? 0) > (tracks?.length ?? 0)}',
    );
  }

  // ---------------------------------------------------------- 2b. 小 n 是否被尊重
  final detailSmall = await run(
    dio,
    'playlistDetail(n=50)',
    method: 'POST',
    path: '/api/v6/playlist/detail',
    form: {'id': '3778678', 'n': 50},
  );
  emit('');
  emit('- 对照: `n=50` → ${detailSmall.verdict}');
  if (detailSmall.ok) {
    final pl = asMap(detailSmall.body!['playlist']);
    emit(
      '  - tracks=${asList(pl?['tracks'])?.length} trackIds=${asList(pl?['trackIds'])?.length}',
    );
  }

  // ------------------------------------------------------------- 3. 新歌速递
  emit('');
  emit('## 3. getNewSongs — GET /api/personalized/newsong');
  final newAll = await run(
    dio,
    'newsong(default)',
    method: 'GET',
    path: '/api/personalized/newsong',
    query: {'limit': 20},
  );
  emit('');
  emit('- 无 type 参数: ${newAll.verdict}, 耗时 ${newAll.elapsed.inMilliseconds}ms');
  if (newAll.ok) {
    final b = newAll.body!;
    emit('- 顶层字段: ${shapeOf(b)}');
    emit('- code=${b['code']}, result 长度=${asList(b['result'])?.length}');
    final result = asList(b['result']);
    if (result != null && result.isNotEmpty) {
      final r0 = asMap(result.first);
      emit('- `result[0]` 字段: ${shapeOf(r0)}');
      emit('- `result[0].type` = ${brief(r0?['type'], 60)}');
      emit('- `result[0].id` = ${brief(r0?['id'], 60)}');
      emit('- `result[0].name` = ${brief(r0?['name'], 60)}');
      emit(
        '- `result[0].song` 存在 = ${r0?.containsKey('song') == true}，字段: ${shapeOf(r0?['song'])}',
      );
      emit('- `result[0]` 样本: ${brief(r0, 600)}');
      final types = result
          .map((e) => asMap(e)?['type']?.toString())
          .toSet()
          .toList();
      emit('- 全量 `type` 取值集合: $types');
      emit(
        '- type=="song" 条数: ${result.where((e) => asMap(e)?['type'] == 'song').length}',
      );
      final firstSong = result.firstWhere(
        (e) => asMap(e)?['type'] == 'song',
        orElse: () => null,
      );
      if (firstSong != null) {
        final s = asMap(asMap(firstSong)?['song']);
        emit('- type==song 的 `song` 字段: ${shapeOf(s)}');
        emit('- type==song 的 `song` 样本: ${brief(s, 600)}');
        for (final k in const ['id', 'name', 'ar', 'al', 'dt', 'fee']) {
          emit('  - `song.$k`: ${s?.containsKey(k) == true ? brief(s![k], 80) : '**缺失**'}');
        }
      }
    }
  }

  for (final region in const [7, 96, 8, 16]) {
    final r = await run(
      dio,
      'newsong(type=$region)',
      method: 'GET',
      path: '/api/personalized/newsong',
      query: {'type': region, 'limit': 5},
    );
    final b = r.body;
    final res0 = asList(b?['result']);
    emit('');
    emit(
      '- `type=$region`: ${r.verdict}, code=${brief(b?['code'], 20)}, result=${res0?.length}, 首条 type=${brief(asMap(res0?.first)?['type'], 20)}',
    );
  }
  // 港台是否可用（契约里有 NewSongRegion.hongKongTaiwan）
  for (final region in const [0, 6, 14, 60]) {
    final r = await run(
      dio,
      'newsong(type=$region)',
      method: 'GET',
      path: '/api/personalized/newsong',
      query: {'type': region, 'limit': 3},
    );
    final b = r.body;
    final res0 = asList(b?['result']);
    emit(
      '- 地区探测 `type=$region`: ${r.verdict}, code=${brief(b?['code'], 20)}, result=${res0?.length}, 首条 type=${brief(asMap(res0?.first)?['type'], 20)}',
    );
  }

  // ------------------------------------------------------------- 4. 艺人详情
  emit('');
  emit('## 4. getArtistDetail — POST /api/artist/head/info/get');
  final artistHead = await run(
    dio,
    'artistHeadInfo',
    method: 'POST',
    path: '/api/artist/head/info/get',
    form: {'id': kArtistId},
  );
  emit('');
  emit('- ${artistHead.verdict}, 耗时 ${artistHead.elapsed.inMilliseconds}ms');
  if (artistHead.body != null) {
    final b = artistHead.body!;
    emit('- 顶层字段: ${shapeOf(b)}');
    emit('- code=${brief(b['code'], 30)}');
    emit('- 样本: ${brief(b, 600)}');
  }

  emit('');
  emit('## 4b. getArtistDetail 备选 — GET /api/artist/{id}');
  final artistLegacy = await run(
    dio,
    'artistLegacy',
    method: 'GET',
    path: '/api/artist/$kArtistId',
  );
  emit('');
  emit('- ${artistLegacy.verdict}, 耗时 ${artistLegacy.elapsed.inMilliseconds}ms');
  if (artistLegacy.ok) {
    final b = artistLegacy.body!;
    emit('- 顶层字段: ${shapeOf(b)}');
    final artist = asMap(b['artist']);
    emit('- `artist` 字段: ${shapeOf(artist)}');
    emit('- `artist.name` = ${brief(artist?['name'], 40)}');
    emit('- `artist.picUrl` = ${brief(artist?['picUrl'], 120)}');
    emit('- `artist.briefDesc` = ${brief(artist?['briefDesc'], 120)}');
    emit('- `artist.musicSize` = ${brief(artist?['musicSize'], 20)}');
    emit('- `artist.albumSize` = ${brief(artist?['albumSize'], 20)}');
    emit('- `artist.fansCount`(粉丝) = ${brief(artist?['fansCount'], 20)}');
    final hot = asList(b['hotSongs']);
    emit('- `hotSongs` 长度: ${hot?.length}');
    if (hot != null && hot.isNotEmpty) {
      emit('- `hotSongs[0]` 字段: ${shapeOf(hot.first)}');
      emit('- `hotSongs[0]` 样本: ${brief(hot.first, 500)}');
    }
    emit(
      '- 结论: 该端点一次返回 信息+热门 = ${artist != null && (hot?.isNotEmpty ?? false)}',
    );
  }

  // ----------------------------------------------- 4c. getArtistTopSongs 备选
  emit('');
  emit('## 4c. getArtistTopSongs 备选 — GET /api/artist/top/song');
  final topSong = await run(
    dio,
    'artistTopSong',
    method: 'GET',
    path: '/api/artist/top/song',
    query: {'id': kArtistId},
  );
  emit('');
  emit('- ${topSong.verdict}, 耗时 ${topSong.elapsed.inMilliseconds}ms');
  if (topSong.ok) {
    final b = topSong.body!;
    emit('- 顶层字段: ${shapeOf(b)}');
    final songs = asList(b['songs']);
    emit('- `songs` 长度: ${songs?.length}');
    if (songs != null && songs.isNotEmpty) {
      emit('- `songs[0]` 字段: ${shapeOf(songs.first)}');
      emit('- `songs[0]` 样本: ${brief(songs.first, 400)}');
    }
  }

  // ------------------------------------------------------------- 5. 艺人专辑
  emit('');
  emit('## 5. getArtistAlbums — GET /api/artist/albums/{id}');
  final albums = await run(
    dio,
    'artistAlbums',
    method: 'GET',
    path: '/api/artist/albums/$kArtistId',
    query: {'limit': 5, 'offset': 0},
  );
  emit('');
  emit('- ${albums.verdict}, 耗时 ${albums.elapsed.inMilliseconds}ms');
  String? firstAlbumId;
  if (albums.ok) {
    final b = albums.body!;
    emit('- 顶层字段: ${shapeOf(b)}');
    emit('- code=${brief(b['code'], 20)}, more=${brief(b['more'], 20)}');
    final hot = asList(b['hotAlbums']);
    emit('- `hotAlbums` 长度: ${hot?.length}');
    if (hot != null && hot.isNotEmpty) {
      final a0 = asMap(hot.first);
      firstAlbumId = a0?['id']?.toString();
      emit('- `hotAlbums[0]` 字段: ${shapeOf(a0)}');
      emit('- `hotAlbums[0]` 样本: ${brief(a0, 500)}');
      for (final k in const [
        'id',
        'name',
        'picUrl',
        'publishTime',
        'size',
        'company',
        'artist',
        'description',
      ]) {
        emit(
          '  - `hotAlbums[0].$k`: ${a0?.containsKey(k) == true ? brief(a0![k], 60) : '**缺失**'}',
        );
      }
    }
  }
  // 分页是否有效
  final albumsPage2 = await run(
    dio,
    'artistAlbums(offset=5)',
    method: 'GET',
    path: '/api/artist/albums/$kArtistId',
    query: {'limit': 5, 'offset': 5},
  );
  emit(
    '- 对照 `offset=5&limit=5`: ${albumsPage2.verdict}, hotAlbums=${asList(albumsPage2.body?['hotAlbums'])?.length}, 首条 id=${brief(asMap(asList(albumsPage2.body?['hotAlbums'])?.first)?['id'], 30)}',
  );

  // ------------------------------------------------------------- 6. 专辑详情
  emit('');
  emit('## 6. getAlbumDetail — GET /api/v1/album/{id}');
  final albumId = firstAlbumId ?? '32311';
  final album = await run(
    dio,
    'albumDetail',
    method: 'GET',
    path: '/api/v1/album/$albumId',
  );
  emit('');
  emit('- 使用 albumId=$albumId');
  emit('- ${album.verdict}, 耗时 ${album.elapsed.inMilliseconds}ms');
  if (album.ok) {
    final b = album.body!;
    emit('- 顶层字段: ${shapeOf(b)}');
    emit('- code=${brief(b['code'], 20)}');
    final a = asMap(b['album']);
    emit('- `album` 字段: ${shapeOf(a)}');
    for (final k in const [
      'id',
      'name',
      'picUrl',
      'publishTime',
      'size',
      'company',
      'description',
      'artist',
      'subType',
      'genre',
    ]) {
      emit(
        '  - `album.$k`: ${a?.containsKey(k) == true ? brief(a![k], 80) : '**缺失**'}',
      );
    }
    final songs = asList(b['songs']);
    emit('- `songs` 长度: ${songs?.length}');
    if (songs != null && songs.isNotEmpty) {
      final s0 = asMap(songs.first);
      emit('- `songs[0]` 字段: ${shapeOf(s0)}');
      for (final k in const ['id', 'name', 'ar', 'al', 'dt', 'no']) {
        emit(
          '  - `songs[0].$k`: ${s0?.containsKey(k) == true ? brief(s0![k], 60) : '**缺失**'}',
        );
      }
      emit('- `songs[0]` 样本: ${brief(s0, 500)}');
      final nos = songs.map((e) => asMap(e)?['no']).toList();
      emit('- 全量 `no` 序列: $nos');
    }
  }

  // ------------------------------------------------- 7. 字段级深挖
  emit('');
  emit('## 7. 字段级深挖（决定解析代码怎么写）');

  // 7a. head/info/get 的 data.artist 到底有哪些计数字段
  emit('');
  emit('### 7a. `POST /api/artist/head/info/get` → `data.artist`');
  if (artistHead.ok) {
    final data = asMap(artistHead.body!['data']);
    emit('- `data` 字段: ${shapeOf(data)}');
    final a = asMap(data?['artist']);
    emit('- `data.artist` 字段: ${shapeOf(a)}');
    for (final k in const [
      'id',
      'name',
      'cover',
      'avatar',
      'briefDesc',
      'musicSize',
      'albumSize',
      'fansCount',
      'followCount',
      'albumSizeS',
      'songSize',
      'mvCount',
      'identities',
      'alias',
    ]) {
      emit(
        '  - `data.artist.$k`: ${a?.containsKey(k) == true ? brief(a![k], 100) : '**缺失**'}',
      );
    }
    emit(
      '- `data.artist.briefDesc` 长度: ${(a?['briefDesc'] as String?)?.length ?? 0}',
    );
  }

  // 7b. newsong: type 的真实取值 + song 子对象字段命名
  emit('');
  emit('### 7b. `GET /api/personalized/newsong` type 取值与 `song` 字段命名');
  final newBig = await run(
    dio,
    'newsong(limit=100)',
    method: 'GET',
    path: '/api/personalized/newsong',
    query: {'type': 0, 'limit': 100},
  );
  if (newBig.ok) {
    final result = asList(newBig.body!['result']) ?? const [];
    emit('- 条数: ${result.length}');
    final typeValues = <String>{};
    for (final e in result) {
      typeValues.add('${asMap(e)?['type']} (${asMap(e)?['type']?.runtimeType})');
    }
    emit('- `type` 取值集合: $typeValues');
    emit(
      '- 含 `song` 子对象的条数: ${result.where((e) => asMap(e)?.containsKey('song') == true).length}/${result.length}',
    );
    final s = asMap(asMap(result.firstWhere((e) => asMap(e)?.containsKey('song') == true, orElse: () => null))?['song']);
    emit('- `song` 是否用搜索接口的 ar/al/dt 命名: ar=${s?.containsKey('ar')} al=${s?.containsKey('al')} dt=${s?.containsKey('dt')}');
    emit('- `song` 是否用 artists/album/duration 命名: artists=${s?.containsKey('artists')} album=${s?.containsKey('album')} duration=${s?.containsKey('duration')}');
    emit('- `song.artists[0]` = ${brief(asList(s?['artists'])?.first, 150)}');
    emit('- `song.album` 字段 = ${shapeOf(s?['album'])}');
    emit('- `song.duration` = ${brief(s?['duration'], 30)}');
  }

  // 7c. 地区参数是否真的过滤（用歌名对比）
  emit('');
  emit('### 7c. 地区 type 是否真的改变结果');
  final regionNames = <int, List<String>>{};
  for (final region in const [0, 7, 96, 8, 16, 6, 14, 60]) {
    final r = await run(
      dio,
      'newsong region names(type=$region)',
      method: 'GET',
      path: '/api/personalized/newsong',
      query: {'type': region, 'limit': 5},
    );
    final res0 = asList(r.body?['result']) ?? const [];
    final names = res0.map((e) => '${asMap(e)?['name']}').toList();
    regionNames[region] = names;
    emit('- `type=$region` → $names');
  }
  final distinct = regionNames.values.map((e) => e.join('|')).toSet();
  emit('- 不同 type 得到的不同结果组数: ${distinct.length} / ${regionNames.length}');
  emit(
    '- 结论: 地区过滤 ${distinct.length > 1 ? '有效' : '**无效（所有 type 返回同一批歌曲）**'}',
  );

  // 7d. 多曲目专辑：no 序列 + size 一致性
  emit('');
  emit('### 7d. 多曲目专辑 `no` 序列（trackNumber 依据）');
  final albumsWide = await run(
    dio,
    'artistAlbums(limit=30)',
    method: 'GET',
    path: '/api/artist/albums/$kArtistId',
    query: {'limit': 30, 'offset': 0},
  );
  final wide = asList(albumsWide.body?['hotAlbums']) ?? const [];
  emit('- 取回 ${wide.length} 张专辑');
  final sized = wide
      .map(asMap)
      .whereType<Map<String, dynamic>>()
      .where((a) => (a['size'] as num?) != null)
      .toList()
    ..sort((a, b) => (b['size'] as num).compareTo(a['size'] as num));
  if (sized.isNotEmpty) {
    final big = sized.first;
    emit('- `size` 最大者: id=${big['id']} name=${big['name']} size=${big['size']} company=${brief(big['company'], 40)} artistName=${brief(asMap(big['artist'])?['name'], 30)}');
    emit(
      '- `hotAlbums[]` 里 `artist`/`artists[0]` 命名: artist=${big.containsKey('artist')} artists=${big.containsKey('artists')}',
    );
    final bigDetail = await run(
      dio,
      'albumDetail(big)',
      method: 'GET',
      path: '/api/v1/album/${big['id']}',
    );
    if (bigDetail.ok) {
      final b = bigDetail.body!;
      final a = asMap(b['album']);
      final songs = asList(b['songs']) ?? const [];
      final albumSongs = asList(a?['songs']);
      emit('- 详情 `size`=${a?['size']} 顶层 `songs`=${songs.length} `album.songs`=${albumSongs?.length}');
      emit('- `no` 序列: ${songs.map((e) => asMap(e)?['no']).toList()}');
      emit(
        '- `no` 是否 1..N 连续: ${_isConsecutive(songs.map((e) => asMap(e)?['no']).toList())}',
      );
      emit('- `album.tags` = ${brief(a?['tags'], 80)}, `album.genre` 存在=${a?.containsKey('genre')}');
      emit('- `album.info` 字段 = ${shapeOf(a?['info'])}');
      emit('- `album.company`(大专辑) = ${brief(a?['company'], 40)}');
      emit('- 顶层 `songs[0].ar`/`al`/`dt` = ${asMap(songs.first)?.containsKey('ar')}/${asMap(songs.first)?.containsKey('al')}/${asMap(songs.first)?.containsKey('dt')}');
    }
  }

  // 7e. 地区筛选是否还有别的可用端点
  emit('');
  emit('### 7e. 地区筛选的其他候选端点');
  for (final region in const [0, 7, 96, 8, 16]) {
    final r = await run(
      dio,
      'newsong category(type=$region)',
      method: 'GET',
      path: '/api/personalized/newsong',
      query: {'type': region, 'limit': 3},
    );
    emit(
      '- `type=$region` → `category`=${brief(r.body?['category'], 40)}, 歌名=${(asList(r.body?['result']) ?? const []).map((e) => asMap(e)?['name']).toList()}',
    );
  }
  for (final path in const [
    '/api/v1/discovery/new/songs',
    '/api/personalized/newsong/area',
  ]) {
    for (final areaId in const [0, 7, 96]) {
      final r = await run(
        dio,
        'newSongs $path areaId=$areaId',
        method: 'GET',
        path: path,
        query: {'areaId': areaId, 'limit': 3},
      );
      final res0 = asList(r.body?['result']) ??
          asList(r.body?['data']) ??
          const [];
      emit(
        '- GET `$path?areaId=$areaId` → ${r.verdict}, code=${brief(r.body?['code'], 20)}, 条数=${res0.length}, 歌名=${res0.map((e) => asMap(e)?['name']).toList()}',
      );
    }
  }
  // 明文 POST 版（weapi 的未加密对应物）
  final areaPost = await run(
    dio,
    'POST /api/v1/discovery/new/songs',
    method: 'POST',
    path: '/api/v1/discovery/new/songs',
    form: {'areaId': 7, 'limit': 3, 'offset': 0},
  );
  emit(
    '- POST `/api/v1/discovery/new/songs` (areaId=7) → ${areaPost.verdict}, code=${brief(areaPost.body?['code'], 20)}, 顶层=${shapeOf(areaPost.body)}',
  );

  // 7f. /api/v1/discovery/new/songs 的字段命名、areaId 映射、limit/offset 语义
  emit('');
  emit('### 7f. `GET /api/v1/discovery/new/songs` 细节');
  final nsGet = await run(
    dio,
    'newSongs areaId=7 limit=3',
    method: 'GET',
    path: '/api/v1/discovery/new/songs',
    query: {'areaId': 7, 'limit': 3, 'offset': 0},
  );
  if (nsGet.ok) {
    final data = asList(nsGet.body!['data']) ?? const [];
    emit('- 顶层字段: ${shapeOf(nsGet.body)}');
    emit('- `data` 条数（**请求 limit=3**）: ${data.length} → limit 参数被服务端忽略');
    final s0 = asMap(data.first);
    emit('- `data[0]` 字段: ${shapeOf(s0)}');
    emit('- `data[0]` 样本: ${brief(s0, 700)}');
    emit('- 命名: ar=${s0?.containsKey('ar')} al=${s0?.containsKey('al')} dt=${s0?.containsKey('dt')} | artists=${s0?.containsKey('artists')} album=${s0?.containsKey('album')} duration=${s0?.containsKey('duration')}');
    emit('- `data[0].ar[0]` = ${brief(asList(s0?['ar'])?.first, 120)}');
    emit('- `data[0].al` = ${brief(s0?['al'], 200)}');
    emit('- `data[0].dt` = ${brief(s0?['dt'], 20)}');
  }
  // offset 是否分页
  final nsOffset = await run(
    dio,
    'newSongs areaId=7 offset=100',
    method: 'GET',
    path: '/api/v1/discovery/new/songs',
    query: {'areaId': 7, 'limit': 100, 'offset': 100},
  );
  if (nsOffset.ok) {
    final off = asList(nsOffset.body!['data']) ?? const [];
    final base = asList(nsGet.body?['data']) ?? const [];
    emit(
      '- `offset=100`: 条数=${off.length}, 首条=${brief(asMap(off.first)?['name'], 40)}, 与 offset=0 首条相同=${asMap(off.first)?['id'] == asMap(base.first)?['id']} → offset ${off.isNotEmpty && asMap(off.first)?['id'] != asMap(base.first)?['id'] ? '有效' : '**无效/被忽略**'}',
    );
  }
  // areaId 映射探测
  emit('');
  emit('- areaId 映射探测（取首 3 首歌名对比）：');
  final areaFirstNames = <int, List<String>>{};
  for (final area in const [0, 7, 96, 8, 16, 6, 14, 60, 3, 4]) {
    final r = await run(
      dio,
      'newSongs areaId=$area',
      method: 'GET',
      path: '/api/v1/discovery/new/songs',
      query: {'areaId': area, 'limit': 3},
    );
    final data = asList(r.body?['data']) ?? const [];
    areaFirstNames[area] = data.take(3).map((e) => '${asMap(e)?['name']}').toList();
    emit('  - areaId=$area → ${areaFirstNames[area]}');
  }
  emit(
    '- 不同 areaId 的不同结果组数: ${areaFirstNames.values.map((e) => e.join("|")).toSet().length} / ${areaFirstNames.length}',
  );

  // 7g. 榜单分页：`n` 是否返回榜单**前 n 首**（排名=下标+1 的前提）
  emit('');
  emit('### 7g. 榜单分页 `n` 语义');
  if (detail.ok) {
    final fullTracks = asList(asMap(detail.body!['playlist'])?['tracks']) ?? const [];
    final fullNames = fullTracks.take(5).map((e) => '${asMap(e)?['name']}').toList();
    emit('- `n=1000` tracks 前 5 首: $fullNames');
    final small = await run(
      dio,
      'playlistDetail(n=3)',
      method: 'POST',
      path: '/api/v6/playlist/detail',
      form: {'id': '3778678', 'n': 3},
    );
    final smallTracks =
        asList(asMap(small.body?['playlist'])?['tracks']) ?? const [];
    emit(
      '- `n=3` tracks 长度=${smallTracks.length}, 歌名=${smallTracks.map((e) => asMap(e)?['name']).toList()}',
    );
    emit(
      '- `n` 是否返回榜单前 n 首（顺序一致）: ${smallTracks.length == 3 && smallTracks.map((e) => asMap(e)?['name']).join('|') == fullNames.take(3).join('|')}',
    );
    final ids = smallTracks.map((e) => asMap(e)?['id']).toList();
    final fullIds = fullTracks.take(3).map((e) => asMap(e)?['id']).toList();
    emit('- id 序列一致: ${ids.join(",") == fullIds.join(",")} ($ids vs $fullIds)');
  }

  // --------------------------------------------------------------- 汇总
  emit('');
  emit('## 汇总');
  emit('');
  emit('| 端点 | 方法 | 判定 | 耗时 |');
  emit('| --- | --- | --- | --- |');
  for (final p in _allProbes) {
    emit('| `${p.label}` | ${p.method} | ${p.verdict} | ${p.elapsed.inMilliseconds}ms |');
  }
  emit('');
  emit('_由 `dart run scripts/test_netease_artist_album_toplist.dart` 生成；失败项即"未实测"，不得在实现中声称已验证。_');
  emit('');

  final out = File('docs/netease-wave-b-probe.md');
  await out.writeAsString(_lines.join('\n'));
  // ignore: avoid_print
  print('\n[probe] 报告已写入 ${out.absolute.path}');
}

final _allProbes = <Probe>[];

/// 记录探针结果供汇总表使用。
void track(Probe p) => _allProbes.add(p);

/// `no` 序列是否为 1..N（专辑曲目序号的契约依据）。
bool _isConsecutive(List<Object?> nos) {
  if (nos.isEmpty) return false;
  for (var i = 0; i < nos.length; i++) {
    final v = nos[i];
    final n = v is int ? v : int.tryParse('$v');
    if (n != i + 1) return false;
  }
  return true;
}
