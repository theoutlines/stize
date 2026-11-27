import 'dart:ui' show Offset;

import 'package:maplibre/maplibre.dart';

import '../../domain/models/stop.dart';
import '../../domain/models/vehicle_type.dart';
import '../map_support.dart';

/// The stop pins of the visible area, sorted into the map's stop layers.
class StopMarkers {
  const StopMarkers({
    required this.clusters,
    required this.bus,
    required this.tram,
    required this.trolley,
    required this.mixed,
  });

  final List<Feature<Point>> clusters;
  final List<Feature<Point>> bus;
  final List<Feature<Point>> tram;
  final List<Feature<Point>> trolley;
  final List<Feature<Point>> mixed;

  /// Screen cell for clustering, in logical pixels.
  static const clusterCell = 66.0;

  /// Sort [stops] into layers. Favourites ([favoriteIds]) are left out: they
  /// have a layer of their own. From [individualZoom] on (or without
  /// [toScreen], i.e. no map yet) every stop is its own pin, typed by the lines
  /// it serves (a stop of several non-tram types gets the one mixed pin).
  /// Below it, stops that fall in one [clusterCell] on screen become a cluster
  /// at their average position; a lone stop stays a pin.
  factory StopMarkers.build({
    required Iterable<Stop> stops,
    required Set<String> favoriteIds,
    required double zoom,
    required double individualZoom,
    Offset Function(double lat, double lon)? toScreen,
  }) {
    final visible = [
      for (final s in stops)
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
      switch (stopMarkerType(s)) {
        case null:
          mixed.add(feature); // one unified marker for multi-type stops (D2)
        case VehicleType.tram:
          tram.add(feature);
        case VehicleType.trolleybus:
          trolley.add(feature);
        case VehicleType.bus:
          bus.add(feature);
      }
    }

    if (toScreen == null || zoom >= individualZoom) {
      visible.forEach(addIndividual);
    } else {
      final buckets = <String, List<Stop>>{};
      for (final s in visible) {
        final off = toScreen(s.lat, s.lon);
        final key =
            '${(off.dx / clusterCell).floor()}:${(off.dy / clusterCell).floor()}';
        buckets.putIfAbsent(key, () => []).add(s);
      }
      for (final bucket in buckets.values) {
        if (bucket.length == 1) {
          addIndividual(bucket.first);
          continue;
        }
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
    return StopMarkers(
      clusters: clusters,
      bus: bus,
      tram: tram,
      trolley: trolley,
      mixed: mixed,
    );
  }
}
