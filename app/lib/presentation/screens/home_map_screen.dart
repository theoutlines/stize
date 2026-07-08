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

/// The app's home screen: a full-screen map (like a navigator app) with a
/// floating universal-search bar on top, nearby/favorite stops shown as
/// markers directly on the map rather than as a separate list.
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

  ll.LatLng? _myPosition;
  List<Stop> _nearbyStops = [];

  bool _searching = false;
  List<Stop> _resultStops = [];
  List<LineInfo> _resultLines = [];
  List<GeocodeResult> _resultPlaces = [];

  ll.LatLng? _pinnedPlace;
  String? _pinnedPlaceLabel;

  @override
  void initState() {
    super.initState();
    _loadMyLocation();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _loadMyLocation() async {
    try {
      final position = await ref.read(locationServiceProvider).getCurrentPosition();
      final point = ll.LatLng(position.latitude, position.longitude);
      final stops = await ref.read(stopsRepositoryProvider).nearby(lat: point.latitude, lon: point.longitude);
      if (!mounted) return;
      setState(() {
        _myPosition = point;
        _nearbyStops = stops;
      });
      _mapController.move(point, 15);
    } on LocationUnavailable {
      // Soft fallback: stay on the default city-wide view, manual search still works.
    } catch (_) {
      // Same soft fallback for any other failure.
    }
  }

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
    final stops = await ref.read(stopsRepositoryProvider).nearby(lat: place.lat, lon: place.lon);
    if (!mounted) return;
    _clearSearch();
    setState(() {
      _pinnedPlace = center;
      _pinnedPlaceLabel = place.displayName;
      _nearbyStops = stops;
    });
    _mapController.move(center, 16);
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
            options: MapOptions(initialCenter: _myPosition ?? _belgradeCenter, initialZoom: _myPosition != null ? 15 : 12),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.theoutlines.stigla',
              ),
              MarkerLayer(
                markers: [
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
                  if (_pinnedPlace != null)
                    Marker(
                      point: _pinnedPlace!,
                      width: 40,
                      height: 40,
                      child: const Icon(Icons.place, color: Colors.redAccent, size: 36),
                    ),
                  for (final stop in _nearbyStops)
                    _stopMarker(context, stop, isFavorite: favoriteIds.contains(stop.stopId)),
                  for (final stop in _resultStops)
                    if (!_nearbyStops.any((s) => s.stopId == stop.stopId))
                      _stopMarker(context, stop, isFavorite: favoriteIds.contains(stop.stopId)),
                  for (final fav in favoriteStops)
                    if (!_nearbyStops.any((s) => s.stopId == fav.stopId) &&
                        !_resultStops.any((s) => s.stopId == fav.stopId))
                      _stopMarker(context, fav, isFavorite: true),
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
