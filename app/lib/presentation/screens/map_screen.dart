import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre/maplibre.dart';

import '../../core/map_style.dart';
import '../../core/map_support.dart';
import '../../data/analytics/event_logger.dart';
import 'map_screen_args.dart';
import '../../domain/models/route_alert.dart';
import '../providers/providers.dart';
import '../widgets/route_alerts_strip.dart';
import '../widgets/stop_sheet.dart';

const _belgradeCenter = Geographic(lon: 20.4612, lat: 44.8125);

/// Shows a set of stops on a MapLibre vector map, optionally with a highlighted
/// center point (a geocoded street/place) and/or a route polyline (a line's
/// full trace).
class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key, required this.args});

  /// What to show: stops, an optional centre point and an optional line trace.
  final MapScreenArgs args;

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  MapController? _controller;
  bool _imagesReady = false;

  Geographic get _initialCenter {
    if (widget.args.center != null)
      return Geographic(
        lon: widget.args.center!.longitude,
        lat: widget.args.center!.latitude,
      );
    final poly = widget.args.polyline;
    if (poly != null && poly.isNotEmpty)
      return Geographic(lon: poly.first[1], lat: poly.first[0]);
    if (widget.args.stops.isNotEmpty)
      return Geographic(
        lon: widget.args.stops.first.lon,
        lat: widget.args.stops.first.lat,
      );
    return _belgradeCenter;
  }

  Future<void> _onStyleLoaded(StyleController style) async {
    await registerStigmaImages(
      style,
      Theme.of(context).colorScheme,
      owner: this,
    );
    if (mounted) setState(() => _imagesReady = true);
  }

  void _onEvent(MapEvent event) {
    if (event is! MapEventClick) return;
    final controller = _controller;
    if (controller == null) return;
    final screen = controller.toScreenLocation(event.point);
    final features = controller.featuresInRect(
      Rect.fromCircle(center: screen, radius: 22),
    );
    for (final f in features) {
      final stopId = f.properties['stopId'];
      if (stopId is String) {
        final stop = widget.args.stops.firstWhere(
          (s) => s.stopId == stopId,
          orElse: () => widget.args.stops.first,
        );
        // Overlay arrivals on this same map (A1) rather than pushing a screen.
        ref
            .read(eventLoggerProvider)
            .log(Ev.stopOpen, props: {'source': Ev.srcPin});
        showStopSheet(context, stopId: stop.stopId, stopName: stop.name);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final alerts = widget.args.lineNumber == null
        ? const <RouteAlert>[]
        : (ref.watch(alertsProvider).valueOrNull ?? const <RouteAlert>[])
              .where(
                (a) => !a.isExpired && a.matchesLine(widget.args.lineNumber!),
              )
              .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.args.title ?? widget.args.centerLabel ?? ''),
      ),
      body: Column(
        children: [
          RouteAlertsStrip(alerts: alerts),
          Expanded(
            child: kMapRenderingEnabled
                ? MapResizeNudge(
                    child: MapLibreMap(
                      options: MapOptions(
                        initCenter: _initialCenter,
                        initZoom: 13,
                        initStyle: MapStyle.forBrightness(theme.brightness),
                      ),
                      onMapCreated: (c) => _controller = c,
                      onStyleLoaded: _onStyleLoaded,
                      onEvent: _onEvent,
                      layers: _buildLayers(theme),
                      children: const [CompactAttribution()],
                    ),
                  )
                : const SizedBox.expand(),
          ),
        ],
      ),
    );
  }

  List<Layer> _buildLayers(ThemeData theme) {
    final poly = widget.args.polyline;
    return [
      if (poly != null && poly.length >= 2)
        PolylineLayer(
          polylines: [
            Feature<LineString>(
              geometry: LineString.from([
                for (final p in poly) Geographic(lon: p[1], lat: p[0]),
              ]),
            ),
          ],
          color: theme.colorScheme.primary,
          width: 4,
        ),
      if (_imagesReady) ...[
        MarkerLayer(
          points: [
            for (final s in widget.args.stops)
              Feature<Point>(
                geometry: Point(Geographic(lon: s.lon, lat: s.lat)),
                // Only `stopId` (the tap handler looks the name up from it). A
                // `name` here would be serialised by the declarative
                // LayerManager's geobase `toText()`, which doesn't escape `"` —
                // stops like `Park "Tašmajdan"` would emit invalid JSON and
                // vanish. See home_map_screen `_pushStopSources`.
                properties: {'stopId': s.stopId},
              ),
          ],
          iconImage: MapImages.bus,
          iconSize: 0.5,
          iconAllowOverlap: true,
        ),
        if (widget.args.center != null)
          MarkerLayer(
            points: [
              Feature<Point>(
                geometry: Point(
                  Geographic(
                    lon: widget.args.center!.longitude,
                    lat: widget.args.center!.latitude,
                  ),
                ),
              ),
            ],
            iconImage: MapImages.place,
            iconSize: 0.5,
            iconAnchor: IconAnchor.bottom,
            iconAllowOverlap: true,
          ),
      ],
    ];
  }
}
