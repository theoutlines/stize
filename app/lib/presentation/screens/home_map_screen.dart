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
import '../../core/follow_camera.dart';
import '../../core/fps_overlay.dart';
import '../../core/hit_test.dart';
import '../../core/map_refresh.dart';
import '../../core/nearby_focus.dart';
import '../../core/live_position.dart';
import '../../core/map_style.dart';
import '../../core/map_support.dart';
import '../../core/moving_object_layer.dart';
import '../../core/route_path.dart';
import '../../core/user_location_tracker.dart';
import '../../core/vehicle_map_mode.dart';
import '../../core/vehicle_track_animator.dart';
import '../../data/location/location_service.dart';
import '../../domain/models/area_vehicle.dart';
import '../../domain/models/arrival.dart';
import '../../domain/models/geocode_result.dart';
import '../../domain/models/line_info.dart';
import '../../domain/models/pinned_line.dart';
import '../../domain/models/nearby_arrival.dart';
import '../../domain/models/stop.dart';
import '../../domain/models/vehicle_source.dart';
import '../../domain/models/vehicle_type.dart';
import '../../l10n/app_localizations.dart';
import '../providers/providers.dart';
import '../widgets/favorites_carousel.dart';
import '../widgets/nearby_sheet.dart';
import '../widgets/stop_sheet.dart';
import '../widgets/vehicle_icon.dart';
import '../widgets/vehicle_mode_toggle.dart';
import 'map_screen_args.dart';

const _belgradeCenter = Geographic(lon: 20.4612, lat: 44.8125);
const _distance = ll.Distance();

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

  // Imperative stop layers. maplibre 0.3.5's declarative `MapLibreMap.layers`
  // reconciles the list *positionally* (`maplibre-layer-$index`) with unawaited
  // add/remove calls; when the set of stop layers changes (types coming/going by
  // area, tram rails loading async) it deterministically drops some — on prod a
  // pure-bus stop lost its whole marker layer, so it had no clickable pin. So the
  // stop layers are managed imperatively instead: added once per style load, then
  // only their GeoJSON source data changes (exactly like the coverage layer), so
  // the buggy LayerManager never touches them. Focus mode still uses the
  // declarative list (a clean, user-initiated 2-layer swap).
  bool _stopLayersAdded = false; // layers+sources present in the current style
  bool _stopLayersAdding = false; // add in flight (guards the ready flag window)
  static const _railsLayerId = 'stg-stops-rails';
  static const _clusterLayerId = 'stg-stops-cluster';
  static const _busLayerId = 'stg-stops-bus';
  static const _tramLayerId = 'stg-stops-tram';
  static const _trolleyLayerId = 'stg-stops-trolley';
  static const _mixedLayerId = 'stg-stops-mixed';
  static const _favLayerId = 'stg-stops-fav';
  static const _placeLayerId = 'stg-stops-place';
  // Focused-line view (route highlight + that line's stops). Added imperatively
  // — like the stop layers, and unlike the old declarative path — so they can be
  // inserted *below* the moving-object symbol layers (belowLayerId), keeping the
  // route from painting over the vehicle coin the user is following.
  static const _focusRouteLayerId = 'stg-focus-route';
  static const _focusStopsLayerId = 'stg-focus-stops';
  bool _focusLayersAdded = false;
  static const _emptyFeatureCollection =
      '{"type":"FeatureCollection","features":[]}';

  // Live vehicles in the viewport: eased between refreshes by the animator, so
  // markers glide instead of teleporting. Only the vehicle WidgetLayer repaints
  // per tick (via an AnimatedBuilder), not the whole map.
  late final AnimationController _vehAnim;
  final _vehAnimator = VehicleTrackAnimator();
  Timer? _vehiclesTimer;
  // A per-vsync repaint driver so continuous motion is smooth (~60fps). The
  // ticker drives the vehicle layer every frame while a plan is playing (or an
  // ease is in flight) and stops the instant motion ends, so a map of stationary
  // vehicles renders zero frames instead of ticking forever (thermal fix —
  // "idle = 0 frames"). See [_startVehDriver].
  Ticker? _vehTicker;

  // Moving vehicles render as one batched GPU symbol layer (sub-linear in count).
  bool _vehLayerAdded = false; // source + symbol layers present in this style
  bool _vehLayerAdding = false; // add in flight (so the flag flips only once real)
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

  // ---- On-demand map context (vehicles_on_demand) --------------------------
  // In on-demand mode the map draws NO background "aquarium" of vehicles; they
  // appear only in context. `_onDemand` mirrors the resolved map mode (read in
  // build): the user's Settings choice gated by the remote flag — see
  // core/vehicle_map_mode.dart.
  // Three states:
  //   A — no context: empty vehicle layer, no /vehicles/nearby fetch. Default.
  //   B — stop context (`_stopContextId` set): the tapped stop's live arrivals
  //       are the only markers, fed from the SAME arrivals provider the sheet
  //       polls (no second fan-out) and refreshed on its 30s cadence.
  //   C — vehicle context (`_following` + `_focus`): one vehicle is followed
  //       with its direction's route highlighted. Works at BOTH flag values.
  bool _onDemand = false;
  // Staging-overlay diagnostics for the on-demand context (debugPrint is stripped
  // in release web, so these surface on the on-screen diagnostics panel instead).
  int? _lastCtxBoardAgeSec; // freshness of the last context board applied
  int _lastCtxLive = 0; // live rows in it
  int _lastCtxWithTraj = 0; // how many carried a timing plan
  // Board age at the moment each poll landed, most recent last (last 12).
  //
  // This is the number that decides whether an *elastic* stop dwell is worth
  // building. The marker stops predicting once a board passes the 45 s gate, and
  // the next board is only 30 s away — so a poll that lands carrying a board
  // already older than 15 s means the marker will freeze before its relief
  // arrives, for (age + 30 − 45) seconds. Under 15 s it never freezes at all.
  // The backend caps board age at 40 s, so the whole question is where in 0..40
  // these samples actually fall — hence a short history rather than one value.
  final List<int> _boardAgePolls = [];
  int _refreshTicks = 0; // 30s refresh ticks fired
  int _pumpCount = 0; // vehicle-driver frames pumped
  // A stop arrivals sheet is currently up. The bottom UI (Nearby panel / search)
  // is hidden while it is, so the two never overlap (#7).
  bool _stopSheetOpen = false;
  String? _stopContextId; // stop feeding the markers (state B); null = not in B
  ProviderSubscription<AsyncValue<ArrivalsBoard>>? _stopArrivalsSub;
  // The stop context to restore when a vehicle context opened *from* a stop is
  // closed (return to B); null → fall back to A.
  String? _returnToStopId;

  // Follow mode: the camera pans to keep the selected vehicle screen-fixed as it
  // moves. Any manual pan/zoom gesture breaks it (the marker and highlight stay
  // — the Google Maps / Flightradar pattern). `_followEngaged` gates the
  // per-frame pan so an entry fly-to settles first; `_lastFollowMarkerPos` is
  // the marker position the last pan was measured from (delta-panning).
  // `_selfCameraMove` marks a camera move the app itself issued, so the
  // move-start it triggers isn't mistaken for a user gesture and doesn't break
  // follow (the classic self-cancelling-follow bug).
  bool _following = false;
  bool _followEngaged = false;
  ll.LatLng? _lastFollowMarkerPos;
  DateTime? _lastFollowMoveAt; // throttle for the smooth follow ease
  bool _selfCameraMove = false;
  // A brief grace window after a resume during which a camera-move event does
  // NOT break follow. Returning to a hidden tab re-lays-out the MapLibre-web
  // canvas, which surfaces a camera event flagged as a user gesture even though
  // the user did nothing — that used to silently drop follow, leaving the marker
  // to wander off-screen with the selection still live. The programmatic follow
  // pan that re-centres on the re-anchored (jumped) marker also happens inside
  // this window, so it can't be mistaken for a manual pan either.
  DateTime? _followResumeGuardUntil;
  // Where the camera sat when the vehicle context was entered, restored on close
  // so the user lands back where they came from (the stop, or the pre-focus
  // viewport) instead of adrift wherever the vehicle wandered.
  Geographic? _preFollowCenter;
  double? _preFollowZoom;
  // Where the camera sat before opening a stop sheet (which pans the stop up
  // above the sheet). Restored when the sheet closes back to browsing, so the
  // return is symmetric to the open.
  Geographic? _preStopCameraCenter;
  double? _preStopCameraZoom;

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
    _stopArrivalsSub?.close();
    _vehiclesTimer?.cancel();
    _shapeResyncTimer?.cancel();
    _stopVehDriver();
    _vehTicker?.dispose();
    _vehAnim.removeStatusListener(_onVehAnimStatus);
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
    _stopVehDriver();
    _vehiclesTimer?.cancel();
    _vehiclesTimer = null;
  }

  void _resumeActivity() {
    if (!_paused) return;
    _paused = false;
    // Hold follow across the resume: the tab-return canvas re-layout can surface
    // a spurious "gesture" camera event that would otherwise break it. Keep
    // `_lastFollowMarkerPos` untouched so the first follow tick pans by the full
    // re-anchor jump and the marker stays centred rather than sliding off.
    if (_following) {
      _followResumeGuardUntil = DateTime.now().add(const Duration(seconds: 1));
    }
    final hiddenAt = _hiddenAt;
    if (hiddenAt != null) {
      // Discount the time spent hidden so a vehicle isn't declared stuck just
      // because the app was in the background across its dwell.
      _vehAnimator.shiftClock(DateTime.now().difference(hiddenAt));
      _hiddenAt = null;
    }
    _startVehiclesTimer();
    // Refresh right away on resume (both modes): the aquarium off-demand, or the
    // active stop/vehicle context on-demand — so a vehicle isn't left on a stale
    // fix after the tab comes back. The fresh board then re-anchors the timed
    // players and the marker catches up to its real position.
    _refreshTick();
    // Restart the driver so the timed players advance the moment we're back —
    // otherwise the marker sits frozen until the refetch lands (and a stale/503
    // board would leave it frozen with no ticker running at all).
    if (_vehAnimator.tracks.isNotEmpty) {
      _startVehDriver();
      _paintVehicles();
    }
  }

  void _startVehiclesTimer() {
    _vehiclesTimer?.cancel();
    _vehiclesTimer = Timer.periodic(_vehiclesRefreshInterval, (_) => _refreshTick());
  }

  /// The steady 30s refresh, matched to the backend cache. In on-demand mode the
  /// background aquarium is off, so instead the ACTIVE context (a stop, or a
  /// followed vehicle still tied to its stop) is kept live by re-fetching that
  /// stop's arrivals — otherwise the markers play their trajectory to the end of
  /// `as_of` and freeze forever, since the sheet's own poll dies when it closes.
  /// This runs regardless of follow, so following never freezes the data. When
  /// off-demand it drives the viewport aquarium exactly as before.
  void _refreshTick() {
    final action = mapRefreshAction(onDemand: _onDemand, stopContextId: _stopContextId);
    _refreshTicks++;
    switch (action) {
      case MapRefresh.aquarium:
        _loadVehiclesForVisibleArea(force: true);
      case MapRefresh.pollStop:
        ref.invalidate(arrivalsProvider(_stopContextId!));
      case MapRefresh.none:
        break;
    }
  }

  // ---- Vehicle-layer driver (runs only while something is actually moving) --

  /// Start driving the vehicle layer's repaints.
  ///
  /// **Timed mode** uses a per-frame (vsync) [Ticker] so continuous plan-driven
  /// motion is smooth (~60fps). **Conservative mode** keeps the coarse 66ms
  /// sampler: the marker only inches toward its last fix, 15fps is plenty, and it
  /// keeps prod off a 60fps loop. Either way the driver stops the instant nothing
  /// is moving (idle = zero frames), for both render paths.
  void _startVehDriver() {
    _vehTicker ??= createTicker((_) => _pumpVehLayer());
    if (!_vehTicker!.isActive) _vehTicker!.start();
  }

  // One repaint step: advance any timed players by wall-clock, then either paint
  // the current positions (while motion continues) or, when nothing is moving,
  // stop the driver and settle on the final frame.
  void _pumpVehLayer() {
    _vehAnimator.advanceTimed(DateTime.now());
    _pumpCount++;
    if (_vehAnim.isAnimating || _vehAnimator.hasPendingMotion) {
      _paintVehicles();
    } else {
      _stopVehDriver();
      _paintVehicles();
      if (mounted) setState(() {});
    }
  }

  /// Push the current vehicle positions to the GPU symbol source.
  void _paintVehicles() {
    _writeVehiclesToSource();
  }

  void _stopVehDriver() {
    _vehTicker?.stop(); // keep the Ticker instance; dispose only in dispose()
  }

  void _onVehAnimStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed ||
        status == AnimationStatus.dismissed) {
      // The 30s ease controller finished. In timed mode the driver must keep
      // running while a plan is still playing, so only stop it when nothing is
      // moving; otherwise leave it to self-stop when the plan is exhausted.
      if (!_vehAnimator.hasPendingMotion) _stopVehDriver();
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
    // the stop layers, heatmap and vehicle symbol layers must be (re)added.
    _coverageAdded = false;
    _stopLayersAdded = false;
    _vehLayerAdded = false;
    _focusLayersAdded = false;
    await registerStigmaImages(style, _scheme);
    if (!mounted) return;
    // Stops FIRST so they sit *under* the vehicle symbols added next — moving
    // objects belong above the stop/rail infrastructure (C2). Rails are the
    // lowest of the stop layers (see _addStopLayers).
    await _addStopLayers(style);
    await registerMovingObjectImages(style);
    await _addVehicleSymbolLayers();
    if (!mounted) return;
    setState(() => _imagesReady = true);
    // Show stops and live vehicles for wherever the map currently sits, even
    // before a location fix — transport shows up right away. Re-push any data
    // already in hand (e.g. tram rails, area stops) onto the fresh sources.
    _pushStopSources();
    // Re-add the focused-line layers (below the vehicle symbols) if a line is
    // focused across this style (re)load — e.g. a theme flip mid-follow.
    if (_focus != null) _syncFocusLayers();
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
    if (style == null || _vehLayerAdded || _vehLayerAdding) return;
    _vehLayerAdding = true;
    try {
      // Vehicle symbols sit above the stop/rail layers (added earlier in
      // _onStyleLoaded). Tram rails are handled by the imperative stop layers
      // (stg-stops-rails) in both modes, not here.
      await style.addSource(movingObjectsSource());
      await style.addLayer(movingObjectsBadgeLayer());
      await style.addLayer(movingObjectsArrowLayer());
      await style.addLayer(movingObjectsLabelLayer());
      // Flip the "added" flag only now that the badge really exists, so a focus
      // that lands mid-add doesn't ask to insert *below a badge that isn't there
      // yet* (belowLayerId → maplibre throws → the route silently vanishes). Until
      // then focusInsertBelowLayerId returns null and the route goes on top
      // (visible), then the re-sync below drops it under the badge.
      _vehLayerAdded = true;
      // Paint whatever the animator already holds, so vehicles show at once
      // (also covers a theme-flip re-add).
      _writeVehiclesToSource();
      // If a line was focused before the vehicle layers came up, re-place its
      // route now that there's a badge to sit under.
      if (_focus != null) _syncFocusLayers();
    } catch (_) {
      _vehLayerAdded = false;
    } finally {
      _vehLayerAdding = false;
    }
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
    // Follow mode: keep the selected vehicle in view as its marker moves. Runs
    // on the same cadence as the layer repaint so the camera tracks smoothly.
    if (_following) _followTick();
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

    // Overlap thresholds, in screen pixels so they mean the same at any zoom —
    // and hysteretic. With one threshold, a pair sitting right at it fans out,
    // collapses, fans out again. So a fan only *forms* on a strong overlap
    // ([enterM], markers clearly on top of each other) and only *collapses*
    // once they are comfortably apart ([exitM]); in between, whatever the fan is
    // already doing wins.
    final enterM = 24.0 * metersPerPixel;
    final exitM = 40.0 * metersPerPixel;
    String cellOf(ll.LatLng p, double m) {
      final lat = m / 111320.0;
      final lon = m / (111320.0 * math.cos(p.latitude * math.pi / 180));
      return '${(p.latitude / lat).floor()}:${(p.longitude / lon).floor()}';
    }

    final driverRunning = _vehTicker?.isActive ?? false;
    final ease = driverRunning ? 0.3 : 1.0;

    // --- Pass 1: fan out stationary coincident vehicles ---------------------
    // Consider ONLY the stationary ones, so a moving vehicle passing through a
    // parked cluster's cell can't collapse the fan. `moving` counts a stop dwell
    // as motion (TimedTrajectory.isPlaying): a bus pausing three seconds is
    // mid-journey, and fanning it out on arrival only to snap it back as it
    // pulls away would be a shove at every stop.
    final crowdedEnter = <String, int>{};
    final byExitCell = <String, List<int>>{};
    for (var i = 0; i < objects.length; i++) {
      if (objects[i].moving) continue;
      final p = objects[i].position;
      crowdedEnter.update(cellOf(p, enterM), (v) => v + 1, ifAbsent: () => 1);
      byExitCell.putIfAbsent(cellOf(p, exitM), () => []).add(i);
    }
    final offsetTarget = <String, ll.LatLng>{}; // dLat,dLon per key
    for (final group in byExitCell.values) {
      // Who in this loose group actually earns a fan: anyone strongly overlapped
      // right now, plus anyone already fanned (that's the hysteresis — they hold
      // their place until the whole group thins out).
      final members = [
        for (final i in group)
          if ((crowdedEnter[cellOf(objects[i].position, enterM)] ?? 0) >= 2 ||
              _spiderfyOffset.containsKey(objects[i].key))
            i
      ];
      if (members.length < 2) continue;
      members.sort((a, b) => objects[a].key.compareTo(objects[b].key));
      for (var r = 0; r < members.length; r++) {
        final o = objects[members[r]];
        final angle = 2 * math.pi * r / members.length;
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
    // sharing a cell with anything else is "crossing" and dims a little. Its own
    // threshold (~a marker's width): the fan's enter/exit pair above is about
    // whether to *move* a marker, which needs the hysteresis; a fade is
    // continuous and eased, so a single threshold can't flicker.
    final overlapM = 30.0 * metersPerPixel;
    final cellCount = <String, int>{};
    for (final p in placedPos) {
      cellCount.update(cellOf(p, overlapM), (v) => v + 1, ifAbsent: () => 1);
    }
    const crossOpacity = 0.7;
    final present = <String>{};
    final result = <MovingObject>[];
    for (var i = 0; i < objects.length; i++) {
      final o = objects[i];
      present.add(o.key);
      final crossing =
          o.moving && (cellCount[cellOf(placedPos[i], overlapM)] ?? 0) > 1;
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
    _tramRails = rails;
    // Rails are one of the imperative stop layers (stg-stops-rails), rendered the
    // same way in both symbol and widget modes — push the fresh geometry onto it.
    _pushStopSources();
  }

  void _onEvent(MapEvent event) {
    if (event is MapEventCameraIdle) {
      // While following, the camera is being panned every frame by us — don't
      // treat those idles as browsing (they'd hammer the stop/vehicle reload).
      if (_following) return;
      _loadStopsForVisibleArea();
      _loadVehiclesForVisibleArea();
      _reconcileCoverageLayer();
    } else if (event is MapEventClick) {
      _handleTap(event.point);
    } else if (event is MapEventStartMoveCamera) {
      // A camera event in the brief post-resume window is the tab-return canvas
      // re-layout, not a user gesture — never break follow on it.
      final guard = _followResumeGuardUntil;
      if (guard != null && DateTime.now().isBefore(guard)) return;
      // Break follow only on a genuine user pan/zoom (the marker + highlight
      // stay). Our own programmatic pans are bracketed by [_selfCameraMove] so
      // they never count — even if the platform mislabels one as a gesture — so
      // the per-frame follow pan can't cancel its own follow.
      if (shouldBreakFollow(
        following: _following,
        selfMove: _selfCameraMove,
        reason: event.reason,
      )) {
        _stopFollow();
      }
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
    // Recentring on the user is an explicit camera intent — it ends any follow
    // (the vehicle marker + route highlight stay put).
    _stopFollow();
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

  String _stopSourceId(String layerId) => '$layerId-src';

  /// Adds the stop marker layers + their (empty) GeoJSON sources to a freshly
  /// loaded style, once. Styling is taken from the same MarkerLayer/PolylineLayer
  /// specs the declarative path used, so the pins look identical. Order = paint
  /// order (first added sits lowest): rails · cluster · bus · tram · trolley ·
  /// mixed · favourites · pinned place. Data arrives later via
  /// [_pushStopSources]; the layers themselves are never removed/re-added, so the
  /// buggy positional reconcile can't drop them.
  Future<void> _addStopLayers(StyleController style) async {
    if (_stopLayersAdded || _stopLayersAdding) return;
    _stopLayersAdding = true;
    MarkerLayer pin(String image, {IconAnchor anchor = IconAnchor.center}) =>
        MarkerLayer(
          points: const [],
          iconImage: image,
          iconSize: _iconSize,
          iconAllowOverlap: true,
          iconAnchor: anchor,
        );
    final specs = <(String, Layer)>[
      (
        _railsLayerId,
        const PolylineLayer(polylines: [], color: tramRailColor, width: 2),
      ),
      (
        _clusterLayerId,
        MarkerLayer(
          points: const [],
          iconImage: MapImages.cluster,
          iconSize: _iconSize,
          iconAllowOverlap: true,
          textField: '{point_count}',
          textColor: _scheme.onPrimary,
          textSize: 13,
          textAllowOverlap: true,
        ),
      ),
      (_busLayerId, pin(MapImages.bus)),
      (_tramLayerId, pin(MapImages.tram)),
      (_trolleyLayerId, pin(MapImages.trolley)),
      (_mixedLayerId, pin(MapImages.mixedStop)),
      (_favLayerId, pin(MapImages.favorite)),
      (_placeLayerId, pin(MapImages.place, anchor: IconAnchor.bottom)),
    ];
    try {
      for (final (id, tmpl) in specs) {
        final srcId = _stopSourceId(id);
        await style.addSource(
          GeoJsonSource(id: srcId, data: _emptyFeatureCollection),
        );
        final StyleLayer layer = tmpl is PolylineLayer
            ? LineStyleLayer(
                id: id,
                sourceId: srcId,
                layout: tmpl.getLayout(),
                paint: tmpl.getPaint(),
              )
            : SymbolStyleLayer(
                id: id,
                sourceId: srcId,
                layout: (tmpl as MarkerLayer).getLayout(),
                paint: tmpl.getPaint(),
              );
        await style.addLayer(layer);
      }
      // Flip the ready flag ONLY once every source exists, so a camera-idle
      // firing mid-add can't call updateGeoJsonSource on a not-yet-created
      // source (that used to throw and poison the whole push — the stop pins
      // then never came back until the data happened to change).
      _stopLayersAdded = true;
    } catch (_) {
      // Style torn down mid-add (e.g. a theme flip) — allow a later retry.
      _stopLayersAdded = false;
    } finally {
      _stopLayersAdding = false;
    }
  }

  /// Pushes the current marker feature lists into the imperative stop layers'
  /// sources. Only source *data* changes — no layers are added or removed — so
  /// the reconcile bug can never drop a layer. Every source is (re)pushed on
  /// each call so a source can never get stuck on stale/empty data.
  void _pushStopSources() {
    final style = _style;
    if (style == null || !_stopLayersAdded) return;
    // While a line is focused, only its own route shows (via the declarative
    // focus layers) — empty every ambient stop source so nothing else competes.
    // Also hide the stops when the coverage heatmap stands in for them (flag on +
    // zoomed out); the heatmap shows through.
    final focused = _focus != null;
    final zoom = _controller?.getCamera().zoom ?? 15.0;
    final hidden =
        focused || (_coverageEnabled && coverageMainStopsOpacity(zoom) <= 0.01);
    final favStops =
        ref.read(favoriteStopLocationsProvider).valueOrNull ?? const <Stop>[];
    // Serialise via `jsonEncode`, NOT geobase's `FeatureCollection.toText()`:
    // toText() does not escape `"` (and other specials) in string properties, so
    // a stop whose name contains a quote — e.g. `Park "Tašmajdan"` (19 such stops
    // in the feed) — produced invalid JSON, which the web plugin's
    // `setData(JSON.parse(data))` threw on, leaving that source empty and its
    // stops unrendered. `jsonEncode` escapes correctly.
    String pointsFc(List<Feature<Point>> f) {
      if (hidden) return _emptyFeatureCollection;
      return jsonEncode({
        'type': 'FeatureCollection',
        'features': [
          for (final feature in f)
            {
              'type': 'Feature',
              'geometry': {
                'type': 'Point',
                'coordinates': [
                  feature.geometry!.position.x,
                  feature.geometry!.position.y,
                ],
              },
              'properties': feature.properties,
            },
        ],
      });
    }

    Map<String, Object?> stopFeature(Stop s) => {
      'type': 'Feature',
      'geometry': {
        'type': 'Point',
        'coordinates': [s.lon, s.lat],
      },
      'properties': {'stopId': s.stopId, 'name': s.name},
    };
    final data = <String, String>{
      _railsLayerId: focused
          ? _emptyFeatureCollection
          : jsonEncode({
              'type': 'FeatureCollection',
              'features': [
                for (final poly in _tramRails)
                  {
                    'type': 'Feature',
                    'geometry': {
                      'type': 'LineString',
                      'coordinates': [
                        for (final p in poly) [p[1], p[0]],
                      ],
                    },
                    'properties': const <String, Object?>{},
                  },
              ],
            }),
      _clusterLayerId: pointsFc(_clusterPts),
      _busLayerId: pointsFc(_busPts),
      _tramLayerId: pointsFc(_tramPts),
      _trolleyLayerId: pointsFc(_trolleyPts),
      _mixedLayerId: pointsFc(_mixedPts),
      _favLayerId: focused
          ? _emptyFeatureCollection
          : jsonEncode({
              'type': 'FeatureCollection',
              'features': [for (final s in favStops) stopFeature(s)],
            }),
      _placeLayerId: focused
          ? _emptyFeatureCollection
          : jsonEncode({
              'type': 'FeatureCollection',
              'features': [
                if (_pinnedPlace case final place?)
                  {
                    'type': 'Feature',
                    'geometry': {
                      'type': 'Point',
                      'coordinates': [place.lon, place.lat],
                    },
                    'properties': const <String, Object?>{},
                  },
              ],
            }),
    };
    // Always push every source (no dedup cache): `updateGeoJsonSource` is a
    // synchronous `setData` on web, so re-pushing unchanged data on a camera
    // idle is cheap, and it guarantees a source that briefly failed an earlier
    // push (or was reset) always recovers on the next one. Each update is
    // isolated so one failure can't abort the rest of the loop.
    for (final entry in data.entries) {
      try {
        style.updateGeoJsonSource(
          id: _stopSourceId(entry.key),
          data: entry.value,
        );
      } catch (_) {
        // Source momentarily absent (mid style reload) — the next push retries.
      }
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
      final type = stopMarkerType(s);
      if (type == null) {
        mixed.add(feature); // one unified marker for multi-type stops (D2)
        return;
      }
      switch (type) {
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
    _pushStopSources();
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
    // On-demand mode (vehicles_on_demand): no background "aquarium" — the map
    // fetches and renders no vehicles without a context. Markers come only from
    // a stop context (the arrivals listener) or an injected followed vehicle, so
    // the map fan-out load (× every open client × 30s) is dropped entirely here.
    if (_onDemand) return;
    // No zoom gate on fetching (F5): the request is always bounded to ≤1 km /
    // ≤12 stops (see _vehiclesMaxRadius and the backend fan-out cap) regardless
    // of zoom, so a zoomed-out view never fans the source out wider. Keeping it
    // live means the city overview still shows the (sparse) vehicles already
    // around the viewport as dots instead of a blank map; the marker layer
    // degrades pills → dots at low zoom on its own. When even the
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
      // Re-check the flag AFTER the await: a fetch kicked off while off-demand
      // (e.g. in the window after a reload, before `/config` resolves the flag to
      // ON) must NOT populate the map once we're on-demand — otherwise the whole
      // aquarium (buses, trams, scheduled objects) leaks onto a context-less map.
      if (!keepAquariumResult(
        mounted: mounted,
        current: seq == _vehiclesRequestSeq,
        onDemand: _onDemand,
      )) {
        return;
      }
      // Placeholder rows (junk garage `P1..P999`, GPS pinned to a stop) aren't
      // tracked vehicles — they'd sit motionless on a stop, so keep them off the
      // map. The arrivals *list* on the stop screen still shows their line/ETA.
      // Scheduled objects are schedule-derived by design, so they bypass this
      // junk filter.
      final vehicles = fetched
          .where((v) =>
              v.source == VehicleSource.scheduled ||
              areaVehicleHasLivePosition(v))
          .toList();
      // Hybrid live+schedule: render whatever the backend sends, live and
      // schedule-predicted alike. (The backend de-dups a scheduled trip that has
      // a live vehicle; the client's key-prefixing keeps the two off the same
      // track.) Scheduled objects are present only where the map endpoint emits
      // them; elsewhere this is just the live set.
      final shown = vehicles;
      // Which shape to move each vehicle along: the *direction the vehicle is
      // actually going* (backend-resolved route_id) so it doesn't ride the
      // canonical direction's street ("through houses"). A null key (older
      // payload) just means no path → straight-line ease (safe).
      String? shapeKeyOf(AreaVehicle v) => v.routeId;
      // Make sure each visible route's geometry is (being) fetched so the
      // animator can move markers along the road, not through buildings (X5) —
      // and, in timed mode, project the plan onto it.
      _ensureShapesFor(
        [for (final v in shown) shapeKeyOf(v)].whereType<String>(),
        byRouteId: true,
      );
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
        _startVehDriver();
      } else {
        _stopVehDriver();
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
    String? shapeKeyOf(AreaVehicle v) => v.routeId;
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
          // Hand the animator each vehicle's forward plan + as-of time so it
          // plays motion forward by time; a vehicle without a plan (null) just
          // eases conservatively to its latest fix.
          trajectory: v.trajectory,
          asOf: v.asOf,
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
        _startVehDriver();
      }
      _paintVehicles();
    });
  }

  /// Highlight a line's route on this same map (hiding the rest) instead of
  /// pushing a separate screen — driven by a vehicle tap, a followed vehicle, or
  /// a favourite-line tap. Closing the focus panel restores normal browsing.
  ///
  /// The camera deliberately stays where the user left it (F2): highlighting a
  /// route must not yank the user out to a whole-route fitBounds. The camera is
  /// handled by the caller (follow mode / none), never here.
  ///
  /// [refreshVehicles] refetches the viewport vehicle set so the focused line's
  /// buses show at once; the §C path passes false so a just-injected followed
  /// marker can't be pruned by a fan-out that doesn't (yet) contain it.
  Future<void> _openVehicleLine(
    String line, {
    bool scheduled = false,
    bool refreshVehicles = true,
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
      _pushStopSources(); // hide the ambient stop layers behind the focused line
      _syncFocusLayers(); // draw the route + its stops UNDER the vehicle symbols
      // Refresh the vehicle set so the focused line's buses show right away.
      if (refreshVehicles) _loadVehiclesForVisibleArea(force: true);
    } catch (_) {
      // Best-effort: a failed shape lookup just doesn't open the route.
    }
  }

  // ---- Follow mode ----------------------------------------------------------

  /// Build one animator sample from an arrival's own data. The [shapeKey] is the
  /// direction route_id whose geometry the marker moves along; [asOf] anchors the
  /// timed-trajectory plan (the arrivals board's `updated_at`).
  VehicleSample _sampleFromArrival(
    Arrival a,
    String shapeKey, {
    DateTime? asOf,
  }) {
    return VehicleSample(
      key: VehicleTrackAnimator.keyFor(a),
      position: ll.LatLng(a.gps!.lat, a.gps!.lon),
      line: a.line,
      type: classifyLine(a.line),
      heading: a.heading,
      path: _shapeCache[shapeKey],
      trajectory: a.trajectory,
      asOf: asOf,
      source: a.scheduled ? VehicleSource.scheduled : VehicleSource.live,
    );
  }

  /// Run a programmatic camera move bracketed so its resulting move-start event
  /// (fired synchronously on web) is recognised as ours, not a user gesture.
  void _selfMove(void Function() move) {
    _selfCameraMove = true;
    try {
      move();
    } finally {
      _selfCameraMove = false;
    }
  }

  /// The single entry into follow mode. Every source — a stop-sheet row, a
  /// Nearby row, a marker tap — funnels through here so they establish an
  /// identical state set: select the vehicle, guarantee the follow bar (via the
  /// `_selectedVehicleKey`-gated bottom UI, which replaces whatever context sheet
  /// was open and offers the × exit), load its route, and start the camera
  /// follow. The caller has already ensured the marker exists.
  ///
  /// The Nearby path used to skip this contract — it nudged only camera+selection
  /// while its (persistent, non-modal) sheet stayed open and the follow bar,
  /// gated on the async route load, never appeared — so there was no way out.
  void _enterFollow({
    required String key,
    required ll.LatLng target,
    required bool flyTo,
    required String line,
    bool scheduled = false,
    bool refreshVehicles = false,
  }) {
    setState(() => _selectedVehicleKey = key);
    _writeVehiclesToSource(); // tap highlight on the symbol layer
    if (!_paused && _vehAnimator.hasPendingMotion) _startVehDriver();
    _paintVehicles();
    // Route highlight (sets `_focus` async). The follow bar no longer waits on
    // it — it shows the instant `_selectedVehicleKey` is set.
    _openVehicleLine(line, scheduled: scheduled, refreshVehicles: refreshVehicles);
    _startFollow(key, target: target, flyTo: flyTo);
  }

  /// Start following [key]. [flyTo] true (entry from a list row) flies the camera
  /// to the vehicle and zooms to a readable pill first, then — once the fly-to
  /// settles — hands over to the continuous per-frame pan; false (a marker tap)
  /// starts tracking from where the camera already is, no jump, no zoom change
  /// (§C.2, don't regress F2).
  void _startFollow(String key, {required ll.LatLng target, required bool flyTo}) {
    final controller = _controller;
    // Snapshot where the user is before we fly off, so closing the context can
    // bring them back here (the stop, or the pre-focus viewport). Only on a fresh
    // entry — a re-seed mid-follow must not overwrite the origin.
    if (!_following && controller != null) {
      final cam = controller.getCamera();
      _preFollowCenter = cam.center;
      _preFollowZoom = cam.zoom;
    }
    _following = true;
    _selectedVehicleKey = key;
    _lastFollowMarkerPos = null; // (re)seed on the first follow tick
    _lastFollowMoveAt = null;
    if (flyTo && controller != null) {
      final zoom = math.max(controller.getCamera().zoom, kMovingObjectDetailZoom);
      _followEngaged = false;
      Future<void>? flight;
      _selfMove(() {
        flight = controller.animateCamera(
          center: Geographic(lon: target.longitude, lat: target.latitude),
          zoom: zoom,
        );
      });
      // Engage the continuous pan only once the fly-to has actually settled, so
      // the two never fight; re-seed at the settled spot so the first pan tick
      // doesn't apply a stale delta.
      flight?.whenComplete(() {
        if (mounted && _following && _selectedVehicleKey == key) {
          _lastFollowMarkerPos = null;
          _followEngaged = true;
        }
      });
    } else {
      _followEngaged = true;
    }
    // Ensure the layer paints (and the follow tick fires) even if the vehicle is
    // momentarily still; a moving vehicle keeps the driver alive on its own.
    _startVehDriver();
    _paintVehicles();
  }

  void _stopFollow() {
    if (!_following) return;
    _following = false;
    _followEngaged = false;
    _lastFollowMarkerPos = null;
  }

  /// A brief "vehicle no longer tracked" notice — shown when we can't build a
  /// followed marker, or the followed vehicle drops out of the feed.
  void _showVehicleLost() {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context).vehicleLost)),
    );
  }

  /// The followed vehicle vanished mid-follow: notify and leave the vehicle
  /// context (back to the stop it came from, or the map), so follow never
  /// continues over an empty map.
  void _onFollowedVehicleLost() {
    if (!_following) return;
    _showVehicleLost();
    _closeVehicleContext();
  }

  // Follow re-centres at ~15fps, not every render frame. Panning the whole map
  // with a jumpTo on every one of ~60 fps thrashes the tile/label renderer and
  // the neighbouring GL layers visibly jitter (pins, street labels) against a
  // moving camera. At 15fps the per-step drift of the followed marker is
  // sub-pixel at follow zoom, so it still reads as screen-fixed, but the map is
  // steady between steps. (Matches the conservative sampler cadence used
  // elsewhere.)
  static const _followInterval = Duration(milliseconds: 66);

  /// One follow step: pan the camera by how far the marker moved since the last
  /// step, so the marker stays put on screen as it travels — a continuous pan,
  /// Flightradar-style. The zoom is never touched (the user's zoom is respected).
  /// Throttled to [_followInterval] to keep the map from jittering. The first
  /// step only seeds the reference position so engaging follow causes no jump; a
  /// vanished vehicle (grace/dropped) holds the camera still and re-seeds on
  /// return so it doesn't lurch.
  void _followTick() {
    if (!_following || !_followEngaged) return;
    final key = _selectedVehicleKey;
    final controller = _controller;
    if (key == null || controller == null) return;
    if (_vehAnimator.trackFor(key) == null) {
      // The vehicle dropped out of the feed for good (past the grace period).
      // Follow without a marker shouldn't exist — surface "vehicle lost" and
      // leave follow rather than chase an empty map (deferred so we don't mutate
      // navigation mid-paint).
      _lastFollowMarkerPos = null;
      WidgetsBinding.instance.addPostFrameCallback((_) => _onFollowedVehicleLost());
      return;
    }
    final now = DateTime.now();
    // Throttle: leave `_lastFollowMarkerPos` untouched so the next allowed step
    // pans by the full delta accumulated over the interval.
    if (_lastFollowMoveAt != null && now.difference(_lastFollowMoveAt!) < _followInterval) {
      return;
    }
    final pos = _vehAnimator.positionOf(key, _vehAnim.value);
    final last = _lastFollowMarkerPos;
    _lastFollowMarkerPos = pos;
    _lastFollowMoveAt = now;
    if (last == null) return; // first step after engage/return: seed only
    final dLat = pos.latitude - last.latitude;
    final dLon = pos.longitude - last.longitude;
    if (dLat.abs() < 1e-7 && dLon.abs() < 1e-7) return; // not moving
    final cam = controller.getCamera();
    // Pan the camera by the marker's own delta → the marker stays screen-fixed.
    _selfMove(() {
      controller.moveCamera(
        center: Geographic(
          lon: cam.center.lon + dLon,
          lat: cam.center.lat + dLat,
        ),
        zoom: cam.zoom, // keep the user's zoom
      );
    });
  }

  // ---- On-demand stop context (state B) ------------------------------------

  /// Enter (or re-enter) stop context: the tapped stop's live arrivals become
  /// the only vehicle markers, fed from the same arrivals provider the sheet
  /// watches (shared fetch, no second fan-out). No-op unless the flag is on.
  ///
  /// The host — not the sheet — owns keeping this fresh: [_refreshTick] re-fetches
  /// this stop every 30s while the context is alive (crucially, also during a
  /// follow after the sheet has closed, so nothing freezes). Because our
  /// subscription pins the provider alive, a re-open would otherwise show a stale
  /// board ("Updated 2 min ago"), so we invalidate on entry to pull a fresh one
  /// (SWR: instant cached value, immediate revalidate).
  void _enterStopContext(String stopId) {
    if (!_onDemand) return;
    if (_stopContextId != stopId || _stopArrivalsSub == null) {
      _stopArrivalsSub?.close();
      _stopContextId = stopId;
      _stopArrivalsSub = ref.listenManual<AsyncValue<ArrivalsBoard>>(
        arrivalsProvider(stopId),
        (_, next) {
          final board = next.valueOrNull;
          if (board != null) _applyStopContextMarkers(board);
        },
      );
    }
    _returnToStopId = null;
    // Apply whatever is already in hand for an instant paint, then force a fresh
    // fetch so neither the markers nor the sheet show a stale board on open.
    final current = _stopArrivalsSub!.read().valueOrNull;
    if (current != null) _applyStopContextMarkers(current);
    ref.invalidate(arrivalsProvider(stopId));
  }

  /// Replace the vehicle set with this stop's live-position arrivals (schedule
  /// rows and P1..P999 placeholders have no real fix and stay list-only). Same
  /// animator/driver path as the background feed, so motion/timed-trajectory and
  /// spiderfy behave identically.
  void _applyStopContextMarkers(ArrivalsBoard board) {
    if (!_onDemand || _stopContextId != board.stopId) return;
    final samples = <VehicleSample>[];
    final shapeKeys = <String>[];
    for (final a in board.arrivals) {
      if (!arrivalHasLivePosition(a)) continue;
      final dirId = a.directionRouteId ?? a.routeId;
      shapeKeys.add(dirId);
      samples.add(_sampleFromArrival(a, dirId, asOf: board.updatedAt));
    }
    _ensureShapesFor(shapeKeys, byRouteId: true);
    _vehAnimator.syncSamples(samples, _vehAnim.value);
    // Diagnostics (staging overlay): board freshness + how many of this stop's
    // rows carried a timing plan, so a "frozen markers" report can be read off
    // the screen without a console (debugPrint is stripped in release web).
    _lastCtxBoardAgeSec =
        DateTime.now().toUtc().difference(board.updatedAt.toUtc()).inSeconds;
    _boardAgePolls.add(_lastCtxBoardAgeSec!);
    if (_boardAgePolls.length > 12) _boardAgePolls.removeAt(0);
    _lastCtxLive = samples.length;
    _lastCtxWithTraj = samples.where((s) => s.trajectory != null).length;
    // Keep the driver alive for the whole poll interval whenever this context has
    // live timed markers — the timed players are advanced by wall-clock each
    // frame, and `hasForwardMotion` can momentarily read false as a fix converges
    // (especially near the 45s staleness gate). Parking the ticker on that flicker
    // is exactly what froze the markers mid-interval. Running the ease controller
    // holds `isAnimating` true across the interval so the ticker keeps advancing
    // them; a genuinely stale/stationary marker just repaints in place. (A context
    // is a handful of vehicles the user is watching, so this doesn't touch the
    // whole-city "idle = 0 frames" thermal budget.)
    final hasLiveTimed = _lastCtxWithTraj > 0;
    if (!_paused && (hasLiveTimed || _vehAnimator.hasPendingMotion)) {
      _vehAnim.forward(from: 0);
      _startVehDriver();
    } else {
      _stopVehDriver();
      _vehAnim.value = 1;
    }
    _paintVehicles();
    setState(() => _hasVehicles = _vehAnimator.tracks.isNotEmpty);
  }

  /// Leave stop context. Drops the subscription; clears the markers only when no
  /// vehicle is being followed (a followed vehicle keeps its injected marker).
  void _exitStopContext() {
    _stopArrivalsSub?.close();
    _stopArrivalsSub = null;
    _stopContextId = null;
    if (_selectedVehicleKey == null) {
      _vehAnimator.clear();
      _paintVehicles();
      setState(() => _hasVehicles = false);
    }
  }

  /// React to the mode changing — the flag resolving at startup, or the user
  /// flipping the Settings choice. Applies on the fly, no restart.
  void _onOnDemandChanged() {
    if (!mounted) return;
    if (_onDemand) {
      // Entering on-demand: the background aquarium goes at once (and the 30s
      // tick stops fetching it — see mapRefreshAction). The contexts survive:
      // a followed vehicle keeps its own marker (§C, works in both modes)…
      final followed = _selectedVehicleKey;
      _vehAnimator.retainOnly({if (followed != null) followed});
      // …and a stop context repaints from the board already in hand instead of
      // waiting out the next 30s tick.
      final board = _stopContextId == null
          ? null
          : _stopArrivalsSub?.read().valueOrNull;
      if (board != null) {
        _applyStopContextMarkers(board);
      } else {
        _paintVehicles();
        setState(() => _hasVehicles = _vehAnimator.tracks.isNotEmpty);
      }
    } else {
      // Left on-demand → repopulate the background set for the viewport.
      _loadVehiclesForVisibleArea(force: true);
    }
  }

  /// Close the vehicle context (line panel / back). Stops following, clears the
  /// route highlight, and — when on-demand — returns to the stop context it was
  /// opened from (state B) or to the empty map (state A).
  void _closeVehicleContext() {
    _stopFollow();
    _clearFocus();
    final returnStop = _onDemand ? _returnToStopId : null;
    _returnToStopId = null;
    if (returnStop != null) {
      // Returning to the stop: reopening it re-pans the camera so the stop sits
      // above the sheet — don't also restore the pre-follow centre (it would
      // fight that), just reopen.
      _preFollowCenter = null;
      _preFollowZoom = null;
      _openStopById(returnStop);
      return;
    }
    // No stop to reopen: ease back to where the user came from. Prefer the
    // pre-stop viewport when the follow was spawned from a stop sheet we're not
    // reopening (so we land back at the original browse position, not the panned
    // stop), else the pre-follow viewport (a follow straight from Nearby).
    final center = _preStopCameraCenter ?? _preFollowCenter;
    final zoom = _preStopCameraCenter != null ? _preStopCameraZoom : _preFollowZoom;
    if (center != null) {
      _easeCameraTo(center, zoom);
    }
    _preFollowCenter = null;
    _preFollowZoom = null;
    _preStopCameraCenter = null;
    _preStopCameraZoom = null;
    if (_onDemand) _exitStopContext();
  }

  /// Enter vehicle context from a tapped arrival row (§C). Builds a guaranteed
  /// marker from the arrival's own data (gps + trajectory + direction) so the
  /// vehicle appears immediately — never waiting on a viewport fan-out, which was
  /// the root of the old bug — highlights its direction's route, flies to it and
  /// follows. Works at both flag values.
  void _focusVehicleFromArrival(Arrival a, DateTime asOf) {
    final gps = a.gps;
    // No live fix → no marker → don't enter follow (it would be a follow over an
    // empty map). Surface "vehicle lost" instead.
    if (gps == null || !arrivalHasLivePosition(a)) {
      _showVehicleLost();
      return;
    }
    _clearSearch();
    _returnToStopId = _onDemand ? _stopContextId : null;
    final key = VehicleTrackAnimator.keyFor(a);
    final pos = ll.LatLng(gps.lat, gps.lon);
    final dirId = a.directionRouteId ?? a.routeId;
    _ensureShapesFor([dirId], byRouteId: true);
    // Guaranteed marker: upsert this one vehicle without disturbing others.
    _vehAnimator.syncSamples(
      [_sampleFromArrival(a, dirId, asOf: asOf)],
      _vehAnim.value,
      prune: false,
    );
    // The marker must actually exist before we commit to follow.
    if (_vehAnimator.trackFor(key) == null) {
      _showVehicleLost();
      return;
    }
    // Single follow entry (fly the camera in from a list row). refreshVehicles
    // false so a fan-out can't prune the marker we just injected.
    _enterFollow(
      key: key,
      target: pos,
      flyTo: true,
      line: a.line,
      scheduled: a.scheduled,
    );
  }

  void _clearFocus() {
    if (_focus == null && _selectedVehicleKey == null) return;
    setState(() {
      _focus = null;
      _selectedVehicleKey = null;
    });
    _pushStopSources(); // restore the ambient stop layers
    _syncFocusLayers(); // remove the focus route/stops layers
    // Drop the tap highlight on the symbol layer.
    _writeVehiclesToSource();
  }

  // ---- Taps -----------------------------------------------------------------

  void _handleTap(Geographic point) {
    final controller = _controller;
    if (controller == null) return;
    final screen = controller.toScreenLocation(point);
    final rect = Rect.fromCircle(center: screen, radius: 22);
    // Symbol-layer vehicles: hit-test the badge layer and open the tapped line
    // (a bottom sheet). Highlight the selected vehicle via its feature
    // `selected` flag.
    if (_vehLayerAdded) {
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
          // §C.2: highlight the route + line panel and start following — but the
          // camera does NOT jump or zoom (don't regress F2). Same single entry
          // as the list-row paths, so all three end in identical state.
          _returnToStopId = _onDemand ? _stopContextId : null;
          if (keyStr != null) {
            _enterFollow(
              key: keyStr,
              target: ll.LatLng(point.lat, point.lon),
              flyTo: false,
              line: line,
              scheduled: scheduled,
              refreshVehicles: true,
            );
          } else {
            _openVehicleLine(line, scheduled: scheduled);
          }
          return;
        }
      }
    }
    final features = controller.featuresInRect(rect);
    // Stops: the fat tap rect can cover several pins in a dense cluster, and
    // featuresInRect returns them in query/z order — the FIRST isn't necessarily
    // the one under the finger. Collect every candidate stop, project it to the
    // screen, and open the one NEAREST the tap point (#2, "tap opens a neighbour").
    final stopCandidates = <(Stop, Offset)>[];
    for (final f in features) {
      final stopId = f.properties['stopId'];
      if (stopId is String) {
        final stop = _stopById(stopId);
        if (stop != null) {
          try {
            final at = controller.toScreenLocation(
              Geographic(lon: stop.lon, lat: stop.lat),
            );
            stopCandidates.add((stop, at));
          } catch (_) {
            stopCandidates.add((stop, screen)); // projection failed — treat as at the tap
          }
        }
      }
    }
    final nearestStop = pickNearest(screen, stopCandidates);
    if (nearestStop != null) {
      _openStop(nearestStop);
      return;
    }
    for (final f in features) {
      final props = f.properties;
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

  void _openStop(Stop stop) => _openStopById(
        stop.stopId,
        stopName: stop.name,
        at: ll.LatLng(stop.lat, stop.lon),
      );

  /// Tap a "Nearby" row → follow that line+direction's soonest **live** vehicle
  /// (#5, owner variant 3). A NearbyGroup carries no gps/trajectory, so we resolve
  /// the vehicle from the same `/arrivals` the sheet uses (SWR-cached): the
  /// nearest live board of this line × direction. If the group has no live vehicle
  /// (schedule-only), fall back to opening the stop. Entering the stop context
  /// (even coming from Nearby) keeps the followed vehicle refreshed by the 30s
  /// poll so it doesn't freeze; but the return target stays the pre-follow
  /// viewport (we didn't arrive through the stop sheet), so closing goes back to
  /// Nearby, not into the stop.
  Future<void> _focusNearbyVehicle(NearbyGroup group) async {
    _clearSearch();
    // A schedule-only row opens the stop without a fetch (its own status says so).
    final hasLiveEta = group.arrivals.any((e) => !e.isScheduled);
    if (!hasLiveEta) {
      _openStopById(group.stopId, stopName: group.stopName);
      return;
    }
    ArrivalsBoard board;
    try {
      board = await ref.read(arrivalsProvider(group.stopId).future);
    } catch (_) {
      _openStopById(group.stopId, stopName: group.stopName);
      return;
    }
    if (!mounted) return;
    // Resolve the live vehicle the row is about (nearbyFollowTarget honours the
    // group status and the board's reality); null → open the stop, never follow a
    // scheduled/absent vehicle.
    final match = nearbyFollowTarget(group, board.arrivals);
    if (match == null) {
      _openStopById(group.stopId, stopName: group.stopName);
      return;
    }
    if (_onDemand) _enterStopContext(group.stopId); // keep the vehicle refreshed
    _focusVehicleFromArrival(match, board.updatedAt);
    _returnToStopId = null; // came from Nearby → close returns to the viewport
  }

  /// Shared stop-opening path (pin tap, Nearby row, or returning to a stop
  /// context after a follow). Seamless (A1): overlays the arrivals on the same
  /// map. When on-demand, entering stop context makes that stop's arrivals the
  /// map's markers (state B); closing the sheet (unless a vehicle was tapped)
  /// clears them back to A.
  void _openStopById(String stopId, {String? stopName, ll.LatLng? at}) {
    _clearSearch();
    // Snapshot the viewport before the stop is panned up, so closing the sheet
    // returns here — symmetric to the open. Only the first open of a session
    // captures it (a return-to-stop re-open must not overwrite the origin).
    if (_preStopCameraCenter == null) {
      final cam = _controller?.getCamera();
      if (cam != null) {
        _preStopCameraCenter = cam.center;
        _preStopCameraZoom = cam.zoom;
      }
    }
    if (_onDemand) _enterStopContext(stopId);
    // Shift the stop up into the visible strip ABOVE the sheet, so it isn't
    // hidden under it (and so returning from a follow lands on a visible stop).
    _bringStopIntoView(stopId, at);
    // Hide the bottom UI (Nearby panel / search) while the sheet is up so they
    // don't overlap (#7).
    setState(() => _stopSheetOpen = true);
    showStopSheet(
      context,
      stopId: stopId,
      stopName: stopName,
      // Tapping a vehicle row hands the whole arrival to the map so it builds a
      // guaranteed marker, highlights the route and follows (§C).
      onFocusVehicle: _focusVehicleFromArrival,
    ).then((_) {
      if (mounted) setState(() => _stopSheetOpen = false);
      _onStopSheetClosed(stopId);
    });
  }

  // A camera glide with a deliberate, deceleration-curve duration. Used for
  // opening a stop (pan it above the sheet) and closing it (ease back), so entry
  // and exit feel symmetric — a slow-ish `flyTo` (low speed, capped) rather than
  // the near-instant default that reads as a teleport on a short move.
  static const _cameraEaseDuration = Duration(milliseconds: 700);
  static const double _cameraEaseSpeed = 0.55;

  void _easeCameraTo(
    Geographic center,
    double? zoom, {
    EdgeInsets padding = EdgeInsets.zero,
  }) {
    final controller = _controller;
    if (controller == null) return;
    _selfMove(() {
      controller.animateCamera(
        center: center,
        zoom: zoom,
        padding: padding,
        nativeDuration: _cameraEaseDuration,
        webSpeed: _cameraEaseSpeed,
        webMaxDuration: const Duration(milliseconds: 800),
      );
    });
  }

  /// Pan [stopId] into the strip of map visible above the arrivals sheet (the
  /// sheet covers the lower ~half), zooming in to at least the individual-stop
  /// level. Resolves the coordinate from the tap ([at]) or the GTFS mirror.
  Future<void> _bringStopIntoView(String stopId, ll.LatLng? at) async {
    final pos = at ?? await _resolveStopLatLng(stopId);
    if (pos == null || !mounted) return;
    final controller = _controller;
    if (controller == null) return;
    final zoom = math.max(controller.getCamera().zoom, _individualZoom);
    final bottomPad = MediaQuery.of(context).size.height * 0.5;
    _easeCameraTo(
      Geographic(lon: pos.longitude, lat: pos.latitude),
      zoom,
      padding: EdgeInsets.only(bottom: bottomPad),
    );
  }

  Future<ll.LatLng?> _resolveStopLatLng(String stopId) async {
    final known = _stopById(stopId);
    if (known != null) return ll.LatLng(known.lat, known.lon);
    try {
      final stop = await ref.read(stopLocationProvider(stopId).future);
      if (stop != null) return ll.LatLng(stop.lat, stop.lon);
    } catch (_) {}
    return null;
  }

  /// The stop sheet was dismissed. If a vehicle from this stop is now being
  /// followed, keep the stop context alive so closing the line panel can return
  /// to it; otherwise leave state B for A.
  void _onStopSheetClosed(String stopId) {
    // A vehicle context is now active (a row was tapped): it owns the camera and
    // will return to the origin later — don't restore here, and keep the stop
    // context alive if we'll come back to it.
    final vehicleContextActive = _following || _focus != null;
    if (_onDemand &&
        _stopContextId == stopId &&
        !(vehicleContextActive && _returnToStopId == stopId)) {
      _exitStopContext();
    }
    if (vehicleContextActive) return;
    _restorePreStopCamera();
  }

  /// Ease the camera back to where it sat before the stop sheet panned it up —
  /// symmetric to the open (same glide), and resetting the sheet's bottom padding
  /// so it doesn't land offset.
  void _restorePreStopCamera() {
    final center = _preStopCameraCenter;
    if (center != null) {
      _easeCameraTo(center, _preStopCameraZoom);
    }
    _preStopCameraCenter = null;
    _preStopCameraZoom = null;
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
    _pushStopSources(); // show the pinned-place marker
    await _controller?.animateCamera(center: center, zoom: 16);
  }


  // ---- Build ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    _scheme = theme.colorScheme;
    final brightness = theme.brightness;
    // Experimental "Nearby" sheet (draggable list of lines around the user),
    // gated remotely — replaces the bottom search bar when on.
    final nearbyEnabled = ref.watch(nearbyEnabledProvider);

    // Follow the app theme: swap the MapTiler style when brightness flips.
    if (_styleBrightness == null) {
      _styleBrightness = brightness;
    } else if (_styleBrightness != brightness && _controller != null) {
      _styleBrightness = brightness;
      _imagesReady = false;
      _controller!.setStyle(MapStyle.forBrightness(brightness));
    }

    // Favourites are drawn by an imperative source now; refresh it whenever the
    // set changes (no widget rebuild needed for the markers themselves).
    ref.listen(favoriteStopLocationsProvider, (_, _) => _pushStopSources());

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

    // The map mode: the Settings choice resolved against the on-demand flag.
    // Flips false→true once remote config resolves, and again whenever the user
    // switches the setting. Reconcile after the frame (clear the background
    // aquarium, or repopulate) so the switch applies without a restart.
    final onDemand = ref.watch(vehicleMapModeProvider) == VehicleMapMode.onDemand;
    if (onDemand != _onDemand) {
      _onDemand = onDemand;
      WidgetsBinding.instance.addPostFrameCallback((_) => _onOnDemandChanged());
    }

    return PopScope(
      // While a line is focused, Android back closes the vehicle context instead
      // of leaving the map.
      canPop: _focus == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _closeVehicleContext();
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
                  layers: _buildLayers(),
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
                    // Live vehicles render as the batched GPU symbol layer,
                    // added imperatively in _addVehicleSymbolLayers — no widget
                    // layer is built for them here.
                  ],
                ),
              ),
            )
          else
            const SizedBox.expand(),
          // Round action buttons at the top: menu (left), recenter (right).
          _topButtons(theme),
          // Staging-only stop-render diagnostics (isStaging; invisible in prod).
          // The one reliable render-observation channel on Flutter-CanvasKit —
          // see _stopDiagnosticsOverlay and the map-render gotchas.
          if (isStaging) _stopDiagnosticsOverlay(theme),
          // Far-out zoom with no vehicles in the bounded area: nudge the user to
          // zoom in rather than leaving them staring at a blank map (F5).
          // On-demand mode has no background vehicle layer, so the "zoom in to
          // see transport" hint (which is about that empty layer) doesn't apply.
          if (_focus == null &&
              !_onDemand &&
              _currentZoom < _minVehiclesZoom &&
              !_hasVehicles)
            _zoomHint(l10n, theme),
          // Bottom UI: while a line is focused, a compact line panel with a close
          // button. Otherwise the experimental "Nearby" sheet when its flag is on
          // (it *replaces* the search bar), else the normal search + favourites.
          // A stop arrivals sheet suppresses the whole bottom cluster so the two
          // never stack on top of each other (#7).
          if (_focus != null || _selectedVehicleKey != null)
            _focusPanel(theme)
          else if (_stopSheetOpen)
            const SizedBox.shrink()
          else if (nearbyEnabled)
            NearbySheet(
              userLocation: _meTo,
              locationDenied: _locationDenied,
              active: _tabActive && _appResumed,
              onEnableLocation: _recenterOnMe,
              onTapGroup: _focusNearbyVehicle,
            )
          else
            _bottomSearch(l10n, theme),
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

  /// True for one of the imperative stop layers (see [_addStopLayers]).
  static bool _isStopLayer(String id) => id.startsWith('stg-stops-');

  /// Short label for a stop layer id in diagnostics ('stg-stops-bus' → 'bus').
  String _glLayerLabel(String id) =>
      _isStopLayer(id) ? id.substring('stg-stops-'.length) : id;

  /// Staging-only render-diagnostics overlay (`isStaging`, invisible in prod).
  /// On Flutter-CanvasKit the map/layers aren't in the DOM and external JS
  /// inspection is blind, so this is the one reliable window into the stop-render
  /// pipeline: the gate flags ([_imagesReady]/[_stopLayersAdded]/style), where
  /// the last viewport fetch landed, how many stops came back and how they split
  /// across the marker lists, which imperative stop layers are actually on the
  /// map, and — via [MapController.queryLayers] — whether each type's layer
  /// really draws at a real stop's pixel (catches "layer present, data pushed,
  /// but nothing rendered"). Keep it: it is what broke the multi-round
  /// stop-render investigation open.
  // One diagnostics line for the followed vehicle's catch-up: live gap (metres
  // behind the plan's predicted-now spot) and display speed (m/s). Reads the
  // timed player directly; falls back to a dash when nothing is being followed.
  String _catchUpDiagLine() {
    final key = _selectedVehicleKey;
    final timed = key == null ? null : _vehAnimator.trackFor(key)?.timed;
    if (timed == null) return 'VEH catchUp gap - plan - vel - age -';
    final now = DateTime.now();
    // `plan` vs `vel` is the pair that diagnoses jitter: the plan's own speed
    // against the marker's. Tracking is healthy when they sit on top of each
    // other with gap ≈ 0. `vel` swinging around a steady `plan` means the
    // catch-up loop is oscillating; both swinging together means the plan is.
    //
    // `age` is the live board age driving the staleness gate; `HOLD` means it
    // has passed 45 s, so this marker has stopped predicting and stands still.
    final age = timed.boardAgeSeconds(now);
    return 'VEH catchUp gap ${timed.catchUpGap(now).toStringAsFixed(2)}m '
        'plan ${timed.planSpeed(now).toStringAsFixed(2)} '
        'vel ${timed.displaySpeed.toStringAsFixed(2)}m/s '
        'age ${age.toStringAsFixed(0)}s${timed.isStale(now) ? " HOLD" : ""}';
  }

  // How stale the vehicles' REAL fixes are, against how stale their boards
  // claim to be. `as_of` is the backend's last successful *fetch*, so re-fetching
  // a board the upstream hasn't refreshed re-stamps it young while the fix
  // underneath is minutes old — and the whole prediction hangs off that stamp.
  // Measured live: two views of one bus 121 m apart from GPS fixes identical to
  // the metre, purely because their as_of differed by 36 s.
  //
  // Read-only evidence for a later call on whether the backend should stop
  // re-stamping. Low numbers → the root fix is painless; high → the feed itself
  // is the conversation.
  String _fixAgeDiagLine() {
    final s = _vehAnimator.fixAgeStats();
    if (s.total == 0) return 'VEH fixAge -';
    return 'VEH fixAge >45s ${s.over45}/${s.total} '
        '>90s ${s.over90}/${s.total} (real fix age, not as_of)';
  }

  // How old each recent board was when it landed, and how many of those doomed
  // the marker to a freeze before the next one (> 15 s; see the field's note).
  String _boardAgeDiagLine() {
    if (_boardAgePolls.isEmpty) return 'VEH boardAge@poll -';
    final doomed = _boardAgePolls.where((a) => a > 15).length;
    final worst = _boardAgePolls.reduce((a, b) => a > b ? a : b);
    return 'VEH boardAge@poll ${_boardAgePolls.join(",")} '
        'max ${worst}s freeze-bound $doomed/${_boardAgePolls.length}';
  }

  Widget _stopDiagnosticsOverlay(ThemeData theme) {
    final center = _lastFetchCenter;
    final controller = _controller;
    final style = _style;

    // Whether the layer for a stop type actually renders at the first such
    // stop's screen pixel — 'ok' drawn, 'MISS' built-but-not-drawn, '-' none.
    String renders(String label, List<Feature<Point>> pts) {
      if (pts.isEmpty) return '$label:-';
      if (controller == null) return '$label:?';
      try {
        final p = pts.first.geometry!.position;
        final off = controller.toScreenLocation(
          Geographic(lon: p.x, lat: p.y),
        );
        final drawn = controller
            .queryLayers(off)
            .any((q) => _isStopLayer(q.layerId));
        return '$label:${drawn ? 'ok' : 'MISS'}';
      } catch (_) {
        return '$label:err';
      }
    }

    // The imperative stop layers actually on the map right now (should be 8).
    // `getLayerIds` is the only style read that surfaces them; guard hard.
    var glLayers = 'style=null';
    if (style != null) {
      try {
        // ignore: invalid_use_of_visible_for_testing_member
        final allIds = style.getLayerIds();
        final ids = allIds.where(_isStopLayer).map(_glLayerLabel).toList();
        glLayers = ids.isEmpty ? 'NONE' : ids.join(' ');
      } catch (_) {
        glLayers = 'err';
      }
    }

    final lines = <String>[
      'STOP DIAGNOSTICS (staging)',
      'zoom ${_currentZoom.toStringAsFixed(2)}  minStops $_minStopsZoom  indiv $_individualZoom',
      // The gates that decide whether ANY stop layer is built/drawn.
      'imagesReady $_imagesReady  stopLayers $_stopLayersAdded  style ${style != null}  focus ${_focus != null}',
      center == null
          ? 'last fetch: none yet (zoom < $_minStopsZoom?)'
          : 'fetch @ ${center.latitude.toStringAsFixed(5)},${center.longitude.toStringAsFixed(5)} r=${_lastFetchRadius.toStringAsFixed(0)}m',
      'returned ${_areaStops.length} stops (cap 50)',
      'markers: bus ${_busPts.length} tram ${_tramPts.length} '
          'trolley ${_trolleyPts.length} mixed ${_mixedPts.length} '
          'cluster ${_clusterPts.length}',
      'GL layers on map: $glLayers',
      // Does each type's layer actually draw at its first stop's pixel?
      'renders: ${renders('bus', _busPts)} ${renders('tram', _tramPts)} '
          '${renders('trolley', _trolleyPts)} ${renders('mixed', _mixedPts)}',
      // Vehicle-animation state (on-demand context / follow diagnosis).
      'VEH onDemand $_onDemand stopCtx ${_stopContextId ?? "-"} '
          'following $_following sel ${_selectedVehicleKey ?? "-"}',
      'VEH tracks ${_vehAnimator.tracks.length} '
          'timed ${_vehAnimator.tracks.values.where((t) => t.timed != null).length} '
          'movingNow ${_vehAnimator.tracks.keys.where(_vehAnimator.hasMotion).length} '
          'pending ${_vehAnimator.hasPendingMotion}',
      // `animV` used to sit here. It's the legacy ease controller's progress,
      // which only moves markers that have NO timing plan — so next to `timed
      // N` it reads as a symptom ("the animation is stuck at 0") while being
      // simply unused. Dropped; `plan`/`vel` below is the real motion read-out.
      'VEH ticker ${_vehTicker?.isActive ?? false} '
          'paused $_paused refreshTicks $_refreshTicks pumps $_pumpCount',
      'VEH lastCtx ageSec ${_lastCtxBoardAgeSec ?? "-"} '
          'live $_lastCtxLive withTraj $_lastCtxWithTraj',
      // Catch-up instrumentation for the followed vehicle: how far behind the
      // plan's predicted-now spot the marker is (gap) and how fast it's moving
      // to close it (vel). A smooth catch-up shows the gap easing to ~0 with vel
      // ramping up then settling to the plan speed — never a spike then a crawl.
      _catchUpDiagLine(),
      _boardAgeDiagLine(),
      _fixAgeDiagLine(),
    ];

    return SafeArea(
      child: Align(
        alignment: Alignment.topLeft,
        child: IgnorePointer(
          child: Container(
            margin: const EdgeInsets.only(top: 72, left: 8, right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final line in lines)
                  Text(
                    line,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      height: 1.35,
                      fontFamily: 'monospace',
                    ),
                  ),
              ],
            ),
          ),
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
    // The follow bar must appear the instant follow starts, from ANY source —
    // not only once the route shape has loaded (async, and it sets `_focus`).
    // A follow entered from the persistent Nearby sheet used to leave `_focus`
    // null until the shape landed, so the bar (and its × exit) never showed and
    // the user was trapped. So derive the badge from the focused line when it's
    // loaded, otherwise from the followed vehicle's own track.
    final focus = _focus;
    final key = _selectedVehicleKey;
    final track = key == null ? null : _vehAnimator.trackFor(key);
    final line = focus?.line ?? track?.line ?? '';
    final type = focus?.type ?? track?.type ?? VehicleType.bus;
    final subtitle =
        focus != null ? '${focus.origin} → ${focus.destination}' : null;
    final scheduled = focus?.scheduled ?? false;
    final color = vehicleColor(type);
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
                      vehicleGlyph(type, size: 16, color: Colors.white),
                      const SizedBox(width: 6),
                      Text(
                        line,
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
                        // Route terminals once the shape is loaded; until then
                        // (or on a shape that failed to load) a neutral label so
                        // the bar is still complete and exitable.
                        subtitle ?? AppLocalizations.of(context).followingVehicle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium,
                      ),
                      // A tapped schedule-predicted object honestly says so — its
                      // position is a GTFS estimate, not a live fix.
                      if (scheduled)
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
                  onPressed: _closeVehicleContext,
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
                // Hides itself — gap and all — while the flag is off, so the
                // killswitch leaves this stack exactly as production has it.
                const VehicleModeToggle(),
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

  // No declarative layers. The ambient stop layers AND the focused-line view are
  // both added imperatively (see [_addStopLayers] / [_syncFocusLayers]) to dodge
  // maplibre 0.3.5's positional LayerManager, which reconciles the declarative
  // list by index with unawaited add/remove and deterministically dropped whole
  // layers (a pure-bus stop lost its pin on prod). Going imperative also lets the
  // focus route be inserted *below* the vehicle symbols (belowLayerId), so it
  // never paints over the coin being followed. "My position" is a WidgetLayer
  // marker (in build) so it can't be culled at low zoom (X2).
  List<Layer> _buildLayers() => const [];

  /// (Re)build the focused-line layers imperatively: the route line (in its type
  /// colour) and that line's own stops, both inserted *below* the vehicle badge
  /// so the followed coin stays on top. Removes them when there's no focus. The
  /// route layer is recreated per focus because its colour is baked into the
  /// layer paint. Best-effort: a failure just leaves the route un-highlighted.
  Future<void> _syncFocusLayers() async {
    final style = _style;
    if (style == null) return;
    // Tear down any previous focus layers first (colour/route may have changed).
    if (_focusLayersAdded) {
      for (final id in const [_focusRouteLayerId, _focusStopsLayerId]) {
        try {
          await style.removeLayer(id);
        } catch (_) {}
        try {
          await style.removeSource(_stopSourceId(id));
        } catch (_) {}
      }
      _focusLayersAdded = false;
    }
    final focus = _focus;
    if (focus == null) return;
    final below = focusInsertBelowLayerId(vehicleLayersAdded: _vehLayerAdded);
    try {
      if (focus.polyline.length >= 2) {
        final srcId = _stopSourceId(_focusRouteLayerId);
        await style.addSource(
          GeoJsonSource(id: srcId, data: _focusRouteGeoJson(focus)),
        );
        final line = PolylineLayer(
          polylines: const [],
          color: vehicleColor(focus.type),
          width: 5,
        );
        await style.addLayer(
          LineStyleLayer(
            id: _focusRouteLayerId,
            sourceId: srcId,
            layout: line.getLayout(),
            paint: line.getPaint(),
          ),
          belowLayerId: below,
        );
      }
      final stopsSrc = _stopSourceId(_focusStopsLayerId);
      await style.addSource(
        GeoJsonSource(id: stopsSrc, data: _focusStopsGeoJson(focus)),
      );
      final pin = MarkerLayer(
        points: const [],
        iconImage: MapImages.forStop(focus.type),
        iconSize: _iconSize,
        iconAllowOverlap: true,
      );
      await style.addLayer(
        SymbolStyleLayer(
          id: _focusStopsLayerId,
          sourceId: stopsSrc,
          layout: pin.getLayout(),
          paint: pin.getPaint(),
        ),
        belowLayerId: below,
      );
      _focusLayersAdded = true;
    } catch (_) {
      _focusLayersAdded = false;
    }
  }

  String _focusRouteGeoJson(_LineFocus focus) => jsonEncode({
    'type': 'FeatureCollection',
    'features': [
      {
        'type': 'Feature',
        'geometry': {
          'type': 'LineString',
          // focus.polyline is [lat, lon]; GeoJSON is [lon, lat].
          'coordinates': [
            for (final p in focus.polyline) [p[1], p[0]],
          ],
        },
        'properties': const <String, dynamic>{},
      },
    ],
  });

  String _focusStopsGeoJson(_LineFocus focus) => jsonEncode({
    'type': 'FeatureCollection',
    'features': [
      for (final s in focus.stops)
        {
          'type': 'Feature',
          'geometry': {
            'type': 'Point',
            'coordinates': [s.lon, s.lat],
          },
          // Only stopId (the tap handler looks the name up) — jsonEncode escapes
          // it correctly regardless, but the name isn't needed here.
          'properties': {'stopId': s.stopId},
        },
    ],
  });

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
                          onPressed: () {
                            setState(() {
                              _pinnedPlace = null;
                              _pinnedPlaceLabel = null;
                            });
                            _pushStopSources(); // clear the pinned-place marker
                          },
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
