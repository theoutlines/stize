import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:maplibre/maplibre.dart';

import '../../core/map_style.dart';
import '../../core/map_support.dart';
import '../../data/location/location_service.dart';
import '../../domain/models/geocode_result.dart';
import '../../domain/models/line_info.dart';
import '../../domain/models/stop.dart';
import '../../domain/models/vehicle_type.dart';
import '../../l10n/app_localizations.dart';
import '../providers/providers.dart';
import '../widgets/vehicle_icon.dart';
import 'map_screen_args.dart';
import 'my_stops_screen.dart';

const _belgradeCenter = Geographic(lon: 20.4612, lat: 44.8125);
const _distance = ll.Distance();

// Load stops for the viewport from this zoom up; below it the map is a clean
// overview. Between here and [_individualZoom] stops are shown clustered; at or
// above it each stop gets its own pin.
const _minStopsZoom = 12.0;
const _individualZoom = 15.0;

/// Full-screen MapLibre + MapTiler vector map with a floating universal-search
/// bar. Stops load for the visible viewport (independent of geolocation) and
/// are clustered when zoomed out; on entry the map recenters on the user.
class HomeMapScreen extends ConsumerStatefulWidget {
  const HomeMapScreen({super.key, this.onOpenDrawer});

  /// Opens the app's navigation drawer (owned by the root scaffold).
  final VoidCallback? onOpenDrawer;

  @override
  ConsumerState<HomeMapScreen> createState() => _HomeMapScreenState();
}

class _HomeMapScreenState extends ConsumerState<HomeMapScreen> {
  MapController? _controller;
  ColorScheme _scheme = const ColorScheme.light();
  Brightness? _styleBrightness;
  bool _imagesReady = false;

  final _searchController = TextEditingController();
  final _focusNode = FocusNode();
  Timer? _searchDebounce;

  Geographic? _myPosition;

  // Stops loaded for the current viewport, and the derived marker features.
  List<Stop> _areaStops = [];
  ll.LatLng? _lastFetchCenter;
  double _lastFetchRadius = 0;
  int _stopsRequestSeq = 0;

  List<Feature<Point>> _clusterPts = [];
  List<Feature<Point>> _busPts = [];
  List<Feature<Point>> _tramPts = [];
  List<Feature<Point>> _trolleyPts = [];

  bool _searching = false;
  List<Stop> _resultStops = [];
  List<LineInfo> _resultLines = [];
  List<GeocodeResult> _resultPlaces = [];

  Geographic? _pinnedPlace;
  String? _pinnedPlaceLabel;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // ---- Map lifecycle --------------------------------------------------------

  void _onMapCreated(MapController controller) {
    _controller = controller;
    _loadMyLocation();
  }

  Future<void> _onStyleLoaded(StyleController style) async {
    await registerStigmaImages(style, _scheme);
    if (!mounted) return;
    setState(() => _imagesReady = true);
    // Show stops for wherever the map currently sits, even before a fix.
    _loadStopsForVisibleArea();
  }

  void _onEvent(MapEvent event) {
    if (event is MapEventCameraIdle) {
      _loadStopsForVisibleArea();
    } else if (event is MapEventClick) {
      _handleTap(event.point);
    }
  }

  // ---- Location -------------------------------------------------------------

  Future<void> _loadMyLocation() async {
    try {
      final position = await ref
          .read(locationServiceProvider)
          .getCurrentPosition();
      final point = Geographic(lon: position.longitude, lat: position.latitude);
      if (!mounted) return;
      setState(() => _myPosition = point);
      await _controller?.animateCamera(center: point, zoom: 16);
    } on LocationUnavailable {
      // Soft fallback: stay on the current view; stops still load, search works.
    } catch (_) {
      // Same soft fallback for any other failure.
    }
  }

  // ---- Stops for the visible area ------------------------------------------

  double _radiusForVisibleArea(MapCamera camera) {
    try {
      final region = _controller!.getVisibleRegion();
      final ne = ll.LatLng(region.latitudeNorth, region.longitudeEast);
      final center = ll.LatLng(camera.center.lat, camera.center.lon);
      return _distance.as(ll.LengthUnit.Meter, center, ne).clamp(400.0, 3000.0);
    } catch (_) {
      return 1200;
    }
  }

  Future<void> _loadStopsForVisibleArea() async {
    final controller = _controller;
    if (controller == null || !mounted) return;
    final camera = controller.getCamera();
    if (camera.zoom < _minStopsZoom) {
      if (_areaStops.isNotEmpty) {
        _lastFetchCenter = null;
        setState(() {
          _areaStops = [];
          _rebuildMarkerFeatures();
        });
      }
      return;
    }
    final center = ll.LatLng(camera.center.lat, camera.center.lon);
    final radius = _radiusForVisibleArea(camera);
    if (_lastFetchCenter != null) {
      final moved = _distance.as(
        ll.LengthUnit.Meter,
        _lastFetchCenter!,
        center,
      );
      if (moved < _lastFetchRadius * 0.35 &&
          (radius - _lastFetchRadius).abs() < _lastFetchRadius * 0.5) {
        // Barely moved — still recluster (zoom may have changed) but skip refetch.
        setState(_rebuildMarkerFeatures);
        return;
      }
    }
    final seq = ++_stopsRequestSeq;
    _lastFetchCenter = center;
    _lastFetchRadius = radius;
    try {
      final stops = await ref
          .read(stopsRepositoryProvider)
          .nearby(
            lat: center.latitude,
            lon: center.longitude,
            radiusMeters: radius,
          );
      if (!mounted || seq != _stopsRequestSeq) return;
      setState(() {
        _areaStops = stops;
        _rebuildMarkerFeatures();
      });
    } catch (_) {
      // Keep whatever is shown on a transient failure.
    }
  }

  /// Rebuilds the cluster/per-type marker feature lists from [_areaStops] using
  /// the current camera. Client-side screen-space grid clustering (the maplibre
  /// 0.3.x GeoJsonSource has no native clustering).
  void _rebuildMarkerFeatures() {
    final controller = _controller;
    final favoriteIds = _favoriteIds;
    final visibleStops = [
      for (final s in _areaStops)
        if (!favoriteIds.contains(s.stopId)) s,
    ];

    final clusters = <Feature<Point>>[];
    final bus = <Feature<Point>>[];
    final tram = <Feature<Point>>[];
    final trolley = <Feature<Point>>[];

    void addIndividual(Stop s) {
      final feature = Feature<Point>(
        geometry: Point(Geographic(lon: s.lon, lat: s.lat)),
        properties: {'stopId': s.stopId, 'name': s.name},
      );
      switch (stopPrimaryType(s)) {
        case VehicleType.tram:
          tram.add(feature);
        case VehicleType.trolleybus:
          trolley.add(feature);
        case VehicleType.bus:
          bus.add(feature);
      }
    }

    final zoom = controller?.getCamera().zoom ?? 14;
    if (controller == null || zoom >= _individualZoom) {
      for (final s in visibleStops) {
        addIndividual(s);
      }
    } else {
      const cell = 66.0;
      final buckets = <String, List<Stop>>{};
      for (final s in visibleStops) {
        final off = controller.toScreenLocation(
          Geographic(lon: s.lon, lat: s.lat),
        );
        final key = '${(off.dx / cell).floor()}:${(off.dy / cell).floor()}';
        buckets.putIfAbsent(key, () => []).add(s);
      }
      for (final bucket in buckets.values) {
        if (bucket.length == 1) {
          addIndividual(bucket.first);
        } else {
          var lat = 0.0, lon = 0.0;
          for (final s in bucket) {
            lat += s.lat;
            lon += s.lon;
          }
          clusters.add(
            Feature<Point>(
              geometry: Point(
                Geographic(lon: lon / bucket.length, lat: lat / bucket.length),
              ),
              properties: {'cluster': true, 'point_count': bucket.length},
            ),
          );
        }
      }
    }

    _clusterPts = clusters;
    _busPts = bus;
    _tramPts = tram;
    _trolleyPts = trolley;
  }

  Set<String> get _favoriteIds =>
      (ref.read(favoriteStopLocationsProvider).valueOrNull ?? const <Stop>[])
          .map((s) => s.stopId)
          .toSet();

  // ---- Taps -----------------------------------------------------------------

  void _handleTap(Geographic point) {
    final controller = _controller;
    if (controller == null) return;
    final screen = controller.toScreenLocation(point);
    final features = controller.featuresInRect(
      Rect.fromCircle(center: screen, radius: 22),
    );
    for (final f in features) {
      final props = f.properties;
      final stopId = props['stopId'];
      if (stopId is String) {
        final stop = _stopById(stopId);
        if (stop != null) {
          _openStop(stop);
          return;
        }
      }
      if (props['cluster'] == true) {
        final camera = controller.getCamera();
        controller.animateCamera(
          center: point,
          zoom: (camera.zoom + 2).clamp(12, 18),
        );
        return;
      }
    }
  }

  Stop? _stopById(String id) {
    for (final s in _areaStops) {
      if (s.stopId == id) return s;
    }
    final favs =
        ref.read(favoriteStopLocationsProvider).valueOrNull ?? const <Stop>[];
    for (final s in favs) {
      if (s.stopId == id) return s;
    }
    return null;
  }

  // ---- Search ---------------------------------------------------------------

  void _onSearchChanged(String query) {
    _searchDebounce?.cancel();
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
    _searchDebounce = Timer(
      const Duration(milliseconds: 300),
      () => _runSearch(query),
    );
  }

  Future<void> _runSearch(String query) async {
    final stops = await ref.read(stopsRepositoryProvider).search(query);
    final lines = await ref.read(linesRepositoryProvider).search(query);
    List<GeocodeResult> places = [];
    try {
      places = await ref.read(geocodeRepositoryProvider).search(query);
    } catch (_) {
      // Geocoding is best-effort.
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
    final shape = await ref
        .read(linesRepositoryProvider)
        .getShapeByLineNumber(line.line);
    if (!mounted) return;
    _clearSearch();
    final routeStops = shape.stops
        .map(
          (s) => Stop(
            stopId: s.stopId,
            name: s.name,
            lat: s.lat,
            lon: s.lon,
            lines: [line.line],
          ),
        )
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
    final center = Geographic(lon: place.lon, lat: place.lat);
    if (!mounted) return;
    _clearSearch();
    setState(() {
      _pinnedPlace = center;
      _pinnedPlaceLabel = place.displayName;
    });
    await _controller?.animateCamera(center: center, zoom: 16);
  }

  void _openFavorites() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const MyStopsScreen()));
  }

  Future<void> _recenterOnMe() async {
    if (_myPosition != null) {
      await _controller?.animateCamera(center: _myPosition!, zoom: 16);
    } else {
      await _loadMyLocation();
    }
  }

  // ---- Build ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    _scheme = theme.colorScheme;
    final brightness = theme.brightness;

    // Follow the app theme: swap the MapTiler style when brightness flips.
    if (_styleBrightness == null) {
      _styleBrightness = brightness;
    } else if (_styleBrightness != brightness && _controller != null) {
      _styleBrightness = brightness;
      _imagesReady = false;
      _controller!.setStyle(MapStyle.forBrightness(brightness));
    }

    final favoriteStops =
        ref.watch(favoriteStopLocationsProvider).valueOrNull ?? const <Stop>[];

    return Scaffold(
      body: Stack(
        children: [
          if (kMapRenderingEnabled)
            Positioned.fill(
              child: MapResizeNudge(
                child: MapLibreMap(
                  options: MapOptions(
                    initCenter: _belgradeCenter,
                    initZoom: 14,
                    minZoom: 10,
                    maxZoom: 18,
                    initStyle: MapStyle.forBrightness(brightness),
                  ),
                  onMapCreated: _onMapCreated,
                  onStyleLoaded: _onStyleLoaded,
                  onEvent: _onEvent,
                  layers: _buildLayers(favoriteStops),
                  children: const [SourceAttribution()],
                ),
              ),
            )
          else
            const SizedBox.expand(),
          _searchOverlay(l10n, theme),
        ],
      ),
      floatingActionButton: _searching
          ? null
          : FloatingActionButton(
              tooltip: l10n.navMyStops,
              onPressed: _recenterOnMe,
              child: const Icon(Icons.my_location),
            ),
    );
  }

  List<Layer> _buildLayers(List<Stop> favoriteStops) {
    if (!_imagesReady) return const [];
    return [
      if (_clusterPts.isNotEmpty)
        MarkerLayer(
          points: _clusterPts,
          iconImage: MapImages.cluster,
          iconSize: _iconSize,
          iconAllowOverlap: true,
          textField: '{point_count}',
          textColor: _scheme.onPrimary,
          textSize: 13,
          textAllowOverlap: true,
        ),
      if (_busPts.isNotEmpty)
        MarkerLayer(
          points: _busPts,
          iconImage: MapImages.bus,
          iconSize: _iconSize,
          iconAllowOverlap: true,
        ),
      if (_tramPts.isNotEmpty)
        MarkerLayer(
          points: _tramPts,
          iconImage: MapImages.tram,
          iconSize: _iconSize,
          iconAllowOverlap: true,
        ),
      if (_trolleyPts.isNotEmpty)
        MarkerLayer(
          points: _trolleyPts,
          iconImage: MapImages.trolley,
          iconSize: _iconSize,
          iconAllowOverlap: true,
        ),
      if (favoriteStops.isNotEmpty)
        MarkerLayer(
          points: [
            for (final s in favoriteStops)
              Feature<Point>(
                geometry: Point(Geographic(lon: s.lon, lat: s.lat)),
                properties: {'stopId': s.stopId, 'name': s.name},
              ),
          ],
          iconImage: MapImages.favorite,
          iconSize: _iconSize,
          iconAllowOverlap: true,
        ),
      if (_pinnedPlace != null)
        MarkerLayer(
          points: [Feature<Point>(geometry: Point(_pinnedPlace!))],
          iconImage: MapImages.place,
          iconSize: _iconSize,
          iconAnchor: IconAnchor.bottom,
          iconAllowOverlap: true,
        ),
      if (_myPosition != null)
        MarkerLayer(
          points: [Feature<Point>(geometry: Point(_myPosition!))],
          iconImage: MapImages.me,
          iconSize: _iconSize,
          iconAllowOverlap: true,
        ),
    ];
  }

  // Widget-rendered marker images are captured at device pixel ratio, so they
  // come out larger than their logical size — scale down to taste.
  static const _iconSize = 0.5;

  Widget _searchOverlay(AppLocalizations l10n, ThemeData theme) {
    return SafeArea(
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
                    icon: const Icon(Icons.menu),
                    tooltip: MaterialLocalizations.of(
                      context,
                    ).openAppDrawerTooltip,
                    onPressed: widget.onOpenDrawer,
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
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: _clearSearch,
                    )
                  else
                    IconButton(
                      icon: const Icon(Icons.star_outline),
                      tooltip: l10n.navMyStops,
                      onPressed: _openFavorites,
                    ),
                ],
              ),
            ),
            if (_searching)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Material(
                    elevation: 4,
                    borderRadius: BorderRadius.circular(16),
                    color: theme.colorScheme.surface,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: _searchResultsList(l10n),
                    ),
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.place,
                          size: 18,
                          color: Color(0xFFE5484D),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            _pinnedPlaceLabel!,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
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
    );
  }

  Widget _searchResultsList(AppLocalizations l10n) {
    final hasResults =
        _resultStops.isNotEmpty ||
        _resultLines.isNotEmpty ||
        _resultPlaces.isNotEmpty;
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
