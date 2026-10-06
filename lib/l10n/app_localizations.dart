import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In zh, this message translates to:
  /// **'Mconnect'**
  String get appTitle;

  /// No description provided for @navSearch.
  ///
  /// In zh, this message translates to:
  /// **'搜索'**
  String get navSearch;

  /// No description provided for @navDiscover.
  ///
  /// In zh, this message translates to:
  /// **'发现'**
  String get navDiscover;

  /// No description provided for @navLibrary.
  ///
  /// In zh, this message translates to:
  /// **'音乐库'**
  String get navLibrary;

  /// No description provided for @navDownloads.
  ///
  /// In zh, this message translates to:
  /// **'下载'**
  String get navDownloads;

  /// No description provided for @settingsTitle.
  ///
  /// In zh, this message translates to:
  /// **'设置'**
  String get settingsTitle;

  /// No description provided for @settingsAccounts.
  ///
  /// In zh, this message translates to:
  /// **'账号管理'**
  String get settingsAccounts;

  /// No description provided for @settingsAccountsSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'网易云音乐、QQ 音乐、酷狗音乐登录状态'**
  String get settingsAccountsSubtitle;

  /// No description provided for @settingsAppearance.
  ///
  /// In zh, this message translates to:
  /// **'外观'**
  String get settingsAppearance;

  /// No description provided for @settingsAppearanceSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'主题模式、主题色与自定义背景'**
  String get settingsAppearanceSubtitle;

  /// No description provided for @settingsFloatingLyrics.
  ///
  /// In zh, this message translates to:
  /// **'悬浮歌词'**
  String get settingsFloatingLyrics;

  /// No description provided for @settingsFloatingLyricsSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'桌面歌词开关、颜色、字号与阴影'**
  String get settingsFloatingLyricsSubtitle;

  /// No description provided for @settingsAudio.
  ///
  /// In zh, this message translates to:
  /// **'音频增强'**
  String get settingsAudio;

  /// No description provided for @settingsAudioSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'淡入淡出、均衡器与睡眠定时'**
  String get settingsAudioSubtitle;

  /// No description provided for @settingsDiagnostics.
  ///
  /// In zh, this message translates to:
  /// **'诊断与关于'**
  String get settingsDiagnostics;

  /// No description provided for @settingsDiagnosticsSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'日志位置与应用版本'**
  String get settingsDiagnosticsSubtitle;

  /// No description provided for @settingsBackup.
  ///
  /// In zh, this message translates to:
  /// **'备份与恢复'**
  String get settingsBackup;

  /// No description provided for @settingsBackupSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'导出/导入收藏、歌单、统计与设置'**
  String get settingsBackupSubtitle;

  /// No description provided for @settingsExportDiagnostics.
  ///
  /// In zh, this message translates to:
  /// **'导出诊断日志'**
  String get settingsExportDiagnostics;

  /// No description provided for @settingsExportDiagnosticsSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'打包最近事件与日志并分享（已脱敏）'**
  String get settingsExportDiagnosticsSubtitle;

  /// No description provided for @settingsAccountsTitle.
  ///
  /// In zh, this message translates to:
  /// **'账号管理'**
  String get settingsAccountsTitle;

  /// No description provided for @settingsAppearanceTitle.
  ///
  /// In zh, this message translates to:
  /// **'外观'**
  String get settingsAppearanceTitle;

  /// No description provided for @settingsFloatingLyricsTitle.
  ///
  /// In zh, this message translates to:
  /// **'悬浮歌词'**
  String get settingsFloatingLyricsTitle;

  /// No description provided for @settingsAudioTitle.
  ///
  /// In zh, this message translates to:
  /// **'音频增强'**
  String get settingsAudioTitle;

  /// No description provided for @settingsDiagnosticsTitle.
  ///
  /// In zh, this message translates to:
  /// **'诊断与关于'**
  String get settingsDiagnosticsTitle;

  /// No description provided for @themeFollowSystem.
  ///
  /// In zh, this message translates to:
  /// **'跟随系统'**
  String get themeFollowSystem;

  /// No description provided for @themeLight.
  ///
  /// In zh, this message translates to:
  /// **'浅色模式'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In zh, this message translates to:
  /// **'深色模式'**
  String get themeDark;

  /// No description provided for @themeColor.
  ///
  /// In zh, this message translates to:
  /// **'主题色'**
  String get themeColor;

  /// No description provided for @themeColorSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'影响按钮、进度条、导航栏和高亮状态'**
  String get themeColorSubtitle;

  /// No description provided for @uiStyle.
  ///
  /// In zh, this message translates to:
  /// **'UI 风格'**
  String get uiStyle;

  /// No description provided for @uiStyleMaterial.
  ///
  /// In zh, this message translates to:
  /// **'Material 风格'**
  String get uiStyleMaterial;

  /// No description provided for @uiStyleMiuix.
  ///
  /// In zh, this message translates to:
  /// **'Miuix 风格'**
  String get uiStyleMiuix;

  /// No description provided for @backgroundRemoved.
  ///
  /// In zh, this message translates to:
  /// **'已移除自定义背景'**
  String get backgroundRemoved;

  /// No description provided for @backgroundApplied.
  ///
  /// In zh, this message translates to:
  /// **'已应用自定义背景'**
  String get backgroundApplied;

  /// No description provided for @backgroundUpdated.
  ///
  /// In zh, this message translates to:
  /// **'已更新自定义背景'**
  String get backgroundUpdated;

  /// No description provided for @backgroundImageUnreadable.
  ///
  /// In zh, this message translates to:
  /// **'无法读取所选图片'**
  String get backgroundImageUnreadable;

  /// No description provided for @backgroundImageSizeUnreadable.
  ///
  /// In zh, this message translates to:
  /// **'无法读取图片尺寸'**
  String get backgroundImageSizeUnreadable;

  /// No description provided for @backgroundFileMissing.
  ///
  /// In zh, this message translates to:
  /// **'背景图片文件不存在，请重新选择'**
  String get backgroundFileMissing;

  /// No description provided for @backgroundProcessFailed.
  ///
  /// In zh, this message translates to:
  /// **'背景图片处理失败：{error}'**
  String backgroundProcessFailed(String error);

  /// No description provided for @customBackground.
  ///
  /// In zh, this message translates to:
  /// **'自定义背景'**
  String get customBackground;

  /// No description provided for @customBackgroundEnabledHint.
  ///
  /// In zh, this message translates to:
  /// **'已启用，点击重新调整背景位置'**
  String get customBackgroundEnabledHint;

  /// No description provided for @customBackgroundChooseHint.
  ///
  /// In zh, this message translates to:
  /// **'选择图片作为全应用背景'**
  String get customBackgroundChooseHint;

  /// No description provided for @removeBackground.
  ///
  /// In zh, this message translates to:
  /// **'移除背景'**
  String get removeBackground;

  /// No description provided for @adjustBackground.
  ///
  /// In zh, this message translates to:
  /// **'调整背景'**
  String get adjustBackground;

  /// No description provided for @backgroundEditorHint.
  ///
  /// In zh, this message translates to:
  /// **'拖动图片调整位置，双指缩放到合适大小'**
  String get backgroundEditorHint;

  /// No description provided for @floatingLyricsEnable.
  ///
  /// In zh, this message translates to:
  /// **'桌面悬浮歌词'**
  String get floatingLyricsEnable;

  /// No description provided for @floatingLyricsEnableSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'在桌面顶部显示歌词，支持拖拽、缩放和锁定'**
  String get floatingLyricsEnableSubtitle;

  /// No description provided for @floatingLyricsPermissionSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'显示在其他应用上方，需要系统悬浮窗权限'**
  String get floatingLyricsPermissionSubtitle;

  /// No description provided for @floatingLyricsLock.
  ///
  /// In zh, this message translates to:
  /// **'锁定位置'**
  String get floatingLyricsLock;

  /// No description provided for @floatingLyricsLockSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'锁定后悬浮歌词不可移动、不可点击，触摸会直接落到下面的应用；关闭悬浮歌词会自动解锁'**
  String get floatingLyricsLockSubtitle;

  /// No description provided for @floatingLyricsTextColor.
  ///
  /// In zh, this message translates to:
  /// **'歌词底色'**
  String get floatingLyricsTextColor;

  /// No description provided for @floatingLyricsTextColorSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'未播放部分的文字颜色，默认白色'**
  String get floatingLyricsTextColorSubtitle;

  /// No description provided for @floatingLyricsHighlightColor.
  ///
  /// In zh, this message translates to:
  /// **'已播放高亮色'**
  String get floatingLyricsHighlightColor;

  /// No description provided for @floatingLyricsHighlightColorSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'唱到的部分变为该颜色，悬浮窗里的圆点也调它'**
  String get floatingLyricsHighlightColorSubtitle;

  /// No description provided for @floatingLyricsFontSize.
  ///
  /// In zh, this message translates to:
  /// **'字号'**
  String get floatingLyricsFontSize;

  /// No description provided for @floatingLyricsStrokeWidth.
  ///
  /// In zh, this message translates to:
  /// **'描边强度'**
  String get floatingLyricsStrokeWidth;

  /// No description provided for @floatingLyricsShadowOpacity.
  ///
  /// In zh, this message translates to:
  /// **'阴影强度'**
  String get floatingLyricsShadowOpacity;

  /// No description provided for @customColor.
  ///
  /// In zh, this message translates to:
  /// **'自定义颜色'**
  String get customColor;

  /// No description provided for @defaultLabel.
  ///
  /// In zh, this message translates to:
  /// **'默认'**
  String get defaultLabel;

  /// No description provided for @audioFade.
  ///
  /// In zh, this message translates to:
  /// **'淡入淡出'**
  String get audioFade;

  /// No description provided for @audioFadeSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'播放、暂停时平滑调整音量，默认关闭'**
  String get audioFadeSubtitle;

  /// No description provided for @audioFadeDuration.
  ///
  /// In zh, this message translates to:
  /// **'淡入淡出时长'**
  String get audioFadeDuration;

  /// No description provided for @audioEqualizer.
  ///
  /// In zh, this message translates to:
  /// **'均衡器'**
  String get audioEqualizer;

  /// No description provided for @audioEqualizerSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'调整播放音频的频段增益，设备不支持时会自动忽略'**
  String get audioEqualizerSubtitle;

  /// No description provided for @audioEqualizerPreset.
  ///
  /// In zh, this message translates to:
  /// **'均衡器预设'**
  String get audioEqualizerPreset;

  /// No description provided for @audioBandLow.
  ///
  /// In zh, this message translates to:
  /// **'低频'**
  String get audioBandLow;

  /// No description provided for @audioBandLowMid.
  ///
  /// In zh, this message translates to:
  /// **'中低频'**
  String get audioBandLowMid;

  /// No description provided for @audioBandMid.
  ///
  /// In zh, this message translates to:
  /// **'中频'**
  String get audioBandMid;

  /// No description provided for @audioBandHighMid.
  ///
  /// In zh, this message translates to:
  /// **'中高频'**
  String get audioBandHighMid;

  /// No description provided for @audioBandHigh.
  ///
  /// In zh, this message translates to:
  /// **'高频'**
  String get audioBandHigh;

  /// No description provided for @audioSleepTimer.
  ///
  /// In zh, this message translates to:
  /// **'睡眠定时'**
  String get audioSleepTimer;

  /// No description provided for @audioSleepTimerRemaining.
  ///
  /// In zh, this message translates to:
  /// **'剩余 {time}'**
  String audioSleepTimerRemaining(String time);

  /// No description provided for @audioSleepTimerCountdown.
  ///
  /// In zh, this message translates to:
  /// **'{minutes} 分钟后暂停播放'**
  String audioSleepTimerCountdown(int minutes);

  /// No description provided for @audioSleepTimerDuration.
  ///
  /// In zh, this message translates to:
  /// **'定时时长'**
  String get audioSleepTimerDuration;

  /// No description provided for @audioMinutes.
  ///
  /// In zh, this message translates to:
  /// **'{minutes} 分钟'**
  String audioMinutes(int minutes);

  /// No description provided for @diagnosticsSection.
  ///
  /// In zh, this message translates to:
  /// **'诊断'**
  String get diagnosticsSection;

  /// No description provided for @aboutSection.
  ///
  /// In zh, this message translates to:
  /// **'关于'**
  String get aboutSection;

  /// No description provided for @version.
  ///
  /// In zh, this message translates to:
  /// **'版本'**
  String get version;

  /// No description provided for @diagnosticsLog.
  ///
  /// In zh, this message translates to:
  /// **'诊断日志'**
  String get diagnosticsLog;

  /// No description provided for @diagnosticsLogPathCopied.
  ///
  /// In zh, this message translates to:
  /// **'日志路径已复制'**
  String get diagnosticsLogPathCopied;

  /// No description provided for @diagnosticsLogCleared.
  ///
  /// In zh, this message translates to:
  /// **'诊断日志已清空'**
  String get diagnosticsLogCleared;

  /// No description provided for @copyPath.
  ///
  /// In zh, this message translates to:
  /// **'复制路径'**
  String get copyPath;

  /// No description provided for @clearLog.
  ///
  /// In zh, this message translates to:
  /// **'清空日志'**
  String get clearLog;

  /// No description provided for @diagnosticsExporting.
  ///
  /// In zh, this message translates to:
  /// **'正在导出诊断日志…'**
  String get diagnosticsExporting;

  /// No description provided for @diagnosticsExported.
  ///
  /// In zh, this message translates to:
  /// **'诊断日志已导出'**
  String get diagnosticsExported;

  /// No description provided for @diagnosticsExportPathCopied.
  ///
  /// In zh, this message translates to:
  /// **'诊断日志已导出，文件路径已复制到剪贴板'**
  String get diagnosticsExportPathCopied;

  /// No description provided for @diagnosticsExportFailed.
  ///
  /// In zh, this message translates to:
  /// **'导出失败：{error}'**
  String diagnosticsExportFailed(String error);

  /// No description provided for @share.
  ///
  /// In zh, this message translates to:
  /// **'分享'**
  String get share;

  /// No description provided for @accountLoggedIn.
  ///
  /// In zh, this message translates to:
  /// **'已登录'**
  String get accountLoggedIn;

  /// No description provided for @accountTapToLogin.
  ///
  /// In zh, this message translates to:
  /// **'点击登录'**
  String get accountTapToLogin;

  /// No description provided for @accountLogout.
  ///
  /// In zh, this message translates to:
  /// **'退出登录'**
  String get accountLogout;

  /// No description provided for @accountLogoutConfirm.
  ///
  /// In zh, this message translates to:
  /// **'确定要退出 {platform} 账号吗？'**
  String accountLogoutConfirm(String platform);

  /// No description provided for @actionSave.
  ///
  /// In zh, this message translates to:
  /// **'保存'**
  String get actionSave;

  /// No description provided for @actionCancel.
  ///
  /// In zh, this message translates to:
  /// **'取消'**
  String get actionCancel;

  /// No description provided for @actionReset.
  ///
  /// In zh, this message translates to:
  /// **'重置'**
  String get actionReset;

  /// No description provided for @actionLogout.
  ///
  /// In zh, this message translates to:
  /// **'退出'**
  String get actionLogout;

  /// No description provided for @playerNowPlaying.
  ///
  /// In zh, this message translates to:
  /// **'正在播放'**
  String get playerNowPlaying;

  /// No description provided for @playerNotPlaying.
  ///
  /// In zh, this message translates to:
  /// **'未在播放'**
  String get playerNotPlaying;

  /// No description provided for @playerAddedToLikes.
  ///
  /// In zh, this message translates to:
  /// **'已收藏到我喜欢'**
  String get playerAddedToLikes;

  /// No description provided for @playerRemovedFromLikes.
  ///
  /// In zh, this message translates to:
  /// **'已取消收藏'**
  String get playerRemovedFromLikes;

  /// No description provided for @playerAddedToQueue.
  ///
  /// In zh, this message translates to:
  /// **'已添加到播放队列'**
  String get playerAddedToQueue;

  /// No description provided for @playerSongInfoCopied.
  ///
  /// In zh, this message translates to:
  /// **'歌曲信息已复制'**
  String get playerSongInfoCopied;

  /// No description provided for @playerPlaybackSettings.
  ///
  /// In zh, this message translates to:
  /// **'播放设置'**
  String get playerPlaybackSettings;

  /// No description provided for @playerAddToPlatformPlaylist.
  ///
  /// In zh, this message translates to:
  /// **'添加到平台歌单'**
  String get playerAddToPlatformPlaylist;

  /// No description provided for @playerAddToQueue.
  ///
  /// In zh, this message translates to:
  /// **'加入播放队列'**
  String get playerAddToQueue;

  /// No description provided for @playerCopySongInfo.
  ///
  /// In zh, this message translates to:
  /// **'复制歌曲信息'**
  String get playerCopySongInfo;

  /// No description provided for @playerAddedToPlaylist.
  ///
  /// In zh, this message translates to:
  /// **'已添加到歌单'**
  String get playerAddedToPlaylist;

  /// No description provided for @playerAddToPlaylistFailed.
  ///
  /// In zh, this message translates to:
  /// **'添加失败，当前平台可能暂不支持编辑该歌单'**
  String get playerAddToPlaylistFailed;

  /// No description provided for @playerPlay.
  ///
  /// In zh, this message translates to:
  /// **'播放'**
  String get playerPlay;

  /// No description provided for @playerPause.
  ///
  /// In zh, this message translates to:
  /// **'暂停'**
  String get playerPause;

  /// No description provided for @playerPrevious.
  ///
  /// In zh, this message translates to:
  /// **'上一首'**
  String get playerPrevious;

  /// No description provided for @playerNext.
  ///
  /// In zh, this message translates to:
  /// **'下一首'**
  String get playerNext;

  /// No description provided for @playerShuffle.
  ///
  /// In zh, this message translates to:
  /// **'随机播放'**
  String get playerShuffle;

  /// No description provided for @playerRepeat.
  ///
  /// In zh, this message translates to:
  /// **'循环模式'**
  String get playerRepeat;

  /// No description provided for @playerToggleLyrics.
  ///
  /// In zh, this message translates to:
  /// **'显示歌词'**
  String get playerToggleLyrics;

  /// No description provided for @playerToggleArtwork.
  ///
  /// In zh, this message translates to:
  /// **'显示封面'**
  String get playerToggleArtwork;

  /// No description provided for @playerLike.
  ///
  /// In zh, this message translates to:
  /// **'我喜欢'**
  String get playerLike;

  /// No description provided for @playerCollapse.
  ///
  /// In zh, this message translates to:
  /// **'收起'**
  String get playerCollapse;

  /// No description provided for @moreActions.
  ///
  /// In zh, this message translates to:
  /// **'更多操作'**
  String get moreActions;

  /// No description provided for @platformLocal.
  ///
  /// In zh, this message translates to:
  /// **'本地音乐'**
  String get platformLocal;

  /// No description provided for @platformNetease.
  ///
  /// In zh, this message translates to:
  /// **'网易云音乐'**
  String get platformNetease;

  /// No description provided for @platformQq.
  ///
  /// In zh, this message translates to:
  /// **'QQ 音乐'**
  String get platformQq;

  /// No description provided for @platformKugou.
  ///
  /// In zh, this message translates to:
  /// **'酷狗音乐'**
  String get platformKugou;

  /// No description provided for @sessionExpired.
  ///
  /// In zh, this message translates to:
  /// **'登录已过期，请重新登录'**
  String get sessionExpired;

  /// No description provided for @sessionGoToLogin.
  ///
  /// In zh, this message translates to:
  /// **'去登录'**
  String get sessionGoToLogin;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
