// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Mconnect';

  @override
  String get navSearch => 'Search';

  @override
  String get navDiscover => 'Discover';

  @override
  String get navLibrary => 'Library';

  @override
  String get navDownloads => 'Downloads';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsAccounts => 'Accounts';

  @override
  String get settingsAccountsSubtitle =>
      'NetEase Cloud, QQ Music and Kugou sign-in status';

  @override
  String get settingsAppearance => 'Appearance';

  @override
  String get settingsAppearanceSubtitle =>
      'Theme mode, accent colour and custom background';

  @override
  String get settingsFloatingLyrics => 'Desktop lyrics';

  @override
  String get settingsFloatingLyricsSubtitle =>
      'Desktop lyrics switch, colours, size and shadow';

  @override
  String get settingsAudio => 'Audio enhancement';

  @override
  String get settingsAudioSubtitle => 'Crossfade, equalizer and sleep timer';

  @override
  String get settingsDiagnostics => 'Diagnostics & about';

  @override
  String get settingsDiagnosticsSubtitle => 'Log location and app version';

  @override
  String get settingsBackup => 'Backup & restore';

  @override
  String get settingsBackupSubtitle =>
      'Export/import likes, playlists, statistics and settings';

  @override
  String get settingsExportDiagnostics => 'Export diagnostic log';

  @override
  String get settingsExportDiagnosticsSubtitle =>
      'Bundle recent events and the log, then share (redacted)';

  @override
  String get settingsAccountsTitle => 'Accounts';

  @override
  String get settingsAppearanceTitle => 'Appearance';

  @override
  String get settingsFloatingLyricsTitle => 'Desktop lyrics';

  @override
  String get settingsAudioTitle => 'Audio enhancement';

  @override
  String get settingsDiagnosticsTitle => 'Diagnostics & about';

  @override
  String get themeFollowSystem => 'Follow system';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get themeColor => 'Accent colour';

  @override
  String get themeColorSubtitle =>
      'Affects buttons, progress bars, the navigation bar and highlights';

  @override
  String get uiStyle => 'UI style';

  @override
  String get uiStyleMaterial => 'Material style';

  @override
  String get uiStyleMiuix => 'Miuix style';

  @override
  String get backgroundRemoved => 'Custom background removed';

  @override
  String get backgroundApplied => 'Custom background applied';

  @override
  String get backgroundUpdated => 'Custom background updated';

  @override
  String get backgroundImageUnreadable => 'Could not read the selected image';

  @override
  String get backgroundImageSizeUnreadable => 'Could not read the image size';

  @override
  String get backgroundFileMissing =>
      'The background file is gone, please pick another one';

  @override
  String backgroundProcessFailed(String error) {
    return 'Processing the background failed: $error';
  }

  @override
  String get customBackground => 'Custom background';

  @override
  String get customBackgroundEnabledHint =>
      'Enabled — tap to reposition the background';

  @override
  String get customBackgroundChooseHint =>
      'Pick an image to use behind the whole app';

  @override
  String get removeBackground => 'Remove background';

  @override
  String get adjustBackground => 'Adjust background';

  @override
  String get backgroundEditorHint =>
      'Drag to move, pinch to zoom to the size you want';

  @override
  String get floatingLyricsEnable => 'Desktop lyrics';

  @override
  String get floatingLyricsEnableSubtitle =>
      'Show lyrics at the top of the desktop; drag, zoom and lock supported';

  @override
  String get floatingLyricsPermissionSubtitle =>
      'Shows above other apps; needs the system overlay permission';

  @override
  String get floatingLyricsLock => 'Lock position';

  @override
  String get floatingLyricsLockSubtitle =>
      'A locked overlay cannot be moved or tapped, so touches reach the app below; turning the overlay off unlocks it';

  @override
  String get floatingLyricsTextColor => 'Lyrics base colour';

  @override
  String get floatingLyricsTextColorSubtitle =>
      'Colour of the not-yet-sung part, white by default';

  @override
  String get floatingLyricsHighlightColor => 'Played highlight colour';

  @override
  String get floatingLyricsHighlightColorSubtitle =>
      'Used for the sung part and for the dot in the overlay';

  @override
  String get floatingLyricsFontSize => 'Font size';

  @override
  String get floatingLyricsStrokeWidth => 'Stroke width';

  @override
  String get floatingLyricsShadowOpacity => 'Shadow strength';

  @override
  String get customColor => 'Custom colour';

  @override
  String get defaultLabel => 'Default';

  @override
  String get audioFade => 'Crossfade';

  @override
  String get audioFadeSubtitle =>
      'Smoothly ramp the volume on play/pause; off by default';

  @override
  String get audioFadeDuration => 'Crossfade duration';

  @override
  String get audioEqualizer => 'Equalizer';

  @override
  String get audioEqualizerSubtitle =>
      'Adjust per-band gain; silently ignored on unsupported devices';

  @override
  String get audioEqualizerPreset => 'Equalizer preset';

  @override
  String get audioBandLow => 'Low';

  @override
  String get audioBandLowMid => 'Low-mid';

  @override
  String get audioBandMid => 'Mid';

  @override
  String get audioBandHighMid => 'High-mid';

  @override
  String get audioBandHigh => 'High';

  @override
  String get audioSleepTimer => 'Sleep timer';

  @override
  String audioSleepTimerRemaining(String time) {
    return '$time left';
  }

  @override
  String audioSleepTimerCountdown(int minutes) {
    return 'Pause playback in $minutes minutes';
  }

  @override
  String get audioSleepTimerDuration => 'Timer length';

  @override
  String audioMinutes(int minutes) {
    return '$minutes minutes';
  }

  @override
  String get diagnosticsSection => 'Diagnostics';

  @override
  String get aboutSection => 'About';

  @override
  String get version => 'Version';

  @override
  String get diagnosticsLog => 'Diagnostic log';

  @override
  String get diagnosticsLogPathCopied => 'Log path copied';

  @override
  String get diagnosticsLogCleared => 'Diagnostic log cleared';

  @override
  String get copyPath => 'Copy path';

  @override
  String get clearLog => 'Clear log';

  @override
  String get diagnosticsExporting => 'Exporting the diagnostic log…';

  @override
  String get diagnosticsExported => 'Diagnostic log exported';

  @override
  String get diagnosticsExportPathCopied =>
      'Diagnostic log exported; its path was copied to the clipboard';

  @override
  String diagnosticsExportFailed(String error) {
    return 'Export failed: $error';
  }

  @override
  String get share => 'Share';

  @override
  String get accountLoggedIn => 'Signed in';

  @override
  String get accountTapToLogin => 'Tap to sign in';

  @override
  String get accountLogout => 'Sign out';

  @override
  String accountLogoutConfirm(String platform) {
    return 'Sign out of $platform?';
  }

  @override
  String get actionSave => 'Save';

  @override
  String get actionCancel => 'Cancel';

  @override
  String get actionReset => 'Reset';

  @override
  String get actionLogout => 'Sign out';

  @override
  String get commonRetry => 'Retry';

  @override
  String get commonPlayNext => 'Play next';

  @override
  String get commonAddToPlaylist => 'Add to playlist';

  @override
  String get commonDownload => 'Download';

  @override
  String get commonDownloaded => 'Downloaded';

  @override
  String get commonLike => 'Like';

  @override
  String get commonUnlike => 'Unlike';

  @override
  String get commonCopyLink => 'Copy link';

  @override
  String get playerNowPlaying => 'Now playing';

  @override
  String get playerNotPlaying => 'Nothing playing';

  @override
  String get playerAddedToLikes => 'Added to your likes';

  @override
  String get playerRemovedFromLikes => 'Removed from your likes';

  @override
  String get playerAddedToQueue => 'Added to the play queue';

  @override
  String get playerSongInfoCopied => 'Song info copied';

  @override
  String get playerPlaybackSettings => 'Playback settings';

  @override
  String get playerAddToPlatformPlaylist => 'Add to a platform playlist';

  @override
  String get playerAddToQueue => 'Add to play queue';

  @override
  String get playerCopySongInfo => 'Copy song info';

  @override
  String get playerAddedToPlaylist => 'Added to the playlist';

  @override
  String get playerAddToPlaylistFailed =>
      'Could not add: this platform may not allow editing that playlist';

  @override
  String get playerPlay => 'Play';

  @override
  String get playerPause => 'Pause';

  @override
  String get playerPrevious => 'Previous track';

  @override
  String get playerNext => 'Next track';

  @override
  String get playerShuffle => 'Shuffle';

  @override
  String get playerRepeat => 'Repeat mode';

  @override
  String get playerToggleLyrics => 'Show lyrics';

  @override
  String get playerToggleArtwork => 'Show artwork';

  @override
  String get playerLike => 'Like';

  @override
  String get playerCollapse => 'Collapse';

  @override
  String get moreActions => 'More actions';

  @override
  String get platformLocal => 'Local music';

  @override
  String get platformNetease => 'NetEase Cloud Music';

  @override
  String get platformQq => 'QQ Music';

  @override
  String get platformKugou => 'Kugou Music';

  @override
  String get sessionExpired => 'Your session expired, please sign in again';

  @override
  String get sessionGoToLogin => 'Sign in';

  @override
  String get netConnectionFailed =>
      'Couldn\'t connect. Check your network and try again';

  @override
  String get netLoginExpired => 'Your session expired, please sign in again';

  @override
  String get netCurrentPlatform => 'the current platform';

  @override
  String netSongNotAvailable(String platform) {
    return 'This song isn\'t available on $platform';
  }

  @override
  String get netQualityNotAvailable => 'That audio quality isn\'t available';

  @override
  String netQualityDowngraded(String quality) {
    return 'That audio quality isn\'t available, switched to $quality';
  }

  @override
  String get netLyricsNotFound => 'No lyrics available';

  @override
  String netNoVip(String platform) {
    return '$platform membership required';
  }

  @override
  String get netStoragePermissionDenied =>
      'Storage permission denied, grant it in Settings';

  @override
  String get netNotFound => 'This content no longer exists';

  @override
  String netUnsupported(String platform) {
    return '$platform doesn\'t support this yet';
  }

  @override
  String get netStorageFull => 'Not enough storage space';

  @override
  String get netRequestCancelled => 'Request cancelled';

  @override
  String netRequestTimeout(String platform) {
    return '$platform request timed out';
  }

  @override
  String netServerError(String platform) {
    return '$platform server error';
  }

  @override
  String get netRequestFailed => 'Request failed';

  @override
  String netRequestFailedWithCode(int code) {
    return 'Request failed ($code)';
  }

  @override
  String get netUnknownPlatform => 'Unknown platform';

  @override
  String get commonLoadFailed => 'Failed to load';

  @override
  String get commonConfirm => 'OK';

  @override
  String get commonAllPlatforms => 'All platforms';

  @override
  String get commonPlaylist => 'Playlists';

  @override
  String get commonNow => 'Just now';

  @override
  String get commonToday => 'Today';

  @override
  String get commonYesterday => 'Yesterday';

  @override
  String commonDaysAgo(int count) {
    return '$count days ago';
  }

  @override
  String commonHoursAgo(int count) {
    return '$count hours ago';
  }

  @override
  String commonMinutesAgo(int count) {
    return '$count minutes ago';
  }

  @override
  String get commonMonthDayPattern => 'MMM d';

  @override
  String get libraryLikes => 'Liked songs';

  @override
  String libraryLikesWithCount(int count) {
    return 'Liked songs ($count)';
  }

  @override
  String get libraryLikesFilter => 'Filter by platform';

  @override
  String get libraryLikesEmpty => 'No liked songs yet';

  @override
  String get libraryLikesEmptyHint => 'Tap the heart in the player to add one';

  @override
  String get libraryLikesEmptyForPlatform => 'No liked songs on this platform';

  @override
  String get libraryHistory => 'Listening history';

  @override
  String libraryHistoryWithCount(int count) {
    return 'Listening history ($count)';
  }

  @override
  String get libraryHistoryClear => 'Clear history';

  @override
  String get libraryHistoryClearConfirm => 'Clear listening history';

  @override
  String get libraryHistoryClearConfirmBody =>
      'Clear the entire listening history?';

  @override
  String get libraryHistoryEmpty => 'No listening history yet';

  @override
  String get libraryImportPlaylist => 'Import playlist';

  @override
  String get statsTitle => 'Listening stats';

  @override
  String get cacheTitle => 'Offline cache';

  @override
  String get smartPlaylistTitle => 'Smart playlists';

  @override
  String get downloadTitle => 'Downloads';

  @override
  String get downloadButtonTooltip => 'Download (long-press to cache offline)';

  @override
  String get cacheQueuedOfflineMode =>
      'Offline mode is on — queued, but it will not start automatically';

  @override
  String get cacheQueuedWifi =>
      'Queued for offline cache — it will start once you are on Wi-Fi';

  @override
  String get cacheQueuedPaused =>
      'Queued for offline cache — the queue is paused';

  @override
  String cacheAdded(String name) {
    return 'Added to the offline cache: $name';
  }

  @override
  String get cacheAlreadyQueued => 'This song is already in the cache list';

  @override
  String downloadQualityPicker(String name) {
    return 'Choose download quality - $name';
  }

  @override
  String get downloadRequiresSvip => 'SVIP';

  @override
  String get downloadRequiresVip => 'VIP';

  @override
  String downloadLosslessFormat(String format) {
    return '$format · lossless';
  }

  @override
  String downloadNeedsSvip(String quality) {
    return 'SVIP is required to download $quality';
  }

  @override
  String downloadNeedsVip(String quality) {
    return 'VIP is required to download $quality';
  }

  @override
  String downloadStarted(String name, String quality) {
    return 'Download started: $name ($quality)';
  }

  @override
  String get libraryRefreshCurrentPlaylist => 'Refresh the current playlists';

  @override
  String get libraryNewPlaylist => 'New playlist';

  @override
  String get libraryMyPlaylists => 'My playlists';

  @override
  String get libraryPlaylistName => 'Playlist name';

  @override
  String get libraryCreate => 'Create';

  @override
  String get libraryCreatePlaylistFailed => 'Couldn\'t create the playlist';

  @override
  String get libraryPlaylistCreated => 'Playlist created';

  @override
  String get libraryDeletePlaylist => 'Delete playlist';

  @override
  String libraryDeletePlaylistConfirm(String name) {
    return 'Delete \"$name\"?';
  }

  @override
  String get libraryPlaylistDeleted => 'Playlist deleted';

  @override
  String get libraryDeletePlaylistFailed => 'Couldn\'t delete the playlist';

  @override
  String get commonDelete => 'Delete';
}
