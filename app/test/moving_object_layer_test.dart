import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:stigla/core/moving_object_layer.dart';
import 'package:stigla/domain/models/vehicle_type.dart';

void main() {
  group('MovingObjectKind', () {
    test('maps every current VehicleType to a kind', () {
      expect(
        MovingObjectKind.fromVehicleType(VehicleType.bus),
        MovingObjectKind.bus,
      );
      expect(
        MovingObjectKind.fromVehicleType(VehicleType.tram),
        MovingObjectKind.tram,
      );
      expect(
        MovingObjectKind.fromVehicleType(VehicleType.trolleybus),
        MovingObjectKind.trolleybus,
      );
    });

    test('reserves the roadmap kinds so the layer needn\'t be rewritten', () {
      // These have no VehicleType yet but exist as first-class kinds.
      expect(MovingObjectKind.values, containsAll([
        MovingObjectKind.metro,
        MovingObjectKind.train,
        MovingObjectKind.scooter,
        MovingObjectKind.bike,
      ]));
      expect(MovingObjectKind.metro.id, 'metro');
    });
  });

  group('movingObjectsFeatureCollection', () {
    MovingObject obj({
      String key = 'P1',
      double lat = 44.80,
      double lon = 20.46,
      MovingObjectKind kind = MovingObjectKind.bus,
      String label = '79',
      double? heading = 90,
      bool selected = false,
      bool stuck = false,
    }) => MovingObject(
      key: key,
      position: ll.LatLng(lat, lon),
      kind: kind,
      label: label,
      heading: heading,
      selected: selected,
      stuck: stuck,
    );

    test('is a FeatureCollection with one feature per object, in order', () {
      final fc = movingObjectsFeatureCollection([
        obj(key: 'A', label: '1'),
        obj(key: 'B', label: '2'),
        obj(key: 'C', label: '3'),
      ]);
      expect(fc['type'], 'FeatureCollection');
      final features = fc['features'] as List;
      expect(features.length, 3);
      expect(
        features.map((f) => (f['properties'] as Map)['key']).toList(),
        ['A', 'B', 'C'],
      );
    });

    test('writes coordinates as [lon, lat] (GeoJSON order)', () {
      final fc = movingObjectsFeatureCollection([obj(lat: 44.80, lon: 20.46)]);
      final feature = (fc['features'] as List).single as Map;
      final geometry = feature['geometry'] as Map;
      expect(geometry['type'], 'Point');
      expect(geometry['coordinates'], [20.46, 44.80]);
    });

    test('carries kind, label, heading, selected and stuck as properties', () {
      final fc = movingObjectsFeatureCollection([
        obj(
          kind: MovingObjectKind.tram,
          label: '2',
          heading: 123.5,
          selected: true,
          stuck: true,
        ),
      ]);
      final props =
          ((fc['features'] as List).single as Map)['properties'] as Map;
      expect(props['kind'], 'tram');
      expect(props['label'], '2');
      expect(props['heading'], 123.5);
      expect(props['selected'], true);
      expect(props['stuck'], true);
    });

    test('defaults a null heading to 0 so the arrow filter can drop it', () {
      final fc = movingObjectsFeatureCollection([obj(heading: null)]);
      final props =
          ((fc['features'] as List).single as Map)['properties'] as Map;
      expect(props['heading'], 0);
    });

    test('never leaks fleet id or identity onto the marker', () {
      // The tracking key is present for taps/spiderfy, but nothing resembling a
      // rich fleet identity (model, garage-as-identity) is exposed. The property
      // set is exactly the small, fixed list the styles read.
      final props =
          ((movingObjectsFeatureCollection([obj()])['features'] as List).single
                  as Map)['properties']
              as Map;
      expect(props.keys.toSet(), {
        'key',
        'kind',
        'label',
        'heading',
        'selected',
        'stuck',
      });
    });

    test('movingObjectsGeoJson emits valid JSON that round-trips', () {
      final json = movingObjectsGeoJson([obj(key: 'A'), obj(key: 'B')]);
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      expect(decoded['type'], 'FeatureCollection');
      expect((decoded['features'] as List).length, 2);
    });

    test('empty input yields an empty FeatureCollection', () {
      final fc = movingObjectsFeatureCollection(const []);
      expect(fc['features'], isEmpty);
    });
  });

  group('spiderfyCoincident', () {
    MovingObject at(String key, double lat, double lon) => MovingObject(
      key: key,
      position: ll.LatLng(lat, lon),
      kind: MovingObjectKind.bus,
      label: key,
    );

    test('returns the same list when nothing is coincident', () {
      final input = [at('A', 44.80, 20.46), at('B', 44.81, 20.47)];
      final out = spiderfyCoincident(input, zoom: 15);
      expect(identical(out, input), isTrue);
    });

    test('single object is returned unchanged', () {
      final input = [at('A', 44.80, 20.46)];
      expect(identical(spiderfyCoincident(input, zoom: 15), input), isTrue);
    });

    test('spreads coincident objects apart while preserving count and keys', () {
      final input = [
        at('A', 44.80, 20.46),
        at('B', 44.80, 20.46), // same spot as A
        at('C', 44.80, 20.46), // same spot as A
        at('D', 44.90, 20.50), // elsewhere — untouched
      ];
      final out = spiderfyCoincident(input, zoom: 15);
      expect(out.length, 4);
      expect(out.map((o) => o.key).toList(), ['A', 'B', 'C', 'D']);
      // The three coincident ones now sit at distinct positions.
      final coincident = out.take(3).map((o) => o.position).toList();
      expect(coincident[0] == coincident[1], isFalse);
      expect(coincident[1] == coincident[2], isFalse);
      // The isolated D is left exactly where it was.
      expect(out[3].position, ll.LatLng(44.90, 20.50));
    });

    test('spread grows as zoom decreases (constant on-screen size)', () {
      final input = [at('A', 44.80, 20.46), at('B', 44.80, 20.46)];
      final near = spiderfyCoincident(input, zoom: 17);
      final far = spiderfyCoincident(input, zoom: 13);
      double offset(MovingObject a, MovingObject b) =>
          (a.position.latitude - b.position.latitude).abs() +
          (a.position.longitude - b.position.longitude).abs();
      // Same pixel spread → more metres (bigger coordinate delta) at lower zoom.
      expect(offset(far[0], input[0]), greaterThan(offset(near[0], input[0])));
    });
  });
}
