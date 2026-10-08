import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// i18n 预算护栏：**新增硬编码中文不得增长**。
///
/// 口径（唯一权威定义见 `docs/i18n-migration-plan.md` §0.1）：
///
/// > 一处 = `lib/**/*.dart`（**排除 `lib/l10n/**`**）里，位于"非注释行"上的 Dart
/// > 字符串字面量，其内容含至少一个 CJK 字符（`U+4E00–U+9FFF`）。
///
/// 与它配套的**人类命令**是地图 §0.2 的命令 A（PowerShell，Windows 原生）。
/// 两者必须打印同一个 `total` —— 不一致就说明有一侧实现跑偏了，**先修实现再改
/// 基线**，不要把基线改成另一个数来"对上"。
///
/// **基线怎么用**：它是"上界"，不是目标。W3-D 每迁一批文案就把这两个常量**调小**；
/// 放开 `en` 那次 PR 要把它调到"白名单行数"（只剩 `// i18n-exempt:` 的那些）。
/// 写成常量而不是从文件读，是为了让"调小基线"在 diff 里一眼可见。
void main() {
  /// 非注释行上的 CJK 字符串字面量。
  ///
  /// `\u0022` 就是 `"`：写成转义而不是 `\"`，是为了让这条正则与地图里的
  /// PowerShell 版**逐字对应**（那边也只能用 `\x22`/`\x27`，直接写引号类会被
  /// shell 吃掉引号）。
  final cjkLiteral = RegExp(
    "['\u0022][^'\u0022\r\n]*[\u4e00-\u9fff][^'\u0022\r\n]*['\u0022]",
  );

  /// 行注释（含尾随注释）：先截断再匹配，否则中文注释会把数字虚高约 20%。
  final lineComment = RegExp(r'(^|\s)//.*$');

  /// 白名单标记：这一行视为"必须保持中文"，其 CJK 字面量计入 `exempt` 而**不计入**
  /// `total`（例如平台层的解析常量 `'今日私享'`、`'概念版'`）。
  final exemptMarker = RegExp(r'//\s*i18n-exempt:');

  // ⚠️ 基线是**快照**，在每个波次边界重新冻结为当时的实测值；边界之间只许降。
  //
  // 不变式是 **measured ≤ baseline**。所以"低于实测值的常量"不是更紧的棘轮，
  // 它就是一条红的测试 —— 边界没到之前不要把它往下压。
  //
  // 冻结历史（每一步都记下来，这样"基线为什么涨"永远可追溯）：
  //   850/95（地图 §0.3）→ 910/102 → 942/103（W3-D B0 首次冻结 + CI 就位）
  //   class B1 把 `lib/core/widgets/**` 从 9 降到 0（`async_state_view.dart` 的
  //     `'重试'`→`commonRetry`、`song_actions_sheet.dart` 8 个动作→`common*`），
  //     `core/utils/**` 本来就 0 ⇒ `core` 89 → 80。
  //   **本边界冻结 = 974/105**（六位 writer 全部停手、`git status` 干净时实测）。
  //
  // 为什么比上一次高：**不是 B1 的错，也不是谁违规** —— `by area` 把责任分得很清：
  //   features=774 core=80 platform=69 models=26 lyrics=21 utils=2 main.dart=2
  // `core` 是**下降**的（89→80），上涨全部来自 Wave 2/3 并行 writer 新增的界面文案
  // （features 736→774、lyrics 18→21）。那些文案的迁移批次（B4–B7）还没做，所以
  // 它们此刻**必须**被计入基线，否则护栏会因为"别人还没来得及迁移"而红。
  // ⚠️ 唯一不能做的事是**在脏树上**把常量往上调去吸收别人的中间态；本值是在
  // writer 全部停手后测的，符合冻结流程。
  //
  // W3-D B2（core/network 归零 + 展示点改走错误码）：
  //   `core` 80 → **55**，即本批 **−25**（`api_exception.dart` 11 处、
  //   `platform_http.dart` 4 处迁到 `net*` key；`api_client.dart` 是**死文件**，
  //   8 处随内容清空一起消失，见该文件的 tombstone 注释）。
  //   `features` 774 → 775（+1，并行 writer 的新文案，不是本批 —— 本批只改
  //   4 个页面里"文案来源"的那一行，新增 0 处字面量）。
  //   ⇒ 净值 974 − 25 + 1 = **950/102**（`files` 105 → 102：network 里原带中文的
  //   3 个文件都归零）。
  // W3-D B4（`library` + `download`，**进行中** —— 本批 253 处只完成了一部分）：
  //   已归零的文件：`library_screen.dart` 11 → 0、`likes_page.dart` 7 → 0、
  //     `history_page.dart` 15 → 0。
  //   另把 `toplists_page.dart` 的 `'加载失败'` 收进共享 key `commonLoadFailed`
  //     （1 处；它属于 B6 的文件，只是在 B2 改过一行的文件里顺手收掉）。
  //   ⇒ 本批至今 `library` **33/157**、`download` **0/96**，新增 28 个 key
  //     （`common*` 11 个 + `library*`/`stats*`/`cache*`/`download*` 17 个）。
  //   整棵树 950/102 → **917/99**（净值 −33/−3 = 本批 33 处，加上并行 writer 的 ±0）。
  //   ⚠️ 剩余 `library` 124 处 + `download` 96 处**还没迁**，仍计入基线；
  //      下一批继续往下压。
  //
  // W3-D B4-2（继续）：
  //   `download/presentation/widgets/download_button.dart` 13 → 0 ⇒ 本批 **−13/−1**
  //   （整棵树 917/99 → **904/98**，与文件实测完全吻合，无并行干扰）。
  //   新增 13 个 key：`downloadButtonTooltip`、`cacheQueuedOfflineMode`、
  //   `cacheQueuedWifi`、`cacheQueuedPaused`、`cacheAdded`、`cacheAlreadyQueued`、
  //   `downloadQualityPicker`、`downloadRequiresSvip`、`downloadRequiresVip`、
  //   `downloadLosslessFormat`、`downloadNeedsSvip`、`downloadNeedsVip`、
  //   `downloadStarted`（6 个参数化 key 带 `@placeholders`）。
  //   ⚠️ 剩余 B4-2：`platform_playlists_page` 37、`download_page` 37、
  //      `playlist_detail_page` 29、`import_playlist_page` 29 = **132 处**。
  //
  // W3-D B4-2（继续，`platform_playlists_page` 的 AppBar/TabBar 区）：
  //   该文件 37 → **33**（本批 −4：`'歌单'` 复用现成的 `commonPlaylist`、
  //   `'刷新当前歌单'`、`'新建歌单'`、`'我的歌单'`），新增 3 个 key
  //   （`libraryRefreshCurrentPlaylist`/`libraryNewPlaylist`/`libraryMyPlaylists`）。
  //   整棵树 904/98 → **900/98**（−4，与文件实测吻合）。
  //   ⚠️ 该文件**还剩 33 处**（对话框/导出/二维码/列表区），下一批继续。
  //
  // W3-D B4-2（继续，`platform_playlists_page` 的对话框区）：
  //   该文件 33 → **15**（本批 −18）：两个**逐字相同**的"新建歌单"对话框用一次
  //   `replace_all` 一起改（各 4 处：标题/名称标签/取消/新建），加两条
  //   `'新建歌单失败'/'已新建歌单'` snackbar、"删除歌单"对话框（标题/确认正文/取消/删除）
  //   与 `'已删除歌单'/'删除歌单失败'` snackbar。
  //   新增 10 个 key：`libraryPlaylistName`、`libraryCreate`、
  //   `libraryCreatePlaylistFailed`、`libraryPlaylistCreated`、`libraryDeletePlaylist`、
  //   `libraryDeletePlaylistConfirm`、`libraryPlaylistDeleted`、
  //   `libraryDeletePlaylistFailed`、`commonDelete`（+ 复用 `actionCancel`）。
  //   整棵树 900/98 → **882/98**（−18，与文件实测吻合）；孤儿仍为 **0**。
  //   ⚠️ 该文件**还剩 15 处**（导出/二维码/分享 + 列表空态/错误区），下一批继续。
  const baselineTotal = 882;
  const baselineFiles = 98;

  test('lib/ 的硬编码中文不得超过基线（总数与文件数都不许涨）', () {
    var total = 0;
    var files = 0;
    var exempt = 0;
    final perArea = <String, int>{};

    // 目录顺序不保证，排序让打印结果可复现、diff 可读。
    final entities = Directory('lib').listSync(recursive: true)
      ..sort((a, b) => a.path.compareTo(b.path));

    for (final entity in entities) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final normalized = entity.path.replaceAll(r'\', '/');
      // **只**排除正本与生成物所在的 lib/l10n/：l10n.dart / platform_labels.dart
      // 是手写代码，把它们一起排除会让"孤儿键检查"误报（见 l10n_test.dart）。
      if (normalized.contains('/l10n/')) continue;

      var count = 0;
      for (final line in entity.readAsLinesSync()) {
        if (exemptMarker.hasMatch(line)) {
          exempt += cjkLiteral.allMatches(line).length;
          continue;
        }
        count += cjkLiteral.allMatches(line.replaceAll(lineComment, '')).length;
      }

      if (count > 0) {
        files++;
        total += count;
        final area = normalized.split('/')[1];
        perArea[area] = (perArea[area] ?? 0) + count;
      }
    }

    // 打印是这条护栏的一半价值：迁移时看得到"哪个区还剩多少"。
    // ignore: avoid_print
    print('i18n budget: total=$total files=$files exempt=$exempt');
    // ignore: avoid_print
    print('  by area: ${Map.fromEntries(perArea.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))}');
    // ignore: avoid_print
    print('  baseline: total=$baselineTotal files=$baselineFiles'
        ' (headroom=${baselineTotal - total})');

    expect(
      total,
      lessThanOrEqualTo(baselineTotal),
      reason:
          '新增了硬编码中文（baseline=$baselineTotal，实际=$total）。'
          '请把文案加进 lib/l10n/app_zh.arb + app_en.arb，跑 `flutter gen-l10n`，'
          '再用 context.l10n 引用（见 docs/i18n-migration-plan.md §4 的分批方案）。'
          '确实必须保留中文的（平台解析常量等）请在该行加 `// i18n-exempt:` 标记。',
    );
    expect(
      files,
      lessThanOrEqualTo(baselineFiles),
      reason: '含硬编码中文的**文件数**变多了（即使总处数没超）：'
          '说明新增文件在使用硬编码文案，而不是复用已迁移的 widget。',
    );
  });

  test('放开 en 之后：只允许带 i18n-exempt 标记的中文', () {
    // 这条用例在 W3-D 完成、基线调到白名单行数之前必然通过（910 <= 910 一类），
    // 它的作用是**把放开 en 的验收条件写在代码里**：那时把 gateArmed 改成 true、
    // 并把两个基线常量换成 exempt 的实测值。
    // Armed with `--dart-define=I18N_EN_GATE=true` on the run that flips
    // `appSupportedLocales` to `en`. It is read from the environment rather than
    // hard-coded so the assertion below is not statically unreachable (a `const
    // false` makes the analyzer report dead code, which fails the 0-issue gate).
    const gateArmed = bool.fromEnvironment('I18N_EN_GATE');
    if (gateArmed) {
      expect(
        baselineTotal,
        lessThanOrEqualTo(20),
        reason: '放开 en 时基线应只剩白名单量级',
      );
    }
  });
}
