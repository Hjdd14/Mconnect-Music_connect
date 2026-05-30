import 'package:hive_flutter/hive_flutter.dart';

import '../domain/smart_playlist_rule.dart';

const smartPlaylistRulesBoxName = 'smart_playlists';
const smartPlaylistRulesKey = 'rules';

abstract class SmartPlaylistRepository {
  Future<List<SmartPlaylistRule>> loadRules();
  Future<void> saveRules(List<SmartPlaylistRule> rules);
}

class HiveSmartPlaylistRepository implements SmartPlaylistRepository {
  const HiveSmartPlaylistRepository();

  Future<Box<dynamic>> _box() => Hive.openBox(smartPlaylistRulesBoxName);

  @override
  Future<List<SmartPlaylistRule>> loadRules() async {
    final box = await _box();
    final raw = box.get(smartPlaylistRulesKey);
    if (raw is! List) return const [];
    final rules = raw.map(SmartPlaylistRule.fromJson).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return rules;
  }

  @override
  Future<void> saveRules(List<SmartPlaylistRule> rules) async {
    final box = await _box();
    await box.put(
      smartPlaylistRulesKey,
      rules.map((rule) => rule.toJson()).toList(),
    );
  }
}

class MemorySmartPlaylistRepository implements SmartPlaylistRepository {
  List<SmartPlaylistRule> _rules;

  MemorySmartPlaylistRepository([
    List<SmartPlaylistRule> initialRules = const [],
  ]) : _rules = List<SmartPlaylistRule>.from(initialRules);

  @override
  Future<List<SmartPlaylistRule>> loadRules() async =>
      List<SmartPlaylistRule>.from(_rules)
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  @override
  Future<void> saveRules(List<SmartPlaylistRule> rules) async {
    _rules = List<SmartPlaylistRule>.from(rules);
  }
}
