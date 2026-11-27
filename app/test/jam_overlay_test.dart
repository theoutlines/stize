import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:stize/core/map/jam_overlay.dart';
import 'package:stize/core/route_path.dart';
import 'package:stize/domain/models/jam.dart';

RoutePath _straightPath() => RoutePath([
  for (var i = 0; i < 20; i++) ll.LatLng(44.80, 20.40 + i * 0.002),
]);

Jam _jam({required List<ll.LatLng> vehicles, String dir = 'r7'}) => Jam(
  line: '7',
  directionRouteId: dir,
  vehicles: [
    for (var i = 0; i < vehicles.length; i++)
      JamVehicle(
        garageNo: 'P8020$i',
        position: vehicles[i],
        stopsRemaining: 5,
        frozenSecs: 360,
        isSubstitute: false,
      ),
  ],
  frozenSecs: 360,
  hasSubstitute: false,
  segmentRear: const ll.LatLng(44.80, 20.404),
  segmentFront: const ll.LatLng(44.80, 20.412),
  affectedStopIds: const {'sX'},
  simulated: false,
);

void main() {
  const stop = ll.LatLng(44.80, 20.41);
  final shape = (path: _straightPath(), stops: {'sX': stop});

  test('no jams: nothing to draw, empty GeoJSON', () {
    final o = JamOverlay.build(const [], const {});
    expect(o.isVisible, isFalse);
    expect(jsonDecode(o.segmentsGeoJson())['features'], isEmpty);
  });

  test('a jam on its route: a segment and a glow, nobody badged', () {
    final o = JamOverlay.build(
      [
        _jam(
          vehicles: const [ll.LatLng(44.80, 20.406), ll.LatLng(44.80, 20.41)],
        ),
      ],
      {'r7': shape},
    );
    expect(o.segments, hasLength(1));
    expect(o.glowStops, [stop]);
    expect(o.jammedGarages, isEmpty);
    expect(o.isVisible, isTrue);
  });

  test('a jam with no shape: no segment, its vehicles badged', () {
    final o = JamOverlay.build([
      _jam(vehicles: const [ll.LatLng(44.80, 20.406)]),
    ], const {});
    expect(o.segments, isEmpty);
    expect(o.glowStops, isEmpty);
    expect(o.jammedGarages, {'P80200'});
  });

  test('the pulse breathes between 0.5 and 1 and survives a refresh', () {
    final o = JamOverlay.build(
      [
        _jam(
          vehicles: const [ll.LatLng(44.80, 20.406), ll.LatLng(44.80, 20.41)],
        ),
      ],
      {'r7': shape},
    );
    final seen = <double>[];
    for (var i = 0; i < 40; i++) {
      o.advancePulse();
      seen.add(o.pulseOpacity);
    }
    expect(seen.reduce((a, b) => a < b ? a : b), greaterThanOrEqualTo(0.5));
    expect(seen.reduce((a, b) => a > b ? a : b), lessThanOrEqualTo(1.0));
    final next = JamOverlay.build(const [], const {})..continuePulseFrom(o);
    expect(next.pulseOpacity, o.pulseOpacity);
  });

  test('the glow is softer than the line', () {
    final o = JamOverlay.build(
      [
        _jam(
          vehicles: const [ll.LatLng(44.80, 20.406), ll.LatLng(44.80, 20.41)],
        ),
      ],
      {'r7': shape},
    );
    final line = jsonDecode(o.segmentsGeoJson())['features'][0]['properties'];
    final glow = jsonDecode(o.glowGeoJson())['features'][0]['properties'];
    expect(glow['opacity'], closeTo(line['opacity'] * 0.55, 1e-9));
  });
}
