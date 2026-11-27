import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/repositories/pinned_favorites_repository.dart';

/// Local-only store of custom names, like the favourite stops store — no
/// accounts, no sync.
class PinnedFavoritesRepositoryImpl implements PinnedFavoritesRepository {
  static const _namesKey = 'custom_names_v1';

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
