import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart' as ll;

import 'package:stigla/core/vehicle_route.dart';
import 'package:stigla/domain/models/route_shape.dart';
import 'package:stigla/domain/models/vehicle_type.dart';

RouteShape _shape() {
  // A straight line heading north; five evenly-spaced stops.
  final stops = [
    for (var i = 0; i < 5; i++)
      RouteShapeStop(
        stopId: 's$i',
        name: 'Stop $i',
        lat: 44.80 + i * 0.01,
        lon: 20.0,
        seq: i,
      ),
  ];
  final poly = [for (var i = 0; i < 5; i++) [44.80 + i * 0.01, 20.0]];
  return RouteShape(
    routeId: '00079',
    vehicleType: VehicleType.bus,
    origin: 'Stop 0',
    destination: 'Stop 4',
    polyline: poly,
    stops: stops,
  );
}

void main() {
  test('splits the trace and anchors ETAs on the board stop', () {
    final plan = planVehicleRoute(
      shape: _shape(),
      vehicle: const ll.LatLng(44.815, 20.0), // between stop 1 and 2
      boardStop: const ll.LatLng(44.83, 20.0), // stop index 3
      stopsRemaining: 2,
      etaToBoardMinutes: 10,
    );

    // Upcoming stops start at the vehicle's next stop (index 2) through the end.
    expect(plan.stops.map((u) => u.stop.stopId), ['s2', 's3', 's4']);
    expect(plan.nextStop?.stopId, 's2');

    // The board stop (index 3) is flagged and lands exactly on the real ETA.
    final board = plan.stops.firstWhere((u) => u.isBoardStop);
    expect(board.stop.stopId, 's3');
    expect(board.etaMinutes, 10);

    // Other stops are linearly extrapolated (5 min per stop here).
    expect(plan.stops[0].etaMinutes, 5); // s2
    expect(plan.stops[2].etaMinutes, 15); // s4

    // Both trace halves are drawable.
    expect(plan.traveled.length, greaterThanOrEqualTo(2));
    expect(plan.upcoming.length, greaterThanOrEqualTo(2));
  });

  test('the upcoming list SLIDES as the vehicle advances (owner R4 #1)', () {
    final shape = _shape();
    // Same fixed feed anchor for both samples (as captured at follow entry).
    List<String> upcomingAt(double lat) => planVehicleRoute(
          shape: shape,
          vehicle: ll.LatLng(lat, 20.0),
          boardStop: const ll.LatLng(44.83, 20.0),
          stopsRemaining: 2,
          etaToBoardMinutes: 10,
        ).stops.map((u) => u.stop.stopId).toList();

    // Between stop 1 and 2 → next is s2.
    expect(upcomingAt(44.815), ['s2', 's3', 's4']);
    // The vehicle drives on, past stop 2, to between stop 2 and 3 → s2 has
    // dropped off and s3 is now next. The list slid, even though the feed's
    // stops_remaining (2) never changed.
    expect(upcomingAt(44.825), ['s3', 's4']);
    // Past stop 3 → only s4 remains.
    expect(upcomingAt(44.835), ['s4']);
  });

  test('degrades gracefully without stops_remaining / eta', () {
    final plan = planVehicleRoute(
      shape: _shape(),
      vehicle: const ll.LatLng(44.815, 20.0),
      boardStop: const ll.LatLng(44.83, 20.0),
      stopsRemaining: null,
      etaToBoardMinutes: null,
    );
    // Still lists upcoming stops (from nearest to the vehicle), just no ETAs.
    expect(plan.stops, isNotEmpty);
    expect(plan.stops.every((u) => u.etaMinutes == null), isTrue);
  });

  test('handles an empty shape without throwing', () {
    const empty = RouteShape(
      routeId: 'x',
      vehicleType: VehicleType.bus,
      origin: 'a',
      destination: 'b',
      polyline: [],
      stops: [],
    );
    final plan = planVehicleRoute(
      shape: empty,
      vehicle: const ll.LatLng(44.8, 20.0),
      boardStop: const ll.LatLng(44.8, 20.0),
      stopsRemaining: 1,
      etaToBoardMinutes: 3,
    );
    expect(plan.stops, isEmpty);
    expect(plan.traveled, isEmpty);
    expect(plan.upcoming, isEmpty);
  });
}
