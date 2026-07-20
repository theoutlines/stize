import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart' as ll;

import 'package:stigla/core/jam_geometry.dart';
import 'package:stigla/core/route_path.dart';
import 'package:stigla/domain/models/jam.dart';

// A straight west→east route along latitude 44.80, ~150m between vertices.
RoutePath _straightPath() => RoutePath([
      for (var i = 0; i < 20; i++) ll.LatLng(44.80, 20.40 + i * 0.002),
    ]);

Jam _jam({
  required ll.LatLng rear,
  required ll.LatLng front,
  required List<ll.LatLng> vehicles,
  String dir = 'r7',
}) =>
    Jam(
      line: '7',
      directionRouteId: dir,
      vehicles: [
        for (final v in vehicles)
          JamVehicle(
            garageNo: 'P8020${vehicles.indexOf(v)}',
            position: v,
            stopsRemaining: 5,
            frozenSecs: 360,
            isSubstitute: false,
          ),
      ],
      frozenSecs: 360,
      hasSubstitute: false,
      segmentRear: rear,
      segmentFront: front,
      affectedStopIds: const {'sX'},
      simulated: false,
    );

void main() {
  group('RoutePath.offsetOf / subPath', () {
    final path = _straightPath();

    test('offsetOf is ~0 on the line and grows off it', () {
      expect(path.offsetOf(const ll.LatLng(44.80, 20.41)), lessThan(5));
      // ~0.005° lat off the line ≈ 550 m.
      expect(path.offsetOf(const ll.LatLng(44.805, 20.41)), greaterThan(400));
    });

    test('subPath returns the stretch between two along-distances', () {
      final d0 = path.project(const ll.LatLng(44.80, 20.404));
      final d1 = path.project(const ll.LatLng(44.80, 20.412));
      final seg = path.subPath(d0, d1);
      expect(seg.length, greaterThanOrEqualTo(2));
      expect(seg.first.longitude, closeTo(20.404, 0.001));
      expect(seg.last.longitude, closeTo(20.412, 0.001));
    });
  });

  group('buildJamSegment', () {
    final path = _straightPath();

    test('draws a segment when vehicles sit on the shape', () {
      final jam = _jam(
        rear: const ll.LatLng(44.80, 20.404),
        front: const ll.LatLng(44.80, 20.414),
        vehicles: const [ll.LatLng(44.80, 20.408), ll.LatLng(44.80, 20.410)],
      );
      final res = buildJamSegment(jam, path);
      expect(res.gated, isFalse);
      expect(res.polyline, isNotNull);
      expect(res.polyline!.length, greaterThanOrEqualTo(2));
    });

    test('gates (no segment) when a vehicle is far off the shape', () {
      // The 26/27/44 failure: vehicles hundreds of metres off the polyline.
      final jam = _jam(
        rear: const ll.LatLng(44.805, 20.404),
        front: const ll.LatLng(44.805, 20.414),
        vehicles: const [ll.LatLng(44.805, 20.408), ll.LatLng(44.805, 20.410)],
      );
      final res = buildJamSegment(jam, path);
      expect(res.gated, isTrue);
      expect(res.polyline, isNull);
    });

    test('no segment info (null endpoints) → none, not gated', () {
      final jam = Jam(
        line: '7',
        directionRouteId: 'r7',
        vehicles: const [],
        frozenSecs: 360,
        hasSubstitute: false,
        segmentRear: null,
        segmentFront: null,
        affectedStopIds: const {},
        simulated: false,
      );
      final res = buildJamSegment(jam, path);
      expect(res.gated, isFalse);
      expect(res.polyline, isNull);
    });
  });

  group('isJamAhead', () {
    final path = _straightPath(); // west→east along lat 44.80
    // A vehicle sitting mid-route, travelling east (direction "r7").
    final vehAlong = path.project(const ll.LatLng(44.80, 20.418));

    Jam jamAt(double lon, {String dir = 'r7'}) => _jam(
          rear: ll.LatLng(44.80, lon - 0.001),
          front: ll.LatLng(44.80, lon + 0.001),
          vehicles: [ll.LatLng(44.80, lon)],
          dir: dir,
        );

    test('true when the jam is ahead on the same direction', () {
      expect(
        isJamAhead(jam: jamAt(20.430), vehicleDirectionRouteId: 'r7', path: path, vehicleAlong: vehAlong),
        isTrue,
      );
    });

    test('false for the opposite direction (different direction_route_id)', () {
      expect(
        isJamAhead(jam: jamAt(20.430, dir: 'r7-1'), vehicleDirectionRouteId: 'r7', path: path, vehicleAlong: vehAlong),
        isFalse,
      );
    });

    test('false when the jam is already behind the vehicle', () {
      expect(
        isJamAhead(jam: jamAt(20.405), vehicleDirectionRouteId: 'r7', path: path, vehicleAlong: vehAlong),
        isFalse,
      );
    });
  });

  group('isJamRelevant', () {
    // A jam on line 7 around (44.80, 20.41) with two frozen vehicles.
    final jam = _jam(
      rear: const ll.LatLng(44.80, 20.408),
      front: const ll.LatLng(44.80, 20.414),
      vehicles: const [ll.LatLng(44.80, 20.410), ll.LatLng(44.80, 20.412)],
    );

    test('a far-away jam with no context match is NOT relevant (quiet button)', () {
      expect(
        isJamRelevant(jam,
            followedLine: '2', openStopId: 'other', userLocation: const ll.LatLng(44.90, 20.60)),
        isFalse,
      );
    });

    test('a jam within the Nearby radius of the user IS relevant', () {
      expect(
        isJamRelevant(jam, userLocation: const ll.LatLng(44.801, 20.411)),
        isTrue,
      );
    });

    test('a jam on the followed vehicle line IS relevant', () {
      expect(isJamRelevant(jam, followedLine: '7'), isTrue);
    });

    test('a jam touching the open stop IS relevant', () {
      expect(isJamRelevant(jam, openStopId: 'sX'), isTrue); // sX is in affectedStopIds
    });
  });

  group('JamsBoard', () {
    test('affectedJamAt matches a jam listing the stop', () {
      final board = JamsBoard(
        feedHealthy: true,
        jams: [
          _jam(
            rear: const ll.LatLng(44.80, 20.40),
            front: const ll.LatLng(44.80, 20.41),
            vehicles: const [ll.LatLng(44.80, 20.405)],
          ),
        ],
        substitutions: const [],
      );
      expect(board.affectedJamAt('sX'), isNotNull);
      expect(board.affectedJamAt('nope'), isNull);
    });

    test('parses the wire format including segment + downstream stops', () {
      final board = JamsBoard.fromJson({
        'feed_healthy': true,
        'jams': [
          {
            'line': '5',
            'direction_route_id': 'r5',
            'vehicles': [
              {'garage_no': 'P80201', 'lat': 44.8, 'lon': 20.46, 'stops_remaining': 3, 'frozen_secs': 340, 'is_substitute': false},
              {'garage_no': 'P80202', 'lat': 44.801, 'lon': 20.461, 'stops_remaining': 4, 'frozen_secs': 360, 'is_substitute': false},
            ],
            'frozen_secs': 360,
            'has_substitute': false,
            'segment': {'rear': {'lat': 44.79, 'lon': 20.45}, 'front': {'lat': 44.81, 'lon': 20.47}},
            'affected_stop_ids': ['a', 'b', 'c'],
          }
        ],
        'substitutions': [
          {'line': '5', 'direction_route_id': 'r5', 'garage_nos': ['P93475']}
        ],
      });
      expect(board.feedHealthy, isTrue);
      expect(board.jams, hasLength(1));
      expect(board.jams.first.vehicles, hasLength(2));
      expect(board.jams.first.segmentRear, isNotNull);
      expect(board.jams.first.affectedStopIds, containsAll(['a', 'b', 'c']));
      expect(board.substitutions.first.garageNos, contains('P93475'));
    });

    test('feed_healthy defaults true when absent, false is honoured', () {
      expect(JamsBoard.fromJson({'jams': [], 'substitutions': []}).feedHealthy, isTrue);
      expect(
        JamsBoard.fromJson({'feed_healthy': false, 'jams': [], 'substitutions': []}).feedHealthy,
        isFalse,
      );
    });
  });
}
