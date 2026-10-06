import 'dart:async';

import 'package:hive_flutter/hive_flutter.dart';

/// Recent search queries, persisted in Hive.
///
/// The search box used to forget everything the moment the page was left, so
/// every common query had to be typed again. Entries are newest-first, unique,
/// and capped so the box cannot grow without bound.
class SearchHistoryStore {
  SearchHistoryStore({Future<Box<dynamic>> Function()? boxOpener})
    : _openBox = boxOpener ?? _openHiveBox;

  static const String boxName = 'search_history';
  static const String _key = 'queries';
  static const int maxEntries = 15;

  final Future<Box<dynamic>> Function() _openBox;

  /// Opens the history box, contained in its own error zone.
  ///
  /// `Hive.openBox` reports a failure through the ambient zone as well as
  /// through its returned future (`HiveImpl._openBox` forks a zone and completes
  /// a completer), so a `try`/`catch` around the `await` is not enough: in a
  /// widget test — where Hive is deliberately not initialised — the ambient
  /// report fails the test even though nothing user-visible broke. Running the
  /// open inside [runZonedGuarded] routes that report here, and the store
  /// degrades to "no history" as documented in [load].
  static Future<Box<dynamic>> _openHiveBox() {
    final completer = Completer<Box<dynamic>>();
    void completeError(Object error, StackTrace stackTrace) {
      if (!completer.isCompleted) completer.completeError(error, stackTrace);
    }

    runZonedGuarded(
      () async {
        try {
          final box = await Hive.openBox<dynamic>(boxName);
          if (!completer.isCompleted) completer.complete(box);
        } catch (error, stackTrace) {
          completeError(error, stackTrace);
        }
      },
      completeError,
    );
    return completer.future;
  }

  /// Reads the history.
  ///
  /// Hive is not initialised in widget tests, and a history panel is not worth
  /// crashing a screen over — a read failure degrades to "no history".
  Future<List<String>> load() async {
    try {
      final box = await _openBox();
      final raw = box.get(_key);
      if (raw is! List) return const [];
      return raw
          .whereType<String>()
          .where((entry) => entry.trim().isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Adds [query] to the front, returning the new list.
  Future<List<String>> add(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return load();
    final current = await load();
    final next = <String>[
      trimmed,
      ...current.where((entry) => entry != trimmed),
    ].take(maxEntries).toList();
    await _write(next);
    return next;
  }

  Future<List<String>> remove(String query) async {
    final current = await load();
    final next = current.where((entry) => entry != query).toList();
    await _write(next);
    return next;
  }

  Future<List<String>> clear() async {
    await _write(const []);
    return const [];
  }

  Future<void> _write(List<String> entries) async {
    try {
      final box = await _openBox();
      await box.put(_key, entries);
    } catch (_) {
      // Persisting is best-effort; the in-memory list in the notifier stays
      // correct for this session.
    }
  }
}
