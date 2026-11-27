import 'package:stize/core/design/stize_text.dart';
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
import '../../core/search.dart';
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
import '../../core/map/jam_overlay.dart';
import '../../core/map/route_shape_cache.dart';
import '../../core/map/stop_markers.dart';
import '../../core/vehicle_arrangement.dart';
import '../../core/vehicle_diagnostics.dart';
import '../../core/vehicle_track_animator.dart';
import '../../data/analytics/event_logger.dart';
import '../../data/compass/compass.dart';
import '../../data/location/location_service.dart';
import '../../domain/models/area_vehicle.dart';
import '../../domain/models/arrival.dart';
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
import '../widgets/stretch_card_list.dart';
import '../widgets/context_shell.dart';
import '../widgets/stop_header_actions.dart';
import '../widgets/fleet_model_card.dart';
import '../widgets/follow_model.dart';
import '../widgets/follow_view.dart';
import '../widgets/sheet_chrome.dart';
import '../widgets/nearby_sheet.dart';
import '../widgets/nearby_view.dart';
import '../widgets/stop_board.dart';
import '../widgets/stop_result_tile.dart';
import '../../core/app_links.dart';
import '../../core/external_link.dart';
import 'settings_screen.dart';
import '../widgets/drawer_footer.dart';
import '../widgets/guide/belgrade_guide.dart';
import '../widgets/level_header.dart';
import '../widgets/map/diagnostics_overlay.dart';
import '../widgets/map/follow_bar.dart';
import '../widgets/map/map_controls.dart';
import '../widgets/map_search_pill.dart';
import '../widgets/my_stops_list.dart';
import '../widgets/vehicle_icon.dart';
import '../widgets/vehicle_mode_toggle.dart';
import '../widgets/vehicle_view.dart';
import 'home_map/search_session.dart';
import 'home_map/sheet_levels.dart';
import 'map_screen_args.dart';

part 'home_map/home_map_layers.dart';
part 'home_map/home_map_location.dart';
part 'home_map/home_map_geometry.dart';
part 'home_map/home_map_context.dart';
part 'home_map/home_map_search.dart';
part 'home_map/home_map_panels.dart';
part 'home_map/home_map_jams.dart';
part 'home_map/home_map_diagnostics.dart';
part 'home_map/home_map_focus.dart';
part 'home_map/home_map_follow.dart';
part 'home_map/home_map_stops.dart';
part 'home_map/home_map_vehicles.dart';
part 'home_map/home_map_sync.dart';
part 'home_map/home_map_view.dart';
part 'home_map/home_map_types.dart';
part 'home_map/home_map_state.dart';
part 'home_map/home_map_lifecycle.dart';
part 'home_map/home_map_levels.dart';
part 'home_map/home_map_pill.dart';

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
const _meEaseDuration = StizeMotion.camera;
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

  final _diag = _DiagState();

  final _shapes = _ShapeState();

  final _follow = _FollowState();

  final _search = _SearchState();

  final _stops = _StopsState();

  final _browse = _BrowseState();

  final _cov = _CoverageState();

  final _jam = _JamState();

  MapController? _controller;
  StyleController? _style;
  ColorScheme _scheme = const ColorScheme.light();
  Brightness? _styleBrightness;
  bool _imagesReady = false;

  bool _focusLayersAdded = false;
  String?
  _focusLayerError; // last focus-layer add failure, for the staging overlay

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

  // Vehicle marker layout (fan at stops, dim when crossing), eased across
  // writes so nothing snaps. See [VehicleArranger].
  final VehicleArranger _vehArranger = VehicleArranger();
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

  // ---- User's own live position --------------------------------------------
  // The marker is driven by a continuous position stream (distance-filtered,
  // not tied to the transport-polling timer). It eases toward each fresh fix
  // over [_meEaseDuration]; between fixes the ticker is idle (no repaints).
  late final AnimationController _meAnim;
  ll.LatLng? _meFrom; // where the marker eased from
  ll.LatLng? _meTo; // the latest fix (null = no marker shown)

  /// The guide was opened on this device (ends the first-launch strip).
  bool _guideSeen = true;
  StreamSubscription<geo.Position>? _positionSub;

  /// The compass, for the location dot's heading cone (DS LocationDot). Runs
  /// alongside the location stream; [_heading] holds the last heading the cone
  /// was drawn at (null = no compass, no cone).
  StreamSubscription<double>? _compassSub;
  final ValueNotifier<double?> _heading = ValueNotifier<double?>(null);
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

  // A camera target known before the map was ready; set in [_onMapCreated].
  Geographic? _pendingCenter;
  double? _pendingZoom;

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
  //   C — vehicle context (`_follow.active` + `_focus`): one vehicle is followed
  //       with its direction's route highlighted. Works at BOTH flag values.
  bool _onDemand = false;
  // A stop arrivals sheet is currently up. The bottom UI (Nearby panel / search)
  // is hidden while it is, so the two never overlap (#7).
  /// The one mobile sheet: the host drives its height (open a level at half,
  /// snap back to peek after a swipe-close). It is never swapped for another
  /// sheet, so its height stays continuous across levels.
  final _sheetCtl = DraggableScrollableController();

  // One-scroll home (mobile): the search pill on the map.
  final _pillCtl = TextEditingController();
  final _pillFocus = FocusNode();
  bool _pillActive = false;
  // Desktop: the same pill above the panel is in its search state.
  bool _deskSearchActive = false;
  final _topButtonsKey = GlobalKey();
  double _topButtonsH = 120; // measured after layout
  bool _wasOneScrollRoot = true;
  double? _bodyHeight; // laid-out Scaffold body height (keyboard-aware)

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
  final _levels = SheetLevelStack();
  String? get _slotStopId => _levels.topStop?.id;

  String? get _slotStopName => _levels.topStop?.name;

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

  String? _stopContextId; // stop feeding the markers (state B); null = not in B
  ProviderSubscription<AsyncValue<ArrivalsBoard>>? _stopArrivalsSub;
  // The stop context to restore when a vehicle context opened *from* a stop is
  // closed (return to B); null → fall back to A.
  String? _returnToStopId;

  static const _followEngageFallback = Duration(milliseconds: 1200);
  bool _selfCameraMove = false;
  // Where the camera sat before opening a stop sheet (which pans the stop up
  // above the sheet). Restored when the sheet closes back to browsing, so the
  // return is symmetric to the open.
  Geographic? _preStopCameraCenter;
  double? _preStopCameraZoom;

  @override
  void initState() {
    super.initState();
    _pillCtl.addListener(_onPillQuery);
    // Desktop pill: leaving an empty field turns it back into the pill.
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus &&
          _searchController.text.isEmpty &&
          _deskSearchActive &&
          mounted) {
        setState(() => _deskSearchActive = false);
      }
    });
    WidgetsBinding.instance.addObserver(this);
    guideOpenedBefore().then((v) {
      if (mounted && v != _guideSeen) setState(() => _guideSeen = v);
    });
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
    _stops.pushTimer?.cancel();
    _stops.railsTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _positionSub?.cancel();
    _compassSub?.cancel();
    _heading.dispose();
    _meAnim.dispose();
    _search.debounce?.cancel();
    _stopArrivalsSub?.close();
    _vehiclesTimer?.cancel();
    _shapes.resyncTimer?.cancel();
    _jam.pulseTimer?.cancel();
    _browse.dropTimer?.cancel();
    _browse.idleTimer?.cancel();
    _stopVehDriver();
    _vehTicker?.dispose();
    _vehAnim.removeStatusListener(_onVehAnimStatus);
    _vehAnim.dispose();
    _searchController.dispose();
    _focusNode.dispose();
    _pillCtl.dispose();
    _pillFocus.dispose();
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

  // ---- Vehicle-layer driver (runs only while something is actually moving) --

  // ---- Location -------------------------------------------------------------

  bool _autoprompted = false;

  // ---- Stops for the visible area ------------------------------------------

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
  static const _cameraEaseDuration = StizeMotion.camera;
  static const double _cameraEaseSpeed = 0.55;

  /// Re-settle the camera after the overlap geometry changed (panel width /
  /// breakpoint / sheet detent / sheet open-close) — the Google-Maps feel: a
  /// short ease that keeps the focus centred in the new visible area, or, with
  /// no focus, shifts the free-browse scene by the geometry delta (open the
  /// panel → the city slides right by half the panel, it isn't covered).
  static const _geometryEaseDuration = StizeMotion.fast;

  // Follow re-centres at ~15fps, not every render frame. Panning the whole map
  // with a jumpTo on every one of ~60 fps thrashes the tile/label renderer and
  // the neighbouring GL layers visibly jitter (pins, street labels) against a
  // moving camera. At 15fps the per-step drift of the followed marker is
  // sub-pixel at follow zoom, so it still reads as screen-fixed, but the map is
  // steady between steps. (Matches the conservative sampler cadence used
  // elsewhere.)
  static const _followInterval = Duration(milliseconds: 66);

  // ---- Build ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    _syncMapState(context);
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final size = MediaQuery.sizeOf(context);

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
        // The Stack must always fill the screen. It used to get its height
        // from the tallest non-positioned child (the top-button column);
        // once that column hugged its buttons, the desktop map and panel were
        // cut at ~200px (owner, 2026-11-23).
        body: SizedBox.expand(
          // The real body height (it shrinks by the keyboard): the search pill
          // rides on the sheet in THIS frame, not the screen's (owner, iPhone:
          // with the keyboard up the pill landed on the first card).
          child: LayoutBuilder(
            builder: (context, box) {
              _bodyHeight = box.maxHeight;
              return Stack(
                children: [
                  _mapView(brightness),
                  // Round action buttons at the top: menu (left), recenter (right).
                  _pushedTopButtons(theme, size),
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
                    const MapZoomHint(),
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
                  else if (_lineOnlyFocus)
                    _focusPanel()
                  else
                    NearbySheet(
                      controller: _sheetCtl,
                      // One scroll is the Nearby root only; a level (Settings, a
                      // stop, a followed vehicle, ...) is a regular draggable
                      // sheet again.
                      oneScroll: _oneScrollRoot,
                      // The follow card carries the grabber on its own colour.
                      headerOwnsHandle: _selectedVehicleKey != null,
                      maxSize: _oneScrollMax(size),
                      searchController: _pillCtl,
                      searchActive: _pillActive,
                      // A level (stop / My stops / model) replaces Nearby inside this
                      // same sheet; null = Nearby.
                      levelHeader: _slotNavRow(l10n),
                      banner: _guideBanner(l10n),
                      levelBody: _oneScrollRoot
                          ? null
                          : (sc) => _slotContent(l10n, scrollController: sc),
                      userLocation: _browse.point ?? _meTo,
                      locationDenied: _locationDenied,
                      active: _tabActive && _appResumed,
                      onEnableLocation: _recenterOnMe,
                      onTapGroup: _focusNearbyVehicle,
                      // Unified global search in the nearby sheet: selecting a global
                      // stop / line opens that context exactly like the desktop search.
                      onSelectStop: (stop) =>
                          _openStop(stop, source: Ev.srcSearch),
                      onSelectLine: _openLine,
                      // Feed the mobile sheet height to the geometry owner so a followed
                      // vehicle is kept above the sheet as it's dragged (R2 #2).
                      onHeightChanged: _onMobileSheetHeight,
                    ),
                  // Always mounted (parked off-screen outside the Nearby root): adding
                  // and removing its PointerInterceptor platform view left stale
                  // copies of the sheet painted on iOS Safari (owner, 2026-11-23).
                  if (!_panelActive) _searchPill(l10n, size),
                  // The sheet's close, outside it: rides above its right edge.
                  if (!_panelActive && !_lineOnlyFocus) _mapSheetClose(size),
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
              );
            },
          ),
        ),
      ),
    );
  }

  // ---- Context panel (desktop-only) rendering ------------------------------

  /// The desktop panel overlay + the conditional "Back to vehicle" pill. Only
  /// built when [_panelActive] (flag ON *and* wide); mobile never reaches here.
  // The panel collapse slide/tab share one short duration + curve (owner A#2:
  // ~200ms, no fancy physics).
  static const _panelCollapseDuration = StizeMotion.panelSlide;
  static const _panelCollapseCurve = StizeMotion.inOut;

  // Gap between the search island and the panel island (and, on staging, between
  // the panel island and the diagnostics overlay) — one value so they match.
  static const double _kIslandGap = 8.0;

  // ---- Tram-jam overlay -----------------------------------------------------

  // Widget-rendered marker images are captured at device pixel ratio, so they
  // come out larger than their logical size — scale down to taste.
  static const _iconSize = 0.5;
}
