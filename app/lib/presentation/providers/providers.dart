import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/api_config.dart';
import '../../core/fleet_matcher.dart';
import '../../core/search.dart';
import '../../core/vehicle_map_mode.dart';
import '../../data/analytics/event_logger.dart';
import '../../data/api/stigla_api_client.dart';
import '../../data/device/device_id_service.dart';
import '../../data/local/gtfs_offline_cache.dart';
import '../../data/local/settings_store.dart';
import '../../data/location/location_service.dart';
import '../../data/repositories/alerts_repository_impl.dart';
import '../../data/repositories/arrivals_repository_impl.dart';
import '../../data/repositories/favorites_repository_impl.dart';
import '../../data/repositories/geocode_repository_impl.dart';
import '../../data/repositories/feedback_repository_impl.dart';
import '../../data/repositories/ideas_repository_impl.dart';
import '../../data/repositories/jams_repository_impl.dart';
import '../../data/repositories/lines_repository_impl.dart';
import '../../data/repositories/nearby_arrivals_repository_impl.dart';
import '../../data/repositories/pinned_favorites_repository_impl.dart';
import '../../data/repositories/stops_repository_impl.dart';
import '../../data/repositories/vehicles_repository_impl.dart';
import '../../domain/models/app_config.dart';
import '../../domain/models/arrival.dart';
import '../../domain/models/favorite_stop.dart';
import '../../domain/models/feed_meta.dart';
import '../../domain/models/line_analytics.dart';
import '../../domain/models/idea.dart';
import '../../domain/models/jam.dart';
import '../../domain/models/pinned_line.dart';
import '../../domain/models/route_alert.dart';
import '../../domain/models/stop.dart';
import '../../domain/repositories/alerts_repository.dart';
import '../../domain/repositories/arrivals_repository.dart';
import '../../domain/repositories/favorites_repository.dart';
import '../../domain/repositories/pinned_favorites_repository.dart';
import '../../domain/repositories/geocode_repository.dart';
import '../../domain/repositories/feedback_repository.dart';
import '../../domain/repositories/ideas_repository.dart';
import '../../domain/repositories/jams_repository.dart';
import '../../domain/repositories/lines_repository.dart';
import '../../domain/repositories/nearby_arrivals_repository.dart';
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

/// Whether the experimental "Nearby" list is enabled for this user (remote
/// `nearby_list` flag). Defaults to false until config resolves, so the feature
/// stays hidden if config can't be reached.
final nearbyEnabledProvider = Provider<bool>(
  (ref) => ref.watch(appConfigProvider).valueOrNull?.nearbyList ?? false,
);

/// Whether the coverage-map tab is enabled for this user (remote
/// `coverage_map_show` flag). Defaults to false until config resolves.
final coverageEnabledProvider = Provider<bool>(
  (ref) => ref.watch(appConfigProvider).valueOrNull?.coverageMapShow ?? false,
);

/// Whether the main map shows the coverage heatmap overlay when zoomed out
/// (remote `coverage_on_main_map` flag). Independent of [coverageEnabledProvider].
/// Defaults to false until config resolves.
final coverageOnMainMapEnabledProvider = Provider<bool>(
  (ref) => ref.watch(appConfigProvider).valueOrNull?.coverageOnMainMap ?? false,
);

/// Whether the on-demand map feature is enabled at all (remote
/// `vehicles_on_demand` flag). Two levels: this flag gates the Settings item and
/// acts as the killswitch; [vehicleMapModeProvider] resolves the actual mode.
/// Defaults to false until config resolves, so the map keeps its current
/// behaviour if config is unreachable.
final vehiclesOnDemandEnabledProvider = Provider<bool>(
  (ref) => ref.watch(appConfigProvider).valueOrNull?.vehiclesOnDemand ?? false,
);

/// Whether the adaptive context slot is enabled for this user (remote
/// `context_panel` flag). Defaults to false until config resolves, so the app
/// keeps today's independent sheets if config can't be reached (killswitch).
final contextPanelEnabledProvider = Provider<bool>(
  (ref) => ref.watch(appConfigProvider).valueOrNull?.contextPanel ?? false,
);

/// Whether the in-app feedback form is available (remote `feedback_form` flag).
/// Defaults to false until config resolves, so the "Write to me" form stays
/// hidden if config is unreachable (matches the endpoint's killswitch).
final feedbackFormEnabledProvider = Provider<bool>(
  (ref) => ref.watch(appConfigProvider).valueOrNull?.feedbackForm ?? false,
);

/// The optional Donate URL (KV `config:donate_url`). Null ⇒ the drawer hides the
/// Donate item; a non-empty value ⇒ it appears and opens this URL.
final donateUrlProvider = Provider<String?>(
  (ref) => ref.watch(appConfigProvider).valueOrNull?.donateUrl,
);

/// Whether tram-jam detection is enabled for this user (remote
/// `jam_detection_show` flag). Defaults to false until config resolves, so the
/// client never calls /jams or draws anything unless it's explicitly on.
final jamDetectionEnabledProvider = Provider<bool>(
  (ref) => ref.watch(appConfigProvider).valueOrNull?.jamDetectionShow ?? false,
);

final jamsRepositoryProvider = Provider<JamsRepository>(
  (ref) => JamsRepositoryImpl(ref.watch(apiClientProvider)),
);

/// The current tram-jam board. Inert (empty) while the flag is off — the client
/// makes ZERO /jams calls in that case, mirroring the worker gate. Auto-refreshed
/// by the map's existing 30s tick via `ref.invalidate`, like the vehicle feed.
final jamsProvider = FutureProvider.autoDispose<JamsBoard>((ref) async {
  if (!ref.watch(jamDetectionEnabledProvider)) return JamsBoard.empty;
  // Staging-only: a `jam:sim` build/QА knob can force a synthetic jam. Off in
  // prod (isStaging false), so this is a no-op there.
  final sim = isStaging ? _jamSimLine : null;
  return ref.watch(jamsRepositoryProvider).current(sim: sim);
});

/// Staging simulation line (null = no simulation). Flipped by the debug affordance
/// so a stand can show a jam without a live one. Prod ignores it (see above).
String? _jamSimLine;
void setJamSimLine(String? line) => _jamSimLine = line;
String? get jamSimLine => _jamSimLine;

/// The map's vehicle mode: the user's Settings choice resolved against the flag
/// (see [resolveVehicleMapMode]). Changing either re-resolves this and the map
/// switches on the fly — no restart.
final vehicleMapModeProvider = Provider<VehicleMapMode>(
  (ref) => resolveVehicleMapMode(
    flagOn: ref.watch(vehiclesOnDemandEnabledProvider),
    choice: ref.watch(settingsControllerProvider).valueOrNull?.vehicleMapMode,
  ),
);


/// GTFS bundle freshness metadata (feed version + data dates), for the
/// `Route data: <date>` line in About. Null on any failure — the line is simply
/// hidden (silent fallback), never an error surface.
final feedMetaProvider = FutureProvider<FeedMeta?>((ref) async {
  try {
    final json = await ref.watch(apiClientProvider).getJson('/api/v1/gtfs-meta');
    return FeedMeta.fromJson(json);
  } catch (_) {
    return null;
  }
});

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

/// Anonymous product-analytics logger (see [EventLogger]). One instance for the
/// app's lifetime — it holds the ephemeral in-memory session id. Its gate is
/// wired to the `product_analytics` flag by [eventLoggerGateProvider].
final eventLoggerProvider = Provider<EventLogger>(
  (ref) => EventLogger(ref.watch(apiClientProvider)),
);

/// Bridges the async `product_analytics` flag onto the [EventLogger] gate: once
/// config resolves, the logger is unlocked (flag on) or silenced (flag off).
/// Watch this once near the root so the gate is set exactly once per launch.
final eventLoggerGateProvider = Provider<bool>((ref) {
  final config = ref.watch(appConfigProvider).valueOrNull;
  final enabled = config?.productAnalytics ?? false;
  if (config != null) ref.read(eventLoggerProvider).setEnabled(enabled);
  return enabled;
});

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

final feedbackRepositoryProvider = Provider<FeedbackRepository>(
  (ref) =>
      FeedbackRepositoryImpl(ref.watch(apiClientProvider), ref.watch(deviceIdServiceProvider)),
);

/// The app's version string — `Stigla <version> (<build>)` — the SINGLE source
/// reused by the drawer footer AND attached to feedback submissions (Part D#5),
/// so a future mobile client reports the same string.
final appVersionProvider = FutureProvider<String>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return 'Stigla ${info.version} (${info.buildNumber})';
});

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

final nearbyArrivalsRepositoryProvider = Provider<NearbyArrivalsRepository>(
  (ref) => NearbyArrivalsRepositoryImpl(ref.watch(apiClientProvider)),
);

final linesRepositoryProvider = Provider<LinesRepository>(
  (ref) => LinesRepositoryImpl(ref.watch(apiClientProvider), ref.watch(gtfsOfflineCacheProvider)),
);

final geocodeRepositoryProvider = Provider<GeocodeRepository>(
  (ref) => GeocodeRepositoryImpl(ref.watch(apiClientProvider)),
);

/// One shared global search for BOTH breakpoints (owner C#4): the desktop
/// persistent panel search and the mobile nearby-sheet search both fan out
/// through here to the same stop + line repositories, so the query matching /
/// ranking lives in exactly one place. (Desktop additionally fans in geocoded
/// places on its own — those are desktop-only in the nearby merge.)
final globalSearchProvider = Provider<GlobalSearch>((ref) => GlobalSearch(ref));

class GlobalSearch {
  GlobalSearch(this._ref);
  final Ref _ref;

  Future<GlobalSearchResults> run(String query) async {
    final stops = await _ref.read(stopsRepositoryProvider).search(query);
    final lines = await _ref.read(linesRepositoryProvider).search(query);
    return GlobalSearchResults(stops: stops, lines: lines);
  }
}

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

  Future<void> setVehicleMapMode(VehicleMapMode? mode) async {
    await ref.read(settingsStoreProvider).saveVehicleMapMode(mode);
    state = AsyncData(
      (state.valueOrNull ?? AppSettings.defaults).copyWith(vehicleMapMode: () => mode),
    );
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
    ref.read(eventLoggerProvider).log(Ev.favoriteAdd);
    ref.invalidateSelf();
  }

  Future<void> remove(String stopId) async {
    await ref.read(favoritesRepositoryProvider).remove(stopId);
    ref.read(eventLoggerProvider).log(Ev.favoriteRemove);
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
    ref.read(eventLoggerProvider).log(Ev.favoriteAdd);
    ref.invalidateSelf();
  }

  Future<void> remove(String line) async {
    await ref.read(pinnedFavoritesRepositoryProvider).removeLine(line);
    ref.read(eventLoggerProvider).log(Ev.favoriteRemove);
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
