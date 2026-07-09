import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/pinned_line.dart';
import '../../domain/repositories/pinned_favorites_repository.dart';

/// Local-only carousel store (pinned lines + custom names), like the favourite
/// stops store — no accounts, no sync.
class PinnedFavoritesRepositoryImpl implements PinnedFavoritesRepository {
  static const _linesKey = 'pinned_lines_v1';
  static const _namesKey = 'custom_names_v1';

  @override
  Future<List<PinnedLine>> getLines() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_linesKey) ?? const [];
    return raw
        .map((s) => PinnedLine.fromJson(jsonDecode(s) as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<void> addLine(PinnedLine line) async {
    final prefs = await SharedPreferences.getInstance();
    final current = await getLines();
    if (current.any((l) => l.line == line.line)) return;
    await prefs.setStringList(_linesKey, [
      ...current.map((l) => jsonEncode(l.toJson())),
      jsonEncode(line.toJson()),
    ]);
  }

  @override
  Future<void> removeLine(String line) async {
    final prefs = await SharedPreferences.getInstance();
    final current = await getLines();
    await prefs.setStringList(
      _linesKey,
      current
          .where((l) => l.line != line)
          .map((l) => jsonEncode(l.toJson()))
          .toList(),
    );
  }

  @override
  Future<Map<String, String>> getCustomNames() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_namesKey);
    if (raw == null) return {};
    final map = jsonDecode(raw) as Map<String, dynamic>;
    return map.map((k, v) => MapEntry(k, v as String));
  }

  @override
  Future<void> setCustomName(String key, String? name) async {
    final prefs = await SharedPreferences.getInstance();
    final names = await getCustomNames();
    final trimmed = name?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      names.remove(key);
    } else {
      names[key] = trimmed;
    }
    await prefs.setString(_namesKey, jsonEncode(names));
  }
}
