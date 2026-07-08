import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/stigla_api_client.dart';
import '../../data/local/gtfs_offline_cache.dart';
import '../../data/local/settings_store.dart';
import '../../data/location/location_service.dart';
import '../../data/repositories/arrivals_repository_impl.dart';
import '../../data/repositories/favorites_repository_impl.dart';
import '../../data/repositories/geocode_repository_impl.dart';
import '../../data/repositories/lines_repository_impl.dart';
import '../../data/repositories/stops_repository_impl.dart';
import '../../domain/models/arrival.dart';
import '../../domain/models/favorite_stop.dart';
import '../../domain/models/stop.dart';
import '../../domain/repositories/arrivals_repository.dart';
import '../../domain/repositories/favorites_repository.dart';
import '../../domain/repositories/geocode_repository.dart';
import '../../domain/repositories/lines_repository.dart';
import '../../domain/repositories/stops_repository.dart';

final apiClientProvider = Provider<StiglaApiClient>((ref) => StiglaApiClient());

final gtfsOfflineCacheProvider = Provider<GtfsOfflineCache>(
  (ref) => GtfsOfflineCache(ref.watch(apiClientProvider)),
);

final arrivalsRepositoryProvider = Provider<ArrivalsRepository>(
  (ref) => ArrivalsRepositoryImpl(ref.watch(apiClientProvider)),
);

final stopsRepositoryProvider = Provider<StopsRepository>(
  (ref) => StopsRepositoryImpl(ref.watch(apiClientProvider), ref.watch(gtfsOfflineCacheProvider)),
);

final linesRepositoryProvider = Provider<LinesRepository>(
  (ref) => LinesRepositoryImpl(ref.watch(apiClientProvider), ref.watch(gtfsOfflineCacheProvider)),
);

final geocodeRepositoryProvider = Provider<GeocodeRepository>(
  (ref) => GeocodeRepositoryImpl(ref.watch(apiClientProvider)),
);

final locationServiceProvider = Provider<LocationService>((ref) => LocationService());

final favoritesRepositoryProvider = Provider<FavoritesRepository>((ref) => FavoritesRepositoryImpl());

final settingsStoreProvider = Provider<SettingsStore>((ref) => SettingsStore());

/// Arrivals for a single stop. Widgets that want auto-refresh should
/// periodically call `ref.invalidate(arrivalsProvider(stopId))`.
final arrivalsProvider = FutureProvider.family.autoDispose<ArrivalsBoard, String>((ref, stopId) {
  return ref.watch(arrivalsRepositoryProvider).getArrivals(stopId);
});

/// Looks up a stop's coordinates from the on-device GTFS mirror, for the
/// live-tracking mini map — the arrivals contract itself doesn't carry the
/// stop's own lat/lon, only the vehicles'.
final stopLocationProvider = FutureProvider.family.autoDispose<Stop?, String>((ref, stopId) async {
  final stops = await ref.watch(gtfsOfflineCacheProvider).getStops();
  for (final s in stops) {
    if (s.stopId == stopId) return s;
  }
  return null;
});

class SettingsController extends AsyncNotifier<AppSettings> {
  @override
  Future<AppSettings> build() {
    return ref.watch(settingsStoreProvider).load();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    await ref.read(settingsStoreProvider).saveThemeMode(mode);
    state = AsyncData((state.valueOrNull ?? AppSettings.defaults).copyWith(themeMode: mode));
  }

  Future<void> setLocaleCode(String? code) async {
    await ref.read(settingsStoreProvider).saveLocaleCode(code);
    state = AsyncData((state.valueOrNull ?? AppSettings.defaults).copyWith(localeCode: () => code));
  }

  Future<void> setRefreshIntervalSeconds(int seconds) async {
    await ref.read(settingsStoreProvider).saveRefreshIntervalSeconds(seconds);
    state = AsyncData((state.valueOrNull ?? AppSettings.defaults).copyWith(refreshIntervalSeconds: seconds));
  }
}

final settingsControllerProvider = AsyncNotifierProvider<SettingsController, AppSettings>(SettingsController.new);

class FavoritesController extends AsyncNotifier<List<FavoriteStop>> {
  @override
  Future<List<FavoriteStop>> build() {
    return ref.watch(favoritesRepositoryProvider).getFavorites();
  }

  Future<void> add(FavoriteStop stop) async {
    await ref.read(favoritesRepositoryProvider).add(stop);
    ref.invalidateSelf();
  }

  Future<void> remove(String stopId) async {
    await ref.read(favoritesRepositoryProvider).remove(stopId);
    ref.invalidateSelf();
  }

  Future<bool> isFavorite(String stopId) {
    return ref.read(favoritesRepositoryProvider).isFavorite(stopId);
  }
}

final favoritesControllerProvider = AsyncNotifierProvider<FavoritesController, List<FavoriteStop>>(
  FavoritesController.new,
);
