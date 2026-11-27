import 'package:flutter_test/flutter_test.dart';
import 'package:stize/core/map/stop_markers.dart';
import 'package:stize/domain/models/stop.dart';
import 'package:stize/domain/models/vehicle_type.dart';

Stop _stop(String id, double lat, double lon, List<VehicleType> types) => Stop(
  stopId: id,
  name: 'Stop $id',
  lat: lat,
  lon: lon,
  lines: const [],
  types: types,
);

void main() {
  final bus = _stop('b', 44.81, 20.46, const [VehicleType.bus]);
  final tram = _stop('t', 44.82, 20.47, const [
    VehicleType.tram,
    VehicleType.bus,
  ]);
  final mixed = _stop('m', 44.83, 20.48, const [
    VehicleType.bus,
    VehicleType.trolleybus,
  ]);
  final fav = _stop('f', 44.84, 20.49, const [VehicleType.bus]);

  test(
    'close in: one pin per stop, typed; a tram line wins; favourites left out',
    () {
      final m = StopMarkers.build(
        stops: [bus, tram, mixed, fav],
        favoriteIds: {'f'},
        zoom: 16,
        individualZoom: 15,
        toScreen: (lat, lon) => Offset.zero,
      );
      expect(m.bus.single.properties['stopId'], 'b');
      expect(m.tram.single.properties['stopId'], 't');
      expect(m.mixed.single.properties['stopId'], 'm');
      expect(m.clusters, isEmpty);
    },
  );

  test(
    'zoomed out: stops in one screen cell cluster, a lone one stays a pin',
    () {
      // b and t share a cell, m is far away on screen.
      Offset screen(double lat, double lon) =>
          lat < 44.825 ? const Offset(10, 10) : const Offset(500, 500);
      final m = StopMarkers.build(
        stops: [bus, tram, mixed],
        favoriteIds: const {},
        zoom: 13,
        individualZoom: 15,
        toScreen: screen,
      );
      expect(m.clusters, hasLength(1));
      expect(m.clusters.single.properties['point_count'], 2);
      expect(m.mixed.single.properties['stopId'], 'm');
      expect(m.bus, isEmpty);
      expect(m.tram, isEmpty);
    },
  );

  test('no map yet: every stop is its own pin', () {
    final m = StopMarkers.build(
      stops: [bus, tram],
      favoriteIds: const {},
      zoom: 10,
      individualZoom: 15,
    );
    expect(m.bus, hasLength(1));
    expect(m.tram, hasLength(1));
  });
}
