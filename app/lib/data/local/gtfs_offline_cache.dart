import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/geo.dart';
import '../../domain/models/line_info.dart';
import '../../domain/models/stop.dart';
import '../api/stigla_api_client.dart';

/// On-device mirror of the GTFS reference data (stop names/coordinates, line
/// metadata), so search and "nearby" keep working — against slightly stale
/// data — when the network is down. Refreshed opportunistically; never
/// blocks the UI since the live backend call is always tried first.
class GtfsOfflineCache {
  GtfsOfflineCache(this._client);

  final StiglaApiClient _client;

  static const _stopsKey = 'gtfs_cache_stops_v1';
  static const _linesKey = 'gtfs_cache_lines_v1';
  static const _fetchedAtKey = 'gtfs_cache_fetched_at_v1';
  static const _maxAge = Duration(days: 1);

  Future<void> refreshIfStale() async {
    final prefs = await SharedPreferences.getInstance();
    final fetchedAtRaw = prefs.getString(_fetchedAtKey);
    if (fetchedAtRaw != null) {
      final age = DateTime.now().difference(DateTime.parse(fetchedAtRaw));
      if (age < _maxAge) return;
    }

    try {
      final stopsJson = await _client.getJson('/api/v1/stops/all');
      final linesJson = await _client.getJson('/api/v1/lines/all');
      await prefs.setString(_stopsKey, jsonEncode(stopsJson['stops']));
      await prefs.setString(_linesKey, jsonEncode(linesJson['lines']));
      await prefs.setString(_fetchedAtKey, DateTime.now().toIso8601String());
    } catch (_) {
      // Best-effort: keep whatever was cached before (possibly nothing).
    }
  }

  Future<List<Stop>> getStops() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_stopsKey);
    if (raw == null) return const [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list.map((e) => Stop.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<LineInfo>> getLines() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_linesKey);
    if (raw == null) return const [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list.map((e) => LineInfo.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<Stop>> searchStopsOffline(String query) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final stops = await getStops();
    return stops.where((s) => s.name.toLowerCase().contains(q)).take(50).toList();
  }

  Future<List<LineInfo>> searchLinesOffline(String query) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final lines = await getLines();
    return lines.where((l) => l.line.toLowerCase().contains(q)).take(50).toList();
  }

  Future<List<Stop>> nearbyOffline(double lat, double lon, double radiusMeters) async {
    final stops = await getStops();
    final withDistance = stops
        .map((s) => (stop: s, distance: haversineDistanceMeters(lat, lon, s.lat, s.lon)))
        .where((e) => e.distance <= radiusMeters)
        .toList()
      ..sort((a, b) => a.distance.compareTo(b.distance));
    return withDistance.take(50).map((e) => e.stop).toList();
  }
}
