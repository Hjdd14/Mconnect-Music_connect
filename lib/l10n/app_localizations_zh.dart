// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => 'Mconnect';

  @override
  String get navSearch => '搜索';

  @override
  String get navDiscover => '发现';

  @override
  String get navLibrary => '音乐库';

  @override
  String get navDownloads => '下载';

  @override
  String get settingsTitle => '设置';

  @override
  String get settingsAccounts => '账号管理';

  @override
  String get settingsAccountsSubtitle => '网易云音乐、QQ 音乐、酷狗音乐登录状态';

  @override
  String get settingsAppearance => '外观';

  @override
  String get settingsAppearanceSubtitle => '主题模式、主题色与自定义背景';

  @override
  String get settingsFloatingLyrics => '悬浮歌词';

  @override
  String get settingsFloatingLyricsSubtitle => '桌面歌词开关、颜色、字号与阴影';

  @override
  String get settingsAudio => '音频增强';

  @override
  String get settingsAudioSubtitle => '淡入淡出、均衡器与睡眠定时';

  @override
  String get settingsDiagnostics => '诊断与关于';

  @override
  String get settingsDiagnosticsSubtitle => '日志位置与应用版本';

  @override
  String get settingsBackup => '备份与恢复';

  @override
  String get settingsBackupSubtitle => '导出/导入收藏、歌单、统计与设置';

  @override
  String get settingsExportDiagnostics => '导出诊断日志';

  @override
  String get settingsExportDiagnosticsSubtitle => '打包最近事件与日志并分享（已脱敏）';

  @override
  String get settingsAccountsTitle => '账号管理';

  @override
  String get settingsAppearanceTitle => '外观';

  @override
  String get settingsFloatingLyricsTitle => '悬浮歌词';

  @override
  String get settingsAudioTitle => '音频增强';

  @override
  String get settingsDiagnosticsTitle => '诊断与关于';

  @override
  String get themeFollowSystem => '跟随系统';

  @override
  String get themeLight => '浅色模式';

  @override
  String get themeDark => '深色模式';

  @override
  String get themeColor => '主题色';

  @override
  String get themeColorSubtitle => '影响按钮、进度条、导航栏和高亮状态';

  @override
  String get uiStyle => 'UI 风格';

  @override
  String get uiStyleMaterial => 'Material 风格';

  @override
  String get uiStyleMiuix => 'Miuix 风格';

  @override
  String get backgroundRemoved => '已移除自定义背景';

  @override
  String get backgroundApplied => '已应用自定义背景';

  @override
  String get backgroundUpdated => '已更新自定义背景';

  @override
  String get backgroundImageUnreadable => '无法读取所选图片';

  @override
  String get backgroundImageSizeUnreadable => '无法读取图片尺寸';

  @override
  String get backgroundFileMissing => '背景图片文件不存在，请重新选择';

  @override
  String backgroundProcessFailed(String error) {
    return '背景图片处理失败：$error';
  }

  @override
  String get customBackground => '自定义背景';

  @override
  String get customBackgroundEnabledHint => '已启用，点击重新调整背景位置';

  @override
  String get customBackgroundChooseHint => '选择图片作为全应用背景';

  @override
  String get removeBackground => '移除背景';

  @override
  String get adjustBackground => '调整背景';

  @override
  String get backgroundEditorHint => '拖动图片调整位置，双指缩放到合适大小';

  @override
  String get floatingLyricsEnable => '桌面悬浮歌词';

  @override
  String get floatingLyricsEnableSubtitle => '在桌面顶部显示歌词，支持拖拽、缩放和锁定';

  @override
  String get floatingLyricsPermissionSubtitle => '显示在其他应用上方，需要系统悬浮窗权限';

  @override
  String get floatingLyricsLock => '锁定位置';

  @override
  String get floatingLyricsLockSubtitle =>
      '锁定后悬浮歌词不可移动、不可点击，触摸会直接落到下面的应用；关闭悬浮歌词会自动解锁';

  @override
  String get floatingLyricsTextColor => '歌词底色';

  @override
  String get floatingLyricsTextColorSubtitle => '未播放部分的文字颜色，默认白色';

  @override
  String get floatingLyricsHighlightColor => '已播放高亮色';

  @override
  String get floatingLyricsHighlightColorSubtitle => '唱到的部分变为该颜色，悬浮窗里的圆点也调它';

  @override
  String get floatingLyricsFontSize => '字号';

  @override
  String get floatingLyricsStrokeWidth => '描边强度';

  @override
  String get floatingLyricsShadowOpacity => '阴影强度';

  @override
  String get customColor => '自定义颜色';

  @override
  String get defaultLabel => '默认';

  @override
  String get audioFade => '淡入淡出';

  @override
  String get audioFadeSubtitle => '播放、暂停时平滑调整音量，默认关闭';

  @override
  String get audioFadeDuration => '淡入淡出时长';

  @override
  String get audioEqualizer => '均衡器';

  @override
  String get audioEqualizerSubtitle => '调整播放音频的频段增益，设备不支持时会自动忽略';

  @override
  String get audioEqualizerPreset => '均衡器预设';

  @override
  String get audioBandLow => '低频';

  @override
  String get audioBandLowMid => '中低频';

  @override
  String get audioBandMid => '中频';

  @override
  String get audioBandHighMid => '中高频';

  @override
  String get audioBandHigh => '高频';

  @override
  String get audioSleepTimer => '睡眠定时';

  @override
  String audioSleepTimerRemaining(String time) {
    return '剩余 $time';
  }

  @override
  String audioSleepTimerCountdown(int minutes) {
    return '$minutes 分钟后暂停播放';
  }

  @override
  String get audioSleepTimerDuration => '定时时长';

  @override
  String audioMinutes(int minutes) {
    return '$minutes 分钟';
  }

  @override
  String get diagnosticsSection => '诊断';

  @override
  String get aboutSection => '关于';

  @override
  String get version => '版本';

  @override
  String get diagnosticsLog => '诊断日志';

  @override
  String get diagnosticsLogPathCopied => '日志路径已复制';

  @override
  String get diagnosticsLogCleared => '诊断日志已清空';

  @override
  String get copyPath => '复制路径';

  @override
  String get clearLog => '清空日志';

  @override
  String get diagnosticsExporting => '正在导出诊断日志…';

  @override
  String get diagnosticsExported => '诊断日志已导出';

  @override
  String get diagnosticsExportPathCopied => '诊断日志已导出，文件路径已复制到剪贴板';

  @override
  String diagnosticsExportFailed(String error) {
    return '导出失败：$error';
  }

  @override
  String get share => '分享';

  @override
  String get accountLoggedIn => '已登录';

  @override
  String get accountTapToLogin => '点击登录';

  @override
  String get accountLogout => '退出登录';

  @override
  String accountLogoutConfirm(String platform) {
    return '确定要退出 $platform 账号吗？';
  }

  @override
  String get actionSave => '保存';

  @override
  String get actionCancel => '取消';

  @override
  String get actionReset => '重置';

  @override
  String get actionLogout => '退出';

  @override
  String get commonRetry => '重试';

  @override
  String get commonPlayNext => '下一首播放';

  @override
  String get commonAddToPlaylist => '添加到歌单';

  @override
  String get commonDownload => '下载';

  @override
  String get commonDownloaded => '已下载';

  @override
  String get commonLike => '喜欢';

  @override
  String get commonUnlike => '取消喜欢';

  @override
  String get commonCopyLink => '复制链接';

  @override
  String get playerNowPlaying => '正在播放';

  @override
  String get playerNotPlaying => '未在播放';

  @override
  String get playerAddedToLikes => '已收藏到我喜欢';

  @override
  String get playerRemovedFromLikes => '已取消收藏';

  @override
  String get playerAddedToQueue => '已添加到播放队列';

  @override
  String get playerSongInfoCopied => '歌曲信息已复制';

  @override
  String get playerPlaybackSettings => '播放设置';

  @override
  String get playerAddToPlatformPlaylist => '添加到平台歌单';

  @override
  String get playerAddToQueue => '加入播放队列';

  @override
  String get playerCopySongInfo => '复制歌曲信息';

  @override
  String get playerAddedToPlaylist => '已添加到歌单';

  @override
  String get playerAddToPlaylistFailed => '添加失败，当前平台可能暂不支持编辑该歌单';

  @override
  String get playerPlay => '播放';

  @override
  String get playerPause => '暂停';

  @override
  String get playerPrevious => '上一首';

  @override
  String get playerNext => '下一首';

  @override
  String get playerShuffle => '随机播放';

  @override
  String get playerRepeat => '循环模式';

  @override
  String get playerToggleLyrics => '显示歌词';

  @override
  String get playerToggleArtwork => '显示封面';

  @override
  String get playerLike => '我喜欢';

  @override
  String get playerCollapse => '收起';

  @override
  String get moreActions => '更多操作';

  @override
  String get platformLocal => '本地音乐';

  @override
  String get platformNetease => '网易云音乐';

  @override
  String get platformQq => 'QQ 音乐';

  @override
  String get platformKugou => '酷狗音乐';

  @override
  String get sessionExpired => '登录已过期，请重新登录';

  @override
  String get sessionGoToLogin => '去登录';

  @override
  String get netConnectionFailed => '网络连接失败，请检查网络后重试';

  @override
  String get netLoginExpired => '登录已过期，请重新登录';

  @override
  String get netCurrentPlatform => '当前平台';

  @override
  String netSongNotAvailable(String platform) {
    return '该歌曲在$platform不可用';
  }

  @override
  String get netQualityNotAvailable => '所选音质不可用';

  @override
  String netQualityDowngraded(String quality) {
    return '所选音质不可用，已降级到$quality';
  }

  @override
  String get netLyricsNotFound => '暂无歌词';

  @override
  String netNoVip(String platform) {
    return '需要开通$platform会员';
  }

  @override
  String get netStoragePermissionDenied => '存储权限被拒绝，请在设置中授权';

  @override
  String get netNotFound => '内容不存在或已被删除';

  @override
  String netUnsupported(String platform) {
    return '$platform暂不支持该功能';
  }

  @override
  String get netStorageFull => '存储空间不足';

  @override
  String get netRequestCancelled => '请求已取消';

  @override
  String netRequestTimeout(String platform) {
    return '$platform请求超时';
  }

  @override
  String netServerError(String platform) {
    return '$platform服务器异常';
  }

  @override
  String get netRequestFailed => '请求失败';

  @override
  String netRequestFailedWithCode(int code) {
    return '请求失败 ($code)';
  }

  @override
  String get netUnknownPlatform => '未知平台';

  @override
  String get commonLoadFailed => '加载失败';

  @override
  String get commonConfirm => '确定';

  @override
  String get commonAllPlatforms => '全部平台';

  @override
  String get commonPlaylist => '歌单';

  @override
  String get commonNow => '刚刚';

  @override
  String get commonToday => '今天';

  @override
  String get commonYesterday => '昨天';

  @override
  String commonDaysAgo(int count) {
    return '$count天前';
  }

  @override
  String commonHoursAgo(int count) {
    return '$count小时前';
  }

  @override
  String commonMinutesAgo(int count) {
    return '$count分钟前';
  }

  @override
  String get commonMonthDayPattern => 'MM月dd日';

  @override
  String get libraryLikes => '我喜欢的音乐';

  @override
  String libraryLikesWithCount(int count) {
    return '我喜欢 ($count)';
  }

  @override
  String get libraryLikesFilter => '平台筛选';

  @override
  String get libraryLikesEmpty => '还没有喜欢的歌曲';

  @override
  String get libraryLikesEmptyHint => '在播放器中点击爱心添加';

  @override
  String get libraryLikesEmptyForPlatform => '该平台没有喜欢的歌曲';

  @override
  String get libraryHistory => '听歌历史';

  @override
  String libraryHistoryWithCount(int count) {
    return '听歌历史 ($count)';
  }

  @override
  String get libraryHistoryClear => '清空历史';

  @override
  String get libraryHistoryClearConfirm => '清空听歌历史';

  @override
  String get libraryHistoryClearConfirmBody => '确定要清空所有听歌历史吗？';

  @override
  String get libraryHistoryEmpty => '还没有听歌记录';

  @override
  String get libraryImportPlaylist => '导入歌单';

  @override
  String get statsTitle => '听歌统计';

  @override
  String get cacheTitle => '离线缓存';

  @override
  String get smartPlaylistTitle => '智能歌单';

  @override
  String get downloadTitle => '下载管理';

  @override
  String get downloadButtonTooltip => '下载（长按加入离线缓存）';

  @override
  String get cacheQueuedOfflineMode => '离线模式已开启，已加入缓存队列但不会自动开始';

  @override
  String get cacheQueuedWifi => '已加入离线缓存队列，将在连接 Wi-Fi 后开始';

  @override
  String get cacheQueuedPaused => '已加入离线缓存队列，队列当前已暂停';

  @override
  String cacheAdded(String name) {
    return '已加入离线缓存：$name';
  }

  @override
  String get cacheAlreadyQueued => '该歌曲已在缓存列表中';

  @override
  String downloadQualityPicker(String name) {
    return '选择下载音质 - $name';
  }

  @override
  String get downloadRequiresSvip => '需 SVIP';

  @override
  String get downloadRequiresVip => '需 VIP';

  @override
  String downloadLosslessFormat(String format) {
    return '$format · 无损音质';
  }

  @override
  String downloadNeedsSvip(String quality) {
    return '需要超级会员才能下载$quality音质';
  }

  @override
  String downloadNeedsVip(String quality) {
    return '需要VIP才能下载$quality音质';
  }

  @override
  String downloadStarted(String name, String quality) {
    return '已开始下载: $name ($quality)';
  }

  @override
  String get libraryRefreshCurrentPlaylist => '刷新当前歌单';

  @override
  String get libraryNewPlaylist => '新建歌单';

  @override
  String get libraryMyPlaylists => '我的歌单';

  @override
  String get libraryPlaylistName => '歌单名称';

  @override
  String get libraryCreate => '新建';

  @override
  String get libraryCreatePlaylistFailed => '新建歌单失败';

  @override
  String get libraryPlaylistCreated => '已新建歌单';

  @override
  String get libraryDeletePlaylist => '删除歌单';

  @override
  String libraryDeletePlaylistConfirm(String name) {
    return '确定要删除“$name”吗？';
  }

  @override
  String get libraryPlaylistDeleted => '已删除歌单';

  @override
  String get libraryDeletePlaylistFailed => '删除歌单失败';

  @override
  String get commonDelete => '删除';

  @override
  String get libraryPlaylistLoadFailed => '加载歌单失败';

  @override
  String get libraryPlaylistsEmpty => '暂无歌单，或当前平台未登录';

  @override
  String get libraryMyPlaylistsEmpty => '暂无我的歌单，可点击右上角新建或从分享链接导入';

  @override
  String librarySongCount(int count) {
    return '$count 首';
  }

  @override
  String get libraryPlaylistActions => '歌单操作';

  @override
  String get libraryExportPlaylist => '导出歌单';
}
