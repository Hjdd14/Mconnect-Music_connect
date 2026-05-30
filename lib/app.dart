import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_provider.dart';
import 'features/auth/presentation/providers/auth_provider.dart';
import 'features/audio_effects/presentation/providers/audio_effects_provider.dart';
import 'features/floating_lyrics/presentation/providers/floating_lyrics_provider.dart';
import 'features/player/presentation/providers/player_provider.dart';
import 'features/stats/presentation/providers/listening_stats_provider.dart';

class MconnectApp extends ConsumerStatefulWidget {
  const MconnectApp({super.key});

  @override
  ConsumerState<MconnectApp> createState() => _MconnectAppState();
}

class _MconnectAppState extends ConsumerState<MconnectApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ref.read(authProvider.notifier).init();
    ref.listenManual(audioEffectsSettingsProvider, (previous, next) {
      ref
          .read(playerProvider.notifier)
          .setFadeOptions(
            enabled: next.fadeEnabled,
            duration: next.fadeDuration,
          );
    }, fireImmediately: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      unawaited(ref.read(playerProvider.notifier).flushPlaybackMemory());
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(floatingLyricsSyncProvider);
    ref.watch(listeningStatsTrackerProvider);
    final themeSettings = ref.watch(themeSettingsProvider);

    return MaterialApp.router(
      title: 'Mconnect',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(seedColor: themeSettings.seedColor),
      darkTheme: AppTheme.dark(seedColor: themeSettings.seedColor),
      themeMode: themeSettings.mode,
      routerConfig: appRouter,
    );
  }
}
