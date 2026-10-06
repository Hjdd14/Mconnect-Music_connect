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
}
