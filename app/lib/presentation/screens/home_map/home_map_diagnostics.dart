part of '../home_map_screen.dart';

// Staging-only render diagnostics (isStaging; never in prod).

extension _MapDiagnostics on _HomeMapScreenState {
  /// True for one of the imperative stop layers — the ambient `stg-stops-*`
  /// set AND the focused-line `stg-focus-*` layers. The focus layers were
  /// silently excluded here, so the render diagnostics (GL-layers list +
  /// `renders`) never saw the focused-line stop pins at all — exactly the
  /// layer whose pins go missing during follow.
  static bool _isStopLayer(String id) =>
      id.startsWith('stg-stops-') || id.startsWith('stg-focus-');

  /// Short label for a stop layer id in diagnostics ('stg-stops-bus' → 'bus',
  /// 'stg-focus-stops' → 'focus-stops').
  String _glLayerLabel(String id) => id.startsWith('stg-stops-')
      ? id.substring('stg-stops-'.length)
      : id.startsWith('stg-')
      ? id.substring('stg-'.length)
      : id;

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
  Widget _stopDiagnosticsOverlay(ThemeData theme) {
    final key = _selectedVehicleKey;
    final timed = key == null ? null : _vehAnimator.trackFor(key)?.timed;
    final now = DateTime.now();
    final center = _lastFetchCenter;
    final controller = _controller;
    final style = _style;

    // How many of a layer's stops actually draw, counted over EVERY on-screen
    // stop — not just the first. The old check sampled `pts.first`, which is
    // usually under this panel (top-left) or off the edge, so it read MISS even
    // while pins drew: a false alarm we both chased. 'drawn/onscreen': `bus:0/6`
    // = six bus stops in view, NONE drew (a real miss); `bus:6/6` = all drew;
    // `bus:-` = no such stops; `bus:0/0offscr` = none currently in view.
    final screen = MediaQuery.sizeOf(context);
    String renderStats(String label, Iterable<({double lat, double lon})> pts) {
      final list = pts.toList();
      if (list.isEmpty) return '$label:-';
      if (controller == null) return '$label:?';
      var onscreen = 0, drawn = 0;
      for (final p in list) {
        try {
          final o = controller.toScreenLocation(
            Geographic(lon: p.lon, lat: p.lat),
          );
          if (o.dx < 0 ||
              o.dy < 0 ||
              o.dx > screen.width ||
              o.dy > screen.height) {
            continue; // off the visible map — a query there is meaningless
          }
          onscreen++;
          if (controller.queryLayers(o).any((q) => _isStopLayer(q.layerId))) {
            drawn++;
          }
        } catch (_) {}
      }
      return onscreen == 0 ? '$label:0/0offscr' : '$label:$drawn/$onscreen';
    }

    ({double lat, double lon}) fromFeature(Feature<Point> f) =>
        (lat: f.geometry!.position.y, lon: f.geometry!.position.x);

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
      // How many stops of each ambient type actually draw, over ALL on-screen
      // stops. During follow the ambient sources are emptied on purpose, so
      // these read `-`/`0/0` — look at the FOCUS render line below instead.
      'renders: ${renderStats('bus', _busPts.map(fromFeature))} '
          '${renderStats('tram', _tramPts.map(fromFeature))} '
          '${renderStats('trolley', _trolleyPts.map(fromFeature))} '
          '${renderStats('mixed', _mixedPts.map(fromFeature))}',
      // Geometry owner: the padding EVERY camera move actually sends to maplibre
      // (owner R3 #1 — prove the panel-aware inset reaches the map).
      'GEO panelActive $_panelActive sheetPx ${_mobileSheetPx.toStringAsFixed(0)} '
          'insets L${_mapInsets.left.toStringAsFixed(0)} B${_mapInsets.bottom.toStringAsFixed(0)}',
      // Follow camera: marker pixel vs visible-area-centre target + camera centre
      // (owner R3 #1 — prove vertical tracking).
      _followCamDiag,
      _routeAheadDiag,
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
      catchUpDiagLine(timed, now),
      dwellDiagLine(timed),
      stopCauseDiagLine(timed, now),
      'FOCUS layersAdded $_focusLayersAdded stops ${_focus?.stops.length ?? 0} '
          'err ${_focusLayerError ?? "-"}',
      // The real test for the followed line's stop pins: of the focus stops in
      // view, how many actually draw. `focus:0/8` with layersAdded true + err -
      // = layer & source are fine but nothing paints (image not resolved for the
      // layer, or z-order); `focus:8/8` = pins ARE there (trust this over eyes).
      'FOCUS render ${renderStats('focus', (_focus?.stops ?? const <Stop>[]).map((s) => (lat: s.lat, lon: s.lon)))}',
      boardAgeDiagLine(_boardAgePolls),
      fixAgeDiagLine(_vehAnimator.fixAgeStats()),
    ];

    return DiagnosticsOverlay(
      lines: lines,
      bottomMargin: _panelActive
          ? 12
          : _mobileSheetPx + (_oneScrollRoot ? MapSearchPill.height + 32 : 8),
    );
  }
}
