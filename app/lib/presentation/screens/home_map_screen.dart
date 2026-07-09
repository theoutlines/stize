import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart' as ll;

import '../../data/location/location_service.dart';
import '../../domain/models/geocode_result.dart';
import '../../domain/models/line_info.dart';
import '../../domain/models/stop.dart';
import '../../l10n/app_localizations.dart';
import '../providers/providers.dart';
import '../widgets/vehicle_icon.dart';
import 'map_screen_args.dart';
import 'my_stops_screen.dart';

const _belgradeCenter = ll.LatLng(44.8125, 20.4612);
const _distance = ll.Distance();

// Below this zoom the whole-city view would pack hundreds of overlapping stop
// markers into an unreadable blob, so we hide them and let the user zoom in —
// the same "stops appear as you zoom" behaviour every map navigator uses.
const _minStopsZoom = 14.0;

/// The app's home screen: a full-screen map (like a navigator app) with a
/// floating universal-search bar on top. Stops are shown as markers for
/// whatever part of the map is currently visible — decoupled from geolocation,
/// so they always appear even if the user denies (or hasn't yet granted)
/// location access. On entry we also try to recenter on the user's own
/// position; after the first permission grant that happens automatically on
/// every launch.
class HomeMapScreen extends ConsumerStatefulWidget {
  const HomeMapScreen({super.key});

  @override
  ConsumerState<HomeMapScreen> createState() => _HomeMapScreenState();
}

class _HomeMapScreenState extends ConsumerState<HomeMapScreen> {
  final _mapController = MapController();
  final _searchController = TextEditingController();
  final _focusNode = FocusNode();
  Timer? _debounce;
  Timer? _mapDebounce;

  // Map-readiness: flutter_map throws if `move()` is called before the widget
  // has laid out at least once. If a camera target resolves before that, we
  // stash it here and apply it in onMapReady.
  bool _mapReady = false;
  ll.LatLng? _pendingCenter;
  double? _pendingZoom;

  ll.LatLng? _myPosition;

  // Stops currently drawn on the map, loaded for the visible area.
  List<Stop> _areaStops = [];
  ll.LatLng? _lastFetchCenter;
  double _lastFetchRadius = 0;
  int _stopsRequestSeq = 0;

  bool _searching = false;
  List<Stop> _resultStops = [];
  List<LineInfo> _resultLines = [];
  List<GeocodeResult> _resultPlaces = [];

  ll.LatLng? _pinnedPlace;
  String? _pinnedPlaceLabel;

  @override
  void initState() {
    super.initState();
    // Kick off geolocation immediately; it recenters the map once resolved.
    // Stop loading is driven separately by onMapReady / onPositionChanged.
    _loadMyLocation();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _mapDebounce?.cancel();
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // ---- Camera helpers -------------------------------------------------------

  void _centerOn(ll.LatLng point, double zoom) {
    if (_mapReady) {
      _mapController.move(point, zoom);
    } else {
      _pendingCenter = point;
      _pendingZoom = zoom;
    }
  }

  void _onMapReady() {
    _mapReady = true;
    if (_pendingCenter != null) {
      _mapController.move(_pendingCenter!, _pendingZoom ?? _mapController.camera.zoom);
      _pendingCenter = null;
      _pendingZoom = null;
    }
    // Always show stops for wherever the map first lands, even before (or
    // without) a geolocation fix.
    _loadStopsForVisibleArea();
  }

  void _onPositionChanged(MapCamera camera, bool hasGesture) {
    // Debounce: only refetch once the camera settles.
    _mapDebounce?.cancel();
    _mapDebounce = Timer(const Duration(milliseconds: 400), _loadStopsForVisibleArea);
  }

  // ---- Location -------------------------------------------------------------

  Future<void> _loadMyLocation() async {
    try {
      final position = await ref.read(locationServiceProvider).getCurrentPosition();
      final point = ll.LatLng(position.latitude, position.longitude);
      if (!mounted) return;
      setState(() => _myPosition = point);
      // Centering fires onPositionChanged, which loads the stops around the
      // new camera position — no need to fetch here as well.
      _centerOn(point, 16);
    } on LocationUnavailable {
      // Soft fallback: stay on the current/default view; stops still load via
      // the map callbacks and manual search still works.
    } catch (_) {
      // Same soft fallback for any other failure.
    }
  }

  // ---- Stops for the visible area ------------------------------------------

  void _loadStopsForVisibleArea() {
    if (!_mapReady || !mounted) return;
    if (_mapController.camera.zoom < _minStopsZoom) {
      // Zoomed too far out — clear the blob and wait for the user to zoom in.
      if (_areaStops.isNotEmpty) {
        setState(() => _areaStops = []);
        _lastFetchCenter = null;
      }
      return;
    }
    _loadStopsAround(_mapController.camera.center);
  }

  /// Radius (meters) that roughly covers the visible viewport, clamped so we
  /// never ask the backend for the whole city at once nor a uselessly tiny
  /// patch when zoomed in tight.
  double _radiusForVisibleArea() {
    try {
      final camera = _mapController.camera;
      final corner = camera.visibleBounds.northEast;
      final meters = _distance.as(ll.LengthUnit.Meter, camera.center, corner);
      return meters.clamp(400.0, 2000.0);
    } catch (_) {
      return 1000;
    }
  }

  Future<void> _loadStopsAround(ll.LatLng center) async {
    final radius = _radiusForVisibleArea();
    // Skip refetching if we've barely moved relative to the last fetch.
    if (_lastFetchCenter != null) {
      final moved = _distance.as(ll.LengthUnit.Meter, _lastFetchCenter!, center);
      if (moved < _lastFetchRadius * 0.35 && (radius - _lastFetchRadius).abs() < _lastFetchRadius * 0.5) {
        return;
      }
    }
    final seq = ++_stopsRequestSeq;
    _lastFetchCenter = center;
    _lastFetchRadius = radius;
    try {
      final stops = await ref
          .read(stopsRepositoryProvider)
          .nearby(lat: center.latitude, lon: center.longitude, radiusMeters: radius);
      if (!mounted || seq != _stopsRequestSeq) return; // a newer request won
      setState(() => _areaStops = stops);
    } catch (_) {
      // Leave whatever stops are already shown; transient failures shouldn't
      // wipe the map.
    }
  }

  // ---- Search ---------------------------------------------------------------

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    if (query.trim().isEmpty) {
      setState(() {
        _searching = false;
        _resultStops = [];
        _resultLines = [];
        _resultPlaces = [];
      });
      return;
    }
    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 300), () => _runSearch(query));
  }

  Future<void> _runSearch(String query) async {
    final stops = await ref.read(stopsRepositoryProvider).search(query);
    final lines = await ref.read(linesRepositoryProvider).search(query);
    List<GeocodeResult> places = [];
    try {
      places = await ref.read(geocodeRepositoryProvider).search(query);
    } catch (_) {
      // Geocoding is a best-effort second layer; ignore failures here.
    }
    if (!mounted) return;
    setState(() {
      _resultStops = stops;
      _resultLines = lines;
      _resultPlaces = places;
    });
  }

  void _clearSearch() {
    _searchController.clear();
    _focusNode.unfocus();
    setState(() {
      _searching = false;
      _resultStops = [];
      _resultLines = [];
      _resultPlaces = [];
    });
  }

  void _openStop(Stop stop) {
    _clearSearch();
    context.push('/stop/${stop.stopId}?name=${Uri.encodeComponent(stop.name)}');
  }

  Future<void> _openLine(LineInfo line) async {
    final shape = await ref.read(linesRepositoryProvider).getShapeByLineNumber(line.line);
    if (!mounted) return;
    _clearSearch();
    final routeStops = shape.stops
        .map((s) => Stop(stopId: s.stopId, name: s.name, lat: s.lat, lon: s.lon, lines: [line.line]))
        .toList();
    context.push(
      '/map',
      extra: MapScreenArgs(
        stops: routeStops,
        polyline: shape.polyline,
        title: '${line.line}: ${shape.origin} → ${shape.destination}',
        lineNumber: line.line,
      ),
    );
  }

  Future<void> _openPlace(GeocodeResult place) async {
    final center = ll.LatLng(place.lat, place.lon);
    if (!mounted) return;
    _clearSearch();
    setState(() {
      _pinnedPlace = center;
      _pinnedPlaceLabel = place.displayName;
    });
    // Centering fires onPositionChanged, which loads the stops there.
    _centerOn(center, 16);
  }

  void _openFavorites() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MyStopsScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final favoriteStops = ref.watch(favoriteStopLocationsProvider).valueOrNull ?? const <Stop>[];
    final favoriteIds = favoriteStops.map((f) => f.stopId).toSet();

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _belgradeCenter,
              initialZoom: 14,
              minZoom: 10,
              maxZoom: 18,
              onMapReady: _onMapReady,
              onPositionChanged: _onPositionChanged,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.theoutlines.stigla',
              ),
              MarkerLayer(
                markers: [
                  for (final stop in _areaStops)
                    _stopMarker(context, stop, isFavorite: favoriteIds.contains(stop.stopId)),
                  for (final stop in _resultStops)
                    if (!_areaStops.any((s) => s.stopId == stop.stopId))
                      _stopMarker(context, stop, isFavorite: favoriteIds.contains(stop.stopId)),
                  for (final fav in favoriteStops)
                    if (!_areaStops.any((s) => s.stopId == fav.stopId) &&
                        !_resultStops.any((s) => s.stopId == fav.stopId))
                      _stopMarker(context, fav, isFavorite: true),
                  if (_pinnedPlace != null)
                    Marker(
                      point: _pinnedPlace!,
                      width: 40,
                      height: 40,
                      child: const Icon(Icons.place, color: Colors.redAccent, size: 36),
                    ),
                  if (_myPosition != null)
                    Marker(
                      point: _myPosition!,
                      width: 22,
                      height: 22,
                      child: Container(
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                        ),
                      ),
                    ),
                ],
              ),
              const SimpleAttributionWidget(source: Text('© OpenStreetMap contributors')),
            ],
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Material(
                    elevation: 4,
                    borderRadius: BorderRadius.circular(28),
                    color: theme.colorScheme.surface,
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.star_outline),
                          tooltip: l10n.navMyStops,
                          onPressed: _openFavorites,
                        ),
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            focusNode: _focusNode,
                            onChanged: _onSearchChanged,
                            decoration: InputDecoration(
                              hintText: l10n.searchHint,
                              border: InputBorder.none,
                            ),
                          ),
                        ),
                        if (_searching)
                          IconButton(icon: const Icon(Icons.close), onPressed: _clearSearch)
                        else
                          IconButton(
                            icon: const Icon(Icons.settings_outlined),
                            tooltip: l10n.settingsTitle,
                            onPressed: () => context.push('/settings'),
                          ),
                      ],
                    ),
                  ),
                  if (_searching)
                    Expanded(
                      child: Material(
                        elevation: 4,
                        borderRadius: BorderRadius.circular(16),
                        color: theme.colorScheme.surface,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: _searchResultsList(l10n),
                        ),
                      ),
                    )
                  else if (_pinnedPlaceLabel != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Material(
                        elevation: 2,
                        borderRadius: BorderRadius.circular(20),
                        color: theme.colorScheme.surface,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.place, size: 18, color: Colors.redAccent),
                              const SizedBox(width: 8),
                              Flexible(child: Text(_pinnedPlaceLabel!, overflow: TextOverflow.ellipsis)),
                              IconButton(
                                icon: const Icon(Icons.close, size: 18),
                                onPressed: () => setState(() {
                                  _pinnedPlace = null;
                                  _pinnedPlaceLabel = null;
                                }),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: _searching
          ? null
          : FloatingActionButton(
              tooltip: l10n.navMyStops,
              onPressed: _loadMyLocation,
              child: const Icon(Icons.my_location),
            ),
    );
  }

  Marker _stopMarker(BuildContext context, Stop stop, {required bool isFavorite}) {
    final theme = Theme.of(context);
    return Marker(
      point: ll.LatLng(stop.lat, stop.lon),
      width: 40,
      height: 40,
      child: GestureDetector(
        onTap: () => _openStop(stop),
        child: Tooltip(
          message: stop.name,
          child: Icon(
            isFavorite ? Icons.star : Icons.directions_bus_rounded,
            color: theme.colorScheme.primary,
            size: isFavorite ? 28 : 30,
          ),
        ),
      ),
    );
  }

  Widget _searchResultsList(AppLocalizations l10n) {
    final hasResults = _resultStops.isNotEmpty || _resultLines.isNotEmpty || _resultPlaces.isNotEmpty;
    if (!hasResults) {
      return Center(child: Text(l10n.searchNoResults));
    }
    return ListView(
      children: [
        for (final stop in _resultStops)
          ListTile(
            leading: const Icon(Icons.location_on_outlined),
            title: Text(stop.name),
            subtitle: Text(stop.lines.join(', ')),
            onTap: () => _openStop(stop),
          ),
        for (final line in _resultLines)
          ListTile(
            leading: Icon(vehicleIconFor(line.vehicleType)),
            title: Text(line.line),
            subtitle: Text('${line.origin} → ${line.destination}'),
            trailing: const Icon(Icons.map_outlined),
            onTap: () => _openLine(line),
          ),
        for (final place in _resultPlaces)
          ListTile(
            leading: const Icon(Icons.map_outlined),
            title: Text(place.displayName),
            onTap: () => _openPlace(place),
          ),
      ],
    );
  }
}
