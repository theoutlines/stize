part of '../home_map_screen.dart';

// The home map's state, grouped by area. The screen holds one instance of
// each; the part files read and write them by name (`_jam.modeOn`,
// `_stops.area`), so it is visible which area a piece of code touches.

/// Ids of the imperative map layers the home map adds.
abstract final class _LayerIds {
  static const rails = 'stg-stops-rails';
  static const cluster = 'stg-stops-cluster';
  static const bus = 'stg-stops-bus';
  static const tram = 'stg-stops-tram';
  static const trolley = 'stg-stops-trolley';
  static const mixed = 'stg-stops-mixed';
  static const fav = 'stg-stops-fav';
  static const place = 'stg-stops-place';
  // Focused-line view (route highlight + that line's stops). Added imperatively
  // — like the stop layers, and unlike the old declarative path — so they can be
  // inserted *below* the moving-object symbol layers (belowLayerId), keeping the
  // route from painting over the vehicle coin the user is following.
  static const focusRoute = 'stg-focus-route';
  static const focusStops = 'stg-focus-stops';
  // Tram-jam ("stalled segment") overlay (feature/jam-detection, flag-gated). An
  // amber, pulsing alert: a thin segment along the route where the geometry gate
  // passes, plus a soft glow on every affected stop (always — the glow is the
  // primary visual, not a fallback). Off-shape lines get glow only. Its OWN state,
  // separate from the animator's "looks stuck". The pulse is a cheap opacity
  // animation (data-driven `['get','opacity']`, tiny source re-push) driven by a
  // timer that runs ONLY while a jam exists — an empty map spins nothing (thermal).
  static const jamSegment = 'stg-jam-segment';
  static const jamGlow = 'stg-jam-glow';
  static const browseDot = 'stg-browse-dot';
  static const emptyFeatureCollection =
      '{"type":"FeatureCollection","features":[]}';
}

/// Tram-jam overlay and jam mode (home_map_jams.dart).
class _JamState {
  bool layersAdded = false;
  bool processing = false; // guards the async shape-load reentrancy
  // What the overlay draws (segments, glows, badged vehicles) and its pulse.
  JamOverlay overlay = JamOverlay.empty;
  // Direction route_id → its shape path + stop id→coord map (for segment + glow).
  final Map<String, JamShape?> shapeCache = {};
  Timer? pulseTimer; // runs only while a jam is shown
  bool modeOn = false; // the jam-mode map toggle (fit to all active jams)
}

/// The coverage heatmap backdrop (feature-flagged, shown zoomed out).
class _CoverageState {
  // Coverage heatmap overlay (feature-flagged): a passive background shown when
  // zoomed out, in place of the stop clusters. The GeoJSON is added lazily on
  // the first zoom-out past the threshold (never fetched if the user stays
  // zoomed in). See core/coverage_heatmap.dart for the shared source/style.
  bool enabled = false; // remote flag, read in build
  bool added = false; // source+layer present in the current style
  bool active = false; // hysteresis state for the mount decision
  // Coverage mode (the menu's Coverage level): the map hides stops and
  // vehicles; CoverageTracesLayer draws the routes over it.
  bool mode = false;
  bool veil = false; // the grey veil over the basemap is on the map
  Geographic? preCenter; // camera to return to when the level closes
  double? preZoom;
}

/// Nearby around a point on the map instead of around you, and its centre dot.
class _BrowseState {
  // Nearby around a point on the map instead of around you (owner,
  // 2026-11-25): your dot leaves its fix and sits on the visible centre while
  // you drag; null = around you.
  ll.LatLng? point;
  bool lifted = false;
  // The centre point is a map layer, not a Flutter overlay: an overlay that
  // appears over the map as a drag starts broke the drag on iPhone Safari, and
  // an overlay tied to the visible centre slid over the map with the sheet
  // (owner, 2026-11-26).
  bool dotAdded = false;
  bool dotShown = false;
  Timer? dropTimer;
  Timer? idleTimer;
  DateTime? dropAt;
}

/// Stops for the visible area, their marker features and the stop layers
/// (home_map_stops.dart).
class _StopsState {
  // Imperative stop layers. maplibre 0.3.5's declarative `MapLibreMap.layers`
  // reconciles the list *positionally* (`maplibre-layer-$index`) with unawaited
  // add/remove calls; when the set of stop layers changes (types coming/going by
  // area, tram rails loading async) it deterministically drops some — on prod a
  // pure-bus stop lost its whole marker layer, so it had no clickable pin. So the
  // stop layers are managed imperatively instead: added once per style load, then
  // only their GeoJSON source data changes (exactly like the coverage layer), so
  // the buggy LayerManager never touches them. Focus mode still uses the
  // declarative list (a clean, user-initiated 2-layer swap).
  bool layersAdded = false; // layers+sources present in the current style
  bool layersAdding = false; // add in flight (guards the ready flag window)
  // Stops loaded for the current viewport, and the derived marker features.
  List<Stop> area = [];
  ll.LatLng? lastFetchCenter;
  double lastFetchRadius = 0;
  int requestSeq = 0;
  List<Feature<Point>> clusterPts = [];
  List<Feature<Point>> busPts = [];
  List<Feature<Point>> tramPts = [];
  List<Feature<Point>> trolleyPts = [];
  List<Feature<Point>> mixedPts = [];
  // Tram rail geometry (C2), fetched once from the tram lines' GTFS shapes and
  // drawn as thin lines under everything else.
  bool railsRequested = false;
  List<List<List<double>>> rails = [];
  Timer? pushTimer;
  Timer? railsTimer;
}

/// The desktop search session (home_map_search.dart).
class _SearchState {
  /// Search mode and the once-per-session log (see [SearchSession]).
  final SearchSession session = SearchSession();
}

/// Following one vehicle: where it was opened from, the camera that tracks it,
/// where to return (home_map_follow.dart).
class _FollowState {
  // Follow mode: the camera keeps the selected vehicle centred in the visible
  // area (right of the panel / above the sheet) as it moves — the Google Maps
  // pattern. Any manual pan/zoom gesture breaks it (the marker and highlight
  // stay). [pacer] gates the per-tick centring so an entry fly-to settles
  // first, and paces it. `_selfCameraMove` marks a camera move the app itself issued,
  // so the move-start it triggers isn't mistaken for a user gesture and doesn't
  // break follow (the classic self-cancelling-follow bug).
  bool active = false;

  /// When the camera may track and how often it moves (see [FollowPacer]).
  final FollowPacer pacer = FollowPacer();
  // The followed line has no route geometry in our GTFS (a suburban / non-GSP
  // carrier like "Ada 4"): follow degrades to raw GPS — no route line, no route
  // ahead, an honest label (owner R4 #2).
  bool noRouteData = false;
  // A brief grace window after a resume during which a camera-move event does
  // NOT break follow. Returning to a hidden tab re-lays-out the MapLibre-web
  // canvas, which surfaces a camera event flagged as a user gesture even though
  // the user did nothing — that used to silently drop follow, leaving the marker
  // to wander off-screen with the selection still live. The programmatic follow
  // pan that re-centres on the re-anchored (jumped) marker also happens inside
  // this window, so it can't be mistaken for a manual pan either.
  DateTime? resumeGuardUntil;
  // Where the camera sat when the vehicle context was entered, restored on close
  // so the user lands back where they came from (the stop, or the pre-focus
  // viewport) instead of adrift wherever the vehicle wandered.
  Geographic? preCenter;
  double? preZoom;
  // ETA anchoring for the followed vehicle's worded route (owner R1 #5), taken
  // from the arrival it was opened from; null for a marker-tap follow (the route
  // then extrapolates from position alone).
  int? stopsRemaining;
  int? etaMinutes;
  ll.LatLng? boardStop; // the stop the follow was opened from ("your stop")
  // That stop's id: its board feeds the follow head's switcher between the
  // vehicles of the same line and direction (owner, 2026-11-25, S1).
  String? boardStopId;
  // Rebuild the desktop vehicle panel ~1/s while following, so its worded route
  // ("Rest of the route") slides as the vehicle progresses along the plan — same
  // progress the marker uses (its plan position), just re-read (owner R3 #3).
  DateTime? lastPanelRefreshAt;
}

/// Route shapes per line for the moving vehicles, and the last vehicle set to
/// re-apply when a shape arrives late (home_map_vehicles.dart).
class _ShapeState {
  /// Route geometry per direction route_id or line number (see
  /// [RouteShapeCache]): fetched once, a failure retried after 30 s.
  final RouteShapeCache cache = RouteShapeCache();

  // The last vehicle set handed to the animator, kept so a route shape that
  // finishes loading *after* a sync can be re-applied immediately (upgrading a
  // vehicle from its raw GPS fix onto the real road geometry)
  // instead of waiting for the next 30s poll. Debounced by [resyncTimer]
  // so a burst of shape loads (panning brings in many lines) coalesces into one
  // re-sync.
  List<AreaVehicle> lastShown = const [];
  Timer? resyncTimer;
}

/// Numbers the staging diagnostics box shows (home_map_diagnostics.dart).
class _DiagState {
  // Staging-overlay diagnostics for the on-demand context (debugPrint is stripped
  // in release web, so these surface on the on-screen diagnostics panel instead).
  int? ctxBoardAgeSec; // freshness of the last context board applied
  int ctxLive = 0; // live rows in it
  int ctxWithTraj = 0; // how many carried a timing plan
  // Board age at the moment each poll landed, most recent last (last 12).
  //
  // This is the number that decides whether an *elastic* stop dwell is worth
  // building. The marker stops predicting once a board passes the 45 s gate, and
  // the next board is only 30 s away — so a poll that lands carrying a board
  // already older than 15 s means the marker will freeze before its relief
  // arrives, for (age + 30 − 45) seconds. Under 15 s it never freezes at all.
  // The backend caps board age at 40 s, so the whole question is where in 0..40
  // these samples actually fall — hence a short history rather than one value.
  final List<int> boardAgePolls = [];
  int refreshTicks = 0; // 30s refresh ticks fired
  int pumpCount = 0; // vehicle-driver frames pumped
  /// Diagnostics for the follow camera (owner R3 #1): the marker's pixel before
  /// the move, the visible-area-centre target pixel, the applied inset and the
  /// resulting camera centre. Surfaced on the staging overlay.
  String followCam = 'FOLLOW cam -';

  /// Route-ahead progress diagnostic (owner R4 #1), set in [_buildUpcomingStops].
  String routeAhead = 'ROUTE ahead -';
}
