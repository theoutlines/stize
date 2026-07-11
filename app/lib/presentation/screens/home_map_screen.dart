import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:maplibre/maplibre.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../../core/map_style.dart';
import '../../core/map_support.dart';
import '../../core/route_path.dart';
import '../../core/vehicle_track_animator.dart';
import '../../data/location/location_service.dart';
import '../../domain/models/geocode_result.dart';
import '../../domain/models/line_info.dart';
import '../../domain/models/pinned_line.dart';
import '../../domain/models/stop.dart';
import '../../domain/models/vehicle_type.dart';
import '../../l10n/app_localizations.dart';
import '../providers/providers.dart';
import '../widgets/favorites_carousel.dart';
import '../widgets/stop_sheet.dart';
import '../widgets/vehicle_icon.dart';
import 'map_screen_args.dart';

const _belgradeCenter = Geographic(lon: 20.4612, lat: 44.8125);
const _distance = ll.Distance();

// Load stops for the viewport from this zoom up; below it the map is a clean
// overview. Between here and [_individualZoom] stops are shown clustered; at or
// above it each stop gets its own pin.
const _minStopsZoom = 12.0;
const _individualZoom = 15.0;

// Live vehicles are only fetched/shown from this zoom up — below it the area is
// too big, which would both flood the map and fan the source out too widely.
// Positions refresh on this cadence (and on camera-idle). It matches the
// backend's ~30s per-stop cache: polling faster just re-reads the same cached
// positions, which the movement heuristic would misread as "stuck".
const _minVehiclesZoom = 14.0;
// At/above this zoom vehicles show as full number pills; between [_minVehiclesZoom,
// this) they render as simple coloured dots (progressive detail, B2).
const _vehicleDetailZoom = 15.5;
const _vehiclesRefreshInterval = Duration(seconds: 30);
const _vehiclesMaxRadius = 1000.0;

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

class _HomeMapScreenState extends ConsumerState<HomeMapScreen>
    with SingleTickerProviderStateMixin {
  MapController? _controller;
  ColorScheme _scheme = const ColorScheme.light();
  Brightness? _styleBrightness;
  bool _imagesReady = false;

  // Live vehicles in the viewport: eased between refreshes by the animator, so
  // markers glide instead of teleporting. Only the vehicle WidgetLayer repaints
  // per tick (via an AnimatedBuilder), not the whole map.
  late final AnimationController _vehAnim;
  final _vehAnimator = VehicleTrackAnimator();
  Timer? _vehiclesTimer;
  // The marker layer is heavy to re-lay-out (each vehicle is a platform-tracked
  // widget), so instead of rebuilding it every animation frame (~60fps) we
  // sample the eased positions on a slower cadence — smooth enough for a slow
  // vehicle, far cheaper, and it stops starving map pan/zoom gestures.
  Timer? _vehRepaintTimer;
  final ValueNotifier<double> _vehTick = ValueNotifier<double>(1);
  int _vehiclesRequestSeq = 0;
  bool _hasVehicles = false;
  ll.LatLng? _lastVehiclesCenter;

  final _searchController = TextEditingController();
  final _focusNode = FocusNode();
  Timer? _searchDebounce;

  Geographic? _myPosition;
  // A camera target that resolved (e.g. from geolocation) before the map
  // controller was ready; applied in [_onMapCreated].
  Geographic? _pendingCenter;
  double? _pendingZoom;

  // Stops loaded for the current viewport, and the derived marker features.
  List<Stop> _areaStops = [];
  ll.LatLng? _lastFetchCenter;
  double _lastFetchRadius = 0;
  int _stopsRequestSeq = 0;

  List<Feature<Point>> _clusterPts = [];
  List<Feature<Point>> _busPts = [];
  List<Feature<Point>> _tramPts = [];
  List<Feature<Point>> _trolleyPts = [];
  List<Feature<Point>> _mixedPts = [];

  // Tram rail geometry (C2), fetched once from the tram lines' GTFS shapes and
  // drawn as thin lines under everything else.
  bool _tramRailsRequested = false;
  List<List<List<double>>> _tramRails = [];

  // Per-line route geometry cache (X5): line number -> path (null = fetched but
  // unavailable). Vehicles move along these instead of teleporting.
  final Map<String, RoutePath?> _shapeCache = {};
  final Set<String> _shapeFetching = {};

  bool _searching = false;
  List<Stop> _resultStops = [];
  List<LineInfo> _resultLines = [];
  List<GeocodeResult> _resultPlaces = [];

  Geographic? _pinnedPlace;
  String? _pinnedPlaceLabel;

  // When a vehicle (or a favourite line) is tapped, its route is highlighted on
  // this same map and everything else is hidden, instead of pushing a separate
  // screen. Null = normal browsing.
  _LineFocus? _focus;

  @override
  void initState() {
    super.initState();
    _vehAnim = AnimationController(
      vsync: this,
      duration: _vehiclesRefreshInterval,
    );
    // Push the current eased position into the marker layer ~15×/s (not every
    // frame) — see [_vehTick].
    _vehRepaintTimer = Timer.periodic(const Duration(milliseconds: 66), (_) {
      if (_vehTick.value != _vehAnim.value) _vehTick.value = _vehAnim.value;
    });
    // Refresh vehicle positions on a steady cadence even if the user isn't
    // panning; the fetch itself is zoom-gated and viewport-bounded.
    _vehiclesTimer = Timer.periodic(
      _vehiclesRefreshInterval,
      (_) => _loadVehiclesForVisibleArea(force: true),
    );
    // Start locating immediately, in parallel with the map creating itself, so
    // an already-granted user is centered the moment either finishes.
    _startLocation();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _vehiclesTimer?.cancel();
    _vehRepaintTimer?.cancel();
    _vehTick.dispose();
    _vehAnim.dispose();
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // ---- Map lifecycle --------------------------------------------------------

  void _onMapCreated(MapController controller) {
    _controller = controller;
    // Apply any camera target that resolved before the map was ready.
    if (_pendingCenter != null) {
      controller.moveCamera(center: _pendingCenter!, zoom: _pendingZoom ?? 16);
      _pendingCenter = null;
      _pendingZoom = null;
    }
  }

  Future<void> _onStyleLoaded(StyleController style) async {
    await registerStigmaImages(style, _scheme);
    if (!mounted) return;
    setState(() => _imagesReady = true);
    // Show stops and live vehicles for wherever the map currently sits, even
    // before a location fix — transport shows up right away.
    _loadStopsForVisibleArea();
    _loadVehiclesForVisibleArea(force: true);
    _loadTramRails();
  }

  /// Fetches the tram lines' route shapes once and keeps them as thin rail
  /// lines on the map (C2). Best-effort per line — a missing shape just omits
  /// that route.
  Future<void> _loadTramRails() async {
    if (_tramRailsRequested) return;
    _tramRailsRequested = true;
    final repo = ref.read(linesRepositoryProvider);
    final rails = <List<List<double>>>[];
    await Future.wait([
      for (final line in tramLineNumbers)
        repo
            .getShapeByLineNumber(line)
            .then((shape) {
              if (shape.polyline.length >= 2) rails.add(shape.polyline);
            })
            .catchError((_) {}),
    ]);
    if (!mounted) return;
    setState(() => _tramRails = rails);
  }

  void _onEvent(MapEvent event) {
    if (event is MapEventCameraIdle) {
      _loadStopsForVisibleArea();
      _loadVehiclesForVisibleArea();
    } else if (event is MapEventClick) {
      _handleTap(event.point);
    }
  }

  // ---- Location -------------------------------------------------------------

  /// Locate the user and recenter on them.
  ///
  /// On entry ([requestPermission] false) we never pop the OS prompt — browsers
  /// block a geolocation request that isn't tied to a user gesture anyway — so
  /// we only auto-center when access is *already* granted (instantly via the
  /// last-known fix, then refined). The recenter button passes
  /// [requestPermission] true so the prompt fires from a real tap, and reports
  /// back if access is denied instead of failing silently.
  Future<void> _startLocation({bool requestPermission = false}) async {
    final service = ref.read(locationServiceProvider);
    if (!requestPermission && !await service.isPermissionGranted()) return;

    final cached = await service.lastKnownIfGranted();
    if (cached != null) {
      _centerOnMe(
        Geographic(lon: cached.longitude, lat: cached.latitude),
        animate: false,
      );
    }
    try {
      final fresh = await service.getCurrentPosition();
      _centerOnMe(
        Geographic(lon: fresh.longitude, lat: fresh.latitude),
        animate: cached != null,
      );
    } on LocationUnavailable catch (e) {
      if (requestPermission) _showLocationMessage(e.reason);
    } catch (_) {
      // An unclassified failure: report it as "unavailable", never as "off".
      if (requestPermission) {
        _showLocationMessage(LocationUnavailableReason.positionUnavailable);
      }
    }
  }

  /// Surface the *real* reason a fix failed, so a timeout or a momentary
  /// unavailability isn't mislabelled as "location is off / access denied" (F3a).
  void _showLocationMessage(LocationUnavailableReason reason) {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    final message = switch (reason) {
      LocationUnavailableReason.serviceDisabled => l10n.locationServicesOff,
      LocationUnavailableReason.permissionDenied ||
      LocationUnavailableReason.permissionDeniedForever => l10n.locationDenied,
      LocationUnavailableReason.timeout => l10n.locationTimeout,
      LocationUnavailableReason.positionUnavailable => l10n.locationUnavailable,
    };
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _centerOnMe(Geographic point, {required bool animate}) {
    if (!mounted) return;
    setState(() => _myPosition = point);
    final controller = _controller;
    if (controller == null) {
      _pendingCenter = point;
      _pendingZoom = 16;
    } else if (animate) {
      controller.animateCamera(center: point, zoom: 16);
    } else {
      controller.moveCamera(center: point, zoom: 16);
    }
  }

  Future<void> _recenterOnMe() async {
    // Recenter immediately on the best position we already have (instant
    // feedback), then always kick off a fresh fix that recenters again — so the
    // button reliably moves the camera to the user on every tap, and a stale
    // cached position gets corrected rather than leaving the button feeling
    // dead (X3).
    final me = _myPosition;
    if (me != null) {
      await _controller?.animateCamera(center: me, zoom: 16);
    }
    await _startLocation(requestPermission: true);
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
    final mixed = <Feature<Point>>[];

    void addIndividual(Stop s) {
      final feature = Feature<Point>(
        geometry: Point(Geographic(lon: s.lon, lat: s.lat)),
        properties: {'stopId': s.stopId, 'name': s.name},
      );
      final types = stopTypes(s);
      if (types.length > 1) {
        mixed.add(feature); // one unified marker for multi-type stops (D2)
        return;
      }
      switch (types.isEmpty ? VehicleType.bus : types.first) {
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
    _mixedPts = mixed;
  }

  Set<String> get _favoriteIds =>
      (ref.read(favoriteStopLocationsProvider).valueOrNull ?? const <Stop>[])
          .map((s) => s.stopId)
          .toSet();

  // ---- Live vehicles in the viewport ---------------------------------------

  /// Loads vehicles for the viewport. [force] bypasses the "viewport hasn't
  /// moved" guard — used by the periodic timer (to refresh positions in place)
  /// and the first load; camera-idle events pass it false so merely re-emitted
  /// idles don't hammer the source.
  Future<void> _loadVehiclesForVisibleArea({bool force = false}) async {
    final controller = _controller;
    if (controller == null || !mounted) return;
    final camera = controller.getCamera();
    // Zoom-gated: clear vehicles when zoomed too far out (declutter + spare the
    // source a wide fan-out).
    if (camera.zoom < _minVehiclesZoom) {
      if (_hasVehicles) {
        _vehAnimator.clear(); // hard reset — no grace period on a zoom-out
        _lastVehiclesCenter = null;
        setState(() => _hasVehicles = false);
      }
      return;
    }
    final center = ll.LatLng(camera.center.lat, camera.center.lon);
    final radius = _radiusForVisibleArea(camera).clamp(400.0, _vehiclesMaxRadius);
    if (!force && _lastVehiclesCenter != null) {
      final moved = _distance.as(ll.LengthUnit.Meter, _lastVehiclesCenter!, center);
      if (moved < radius * 0.3) return; // viewport barely changed — skip refetch
    }
    final seq = ++_vehiclesRequestSeq;
    _lastVehiclesCenter = center;
    try {
      final vehicles = await ref
          .read(vehiclesRepositoryProvider)
          .nearby(lat: center.latitude, lon: center.longitude, radiusMeters: radius);
      if (!mounted || seq != _vehiclesRequestSeq) return;
      // Make sure each visible line's route geometry is (being) fetched so the
      // animator can move markers along the road, not through buildings (X5).
      _ensureShapesFor(vehicles.map((v) => v.line));
      _vehAnimator.syncSamples([
        for (final v in vehicles)
          VehicleSample(
            key: v.key,
            position: ll.LatLng(v.lat, v.lon),
            line: v.line,
            // Classify by the well-known Belgrade tram/trolley line sets rather
            // than the feed's per-vehicle type, which mislabels some lines (e.g.
            // trolley 40/40L as a bus). Keeps moving vehicles consistent with
            // how the same line's stops are coloured.
            type: classifyLine(v.line),
            heading: v.heading,
            path: _shapeCache[v.line],
          ),
      ], _vehAnim.value);
      _vehAnim.forward(from: 0);
      // Reflect the animator's set (which may still hold briefly-missing
      // vehicles during their grace period), not just this response (X6).
      setState(() => _hasVehicles = _vehAnimator.tracks.isNotEmpty);
    } catch (_) {
      // Keep whatever is shown on a transient failure.
    }
  }

  /// Lazily fetches (once, cached) the route geometry for each given line so
  /// vehicles on it can be animated along the route. A failed lookup caches
  /// null — the vehicle then falls back to a plain straight-line ease.
  void _ensureShapesFor(Iterable<String> lines) {
    for (final line in lines.toSet()) {
      if (_shapeCache.containsKey(line) || _shapeFetching.contains(line)) {
        continue;
      }
      _shapeFetching.add(line);
      ref
          .read(linesRepositoryProvider)
          .getShapeByLineNumber(line)
          .then((shape) {
            _shapeCache[line] = RoutePath.fromLatLon(shape.polyline);
          })
          .catchError((_) {
            _shapeCache[line] = null;
          })
          .whenComplete(() => _shapeFetching.remove(line));
    }
  }

  /// Highlight a line's route on this same map (hiding the rest) instead of
  /// pushing a separate screen — driven by a vehicle tap or a favourite-line
  /// tap. Closing the focus panel restores normal browsing.
  ///
  /// The camera deliberately stays where the user left it (F2): tapping a
  /// vehicle must not yank them out to a whole-route fitBounds. The route is
  /// drawn as a highlighted layer, so panning/zooming out reveals all of it;
  /// [focusOn] (the tapped vehicle's position) only triggers a gentle pan when
  /// the vehicle sits at/off the viewport edge, never a zoom change.
  Future<void> _openVehicleLine(String line, {ll.LatLng? focusOn}) async {
    _clearSearch();
    try {
      final shape = await ref
          .read(linesRepositoryProvider)
          .getShapeByLineNumber(line);
      if (!mounted) return;
      final routeStops = shape.stops
          .map(
            (s) => Stop(
              stopId: s.stopId,
              name: s.name,
              lat: s.lat,
              lon: s.lon,
              lines: [line],
            ),
          )
          .toList();
      // Cache the geometry so the focused line's vehicles ease along the road.
      if (shape.polyline.length >= 2) {
        _shapeCache[line] = RoutePath.fromLatLon(shape.polyline);
      }
      setState(() {
        _focus = _LineFocus(
          line: line,
          type: classifyLine(line),
          origin: shape.origin,
          destination: shape.destination,
          polyline: shape.polyline,
          stops: routeStops,
        );
      });
      if (focusOn != null) _nudgeIntoView(focusOn);
      // Refresh the vehicle set so the focused line's buses show right away.
      _loadVehiclesForVisibleArea(force: true);
    } catch (_) {
      // Best-effort: a failed shape lookup just doesn't open the route.
    }
  }

  /// Gently pan the camera (keeping the current zoom) so [point] is comfortably
  /// on screen, but only when it's near/off the viewport edge — a selected
  /// vehicle that's already well within view isn't moved at all (F2).
  void _nudgeIntoView(ll.LatLng point) {
    final controller = _controller;
    if (controller == null) return;
    final geo = Geographic(lon: point.longitude, lat: point.latitude);
    final size = MediaQuery.of(context).size;
    // Keep clear of the top buttons and the bottom line panel.
    const margin = 96.0;
    try {
      final screen = controller.toScreenLocation(geo);
      final inside =
          screen.dx >= margin &&
          screen.dx <= size.width - margin &&
          screen.dy >= margin &&
          screen.dy <= size.height - margin;
      if (inside) return;
    } catch (_) {
      // If the projection isn't available, fall through and recenter.
    }
    controller.animateCamera(center: geo, zoom: controller.getCamera().zoom);
  }

  void _clearFocus() {
    if (_focus == null) return;
    setState(() => _focus = null);
  }

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
    // While a line is focused, its own stops are the ones on screen.
    for (final s in _focus?.stops ?? const <Stop>[]) {
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
    // Seamless (A1): overlay the arrivals on the same map instead of pushing a
    // whole new screen with its own map.
    showStopSheet(
      context,
      stopId: stop.stopId,
      stopName: stop.name,
      // Tapping a vehicle row pans the map to it (zoom in past the dot→pill
      // threshold so its marker is visible).
      onFocusVehicle: (lat, lon) => _controller?.animateCamera(
        center: Geographic(lon: lon, lat: lat),
        zoom: 16.5,
      ),
    );
  }

  bool _isLinePinned(String line) {
    final pinned =
        ref.watch(pinnedLinesControllerProvider).valueOrNull ??
        const <PinnedLine>[];
    return pinned.any((l) => l.line == line);
  }

  void _togglePinLine(LineInfo line) {
    final notifier = ref.read(pinnedLinesControllerProvider.notifier);
    final pinned =
        ref.read(pinnedLinesControllerProvider).valueOrNull ??
        const <PinnedLine>[];
    if (pinned.any((l) => l.line == line.line)) {
      notifier.remove(line.line);
    } else {
      notifier.add(
        PinnedLine(
          line: line.line,
          vehicleType: line.vehicleType,
          origin: line.origin,
          destination: line.destination,
        ),
      );
    }
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

    return PopScope(
      // While a line is focused, Android back closes the focus overlay instead
      // of leaving the map.
      canPop: _focus == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _clearFocus();
      },
      child: Scaffold(
      body: Stack(
        children: [
          if (kMapRenderingEnabled)
            Positioned.fill(
              child: MapResizeNudge(
                child: MapLibreMap(
                  options: MapOptions(
                    initCenter: _belgradeCenter,
                    initZoom: 15,
                    // Fence the camera to the city (B1): no zooming out to a
                    // country view, no dragging far past the agglomeration.
                    minZoom: kCityMinZoom,
                    maxZoom: kCityMaxZoom,
                    maxBounds: belgradeMaxBounds,
                    initStyle: MapStyle.forBrightness(brightness),
                  ),
                  onMapCreated: _onMapCreated,
                  onStyleLoaded: _onStyleLoaded,
                  onEvent: _onEvent,
                  layers: _buildLayers(favoriteStops),
                  children: [
                    const CompactAttribution(),
                    // "My position" as a widget marker so it survives every zoom
                    // level (X2), not a cullable GL symbol.
                    if (_myPosition != null)
                      WidgetLayer(
                        markers: [
                          Marker(
                            point: _myPosition!,
                            size: MeLocationDot.markerSize,
                            child: const MeLocationDot(),
                          ),
                        ],
                      ),
                    // Live vehicles, rebuilt on the throttled tick so their eased
                    // positions update; only this subtree repaints.
                    ValueListenableBuilder<double>(
                      valueListenable: _vehTick,
                      builder: (context, t, _) => WidgetLayer(
                        markers: _vehicleMarkers(t),
                        allowInteraction: true,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            const SizedBox.expand(),
          // Round action buttons at the top: menu (left), recenter (right).
          _topButtons(theme),
          // Bottom UI: normally the search + favourites bar; while a line is
          // focused, a compact line panel with a close button instead.
          if (_focus == null)
            _bottomSearch(l10n, theme)
          else
            _focusPanel(theme),
        ],
      ),
      ),
    );
  }

  Widget _focusPanel(ThemeData theme) {
    final focus = _focus!;
    final color = vehicleColor(focus.type);
    return SafeArea(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: PointerInterceptor(
          child: Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 8,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      vehicleGlyph(focus.type, size: 16, color: Colors.white),
                      const SizedBox(width: 6),
                      Text(
                        focus.line,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '${focus.origin} → ${focus.destination}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: _clearFocus,
                  tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Zoom +/- buttons make sense only with a mouse: show them on desktop
  // browsers. On the native mobile apps and mobile web, pinch/double-tap
  // gestures handle zoom, so they'd just be clutter.
  bool get _showZoomControls {
    if (!kIsWeb) return false;
    switch (defaultTargetPlatform) {
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
        return true;
      default:
        return false;
    }
  }

  void _zoomBy(double delta) {
    final controller = _controller;
    if (controller == null) return;
    final camera = controller.getCamera();
    controller.animateCamera(
      center: camera.center,
      zoom: (camera.zoom + delta).clamp(kCityMinZoom, kCityMaxZoom),
    );
  }

  Widget _topButtons(ThemeData theme) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _roundButton(
              theme,
              icon: Icons.menu,
              tooltip: MaterialLocalizations.of(context).openAppDrawerTooltip,
              onTap: widget.onOpenDrawer,
            ),
            Column(
              children: [
                _roundButton(
                  theme,
                  icon: Icons.my_location,
                  onTap: _recenterOnMe,
                ),
                if (_showZoomControls) ...[
                  const SizedBox(height: 10),
                  _zoomControl(theme),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _zoomControl(ThemeData theme) {
    return PointerInterceptor(
      child: Material(
      color: theme.colorScheme.surface,
      elevation: 3,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(icon: const Icon(Icons.add), onPressed: () => _zoomBy(1)),
          Divider(height: 1, thickness: 1, color: theme.dividerColor),
          IconButton(
            icon: const Icon(Icons.remove),
            onPressed: () => _zoomBy(-1),
          ),
        ],
      ),
      ),
    );
  }

  Widget _roundButton(
    ThemeData theme, {
    required IconData icon,
    String? tooltip,
    VoidCallback? onTap,
  }) {
    return PointerInterceptor(
      child: Material(
        color: theme.colorScheme.surface,
        elevation: 3,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: IconButton(icon: Icon(icon), tooltip: tooltip, onPressed: onTap),
      ),
    );
  }

  List<Marker> _vehicleMarkers(double t) {
    if (!_hasVehicles) return const [];
    final zoom = _controller?.getCamera().zoom ?? 15.0;
    final compact = zoom < _vehicleDetailZoom;
    final focusLine = _focus?.line;
    final markers = <Marker>[];
    for (final entry in _vehAnimator.currentPositions(t)) {
      final key = entry.key;
      final track = _vehAnimator.trackFor(key);
      if (track == null) continue;
      // When a line is focused, show only that line's vehicles.
      if (focusLine != null && track.line != focusLine) continue;
      final pos = entry.value;
      final opacity = _vehAnimator.opacityFor(key);
      final marker = VehicleMarker(
        key: ValueKey(key),
        line: track.line,
        type: track.type,
        color: vehicleColor(track.type),
        // Heading follows the route tangent so the arrow matches the motion.
        heading: compact ? null : _vehAnimator.headingAt(key, t),
        stuck: _vehAnimator.isStuck(key),
        compact: compact,
        onTap: () => _openVehicleLine(track.line, focusOn: pos),
      );
      markers.add(
        Marker(
          point: Geographic(lon: pos.longitude, lat: pos.latitude),
          size: VehicleMarker.markerSize,
          // Isolate each pill's breathing-halo repaints from the layer.
          child: RepaintBoundary(
            child: opacity >= 1.0
                ? marker
                : Opacity(opacity: opacity, child: marker),
          ),
        ),
      );
    }
    return markers;
  }

  List<Layer> _buildLayers(List<Stop> favoriteStops) {
    if (!_imagesReady) return const [];
    final focus = _focus;
    if (focus != null) return _focusLayers(focus);
    return [
      // Tram rails, under everything (C2).
      if (_tramRails.isNotEmpty)
        PolylineLayer(
          polylines: [
            for (final poly in _tramRails)
              Feature<LineString>(
                geometry: LineString.from([
                  for (final p in poly) Geographic(lon: p[1], lat: p[0]),
                ]),
              ),
          ],
          color: tramRailColor,
          width: 2,
        ),
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
      if (_mixedPts.isNotEmpty)
        MarkerLayer(
          points: _mixedPts,
          iconImage: MapImages.mixedStop,
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
      // NB: "my position" is intentionally *not* here — it's a WidgetLayer
      // marker (see build) so it can't be culled at low zoom (X2).
    ];
  }

  /// Layers for the focused-line view: just that route (highlighted in its type
  /// colour) and its own stops — every other stop/cluster is hidden so the line
  /// reads cleanly, like tapping a vehicle in Yandex/Google transit.
  List<Layer> _focusLayers(_LineFocus focus) {
    return [
      if (focus.polyline.length >= 2)
        PolylineLayer(
          polylines: [
            Feature<LineString>(
              geometry: LineString.from([
                for (final p in focus.polyline) Geographic(lon: p[1], lat: p[0]),
              ]),
            ),
          ],
          color: vehicleColor(focus.type),
          width: 5,
        ),
      MarkerLayer(
        points: [
          for (final s in focus.stops)
            Feature<Point>(
              geometry: Point(Geographic(lon: s.lon, lat: s.lat)),
              properties: {'stopId': s.stopId, 'name': s.name},
            ),
        ],
        iconImage: MapImages.forStop(focus.type),
        iconSize: _iconSize,
        iconAllowOverlap: true,
      ),
    ];
  }

  // Widget-rendered marker images are captured at device pixel ratio, so they
  // come out larger than their logical size — scale down to taste.
  static const _iconSize = 0.5;

  Widget _bottomSearch(AppLocalizations l10n, ThemeData theme) {
    final maxResultsHeight = MediaQuery.of(context).size.height * 0.4;
    return SafeArea(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Results / pinned place sit ABOVE the bar since it's at the bottom.
              if (_searching)
                PointerInterceptor(
                  child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: maxResultsHeight),
                  child: Material(
                    elevation: 4,
                    borderRadius: BorderRadius.circular(16),
                    color: theme.colorScheme.surface,
                    clipBehavior: Clip.antiAlias,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: _searchResultsList(l10n),
                    ),
                  ),
                  ),
                )
              else if (_pinnedPlaceLabel != null)
                PointerInterceptor(
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
              if (_searching || _pinnedPlaceLabel != null)
                const SizedBox(height: 8),
              // Quick-access favourites carousel just above the search bar (P3);
              // hidden while searching and when there are no favourites.
              if (!_searching)
                FavoritesCarousel(
                  onOpenStop: _openStop,
                  onOpenLine: (line) => _openVehicleLine(line.line),
                ),
              PointerInterceptor(
                child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(28),
                color: theme.colorScheme.surface,
                child: Row(
                  children: [
                    const SizedBox(width: 16),
                    Icon(
                      Icons.search,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        focusNode: _focusNode,
                        onChanged: _onSearchChanged,
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          hintText: l10n.searchHint,
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 14,
                          ),
                        ),
                      ),
                    ),
                    if (_searching)
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: _clearSearch,
                      )
                    else
                      const SizedBox(width: 8),
                  ],
                ),
              ),
              ),
            ],
          ),
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
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text(l10n.searchNoResults, textAlign: TextAlign.center),
      );
    }
    return ListView(
      shrinkWrap: true,
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
            leading: vehicleGlyph(
              line.vehicleType,
              size: 24,
              color: vehicleColor(line.vehicleType),
            ),
            title: Text(line.line),
            subtitle: Text('${line.origin} → ${line.destination}'),
            trailing: IconButton(
              icon: Icon(
                _isLinePinned(line.line)
                    ? Icons.push_pin
                    : Icons.push_pin_outlined,
              ),
              tooltip: l10n.pinLineTooltip,
              onPressed: () => _togglePinLine(line),
            ),
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

/// A line whose route is currently highlighted on the home map (the inline
/// alternative to pushing a separate route screen).
class _LineFocus {
  const _LineFocus({
    required this.line,
    required this.type,
    required this.origin,
    required this.destination,
    required this.polyline,
    required this.stops,
  });

  final String line;
  final VehicleType type;
  final String origin;
  final String destination;
  final List<List<double>> polyline; // [[lat, lon], ...]
  final List<Stop> stops;
}
