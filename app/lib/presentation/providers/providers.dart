import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/fleet_matcher.dart';
import '../../data/api/stigla_api_client.dart';
import '../../data/device/device_id_service.dart';
import '../../data/local/gtfs_offline_cache.dart';
import '../../data/local/settings_store.dart';
import '../../data/location/location_service.dart';
import '../../data/repositories/alerts_repository_impl.dart';
import '../../data/repositories/arrivals_repository_impl.dart';
import '../../data/repositories/favorites_repository_impl.dart';
import '../../data/repositories/geocode_repository_impl.dart';
import '../../data/repositories/ideas_repository_impl.dart';
import '../../data/repositories/lines_repository_impl.dart';
import '../../data/repositories/pinned_favorites_repository_impl.dart';
import '../../data/repositories/stops_repository_impl.dart';
import '../../data/repositories/vehicles_repository_impl.dart';
import '../../domain/models/app_config.dart';
import '../../domain/models/arrival.dart';
import '../../domain/models/favorite_stop.dart';
import '../../domain/models/line_analytics.dart';
import '../../domain/models/idea.dart';
import '../../domain/models/pinned_line.dart';
import '../../domain/models/route_alert.dart';
import '../../domain/models/stop.dart';
import '../../domain/repositories/alerts_repository.dart';
import '../../domain/repositories/arrivals_repository.dart';
import '../../domain/repositories/favorites_repository.dart';
import '../../domain/repositories/pinned_favorites_repository.dart';
import '../../domain/repositories/geocode_repository.dart';
import '../../domain/repositories/ideas_repository.dart';
import '../../domain/repositories/lines_repository.dart';
import '../../domain/repositories/stops_repository.dart';
import '../../domain/repositories/vehicles_repository.dart';

final apiClientProvider = Provider<StiglaApiClient>((ref) => StiglaApiClient());

/// Runtime config + feature flags from the backend. Fetched once at startup;
/// on any failure it falls back to [AppConfig.empty] (all flags off), so a
/// dormant feature never leaks if config can't be reached.
final appConfigProvider = FutureProvider<AppConfig>((ref) async {
  try {
    final json = await ref.watch(apiClientProvider).getJson('/api/v1/config');
    return AppConfig.fromJson(json);
  } catch (_) {
    return AppConfig.empty;
  }
});

/// Whether the transport-analytics screens are enabled for this user (remote
/// `analytics_show` flag). Defaults to false until config resolves.
final analyticsEnabledProvider = Provider<bool>(
  (ref) => ref.watch(appConfigProvider).valueOrNull?.analyticsShow ?? false,
);

/// Whether the coverage-map tab is enabled for this user (remote
/// `coverage_map_show` flag). Defaults to false until config resolves.
final coverageEnabledProvider = Provider<bool>(
  (ref) => ref.watch(appConfigProvider).valueOrNull?.coverageMapShow ?? false,
);

/// Rolled-up analytics for one line number (draft transport-analytics feature).
final lineAnalyticsProvider = FutureProvider.family<LineAnalytics, String>((
  ref,
  line,
) async {
  final json = await ref
      .watch(apiClientProvider)
      .getJson('/api/v1/analytics/lines/$line');
  return LineAnalytics.fromJson(json);
});

/// Fleet-ID reference data (task B1–B5). Parsed once from the static asset.
///
/// Returns null — silently disabling every Fleet-ID surface (badges, model
/// card, comfort sort) — if the asset is missing, unreadable, unparseable, or
/// schema-invalid. Transit features are unaffected (spec §5 / B5). No network
/// request: the catalog is a bundled asset.
final fleetCatalogProvider = FutureProvider<FleetCatalog?>((ref) async {
  try {
    final source = await rootBundle.loadString('assets/data/fleet_models.json');
    return FleetCatalog.tryParse(source);
  } catch (_) {
    return null;
  }
});

final deviceIdServiceProvider = Provider<DeviceIdService>((ref) => DeviceIdService());

final alertsRepositoryProvider = Provider<AlertsRepository>(
  (ref) => AlertsRepositoryImpl(ref.watch(apiClientProvider)),
);

/// Route-change alerts (experimental). Small volume, refreshed on each
/// screen visit rather than cached — no need for anything fancier.
final alertsProvider = FutureProvider.autoDispose<List<RouteAlert>>((ref) {
  return ref.watch(alertsRepositoryProvider).list();
});

final ideasRepositoryProvider = Provider<IdeasRepository>(
  (ref) => IdeasRepositoryImpl(ref.watch(apiClientProvider), ref.watch(deviceIdServiceProvider)),
);

final gtfsOfflineCacheProvider = Provider<GtfsOfflineCache>(
  (ref) => GtfsOfflineCache(ref.watch(apiClientProvider)),
);

final arrivalsRepositoryProvider = Provider<ArrivalsRepository>(
  (ref) => ArrivalsRepositoryImpl(ref.watch(apiClientProvider)),
);

final stopsRepositoryProvider = Provider<StopsRepository>(
  (ref) => StopsRepositoryImpl(ref.watch(apiClientProvider), ref.watch(gtfsOfflineCacheProvider)),
);

final vehiclesRepositoryProvider = Provider<VehiclesRepository>(
  (ref) => VehiclesRepositoryImpl(ref.watch(apiClientProvider)),
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

/// Favorites resolved against the on-device GTFS mirror to get coordinates
/// for map markers — `FavoriteStop` itself only stores id+name.
final favoriteStopLocationsProvider = FutureProvider.autoDispose<List<Stop>>((ref) async {
  final favorites = await ref.watch(favoritesControllerProvider.future);
  if (favorites.isEmpty) return const [];
  final allStops = await ref.watch(gtfsOfflineCacheProvider).getStops();
  final byId = {for (final s in allStops) s.stopId: s};
  return [for (final f in favorites) if (byId[f.stopId] != null) byId[f.stopId]!];
});

// ---- Carousel favourites: pinned lines + custom names (P3) -----------------

final pinnedFavoritesRepositoryProvider = Provider<PinnedFavoritesRepository>(
  (ref) => PinnedFavoritesRepositoryImpl(),
);

class PinnedLinesController extends AsyncNotifier<List<PinnedLine>> {
  @override
  Future<List<PinnedLine>> build() {
    return ref.watch(pinnedFavoritesRepositoryProvider).getLines();
  }

  Future<void> add(PinnedLine line) async {
    await ref.read(pinnedFavoritesRepositoryProvider).addLine(line);
    ref.invalidateSelf();
  }

  Future<void> remove(String line) async {
    await ref.read(pinnedFavoritesRepositoryProvider).removeLine(line);
    ref.invalidateSelf();
  }
}

final pinnedLinesControllerProvider =
    AsyncNotifierProvider<PinnedLinesController, List<PinnedLine>>(
      PinnedLinesController.new,
    );

/// Custom display names keyed by `stop:<id>` / `line:<number>` / `route:<id>`.
class CustomNamesController extends AsyncNotifier<Map<String, String>> {
  @override
  Future<Map<String, String>> build() {
    return ref.watch(pinnedFavoritesRepositoryProvider).getCustomNames();
  }

  Future<void> setName(String key, String? name) async {
    await ref.read(pinnedFavoritesRepositoryProvider).setCustomName(key, name);
    ref.invalidateSelf();
  }
}

final customNamesControllerProvider =
    AsyncNotifierProvider<CustomNamesController, Map<String, String>>(
      CustomNamesController.new,
    );

class IdeasController extends AsyncNotifier<List<Idea>> {
  @override
  Future<List<Idea>> build() {
    return ref.watch(ideasRepositoryProvider).list();
  }

  Future<void> submit(String text) async {
    await ref.read(ideasRepositoryProvider).submit(text);
    ref.invalidateSelf();
  }

  Future<void> toggleVote(int ideaId) async {
    final repo = ref.read(ideasRepositoryProvider);
    final result = await repo.toggleVote(ideaId);
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData([
      for (final idea in current)
        if (idea.id == ideaId) idea.copyWith(votes: result.votes, hasVoted: result.hasVoted) else idea,
    ]);
  }
}

final ideasControllerProvider = AsyncNotifierProvider<IdeasController, List<Idea>>(IdeasController.new);

final ideaCommentsProvider = FutureProvider.family.autoDispose<List<IdeaComment>, int>((ref, ideaId) {
  return ref.watch(ideasRepositoryProvider).listComments(ideaId);
});
