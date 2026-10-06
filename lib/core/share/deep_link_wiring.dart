import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/library/presentation/providers/my_playlists_provider.dart';
import '../../features/player/presentation/providers/player_provider.dart';
import '../router/app_router.dart';
import 'deep_link_service.dart';
import 'share_links.dart';

/// Wires inbound links into the app: plays a linked song, imports a linked
/// playlist, and routes to the right page.
///
/// This is the only file in `lib/core/share/` that knows about the router, the
/// player and the widget tree — `deep_link_service.dart` stays pure so its
/// parsing/subscription logic is testable on its own.
///
/// Call it once from the app state's `initState`; the listener starts after the
/// first frame, so a navigation is never issued before the router exists.
/// Dispose the returned service with the state.
///
/// ```dart
/// _deepLinks = attachDeepLinkHandling(
///   ref,
///   navigate: appRouter.go,
///   onMessage: (message) => showSuccessSnackBar(context, message),
/// );
/// // dispose(): _deepLinks?.dispose();
/// ```
///
/// [navigate] is injected rather than hard-wired to [appRouter] so the app can
/// pass whatever it uses for navigation (and so tests can observe it).
DeepLinkService attachDeepLinkHandling(
  WidgetRef ref, {
  required void Function(String location) navigate,
  LinkSource source = const AppLinksSource(),
  void Function(String message)? onMessage,
}) {
  final service = DeepLinkService(
    source: source,
    handler: InboundLinkHandler(
      playlists: ref.read(myPlaylistsProvider.notifier),
    ),
    onOutcome: (outcome) {
      switch (outcome) {
        case PlaySongOutcome(song: final song):
          unawaited(ref.read(playerProvider.notifier).playSong(song));
          navigate(ShareLinks.playerLocation);
        case NavigateOutcome(location: final location, message: final message):
          navigate(location);
          if (message != null) onMessage?.call(message);
      }
    },
  );

  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(service.start());
  });

  return service;
}
