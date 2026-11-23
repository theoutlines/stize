import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform;
import 'package:flutter/material.dart';
import '../../core/design/stize_icons.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart' as geo show Position;
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:maplibre/maplibre.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../../core/api_config.dart';
import '../../core/context_slot.dart';
import '../../core/coverage_heatmap.dart';
import '../../core/design/stize_tokens.dart';
import '../../core/fleet_matcher.dart';
import '../../core/follow_camera.dart';
import '../../core/fps_overlay.dart';
import '../../core/hit_test.dart';
import '../../core/map_refresh.dart';
import '../../core/nearby_focus.dart';
import '../../core/live_position.dart';
import '../../core/jam_geometry.dart';
import '../../core/map_style.dart';
import '../../core/map_support.dart';
import '../../core/moving_object_layer.dart';
import '../../core/route_path.dart';
import '../../core/user_location_tracker.dart';
import '../../core/vehicle_map_mode.dart';
import '../../core/vehicle_route.dart';
import '../../core/vehicle_track_animator.dart';
import '../../data/analytics/event_logger.dart';
import '../../data/location/location_service.dart';
import '../../domain/models/area_vehicle.dart';
import '../../domain/models/arrival.dart';
import '../../domain/models/favorite_stop.dart';
import '../../domain/models/geocode_result.dart';
import '../../domain/models/jam.dart';
import '../../domain/models/line_info.dart';
import '../../domain/models/pinned_line.dart';
import '../../domain/models/nearby_arrival.dart';
import '../../domain/models/route_shape.dart';
import '../../domain/models/stop.dart';
import '../../domain/models/vehicle_source.dart';
import '../../domain/models/vehicle_type.dart';
import '../../l10n/app_localizations.dart';
import '../providers/providers.dart';
import '../widgets/context_shell.dart';
import '../widgets/fleet_model_card.dart';
import '../widgets/nearby_sheet.dart';
import '../widgets/nearby_view.dart';
import '../widgets/stop_board.dart';
import '../widgets/level_header.dart';
import '../widgets/my_stops_list.dart';
import '../widgets/vehicle_icon.dart';
import '../widgets/vehicle_mode_toggle.dart';
import '../widgets/vehicle_view.dart';
import 'map_screen_args.dart';

part 'home_map/home_map_layers.dart';
part 'home_map/home_map_location.dart';
part 'home_map/home_map_geometry.dart';
part 'home_map/home_map_context.dart';
part 'home_map/home_map_search.dart';
part 'home_map/home_map_panels.dart';
part 'home_map/home_map_jams.dart';

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
  /// the user is on another section).
  final bool active;

  @override
  ConsumerState<HomeMapScreen> createState() => _HomeMapScreenState();
}

class _HomeMapScreenState extends ConsumerState<HomeMapScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  /// setState for the part-file extensions (setState is @protected).
  void _setState(VoidCallback fn) => setState(fn);

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
  bool _stopLayersAdding =
      false; // add in flight (guards the ready flag window)
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
  String?
  _focusLayerError; // last focus-layer add failure, for the staging overlay
  static const _emptyFeatureCollection =
      '{"type":"FeatureCollection","features":[]}';

  // Tram-jam ("stalled segment") overlay (feature/jam-detection, flag-gated). An
  // amber, pulsing alert: a thin segment along the route where the geometry gate
  // passes, plus a soft glow on every affected stop (always — the glow is the
  // primary visual, not a fallback). Off-shape lines get glow only. Its OWN state,
  // separate from the animator's "looks stuck". The pulse is a cheap opacity
  // animation (data-driven `['get','opacity']`, tiny source re-push) driven by a
  // timer that runs ONLY while a jam exists — an empty map spins nothing (thermal).
  static const _jamSegmentLayerId = 'stg-jam-segment';
  static const _jamGlowLayerId = 'stg-jam-glow';
  bool _jamLayersAdded = false;
  bool _jamsProcessing = false; // guards the async shape-load reentrancy
  List<List<ll.LatLng>> _jamSegments = const []; // amber polylines to draw
  List<ll.LatLng> _jamGlowStops = const []; // affected-stop points to glow
  Set<String> _jammedGarages = const {}; // off-shape jams → badge these markers
  // Direction route_id → its shape path + stop id→coord map (for segment + glow).
  final Map<String, ({RoutePath? path, Map<String, ll.LatLng> stops})?>
  _jamShapeCache = {};
  Timer? _jamPulseTimer; // runs only while a jam is shown
  double _jamPulsePhase = 0; // 0..2π, advanced by the pulse timer
  static const _jamAmber = Color(0xFFE8A317);
  bool _jamModeOn = false; // the jam-mode map toggle (fit to all active jams)

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
  bool _vehLayerAdding =
      false; // add in flight (so the flag flips only once real)
  // The currently-selected vehicle's tracking key (tap highlight on the symbol
  // layer via the feature's `selected` property). Null = nothing selected.
  String? _selectedVehicleKey;

  // Vehicle-arrangement state (symbol path), eased across writes so nothing
  // snaps. `_spiderfyOffset` is the applied fan offset per key (dLat,dLon, only
  // for stationary coincident vehicles); `_crossOpacity` is the eased crossing
  // dim per key (a moving vehicle overlapping another). See [_arrangeVehicles].
  final Map<String, ll.LatLng> _spiderfyOffset = {};
  final Map<String, double> _crossOpacity = {};
  // True while a fan offset / crossing dim is still easing toward its target, so
  // the driver keeps ticking to animate the transition even when NO vehicle is
  // "playing" (a choral HOLD on a stale feed parks every marker, so nothing else
  // would keep the ticker alive and the fan would snap). Clears the moment the
  // arrangement settles → idle stays at zero frames.
  bool _fanAnimating = false;
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
  // Dedupe the `search_used` event to once per search session (reset when the
  // query is cleared) so a debounced keystroke burst logs a single event.
  bool _searchLogged = false;
  List<Stop> _resultStops = [];
  List<LineInfo> _resultLines = [];
  List<GeocodeResult> _resultPlaces = [];

  Geographic? _pinnedPlace;

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
  /// The one mobile sheet: the host drives its height (open a level at half,
  /// snap back to peek after a swipe-close). It is never swapped for another
  /// sheet, so its height stays continuous across levels.
  final _sheetCtl = DraggableScrollableController();

  // ---- Adaptive context slot (context_panel) -------------------------------
  // With the flag ON the three views (nearby → stop → vehicle) share ONE
  // surface: a persistent left panel on desktop (≥840px) or unified bottom
  // sheets on mobile (the `context_panel` flag was retired once it had been ON
  // since 2026-07; the legacy independent-sheets path is gone). `_slotStopId` is
  // the stop shown in the slot's stop view (distinct from `_stopContextId`,
  // which drives the on-demand markers and only exists in on-demand mode).
  // The panel is a DESKTOP-ONLY surface (owner R1): on the mobile breakpoint the
  // app keeps today's independent sheets untouched, so ALL new panel behaviour
  // gates on `_panelActive` (wide layout).
  bool _wideNow = false; // last-built breakpoint class (≥840)
  bool get _panelActive => _wideNow;

  /// The chain of levels open in the context slot — the mobile sheet and the
  /// desktop panel alike (owner, 2026-11-23: one sheet, levels stack inside it).
  /// Oldest first; the last is what's shown. Empty = Nearby.
  final List<_SlotLevel> _levels = [];
  String? get _slotStopId {
    final top = _levels.isEmpty ? null : _levels.last;
    return top is _StopLevel ? top.id : null;
  }

  String? get _slotStopName {
    final top = _levels.isEmpty ? null : _levels.last;
    return top is _StopLevel ? top.name : null;
  }

  // A tapped Fleet-ID vehicle shown as a leaf sub-view of the vehicle view (the
  // desktop model card lives INSIDE the panel — no second surface). Null = not
  // showing the model. (`(fleet, garageNo, type)`.)
  ({FleetVehicle fleet, String? garageNo, VehicleType type})? _slotModel;
  // Desktop collapse (the ◄/► tab). Session-only, default expanded (owner A#5):
  // no persistence — a fresh load always opens expanded. Collapsing hides the
  // panel view and drops the left map inset to zero (via `_mapInsets`); it NEVER
  // touches the state machine's current context (A#4). Entering a context while
  // collapsed re-expands (see `_expandPanelIfCollapsed`).
  bool _panelCollapsed = false;
  EdgeInsets? _appliedInsets; // last geometry the camera was settled for
  // ETA anchoring for the followed vehicle's worded route (owner R1 #5), taken
  // from the arrival it was opened from; null for a marker-tap follow (the route
  // then extrapolates from position alone).
  int? _followStopsRemaining;
  int? _followEtaMinutes;
  ll.LatLng?
  _followBoardStop; // the stop the follow was opened from ("your stop")

  String? _stopContextId; // stop feeding the markers (state B); null = not in B
  ProviderSubscription<AsyncValue<ArrivalsBoard>>? _stopArrivalsSub;
  // The stop context to restore when a vehicle context opened *from* a stop is
  // closed (return to B); null → fall back to A.
  String? _returnToStopId;

  // Follow mode: the camera keeps the selected vehicle centred in the visible
  // area (right of the panel / above the sheet) as it moves — the Google Maps
  // pattern. Any manual pan/zoom gesture breaks it (the marker and highlight
  // stay). `_followEngaged` gates the per-tick centring so an entry fly-to
  // settles first. `_selfCameraMove` marks a camera move the app itself issued,
  // so the move-start it triggers isn't mistaken for a user gesture and doesn't
  // break follow (the classic self-cancelling-follow bug).
  bool _following = false;
  bool _followEngaged = false;
  // The followed line has no route geometry in our GTFS (a suburban / non-GSP
  // carrier like "Ada 4"): follow degrades to raw GPS — no route line, no route
  // ahead, an honest label (owner R4 #2).
  bool _followNoRouteData = false;
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
    // The user switched between the map and another section in the root IndexedStack:
    // pause the stream when the map is hidden, resume when it's shown again.
    if (widget.active != _tabActive) {
      _tabActive = widget.active;
      _reconcileLocationStream();
    }
  }

  bool _appResumed = true;

  @override
  void dispose() {
    _stopPushTimer?.cancel();
    _railsTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _positionSub?.cancel();
    _meAnim.dispose();
    _searchDebounce?.cancel();
    _stopArrivalsSub?.close();
    _vehiclesTimer?.cancel();
    _shapeResyncTimer?.cancel();
    _jamPulseTimer?.cancel();
    _stopVehDriver();
    _vehTicker?.dispose();
    _vehAnim.removeStatusListener(_onVehAnimStatus);
    _vehAnim.dispose();
    _searchController.dispose();
    _focusNode.dispose();
    _sheetCtl.dispose();
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
    // a spurious "gesture" camera event that would otherwise break it. The next
    // follow tick re-centres on the marker, so a re-anchor jump just re-centres.
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
    _vehiclesTimer = Timer.periodic(
      _vehiclesRefreshInterval,
      (_) => _refreshTick(),
    );
  }

  /// The steady 30s refresh, matched to the backend cache. In on-demand mode the
  /// background aquarium is off, so instead the ACTIVE context (a stop, or a
  /// followed vehicle still tied to its stop) is kept live by re-fetching that
  /// stop's arrivals — otherwise the markers play their trajectory to the end of
  /// `as_of` and freeze forever, since the sheet's own poll dies when it closes.
  /// This runs regardless of follow, so following never freezes the data. When
  /// off-demand it drives the viewport aquarium exactly as before.
  void _refreshTick() {
    final action = mapRefreshAction(
      onDemand: _onDemand,
      stopContextId: _stopContextId,
    );
    _refreshTicks++;
    // Refresh the jam board on the same 30s cadence (no-op / no request when the
    // flag is off — the provider short-circuits to an empty board).
    if (ref.read(jamDetectionEnabledProvider)) ref.invalidate(jamsProvider);
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

  // Rebuild the desktop vehicle panel ~1/s while following, so its worded route
  // ("Rest of the route") slides as the vehicle progresses along the plan — same
  // progress the marker uses (its plan position), just re-read (owner R3 #3).
  DateTime? _lastFollowPanelRefreshAt;

  // ---- Map lifecycle --------------------------------------------------------

  // ---- Location -------------------------------------------------------------

  bool _autoprompted = false;

  // ---- Stops for the visible area ------------------------------------------

  Timer? _stopPushTimer;
  Timer? _railsTimer;

  // ---- Live vehicles in the viewport ---------------------------------------

  // ---- Follow mode ----------------------------------------------------------

  // ---- Map geometry owner (single source of truth) --------------------------
  //
  // The overlap the UI puts over the map, in logical pixels: the desktop panel
  // (left) or the mobile bottom sheet at its current detent (bottom). EVERY
  // programmatic camera move passes this as maplibre `padding`, because
  // maplibre_web forwards a `padding` on every jumpTo/flyTo — a call WITHOUT it
  // silently resets the map's *persistent* camera padding to zero. That reset,
  // every follow tick, is exactly why centring "didn't reach maplibre": the
  // next move wiped it. One owner, read by locate / follow / stop / initial /
  // deep-link / "Back to vehicle" alike, so a focused target sits in the centre
  // of the VISIBLE (unobscured) area and a free-browse scene shifts by the
  // geometry delta instead of being covered.
  double _mobileSheetPx = 0; // active mobile sheet height (from the sheet host)
  bool _wasPanelActive = false; // to catch the breakpoint flip in build

  // A deliberate deceleration-curve glide (slow-ish flyTo), so a short move
  // reads as a glide, not a teleport.
  static const _cameraEaseDuration = Duration(milliseconds: 700);
  static const double _cameraEaseSpeed = 0.55;

  /// Re-settle the camera after the overlap geometry changed (panel width /
  /// breakpoint / sheet detent / sheet open-close) — the Google-Maps feel: a
  /// short ease that keeps the focus centred in the new visible area, or, with
  /// no focus, shifts the free-browse scene by the geometry delta (open the
  /// panel → the city slides right by half the panel, it isn't covered).
  static const _geometryEaseDuration = Duration(milliseconds: 280);

  // Follow re-centres at ~15fps, not every render frame. Panning the whole map
  // with a jumpTo on every one of ~60 fps thrashes the tile/label renderer and
  // the neighbouring GL layers visibly jitter (pins, street labels) against a
  // moving camera. At 15fps the per-step drift of the followed marker is
  // sub-pixel at follow zoom, so it still reads as screen-fixed, but the map is
  // steady between steps. (Matches the conservative sampler cadence used
  // elsewhere.)
  static const _followInterval = Duration(milliseconds: 66);

  /// Route-ahead progress diagnostic (owner R4 #1), set in [_buildUpcomingStops].
  String _routeAheadDiag = 'ROUTE ahead -';

  /// Diagnostics for the follow camera (owner R3 #1): the marker's pixel before
  /// the move, the visible-area-centre target pixel, the applied inset and the
  /// resulting camera centre. Surfaced on the staging overlay.
  String _followCamDiag = 'FOLLOW cam -';

  // ---- On-demand stop context (state B) ------------------------------------

  // ---- Adaptive context slot ------------------------------------------------

  // ---- Taps -----------------------------------------------------------------

  // ---- Search ---------------------------------------------------------------

  // ---- Build ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    // "My stops" from the menu opens as a level in the same sheet / panel.
    ref.listen(myStopsRequestProvider, (prev, next) {
      if (prev == next) return;
      _openMyStopsLevel();
    });
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

    // Favourites are drawn by an imperative source now; refresh it whenever the
    // set changes (no widget rebuild needed for the markers themselves).
    ref.listen(favoriteStopLocationsProvider, (_, _) => _pushStopSources());
    ref.listen<bool>(locationAutopromptEnabledProvider, (prev, next) {
      if (next && prev != true) _autopromptLocation();
    });

    // Tram-jam overlay: whenever the jam board changes, (re)build the red segment
    // layer and the badged-vehicle set. Flag-gated (empty board when off → clears).
    ref.listen(jamsProvider, (_, next) {
      final board = next.valueOrNull;
      if (board != null) _onJamsUpdated(board);
    });

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
    final onDemand =
        ref.watch(vehicleMapModeProvider) == VehicleMapMode.onDemand;
    if (onDemand != _onDemand) {
      _onDemand = onDemand;
      WidgetsBinding.instance.addPostFrameCallback((_) => _onOnDemandChanged());
    }

    // Adaptive context slot flag (killswitch): OFF = today's independent sheets,
    // untouched. The map itself is ALWAYS the same Positioned.fill widget below
    // — only the OVERLAY (panel vs sheets) changes — so crossing the breakpoint
    // never rebuilds/recreates the map (the IndexedStack/render-cycle gotcha).
    final size = MediaQuery.sizeOf(context);
    _wideNow = isWideLayout(size.width);
    // Panel is a DESKTOP-ONLY surface: on mobile the app falls through to the
    // legacy bottom cluster, unchanged. The map is ALWAYS the same Positioned.
    // fill widget — crossing the breakpoint only swaps the overlay, never
    // rebuilds the map. Whenever the overlap GEOMETRY changes (panel width on a
    // window resize, breakpoint flip, or the mobile sheet detent), re-settle the
    // camera so the focus stays centred in the new visible area / the scene
    // shifts by the delta — one owner, [_mapInsets] (owner R3 #1/#2).
    // The nearby sheet AND the stop sheet feed their live height to the geometry
    // owner (owner R2 #3). When NEITHER is shown (desktop panel, a follow bar)
    // drop the stale value so the owner doesn't keep a phantom bottom inset.
    // (Assigned during build, no setState — the value is read just below.)
    final showingNearbySheet =
        !_panelActive && _focus == null && _selectedVehicleKey == null;
    final mobileSheetShowing = showingNearbySheet;
    if (!mobileSheetShowing && _mobileSheetPx != 0) _mobileSheetPx = 0;

    final insets = _mapInsets;
    if (insets != _appliedInsets) {
      final first = _appliedInsets == null;
      // Ease only for desktop panel-geometry / breakpoint changes. A mobile
      // sheet DRAG also moves the inset, but the 66ms follow tick re-centres a
      // followed vehicle smoothly from it — a 280ms ease every drag frame would
      // lag, so we don't fire one here for the mobile-only case.
      final easeWorthy = !first && (_panelActive || _wasPanelActive);
      _wasPanelActive = _panelActive;
      _appliedInsets = insets;
      if (easeWorthy) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _onMapGeometryChanged(),
        );
      }
    }

    // Android back / PopScope: with the panel active, back walks up the chain
    // (model → vehicle → stop → nearby) before leaving the map.
    final canPopMap = _slotModel == null && _activeView == ContextView.nearby;

    return PopScope(
      // While a context is open, Android back closes it instead of leaving.
      canPop: canPopMap,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _slotBack();
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
            // Bottom UI. On desktop with the flag ON the three views live in the
            // persistent left panel. On mobile (and flag OFF) we fall through to
            // today's independent bottom cluster, UNTOUCHED — the panel is a
            // desktop-only surface (owner R1 #1).
            if (_panelActive)
              ..._contextSlot(l10n, theme, size: size)
            // While a line is focused, a compact line panel with a close button.
            // Otherwise the experimental "Nearby" sheet when its flag is on (it
            // *replaces* the search bar), else the normal search + favourites. A
            // stop arrivals sheet suppresses the whole cluster (#7).
            else if (_focus != null || _selectedVehicleKey != null)
              _focusPanel(theme)
            else
              NearbySheet(
                controller: _sheetCtl,
                // A level (stop / My stops / model) replaces Nearby inside this
                // same sheet; null = Nearby.
                levelHeader: _slotNavRow(l10n),
                levelBody: (_levels.isEmpty && _slotModel == null)
                    ? null
                    : (sc) => _slotContent(l10n, scrollController: sc),
                userLocation: _meTo,
                locationDenied: _locationDenied,
                active: _tabActive && _appResumed,
                onEnableLocation: _recenterOnMe,
                onTapGroup: _focusNearbyVehicle,
                // Unified global search in the nearby sheet: selecting a global
                // stop / line opens that context exactly like the desktop search.
                onSelectStop: (stop) => _openStop(stop, source: Ev.srcSearch),
                onSelectLine: _openLine,
                // Feed the mobile sheet height to the geometry owner so a followed
                // vehicle is kept above the sheet as it's dragged (R2 #2).
                onHeightChanged: _onMobileSheetHeight,
              ),
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

  // ---- Context panel (desktop-only) rendering ------------------------------

  /// The desktop panel overlay + the conditional "Back to vehicle" pill. Only
  /// built when [_panelActive] (flag ON *and* wide); mobile never reaches here.
  // The panel collapse slide/tab share one short duration + curve (owner A#2:
  // ~200ms, no fancy physics).
  static const _panelCollapseDuration = Duration(milliseconds: 200);
  static const _panelCollapseCurve = Curves.easeInOut;

  // Gap between the search island and the panel island (and, on staging, between
  // the panel island and the diagnostics overlay) — one value so they match.
  static const double _kIslandGap = 8.0;

  // ---- Tram-jam overlay -----------------------------------------------------

  // Widget-rendered marker images are captured at device pixel ratio, so they
  // come out larger than their logical size — scale down to taste.
  static const _iconSize = 0.5;
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

/// A level in the context slot's chain.
sealed class _SlotLevel {
  const _SlotLevel();
}

class _StopLevel extends _SlotLevel {
  const _StopLevel(this.id, this.name);
  final String id;
  final String? name;
}

class _MyStopsLevel extends _SlotLevel {
  const _MyStopsLevel();
}
