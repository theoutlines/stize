part of '../home_map_screen.dart';

// The map widget itself, built once per frame from build().

extension _MapView on _HomeMapScreenState {
  /// The map itself: MapLibre fenced to the city, the attribution and the
  /// "my position" marker. Vehicles, stops and the focused line are added
  /// imperatively (see the layer parts), never declared here.
  Widget _mapView(Brightness brightness) {
    if (!kMapRenderingEnabled) {
      // Positioned like the real map, so tests see the same Stack
      // sizing as production.
      return const Positioned.fill(child: SizedBox());
    }
    return Positioned.fill(
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
          // No declarative layers: stops, the focused line and
          // vehicles are added imperatively (maplibre 0.3.5's
          // positional LayerManager dropped whole layers; see
          // _addStopLayers / _syncFocusLayers).
          layers: const [],
          children: [
            // Coverage: the routes drawn by the app over the grey basemap.
            if (_cov.mode) const CoverageTracesLayer(),
            const CompactAttribution(),
            // "My position" as a widget marker so it survives every zoom
            // level (X2), not a cullable GL symbol. Wrapped in an
            // AnimatedBuilder so it eases to each fresh fix; the ticker
            // is idle between fixes, so this only repaints while moving.
            // While Nearby is around a map point, your dot is the
            // centre point instead (drawn over the map below).
            if (_meTo != null && _browse.point == null)
              AnimatedBuilder(
                animation: _meAnim,
                builder: (context, _) {
                  final me = _displayedMe ?? _meTo!;
                  return WidgetLayer(
                    markers: [
                      Marker(
                        point: Geographic(lon: me.longitude, lat: me.latitude),
                        size: MeLocationDot.markerSize,
                        // Turns with the map, so the cone's
                        // compass heading stays true on a
                        // rotated map.
                        rotate: true,
                        child: ValueListenableBuilder<double?>(
                          valueListenable: _heading,
                          builder: (context, h, _) => MeLocationDot(heading: h),
                        ),
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
    );
  }
}
