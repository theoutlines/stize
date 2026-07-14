import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart' as geo show Position;
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:maplibre/maplibre.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../../core/api_config.dart';
import '../../core/coverage_heatmap.dart';
import '../../core/fps_overlay.dart';
import '../../core/live_position.dart';
import '../../core/map_style.dart';
import '../../core/map_support.dart';
import '../../core/moving_object_layer.dart';
import '../../core/route_path.dart';
import '../../core/user_location_tracker.dart';
import '../../core/vehicle_track_animator.dart';
import '../../data/location/location_service.dart';
import '../../domain/models/area_vehicle.dart';
import '../../domain/models/geocode_result.dart';
import '../../domain/models/line_info.dart';
import '../../domain/models/pinned_line.dart';
import '../../domain/models/stop.dart';
import '../../domain/models/vehicle_source.dart';
import '../../domain/models/vehicle_type.dart';
import '../../l10n/app_localizations.dart';
import '../providers/providers.dart';
import '../widgets/favorites_carousel.dart';
import '../widgets/stop_sheet.dart';
import '../widgets/vehicle_icon.dart';
import 'map_screen_args.dart';

const _belgradeCenter = Geographic(lon: 20.4612, lat: 44.8125);
const _distance = ll.Distance();

// Imperative tram-rail network layer (symbol_layer mode only) — see
// _addVehicleSymbolLayers for why the rails are owned here rather than as the
// declarative PolylineLayer the widget path uses.
const _tramRailsSourceId = 'tram-rails-src';
const _tramRailsLayerId = 'tram-rails';

// Load stops for the viewport from this zoom up; below it the map is a clean
// overview. Between here and [_individualZoom] stops are shown clustered; at or
// above it each stop gets its own pin.
const _minStopsZoom = 12.0;
const _individualZoom = 15.0;

// Below this zoom the bounded (≤1 km) vehicle fetch covers only a small part of
// the visible city, so when it comes back empty we show a "zoom in" hint (F5)
// rather than a blank map. Vehicles are still fetched and shown at every zoom —
// the fetch is always bounded, so it never fans the source out wider.
// Positions refresh on a fixed 30s cadence (and on camera-idle), matched to the
// backend's ~30s per-stop cache: polling faster just re-reads the same cached
// positions, which the movement heuristic would misread as "stuck".
const _minVehiclesZoom = 14.0;
// At/above this zoom vehicles show as full number pills; below it they render as
// simple coloured dots (progressive detail, B2) — including the far-out overview.
const _vehicleDetailZoom = 15.5;
// Fixed 30s cadence, shared with the stop views, matched to the backend cache.
const _vehiclesRefreshInterval = kLiveRefreshInterval;
// Widened 1000 -> 1500 m (matched to the backend's MAX_RADIUS_METERS and the
// 18-stop fan-out) so a panned viewport has fewer patches with no live vehicles.
const _vehiclesMaxRadius = 1500.0;

// Short ease so the "my position" marker glides to each fresh GPS fix instead
// of snapping. Fixes are frequent (distance-filtered ~8 m), so this stays well
// under the typical gap between them; linear reads as constant travel speed.
const _meEaseDuration = Duration(milliseconds: 700);
// If the active screen hasn't seen a fix for this long, the position stream is
// assumed to have silently stalled (a known web / iOS-Safari quirk after the
// tab regains visibility) and is recreated. Only applies while active.
const _meStaleThreshold = Duration(seconds: 15);

/// Full-screen MapLibre + MapTiler vector map with a floating universal-search
/// bar. Stops load for the visible viewport (independent of geolocation) and
/// are clustered when zoomed out; on entry the map recenters on the user.
class HomeMapScreen extends ConsumerStatefulWidget {
  const HomeMapScreen({super.key, this.onOpenDrawer, this.active = true});

  /// Opens the app's navigation drawer (owned by the root scaffold).
  final VoidCallback? onOpenDrawer;

  /// Whether this screen is the one currently visible in the root
  /// [IndexedStack]. Both section pages stay mounted, so the map needs this to
  /// know when to pause the live location stream (don't drain the battery while
  /// the user is on Ideas).
  final bool active;

  @override
  ConsumerState<HomeMapScreen> createState() => _HomeMapScreenState();
}

class _HomeMapScreenState extends ConsumerState<HomeMapScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  MapController? _controller;
  StyleController? _style;
  ColorScheme _scheme = const ColorScheme.light();
  Brightness? _styleBrightness;
  bool _imagesReady = false;

  // Coverage heatmap overlay (feature-flagged): a passive background shown when
  // zoomed out, in place of the stop clusters. The GeoJSON is added lazily on
  // the first zoom-out past the threshold (never fetched if the user stays
  // zoomed in). See core/coverage_heatmap.dart for the shared source/style.
  bool _coverageEnabled = false; // remote flag, read in build
  bool _coverageAdded = false; // source+layer present in the current style
  bool _coverageActive = false; // hysteresis state for the mount decision

  // Live vehicles in the viewport: eased between refreshes by the animator, so
  // markers glide instead of teleporting. Only the vehicle WidgetLayer repaints
  // per tick (via an AnimatedBuilder), not the whole map.
  late final AnimationController _vehAnim;
  final _vehAnimator = VehicleTrackAnimator();
  Timer? _vehiclesTimer;
  // The marker layer is heavy to re-lay-out (each vehicle is a platform-tracked
  // widget), so instead of rebuilding it every animation frame (~60fps) we
  // sample the eased positions on a slower cadence — smooth enough for a slow
  // vehicle, far cheaper, and it stops starving map pan/zoom gestures. It runs
  // *only while the ease is actually in flight* (started when a fix brings
  // motion, stopped when it settles) so a map of stationary vehicles renders
  // zero frames instead of ticking forever (thermal fix — "idle = 0 frames").
  Timer? _vehSampler;
  // Timed mode needs a per-vsync repaint so continuous motion is actually smooth
  // (~60fps): a 66ms timer caps it at ~15fps, which reads as choppy. The ticker
  // drives the vehicle layer every frame while a plan is playing and stops the
  // instant motion ends (idle = 0). Kept alongside the coarse sampler; only one
  // runs at a time (see [_startVehDriver]).
  Ticker? _vehTicker;
  final ValueNotifier<double> _vehTick = ValueNotifier<double>(1);

  // Symbol-layer render path (remote `symbol_layer` flag): when on, moving
  // vehicles are one batched GPU symbol layer (sub-linear in count) instead of
  // per-vehicle Flutter widgets. When off — prod — the widget path below is the
  // unchanged fallback. Read in build; the two paths never render at once.
  bool _symbolLayerEnabled = false;
  bool _vehLayerAdded = false; // source + symbol layers present in this style
  // The currently-selected vehicle's tracking key (tap highlight on the symbol
  // layer via the feature's `selected` property). Null = nothing selected.
  String? _selectedVehicleKey;

  // Vehicle-arrangement state (symbol path), eased across writes so nothing
  // snaps. `_spiderfyOffset` is the applied fan offset per key (dLat,dLon, only
  // for stationary coincident vehicles); `_crossOpacity` is the eased crossing
  // dim per key (a moving vehicle overlapping another). See [_arrangeVehicles].
  final Map<String, ll.LatLng> _spiderfyOffset = {};
  final Map<String, double> _crossOpacity = {};
  // Backgrounded (tab hidden / app paused): all animation and polling stop, and
  // we remember when so the frozen span can be discounted from the "stuck"
  // heuristic on resume.
  bool _paused = false;
  DateTime? _hiddenAt;
  int _vehiclesRequestSeq = 0;
  bool _hasVehicles = false;
  ll.LatLng? _lastVehiclesCenter;
  // Last settled camera zoom, tracked so the build can show the "zoom in to see
  // transport" hint at far-out zoom when the bounded area has no vehicles (F5).
  double _currentZoom = 15;

  final _searchController = TextEditingController();
  final _focusNode = FocusNode();
  Timer? _searchDebounce;

  // ---- User's own live position --------------------------------------------
  // The marker is driven by a continuous position stream (distance-filtered,
  // not tied to the transport-polling timer). It eases toward each fresh fix
  // over [_meEaseDuration]; between fixes the ticker is idle (no repaints).
  late final AnimationController _meAnim;
  ll.LatLng? _meFrom; // where the marker eased from
  ll.LatLng? _meTo; // the latest fix (null = no marker shown)
  StreamSubscription<geo.Position>? _positionSub;
  DateTime? _subscribedAt;
  DateTime? _lastFixAt;
  // The next fix should recenter the camera on the user (initial locate / the
  // recenter button). Steady stream fixes only move the marker, never the
  // camera, so they don't fight the user's panning.
  bool _pendingRecenter = false;
  // Permission was refused/revoked this session: hide the marker, stop the
  // stream, and don't re-prompt on our own — only the recenter button (a real
  // user gesture) asks again.
  bool _locationDenied = false;
  bool _tabActive = true; // is the map the selected IndexedStack child

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

  // The last vehicle set handed to the animator, kept so a route shape that
  // finishes loading *after* a sync can be re-applied immediately (upgrading a
  // timed track from the plan-point chord fallback to the real road geometry)
  // instead of waiting for the next 30s poll. Debounced by [_shapeResyncTimer]
  // so a burst of shape loads (panning brings in many lines) coalesces into one
  // re-sync.
  List<AreaVehicle> _lastShownVehicles = const [];
  Timer? _shapeResyncTimer;

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
    WidgetsBinding.instance.addObserver(this);
    _vehAnim = AnimationController(
      vsync: this,
      duration: _vehiclesRefreshInterval,
    );
    // Stop sampling the eased positions the moment the ease has played out, so
    // an idle (all-settled) layer renders nothing until the next fix.
    _vehAnim.addStatusListener(_onVehAnimStatus);
    // Refresh vehicle positions on a steady cadence even if the user isn't
    // panning; the fetch itself is zoom-gated and viewport-bounded.
    _startVehiclesTimer();
    _tabActive = widget.active;
    _meAnim = AnimationController(vsync: this, duration: _meEaseDuration);
    // Start locating immediately, in parallel with the map creating itself, so
    // an already-granted user is centered the moment either finishes.
    _initLocation();
  }

  @override
  void didUpdateWidget(covariant HomeMapScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The user switched between the map and Ideas in the root IndexedStack:
    // pause the stream when the map is hidden, resume when it's shown again.
    if (widget.active != _tabActive) {
      _tabActive = widget.active;
      _reconcileLocationStream();
    }
  }

  bool _appResumed = true;

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _positionSub?.cancel();
    _meAnim.dispose();
    _searchDebounce?.cancel();
    _vehiclesTimer?.cancel();
    _shapeResyncTimer?.cancel();
    _stopVehSampler();
    _vehTicker?.dispose();
    _vehAnim.removeStatusListener(_onVehAnimStatus);
    _vehTick.dispose();
    _vehAnim.dispose();
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // ---- App lifecycle (thermal: zero work while hidden) ----------------------

  /// Pause every recurring cost when the tab/app goes to the background and
  /// resume on return. Browsers already throttle the animation ticker when a
  /// tab is hidden, but the position ease, the marker-layer sampler and the
  /// 30s poll are all timer-driven and would otherwise keep firing (and, on
  /// resume, mis-flag every vehicle as "stuck" for the time spent away). The
  /// user's own live-position stream is paused/resumed on the same signal.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final resumed = state == AppLifecycleState.resumed;
    if (resumed) {
      _resumeActivity();
    } else {
      _pauseActivity();
    }
    // Location stream reconcile — only on an actual resumed-state change.
    if (resumed != _appResumed) {
      _appResumed = resumed;
      _reconcileLocationStream();
    }
  }

  void _pauseActivity() {
    if (_paused) return;
    _paused = true;
    _hiddenAt = DateTime.now();
    _vehAnim.stop();
    _stopVehSampler();
    _vehiclesTimer?.cancel();
    _vehiclesTimer = null;
  }

  void _resumeActivity() {
    if (!_paused) return;
    _paused = false;
    final hiddenAt = _hiddenAt;
    if (hiddenAt != null) {
      // Discount the time spent hidden so a vehicle isn't declared stuck just
      // because the app was in the background across its dwell.
      _vehAnimator.shiftClock(DateTime.now().difference(hiddenAt));
      _hiddenAt = null;
    }
    _startVehiclesTimer();
    _loadVehiclesForVisibleArea(force: true);
  }

  void _startVehiclesTimer() {
    _vehiclesTimer?.cancel();
    _vehiclesTimer = Timer.periodic(
      _vehiclesRefreshInterval,
      (_) => _loadVehiclesForVisibleArea(force: true),
    );
  }

  // ---- Vehicle-layer driver (runs only while something is actually moving) --

  /// Start driving the vehicle layer's repaints.
  ///
  /// **Timed mode** uses a per-frame (vsync) [Ticker] so continuous plan-driven
  /// motion is smooth (~60fps). **Conservative mode** keeps the coarse 66ms
  /// sampler: the marker only inches toward its last fix, 15fps is plenty, and it
  /// keeps prod off a 60fps loop. Either way the driver stops the instant nothing
  /// is moving (idle = zero frames), for both render paths.
  void _startVehDriver({required bool timed}) {
    if (timed) {
      _vehSampler?.cancel();
      _vehSampler = null;
      _vehTicker ??= createTicker((_) => _pumpVehLayer());
      if (!_vehTicker!.isActive) _vehTicker!.start();
    } else {
      _vehTicker?.stop();
      _vehSampler ??=
          Timer.periodic(const Duration(milliseconds: 66), (_) => _pumpVehLayer());
    }
  }

  // One repaint step: advance any timed players by wall-clock, then either paint
  // the current positions (while motion continues) or, when nothing is moving,
  // stop the driver and settle on the final frame.
  void _pumpVehLayer() {
    _vehAnimator.advanceTimed(DateTime.now());
    if (_vehAnim.isAnimating || _vehAnimator.hasPendingMotion) {
      _paintVehicles();
    } else {
      _stopVehSampler();
      _paintVehicles();
      if (mounted) setState(() {});
    }
  }

  /// Push the current vehicle positions to whichever render path is active: the
  /// GPU symbol source (flag on) or the widget marker layer's tick (flag off).
  void _paintVehicles() {
    if (_symbolLayerEnabled) {
      _writeVehiclesToSource();
    } else if (_vehTick.value != _vehAnim.value) {
      _vehTick.value = _vehAnim.value;
    }
  }

  void _stopVehSampler() {
    _vehSampler?.cancel();
    _vehSampler = null;
    _vehTicker?.stop(); // keep the Ticker instance; dispose only in dispose()
  }

  void _onVehAnimStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed ||
        status == AnimationStatus.dismissed) {
      // The 30s ease controller finished. In timed mode the driver must keep
      // running while a plan is still playing, so only stop it when nothing is
      // moving; otherwise leave it to self-stop when the plan is exhausted.
      if (!_vehAnimator.hasPendingMotion) _stopVehSampler();
      // One final paint so the layer lands on the settled positions and the
      // markers' halos drop out of their breathing state (animate == false).
      _paintVehicles();
      if (mounted) setState(() {});
    }
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
    _style = style;
    // A fresh style (first load or after a theme flip) has none of our layers;
    // the heatmap and the vehicle symbol layers must be (re)added if they should
    // currently be visible.
    _coverageAdded = false;
    _vehLayerAdded = false;
    await registerStigmaImages(style, _scheme);
    if (_symbolLayerEnabled) {
      await registerMovingObjectImages(style);
      await _addVehicleSymbolLayers();
    }
    if (!mounted) return;
    setState(() => _imagesReady = true);
    // Show stops and live vehicles for wherever the map currently sits, even
    // before a location fix — transport shows up right away.
    _loadStopsForVisibleArea();
    _loadVehiclesForVisibleArea(force: true);
    _loadTramRails();
    _reconcileCoverageLayer();
  }

  /// Adds the moving-object GeoJSON source and its three symbol layers (badge,
  /// direction arrow, coin label). Idempotent per style load. On any failure it
  /// degrades quietly: the flag is left un-added so a later reconcile can retry,
  /// and the map simply shows no vehicle symbols rather than crashing.
  Future<void> _addVehicleSymbolLayers() async {
    final style = _style;
    if (style == null || _vehLayerAdded) return;
    _vehLayerAdded = true;
    try {
      // Tram rails FIRST, so they sit *under* the vehicle layers (infrastructure
      // beneath moving objects, C2). In symbol mode the rails are their own
      // imperative line layer rather than the declarative PolylineLayer: mixing
      // the declarative index-managed layers with our imperative ones drops the
      // rails (the reason they vanished), so we own them here directly. The
      // widget-path (flag off) keeps the declarative rails unchanged.
      await style.addSource(
        const GeoJsonSource(
          id: _tramRailsSourceId,
          data: '{"type":"FeatureCollection","features":[]}',
        ),
      );
      await style.addLayer(
        const LineStyleLayer(
          id: _tramRailsLayerId,
          sourceId: _tramRailsSourceId,
          layout: {'line-cap': 'round', 'line-join': 'round'},
          paint: {
            'line-color': '#D3342B', // tram red (matches tramRailColor)
            'line-opacity': 0.6,
            'line-width': 2.0,
          },
        ),
      );
      await style.addSource(movingObjectsSource());
      await style.addLayer(movingObjectsBadgeLayer());
      await style.addLayer(movingObjectsArrowLayer());
      await style.addLayer(movingObjectsLabelLayer());
      // Paint whatever the animator / rails cache already hold, so they show at
      // once (also covers a theme-flip re-add, where _loadTramRails won't refire).
      _writeVehiclesToSource();
      _pushTramRailsToSource();
    } catch (_) {
      _vehLayerAdded = false;
    }
  }

  /// Pushes the cached tram rail polylines into the imperative rails source
  /// (symbol mode only). No-op until the layer exists / rails have loaded.
  void _pushTramRailsToSource() {
    final style = _style;
    if (style == null || !_vehLayerAdded || _tramRails.isEmpty) return;
    final features = [
      for (final poly in _tramRails)
        {
          'type': 'Feature',
          'geometry': {
            'type': 'LineString',
            'coordinates': [
              for (final p in poly) [p[1], p[0]], // [lat,lon] -> [lon,lat]
            ],
          },
        },
    ];
    style.updateGeoJsonSource(
      id: _tramRailsSourceId,
      data: jsonEncode({'type': 'FeatureCollection', 'features': features}),
    );
  }

  /// Enable the symbol layer after the fact — when the remote flag resolves
  /// true *after* the style already loaded (config usually lands a beat later).
  /// Registers the images, then adds the source+layers. No-op if already added
  /// or the flag is off / style not ready.
  Future<void> _reconcileVehicleSymbolLayers() async {
    if (!_symbolLayerEnabled || _vehLayerAdded) return;
    final style = _style;
    if (style == null) return;
    await registerMovingObjectImages(style);
    await _addVehicleSymbolLayers();
  }

  /// Builds the typed moving-object set from the animator's current positions
  /// and pushes it to the GPU symbol source. Applies spiderfy (coincident
  /// vehicles fanned out) and the selected/focus state. No fleet id / identity
  /// is written — only what the layer draws and a tap needs to route.
  void _writeVehiclesToSource() {
    final style = _style;
    if (style == null || !_vehLayerAdded) return;
    final t = _vehAnim.value;
    final focusLine = _focus?.line;
    final objects = <MovingObject>[];
    for (final entry in _vehAnimator.currentPositions(t)) {
      final track = _vehAnimator.trackFor(entry.key);
      if (track == null) continue;
      if (focusLine != null && track.line != focusLine) continue;
      final scheduled = track.source == VehicleSource.scheduled;
      objects.add(
        MovingObject(
          key: entry.key,
          position: entry.value,
          kind: MovingObjectKind.fromVehicleType(track.type),
          label: track.line,
          heading: _vehAnimator.headingAt(entry.key, t),
          selected: entry.key == _selectedVehicleKey,
          stuck: _vehAnimator.isStuck(entry.key),
          // Fade a vanishing/stale vehicle over its grace period (X6), and dim a
          // schedule-predicted object so it reads as "by schedule, not live".
          opacity: _vehAnimator.opacityFor(entry.key) *
              (scheduled ? kScheduledBaseOpacity : 1.0),
          moving: _vehAnimator.hasMotion(entry.key),
          source: track.source,
        ),
      );
    }
    final zoom = _controller?.getCamera().zoom ?? 15.0;
    final placed = _arrangeVehicles(objects, zoom);
    // Draw scheduled objects first (underneath) so a live vehicle always sits on
    // top where the two overlap — live is the authoritative position.
    placed.sort((a, b) {
      final av = a.source == VehicleSource.scheduled ? 0 : 1;
      final bv = b.source == VehicleSource.scheduled ? 0 : 1;
      return av.compareTo(bv);
    });
    style.updateGeoJsonSource(
      id: movingObjectsSourceId,
      data: movingObjectsGeoJson(placed),
    );
  }

  /// Arranges the vehicle set for the symbol source with two distinct behaviours,
  /// per the owner's brief:
  ///
  ///  * **Stationary coincident vehicles are fanned out** (several at a stop /
  ///    terminus read as several, F4). Their positions don't move, so the fan is
  ///    stable — no hold/debounce needed.
  ///  * **Moving vehicles are never displaced.** Two that cross (oncoming lanes,
  ///    an intersection) simply **pass over each other**; the one(s) overlapping
  ///    fade slightly so the overlap reads as two, not one. No sideways jumps.
  ///
  /// Position offsets (stationary fan) and crossing opacity are both eased while a
  /// driver produces frames and snapped on a one-off write at rest, so nothing is
  /// left half-arranged and idle stays at zero frames.
  List<MovingObject> _arrangeVehicles(List<MovingObject> objects, double zoom) {
    // Far zoom shows plain dots (below the detail threshold): don't fan or
    // cross-fade there. The cell grid is coarse in metres when zoomed out, so
    // membership churns as the camera moves — that churn read as jitter on the
    // overview. Dots overlapping is fine; render true positions, state cleared.
    if (objects.isEmpty || zoom < kMovingObjectDetailZoom) {
      _spiderfyOffset.clear();
      _crossOpacity.clear();
      return objects;
    }
    final metersPerPixel =
        156543.03392 * math.cos(_belgradeCenter.lat * math.pi / 180) /
        math.pow(2, zoom);
    final radiusM = 16.0 * metersPerPixel; // fan radius, constant on screen
    final cellM = 30.0 * metersPerPixel; // ~coin size: closer than this overlaps
    final cellLat = cellM / 111320.0;
    String cellOf(ll.LatLng p) {
      final cellLon = cellM / (111320.0 * math.cos(p.latitude * math.pi / 180));
      return '${(p.latitude / cellLat).floor()}:'
          '${(p.longitude / cellLon).floor()}';
    }

    final driverRunning = (_vehTicker?.isActive ?? false) || _vehSampler != null;
    final ease = driverRunning ? 0.3 : 1.0;

    // --- Pass 1: fan out stationary coincident vehicles ---------------------
    // Group ONLY the stationary vehicles, so a moving vehicle passing through a
    // parked cluster's cell can't collapse the fan.
    final stationaryByCell = <String, List<int>>{};
    for (var i = 0; i < objects.length; i++) {
      if (objects[i].moving) continue;
      stationaryByCell.putIfAbsent(cellOf(objects[i].position), () => []).add(i);
    }
    final offsetTarget = <String, ll.LatLng>{}; // dLat,dLon per key
    for (final group in stationaryByCell.values) {
      if (group.length < 2) continue;
      group.sort((a, b) => objects[a].key.compareTo(objects[b].key));
      for (var r = 0; r < group.length; r++) {
        final o = objects[group[r]];
        final angle = 2 * math.pi * r / group.length;
        offsetTarget[o.key] = ll.LatLng(
          radiusM * math.sin(angle) / 111320.0,
          radiusM *
              math.cos(angle) /
              (111320.0 * math.cos(o.position.latitude * math.pi / 180)),
        );
      }
    }

    // Ease each key's applied offset toward its target (zero if not in a
    // stationary cluster) and compute placed positions.
    final placedPos = <ll.LatLng>[];
    for (final o in objects) {
      final target = offsetTarget[o.key] ?? const ll.LatLng(0, 0);
      final cur = _spiderfyOffset[o.key] ?? const ll.LatLng(0, 0);
      final applied = ll.LatLng(
        cur.latitude + (target.latitude - cur.latitude) * ease,
        cur.longitude + (target.longitude - cur.longitude) * ease,
      );
      if (applied.latitude.abs() < 1e-7 && applied.longitude.abs() < 1e-7) {
        _spiderfyOffset.remove(o.key);
        placedPos.add(o.position);
      } else {
        _spiderfyOffset[o.key] = applied;
        placedPos.add(ll.LatLng(
          o.position.latitude + applied.latitude,
          o.position.longitude + applied.longitude,
        ));
      }
    }

    // --- Pass 2: cross-fade moving vehicles that overlap --------------------
    // Count occupancy of each cell at the placed positions; a MOVING vehicle
    // sharing a cell with anything else is "crossing" and dims a little.
    final cellCount = <String, int>{};
    for (final p in placedPos) {
      cellCount.update(cellOf(p), (v) => v + 1, ifAbsent: () => 1);
    }
    const crossOpacity = 0.7;
    final present = <String>{};
    final result = <MovingObject>[];
    for (var i = 0; i < objects.length; i++) {
      final o = objects[i];
      present.add(o.key);
      final crossing = o.moving && (cellCount[cellOf(placedPos[i])] ?? 0) > 1;
      final targetOpacity = crossing ? crossOpacity : 1.0;
      final curOpacity = _crossOpacity[o.key] ?? 1.0;
      final appliedOpacity = curOpacity + (targetOpacity - curOpacity) * ease;
      if ((appliedOpacity - 1.0).abs() < 0.02) {
        _crossOpacity.remove(o.key);
      } else {
        _crossOpacity[o.key] = appliedOpacity;
      }
      result.add(
        MovingObject(
          key: o.key,
          position: placedPos[i],
          kind: o.kind,
          label: o.label,
          heading: o.heading,
          selected: o.selected,
          stuck: o.stuck,
          // Combine the grace/scheduled fade with the crossing dim.
          opacity: o.opacity * appliedOpacity,
          moving: o.moving,
          source: o.source,
        ),
      );
    }
    _spiderfyOffset.removeWhere((k, _) => !present.contains(k));
    _crossOpacity.removeWhere((k, _) => !present.contains(k));
    return result;
  }

  /// Adds the coverage heatmap source + layer the first time the map is zoomed
  /// out past the threshold (and re-adds it after a theme flip while it's
  /// visible). The layer is never removed once added — its zoom-driven opacity
  /// hides it when zoomed in — so this only ever mounts, guarded by hysteresis
  /// so a zoom hovering at the threshold doesn't churn. No-op when the flag is
  /// off or the style/controller isn't ready yet.
  Future<void> _reconcileCoverageLayer() async {
    if (!_coverageEnabled) return;
    final style = _style;
    final controller = _controller;
    if (style == null || controller == null) return;
    final zoom = controller.getCamera().zoom;
    _coverageActive = coverageMainHeatmapActive(
      zoom: zoom,
      wasActive: _coverageActive,
    );
    if (!_coverageActive || _coverageAdded) return;
    // Claim the slot before the first await so a burst of idle events can't
    // race two adds of the same source/layer.
    _coverageAdded = true;
    final dark = Theme.of(context).brightness == Brightness.dark;
    try {
      await style.addSource(coverageSource());
      await style.addLayer(coverageMainLayer(dark: dark));
    } catch (_) {
      // Failed (e.g. style torn down mid-add) — allow a later retry.
      _coverageAdded = false;
    }
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
    // Symbol mode draws the rails as its own imperative line layer; push the
    // freshly-loaded geometry into it. The widget path renders them declaratively
    // from _tramRails (see _buildLayers), so nothing more is needed there.
    if (_symbolLayerEnabled) _pushTramRailsToSource();
  }

  void _onEvent(MapEvent event) {
    if (event is MapEventCameraIdle) {
      _loadStopsForVisibleArea();
      _loadVehiclesForVisibleArea();
      _reconcileCoverageLayer();
    } else if (event is MapEventClick) {
      _handleTap(event.point);
    }
  }

  // ---- Location -------------------------------------------------------------

  /// On entry we never pop the OS prompt — browsers block a geolocation request
  /// that isn't tied to a user gesture anyway — so we only start locating when
  /// access is *already* granted: center instantly on the last-known fix, then
  /// let the live stream take over. The recenter button ([_recenterOnMe]) is the
  /// only place we request permission, from a real tap.
  Future<void> _initLocation() async {
    final service = ref.read(locationServiceProvider);
    if (!await service.isPermissionGranted()) return;
    // The first fix (cached or streamed) recenters the camera on the user.
    _pendingRecenter = true;
    final cached = await service.lastKnownIfGranted();
    if (cached != null && mounted) {
      _onFix(ll.LatLng(cached.latitude, cached.longitude), ease: false);
    }
    _reconcileLocationStream();
  }

  /// Applies a fresh position fix: eases the marker toward it (or snaps on the
  /// first one), records the time (feeds the staleness watchdog), and — only
  /// when a recenter was requested — moves the camera onto it.
  void _onFix(ll.LatLng point, {bool ease = true}) {
    if (!mounted) return;
    _lastFixAt = DateTime.now();
    _locationDenied = false;
    setState(() {
      if (ease && _meTo != null) {
        _meFrom = _displayedMe ?? _meTo;
        _meTo = point;
        _meAnim.forward(from: 0);
      } else {
        // First fix (or an explicit snap): no ease, jump straight there.
        _meFrom = point;
        _meTo = point;
        _meAnim.value = 1;
      }
    });
    if (_pendingRecenter) {
      _pendingRecenter = false;
      final geo = Geographic(lon: point.longitude, lat: point.latitude);
      final controller = _controller;
      if (controller == null) {
        _pendingCenter = geo;
        _pendingZoom = 16;
      } else {
        controller.moveCamera(center: geo, zoom: 16);
      }
    }
  }

  /// The marker's currently-drawn position (eased between [_meFrom] and
  /// [_meTo]); null when there's no fix to show.
  ll.LatLng? get _displayedMe {
    final to = _meTo;
    if (to == null) return null;
    return lerpLatLng(_meFrom ?? to, to, _meAnim.value);
  }

  /// Brings the position stream into line with the current lifecycle: run it
  /// only while the map is the visible tab *and* the app is foregrounded and
  /// access isn't denied; otherwise pause it. On becoming active again a stream
  /// that has silently stalled (web / iOS Safari) is recreated.
  void _reconcileLocationStream() {
    final shouldStream = _tabActive && _appResumed && !_locationDenied;
    if (!shouldStream) {
      _stopLocationStream();
      return;
    }
    if (_positionSub == null) {
      _startLocationStream();
    } else if (shouldResubscribe(
      active: true,
      lastFixAt: _lastFixAt,
      subscribedAt: _subscribedAt!,
      now: DateTime.now(),
      staleThreshold: _meStaleThreshold,
    )) {
      _startLocationStream();
    }
  }

  void _startLocationStream() {
    final service = ref.read(locationServiceProvider);
    _positionSub?.cancel();
    _subscribedAt = DateTime.now();
    _positionSub = service.positionStream().listen(
      (p) => _onFix(ll.LatLng(p.latitude, p.longitude)),
      onError: _onLocationStreamError,
      cancelOnError: false,
    );
  }

  void _stopLocationStream() {
    _positionSub?.cancel();
    _positionSub = null;
  }

  void _onLocationStreamError(Object error) {
    // Permission revoked (or services switched off) mid-stream: hide the marker
    // quietly and stop. Never re-prompt on our own — the recenter button is the
    // only place we ask again. Other errors are transient; keep listening.
    final revoked =
        error is LocationUnavailable &&
        (error.reason == LocationUnavailableReason.permissionDenied ||
            error.reason == LocationUnavailableReason.permissionDeniedForever ||
            error.reason == LocationUnavailableReason.serviceDisabled);
    if (!revoked) return;
    _stopLocationStream();
    if (!mounted) return;
    setState(() {
      _locationDenied = true;
      _meFrom = null;
      _meTo = null;
    });
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

  Future<void> _recenterOnMe() async {
    // Recenter immediately on the best position we already have (instant
    // feedback), then always kick off a fresh fix that recenters again — so the
    // button reliably moves the camera to the user on every tap, and a stale
    // cached position gets corrected rather than leaving the button feeling
    // dead (X3).
    final me = _meTo;
    if (me != null) {
      await _controller?.animateCamera(
        center: Geographic(lon: me.longitude, lat: me.latitude),
        zoom: 16,
      );
    }
    // A real user gesture — allowed to prompt. One fresh fix (also fires the OS
    // prompt on first use) gives an instant recenter; the live stream then keeps
    // the marker tracking.
    final service = ref.read(locationServiceProvider);
    try {
      final fresh = await service.getCurrentPosition();
      _locationDenied = false;
      _pendingRecenter = true;
      _onFix(ll.LatLng(fresh.latitude, fresh.longitude), ease: me != null);
      _reconcileLocationStream();
    } on LocationUnavailable catch (e) {
      _showLocationMessage(e.reason);
    } catch (_) {
      // An unclassified failure: report it as "unavailable", never as "off".
      _showLocationMessage(LocationUnavailableReason.positionUnavailable);
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
    if (_currentZoom != camera.zoom) {
      setState(() => _currentZoom = camera.zoom);
    }
    // No zoom gate on fetching (F5): the request is always bounded to ≤1 km /
    // ≤12 stops (see _vehiclesMaxRadius and the backend fan-out cap) regardless
    // of zoom, so a zoomed-out view never fans the source out wider. Keeping it
    // live means the city overview still shows the (sparse) vehicles already
    // around the viewport as dots instead of a blank map; the marker layer
    // degrades pills → dots below _vehicleDetailZoom on its own. When even the
    // bounded area is empty, a hint tells the user to zoom in (see _zoomHint).
    final center = ll.LatLng(camera.center.lat, camera.center.lon);
    final radius = _radiusForVisibleArea(camera).clamp(400.0, _vehiclesMaxRadius);
    if (!force && _lastVehiclesCenter != null) {
      final moved = _distance.as(ll.LengthUnit.Meter, _lastVehiclesCenter!, center);
      if (moved < radius * 0.3) return; // viewport barely changed — skip refetch
    }
    final seq = ++_vehiclesRequestSeq;
    _lastVehiclesCenter = center;
    try {
      final fetched = await ref
          .read(vehiclesRepositoryProvider)
          .nearby(lat: center.latitude, lon: center.longitude, radiusMeters: radius);
      if (!mounted || seq != _vehiclesRequestSeq) return;
      // Placeholder rows (junk garage `P1..P999`, GPS pinned to a stop) aren't
      // tracked vehicles — they'd sit motionless on a stop. Keep them off the
      // map when the flag is on; the arrivals *list* on the stop screen still
      // shows their line/ETA. Scheduled objects are schedule-derived by design,
      // so they bypass this junk filter. Flag off ⇒ unchanged.
      final vehicles = ref.read(livePositionOnlyProvider)
          ? fetched
              .where((v) =>
                  v.source == VehicleSource.scheduled ||
                  areaVehicleHasLivePosition(v))
              .toList()
          : fetched;
      // Hybrid live+schedule: schedule-predicted vehicles only render when the
      // `schedule_fallback` flag is on; otherwise drop them so they never enter
      // the animator. (The backend de-dups a scheduled trip that has a live
      // vehicle; the client's key-prefixing keeps the two off the same track.)
      final scheduleOn =
          ref.read(appConfigProvider).valueOrNull?.scheduleFallback ?? false;
      final shown = scheduleOn
          ? vehicles
          : [for (final v in vehicles) if (v.source == VehicleSource.live) v];
      // Which shape to move each vehicle along. With `vehicle_direction_shape`
      // on, stitch to the *direction the vehicle is actually going* (backend-
      // resolved route_id) so it doesn't ride the canonical direction's street
      // ("through houses"); off ⇒ the line's canonical shape, as before. A null
      // key (older payload) just means no path → straight-line ease (safe).
      final byDirection = ref.read(vehicleDirectionShapeProvider);
      String? shapeKeyOf(AreaVehicle v) => byDirection ? v.routeId : v.line;
      // Make sure each visible route's geometry is (being) fetched so the
      // animator can move markers along the road, not through buildings (X5) —
      // and, in timed mode, project the plan onto it.
      _ensureShapesFor(
        [for (final v in shown) shapeKeyOf(v)].whereType<String>(),
        byRouteId: byDirection,
      );
      // Timed-trajectory playback is remote-gated (OFF prod, ON staging). When
      // on, hand the animator each vehicle's forward plan + as-of time so it
      // plays them forward by time; when off, plan/as-of are null and the marker
      // eases conservatively exactly as before. Orthogonal to the render path.
      final timedOn =
          ref.read(appConfigProvider).valueOrNull?.timedTrajectory ?? false;
      _lastShownVehicles = shown;
      _vehAnimator.syncSamples(_buildVehicleSamples(shown), _vehAnim.value);
      // Drive the layer whenever a fix brings motion (foregrounded); otherwise
      // settle so a screen of stationary vehicles renders zero frames until the
      // next move. Always run the 30s ease controller here — NOT only when
      // timed is off: a vehicle whose route geometry/plan isn't available yet
      // (shape still loading, or no trajectory) falls back to the conservative
      // ease, and that ease needs the controller's t-ramp to move at all.
      // Without it such a fallback vehicle would sit pinned at its last fix and
      // jump on the next refetch. In timed mode the wall-clock ticker also runs
      // (it advances the timed players and repaints); the two coexist — the
      // ticker reads each track's live position, easing for fallback tracks,
      // wall-clock for timed ones.
      if (!_paused && _vehAnimator.hasPendingMotion) {
        _vehAnim.forward(from: 0);
        _startVehDriver(timed: timedOn);
      } else {
        _stopVehSampler();
        _vehAnim.value = 1; // land straight on the latest fixes, no per-frame ease
      }
      // Always push the fresh set to the render path right away, so newly-entered
      // vehicles appear and departed ones drop this frame (not only on the next
      // ticker tick). The symbol source is write-driven — unlike the widget path
      // it doesn't self-heal on every rebuild — so the set membership must be
      // written on every sync.
      _paintVehicles();
      // Reflect the animator's set (which may still hold briefly-missing
      // vehicles during their grace period), not just this response (X6).
      setState(() => _hasVehicles = _vehAnimator.tracks.isNotEmpty);
    } catch (_) {
      // Keep whatever is shown on a transient failure.
    }
  }

  /// Lazily fetches (once, cached) the route geometry for each given key so
  /// vehicles on it can be animated along the route. Keys are direction route_ids
  /// when [byRouteId] (fetched by route_id), else line numbers (fetched by
  /// number). A failed lookup caches null — the vehicle then falls back to a
  /// plain straight-line ease. Route_ids and line numbers don't collide, so the
  /// one cache safely holds both across a flag flip.
  void _ensureShapesFor(Iterable<String> keys, {required bool byRouteId}) {
    final repo = ref.read(linesRepositoryProvider);
    for (final key in keys.toSet()) {
      if (_shapeCache.containsKey(key) || _shapeFetching.contains(key)) {
        continue;
      }
      _shapeFetching.add(key);
      (byRouteId ? repo.getShapeByRouteId(key) : repo.getShapeByLineNumber(key))
          .then((shape) {
            final path = RoutePath.fromLatLon(shape.polyline);
            _shapeCache[key] = path;
            // The shape landed after the sync that needed it: re-apply the
            // current set so any timed track still on the plan-point chord
            // fallback upgrades to this road geometry now (~fetch latency)
            // instead of driving straight "through buildings" until the next
            // 30s poll. updatePlan re-anchors onto the new path without a jump.
            if (path != null && path.isUsable) _scheduleVehicleResync();
          })
          .catchError((_) {
            _shapeCache[key] = null;
          })
          .whenComplete(() => _shapeFetching.remove(key));
    }
  }

  /// Build the animator samples for a vehicle set from the current flags and the
  /// (possibly just-updated) shape cache. Self-contained so both the 30s poll
  /// and the shape-load re-sync produce identical samples.
  List<VehicleSample> _buildVehicleSamples(List<AreaVehicle> shown) {
    final byDirection = ref.read(vehicleDirectionShapeProvider);
    final timedOn =
        ref.read(appConfigProvider).valueOrNull?.timedTrajectory ?? false;
    String? shapeKeyOf(AreaVehicle v) => byDirection ? v.routeId : v.line;
    return [
      for (final v in shown)
        VehicleSample(
          key: v.key,
          position: ll.LatLng(v.lat, v.lon),
          line: v.line,
          // Classify by the well-known Belgrade tram/trolley line sets rather
          // than the feed's per-vehicle type, which mislabels some lines (e.g.
          // trolley 40/40L as a bus). Keeps moving vehicles consistent with how
          // the same line's stops are coloured.
          type: classifyLine(v.line),
          heading: v.heading,
          // Stitch to the direction-resolved shape when available (fixes
          // "through houses"); null key ⇒ no path ⇒ straight-line ease.
          path: shapeKeyOf(v) == null ? null : _shapeCache[shapeKeyOf(v)!],
          // A scheduled object always carries a timed plan (its predicted
          // motion); play it like a live one regardless of the timed flag.
          trajectory: (timedOn || v.source == VehicleSource.scheduled)
              ? v.trajectory
              : null,
          asOf: (timedOn || v.source == VehicleSource.scheduled) ? v.asOf : null,
          source: v.source,
        ),
    ];
  }

  /// Debounced re-sync after a route shape finishes loading (see
  /// [_ensureShapesFor]). Coalesces a burst of shape loads into one animator
  /// re-sync so a newly-fetched road geometry replaces the chord fallback
  /// promptly, without resetting the 30s ease ramp (that would nudge fallback
  /// tracks) — timed tracks upgrade their path in place via updatePlan.
  void _scheduleVehicleResync() {
    _shapeResyncTimer?.cancel();
    _shapeResyncTimer = Timer(const Duration(milliseconds: 120), () {
      if (!mounted || _lastShownVehicles.isEmpty) return;
      _vehAnimator.syncSamples(
        _buildVehicleSamples(_lastShownVehicles),
        _vehAnim.value,
      );
      if (!_paused && _vehAnimator.hasPendingMotion) {
        final timedOn =
            ref.read(appConfigProvider).valueOrNull?.timedTrajectory ?? false;
        _startVehDriver(timed: timedOn);
      }
      _paintVehicles();
    });
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
  Future<void> _openVehicleLine(
    String line, {
    ll.LatLng? focusOn,
    bool scheduled = false,
  }) async {
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
          scheduled: scheduled,
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
    if (_focus == null && _selectedVehicleKey == null) return;
    setState(() {
      _focus = null;
      _selectedVehicleKey = null;
    });
    // Drop the tap highlight on the symbol layer.
    if (_symbolLayerEnabled) _writeVehiclesToSource();
  }

  // ---- Taps -----------------------------------------------------------------

  void _handleTap(Geographic point) {
    final controller = _controller;
    if (controller == null) return;
    final screen = controller.toScreenLocation(point);
    final rect = Rect.fromCircle(center: screen, radius: 22);
    // Symbol-layer vehicles: hit-test the badge layer and open the tapped line
    // (the same bottom sheet the widget marker's onTap opens). Highlight the
    // selected vehicle via its feature `selected` flag. Widget-path vehicles
    // keep handling their own taps through the marker's onTap.
    if (_symbolLayerEnabled && _vehLayerAdded) {
      final vehicleFeatures = controller.featuresInRect(
        rect,
        layerIds: movingObjectsTapLayerIds,
      );
      for (final f in vehicleFeatures) {
        final line = f.properties['label'];
        if (line is String && line.isNotEmpty) {
          final key = f.properties['key'];
          final keyStr = key is String ? key : null;
          // Honestly mark a schedule-predicted object when its line opens.
          final scheduled = keyStr != null &&
              _vehAnimator.trackFor(keyStr)?.source == VehicleSource.scheduled;
          setState(() => _selectedVehicleKey = keyStr);
          _writeVehiclesToSource();
          _openVehicleLine(
            line,
            focusOn: ll.LatLng(point.lat, point.lon),
            scheduled: scheduled,
          );
          return;
        }
      }
    }
    final features = controller.featuresInRect(rect);
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
    // Fetch by the entry's route/direction key, not by number, so the exact
    // direction the user tapped in the results opens (F8).
    final shape = await ref
        .read(linesRepositoryProvider)
        .getShapeByRouteId(line.routeId);
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

    // Coverage overlay flag: usually flips false→true once the remote config
    // resolves. When it turns on, reconcile after this frame so the layer is
    // added if the map is already zoomed out.
    final coverageEnabled = ref.watch(coverageOnMainMapEnabledProvider);
    if (coverageEnabled != _coverageEnabled) {
      _coverageEnabled = coverageEnabled;
      if (coverageEnabled) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _reconcileCoverageLayer(),
        );
      }
    }

    // Symbol-layer render flag: usually flips false→true once config resolves.
    // When it turns on, add the source+layers after this frame (the style may
    // already be loaded). The widget vehicle layer is built only while it's off.
    final symbolEnabled = ref.watch(symbolLayerEnabledProvider);
    if (symbolEnabled != _symbolLayerEnabled) {
      _symbolLayerEnabled = symbolEnabled;
      if (symbolEnabled) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _reconcileVehicleSymbolLayers(),
        );
      }
    }

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
                    // level (X2), not a cullable GL symbol. Wrapped in an
                    // AnimatedBuilder so it eases to each fresh fix; the ticker
                    // is idle between fixes, so this only repaints while moving.
                    if (_meTo != null)
                      AnimatedBuilder(
                        animation: _meAnim,
                        builder: (context, _) {
                          final me = _displayedMe ?? _meTo!;
                          return WidgetLayer(
                            markers: [
                              Marker(
                                point: Geographic(
                                  lon: me.longitude,
                                  lat: me.latitude,
                                ),
                                size: MeLocationDot.markerSize,
                                child: const MeLocationDot(),
                              ),
                            ],
                          );
                        },
                      ),
                    // Live vehicles. With the symbol_layer flag ON they render
                    // as the batched GPU symbol layer (added imperatively in
                    // _addVehicleSymbolLayers), so no widget layer is built here.
                    // With it OFF this is the unchanged fallback: a WidgetLayer
                    // rebuilt on the throttled tick so eased positions update.
                    if (!_symbolLayerEnabled)
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
          // Far-out zoom with no vehicles in the bounded area: nudge the user to
          // zoom in rather than leaving them staring at a blank map (F5).
          if (_focus == null && _currentZoom < _minVehiclesZoom && !_hasVehicles)
            _zoomHint(l10n, theme),
          // Bottom UI: normally the search + favourites bar; while a line is
          // focused, a compact line panel with a close button instead.
          if (_focus == null)
            _bottomSearch(l10n, theme)
          else
            _focusPanel(theme),
          // On-device FPS meter — diagnostic only, off in the normal app; on a
          // staging preview the owner enables it with `?fps=1` to compare the
          // symbol layer against the widget path at different vehicle counts.
          if (fpsOverlayEnabled())
            const Positioned(
              left: 12,
              bottom: 96,
              child: SafeArea(child: FpsOverlay()),
            ),
        ],
      ),
      ),
    );
  }

  /// A small top-centered hint shown at far-out zoom when no live vehicles are
  /// in the bounded fetch area — the "zoom in to see transport" nudge (F5).
  Widget _zoomHint(AppLocalizations l10n, ThemeData theme) {
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          // Clear of the top buttons.
          padding: const EdgeInsets.only(top: 72),
          child: PointerInterceptor(
            child: Material(
              elevation: 2,
              borderRadius: BorderRadius.circular(20),
              color: theme.colorScheme.surface.withValues(alpha: 0.92),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.zoom_in,
                      size: 18,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      l10n.mapZoomInForVehicles,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ),
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${focus.origin} → ${focus.destination}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium,
                      ),
                      // A tapped schedule-predicted object honestly says so — its
                      // position is a GTFS estimate, not a live fix.
                      if (focus.scheduled)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.schedule,
                              size: 13,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                AppLocalizations.of(context).vehicleScheduled,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                    ],
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
    // Breathing halos animate only while the layer is live (a fix is easing);
    // once settled they rest, so an idle map holds at zero frames (thermal).
    final live = _vehAnim.isAnimating;

    // Collect the visible vehicles first so we can detect and spread any that
    // land on (nearly) the same spot.
    final keys = <String>[];
    final tracks = <VehicleTrack>[];
    final positions = <ll.LatLng>[];
    for (final entry in _vehAnimator.currentPositions(t)) {
      final track = _vehAnimator.trackFor(entry.key);
      if (track == null) continue;
      // When a line is focused, show only that line's vehicles.
      if (focusLine != null && track.line != focusLine) continue;
      keys.add(entry.key);
      tracks.add(track);
      positions.add(entry.value);
    }

    // Spiderfy coincident vehicles so several at one point read as several,
    // not one blob of overlapping pills and crossed arrows (F4).
    final placed = _spiderfy(positions, zoom);

    final markers = <Marker>[];
    for (var i = 0; i < keys.length; i++) {
      final key = keys[i];
      final track = tracks[i];
      final pos = placed[i];
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
        animate: live,
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

  /// Fans out markers that share (almost) the same coordinate onto a small
  /// circle so co-located vehicles are each visible, instead of being drawn on
  /// top of one another (F4). Non-coincident markers are returned unchanged.
  List<ll.LatLng> _spiderfy(List<ll.LatLng> positions, double zoom) {
    if (positions.length < 2) return positions;
    // Group by a ~1 m grid so only genuinely-coincident vehicles are spread.
    final groups = <String, List<int>>{};
    for (var i = 0; i < positions.length; i++) {
      final p = positions[i];
      final key =
          '${p.latitude.toStringAsFixed(5)}:${p.longitude.toStringAsFixed(5)}';
      groups.putIfAbsent(key, () => []).add(i);
    }
    final out = List<ll.LatLng>.of(positions);
    // Screen-space spread turned into metres at the current zoom, so the fan is
    // a constant on-screen size regardless of how far in/out the user is.
    const spreadPx = 20.0;
    final metersPerPixel =
        156543.03392 * math.cos(_belgradeCenter.lat * math.pi / 180) /
        math.pow(2, zoom);
    final radiusM = spreadPx * metersPerPixel;
    for (final idxs in groups.values) {
      if (idxs.length < 2) continue;
      for (var j = 0; j < idxs.length; j++) {
        final base = positions[idxs[j]];
        final angle = 2 * math.pi * j / idxs.length;
        final dLat = radiusM * math.sin(angle) / 111320.0;
        final dLon =
            radiusM *
            math.cos(angle) /
            (111320.0 * math.cos(base.latitude * math.pi / 180));
        out[idxs[j]] = ll.LatLng(base.latitude + dLat, base.longitude + dLon);
      }
    }
    return out;
  }

  List<Layer> _buildLayers(List<Stop> favoriteStops) {
    if (!_imagesReady) return const [];
    final focus = _focus;
    if (focus != null) return _focusLayers(focus);
    // While the coverage overlay is on, the stop clusters crossfade with the
    // heatmap over a zoom band: hidden far out (heatmap stands in for them),
    // full once zoomed in. The heatmap's own opacity is a GPU zoom expression
    // (smooth during a pinch); the markers rebuild on camera-idle, so they
    // settle to this opacity at each rest. Flag off ⇒ 1.0, unchanged behaviour.
    final zoom = _controller?.getCamera().zoom ?? 15.0;
    final stopsOpacity = _coverageEnabled
        ? coverageMainStopsOpacity(zoom)
        : 1.0;
    // Fully faded out ⇒ don't build the stop layers at all (heatmap-only view).
    final showStops = stopsOpacity > 0.01;
    return [
      // Tram rails, under everything (C2). Symbol mode owns them as an imperative
      // line layer (see _addVehicleSymbolLayers), so only the widget path draws
      // them declaratively here.
      if (!_symbolLayerEnabled && _tramRails.isNotEmpty)
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
      if (showStops && _clusterPts.isNotEmpty)
        MarkerLayer(
          points: _clusterPts,
          iconImage: MapImages.cluster,
          iconSize: _iconSize,
          iconOpacity: stopsOpacity,
          iconAllowOverlap: true,
          textField: '{point_count}',
          textColor: _scheme.onPrimary,
          textSize: 13,
          textAllowOverlap: true,
        ),
      if (showStops && _busPts.isNotEmpty)
        MarkerLayer(
          points: _busPts,
          iconImage: MapImages.bus,
          iconSize: _iconSize,
          iconOpacity: stopsOpacity,
          iconAllowOverlap: true,
        ),
      if (showStops && _tramPts.isNotEmpty)
        MarkerLayer(
          points: _tramPts,
          iconImage: MapImages.tram,
          iconSize: _iconSize,
          iconOpacity: stopsOpacity,
          iconAllowOverlap: true,
        ),
      if (showStops && _trolleyPts.isNotEmpty)
        MarkerLayer(
          points: _trolleyPts,
          iconImage: MapImages.trolley,
          iconSize: _iconSize,
          iconOpacity: stopsOpacity,
          iconAllowOverlap: true,
        ),
      if (showStops && _mixedPts.isNotEmpty)
        MarkerLayer(
          points: _mixedPts,
          iconImage: MapImages.mixedStop,
          iconSize: _iconSize,
          iconOpacity: stopsOpacity,
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
    this.scheduled = false,
  });

  final String line;
  final VehicleType type;
  final String origin;
  final String destination;
  final List<List<double>> polyline; // [[lat, lon], ...]
  final List<Stop> stops;

  /// Opened from a tap on a schedule-predicted object — the panel notes it.
  final bool scheduled;
}
