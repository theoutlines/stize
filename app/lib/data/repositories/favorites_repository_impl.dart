import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/favorite_stop.dart';
import '../../domain/repositories/favorites_repository.dart';

/// Favorite stops live only on-device — no accounts, no sync.
class FavoritesRepositoryImpl implements FavoritesRepository {
  static const _prefsKey = 'favorite_stops_v1';

  Future<List<FavoriteStop>> _readAll(SharedPreferences prefs) async {
    final raw = prefs.getStringList(_prefsKey) ?? const [];
    return raw.map((s) => FavoriteStop.fromJson(jsonDecode(s) as Map<String, dynamic>)).toList();
  }

  Future<void> _writeAll(SharedPreferences prefs, List<FavoriteStop> stops) async {
    await prefs.setStringList(_prefsKey, stops.map((s) => jsonEncode(s.toJson())).toList());
  }

  @override
  Future<List<FavoriteStop>> getFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    return _readAll(prefs);
  }

  @override
  Future<void> add(FavoriteStop stop) async {
    final prefs = await SharedPreferences.getInstance();
    final current = await _readAll(prefs);
    if (current.any((s) => s.stopId == stop.stopId)) return;
    await _writeAll(prefs, [...current, stop]);
  }

  @override
  Future<void> remove(String stopId) async {
    final prefs = await SharedPreferences.getInstance();
    final current = await _readAll(prefs);
    await _writeAll(prefs, current.where((s) => s.stopId != stopId).toList());
  }

  @override
  Future<bool> isFavorite(String stopId) async {
    final current = await getFavorites();
    return current.any((s) => s.stopId == stopId);
  }
}
