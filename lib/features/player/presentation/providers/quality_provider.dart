import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../models/audio_quality.dart';
import '../../../../platform/base/platform_registry.dart';
import 'player_provider.dart';

/// Fetches available audio qualities for the currently playing song.
final availableQualitiesProvider =
    FutureProvider.autoDispose<List<AudioQuality>>((ref) async {
      final song = ref.watch(playerProvider.select((s) => s.currentSong));
      if (song == null) return [];

      try {
        final platform = PlatformRegistry.get(song.platform);
        return await platform
            .getAvailableQualities(song.id)
            .timeout(const Duration(seconds: 8));
      } catch (e) {
        return [];
      }
    });
