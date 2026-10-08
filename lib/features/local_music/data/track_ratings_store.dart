import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../core/database/app_database.dart';

/// Ratings and the play counts the local library sorts and filters by.
///
/// An abstract store with a Drift implementation and a memory one, exactly like
/// `LocalTrackStore`: the provider must be testable without a database. Ratings
/// live in `track_ratings` (schema v4) keyed by `<platform>:<songId>`, and the
/// play counts are **aggregated from `play_events`** — see
/// [TrackRatingsDao.playCountsFromEvents] — so this feature never introduces a
/// second place where "how often was this played" is decided.
abstract class TrackRatingsStore {
  /// `songKey` → rating for every **rated** song; unrated songs are absent.
  Future<Map<String, int>> loadRatings();

  /// `songKey` → play count, aggregated from the play events. Songs with no
  /// events are absent (the query layer reads absence as `0`).
  Future<Map<String, int>> loadPlayCounts();

  /// Sets (or clears, at `0`) the rating for [songKey].
  Future<void> setRating(String songKey, int rating);

  /// Recomputes the materialised `play_count` / `last_played_at` cache from the
  /// play events.
  ///
  /// Not needed for the numbers this store returns — those are aggregated live —
  /// but it keeps the cached columns that other consumers read from drifting.
  Future<void> syncPlayStats();
}

/// The store the app uses: the real database outside tests, an in-memory one
/// under `flutter test`.
///
/// Same reasoning as `defaultDownloadTaskStore()`: a widget test that knows
/// nothing about ratings must not open the app's sqlite file (path_provider is
/// not available there), and a memory store is more useful than a no-op because
/// the page tests can then exercise rating at all.
TrackRatingsStore defaultTrackRatingsStore() {
  if (Platform.environment.containsKey('FLUTTER_TEST')) {
    return MemoryTrackRatingsStore();
  }
  return DriftTrackRatingsStore();
}

class DriftTrackRatingsStore implements TrackRatingsStore {
  DriftTrackRatingsStore({AppDatabase? database})
    : _db = database ?? _appDatabase();

  /// Resolves the process-wide database without shadowing it with the
  /// constructor parameter of the same name.
  static AppDatabase _appDatabase() => database;

  final AppDatabase _db;

  @override
  Future<Map<String, int>> loadRatings() => _db.trackRatingsDao.allRatings();

  @override
  Future<Map<String, int>> loadPlayCounts() =>
      _db.trackRatingsDao.playCountsFromEvents();

  @override
  Future<void> setRating(String songKey, int rating) =>
      _db.trackRatingsDao.setRating(songKey, rating);

  @override
  Future<void> syncPlayStats() => _db.trackRatingsDao.syncPlayStats();
}

/// In-memory store for tests and previews.
class MemoryTrackRatingsStore implements TrackRatingsStore {
  MemoryTrackRatingsStore({
    Map<String, int> ratings = const {},
    Map<String, int> playCounts = const {},
  }) : _ratings = {...ratings},
       _playCounts = {...playCounts};

  final Map<String, int> _ratings;
  final Map<String, int> _playCounts;

  /// How many times [syncPlayStats] was called, so a test can assert the page
  /// does not recompute the whole aggregate on every rebuild.
  int syncCalls = 0;

  @override
  Future<Map<String, int>> loadRatings() async => Map.of(_ratings);

  @override
  Future<Map<String, int>> loadPlayCounts() async => Map.of(_playCounts);

  @override
  Future<void> setRating(String songKey, int rating) async {
    if (rating <= 0) {
      _ratings.remove(songKey);
      return;
    }
    _ratings[songKey] = rating.clamp(1, 5);
  }

  @override
  Future<void> syncPlayStats() async {
    syncCalls++;
  }

  /// Test hook: pretend the play history changed.
  @visibleForTesting
  void setPlayCount(String songKey, int count) {
    _playCounts[songKey] = count;
  }
}
