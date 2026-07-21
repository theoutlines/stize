import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:stize/core/vehicle_track_animator.dart';
import 'package:stize/domain/models/area_vehicle.dart';
import 'package:stize/domain/models/trajectory_point.dart';
import 'package:stize/domain/models/vehicle_source.dart';
import 'package:stize/domain/models/vehicle_type.dart';

void main() {
  group('VehicleSource.fromApi (tolerant classification)', () {
    test('only an explicit "scheduled" is scheduled; everything else is live', () {
      expect(VehicleSource.fromApi('scheduled'), VehicleSource.scheduled);
      expect(VehicleSource.fromApi('live'), VehicleSource.live);
      expect(VehicleSource.fromApi(null), VehicleSource.live); // field absent
      expect(VehicleSource.fromApi('whatever'), VehicleSource.live);
    });
  });

  group('AreaVehicle scheduled parsing', () {
    Map<String, dynamic> json({String? source, String? tripId, String? garage}) => {
          'line': '2',
          'vehicle_type': 'tram',
          'garage_no': garage,
          'lat': 44.80,
          'lon': 20.46,
          'heading': 90,
          if (source != null) 'source': source,
          if (tripId != null) 'trip_id': tripId,
        };

    test('defaults to live when the backend does not mark the source', () {
      final v = AreaVehicle.fromJson(json(garage: 'P123'));
      expect(v.source, VehicleSource.live);
      expect(v.tripId, isNull);
      expect(v.key, 'P123');
    });

    test('parses a scheduled object with a trip id', () {
      final v = AreaVehicle.fromJson(
        json(source: 'scheduled', tripId: 'T-77-1'),
      );
      expect(v.source, VehicleSource.scheduled);
      expect(v.tripId, 'T-77-1');
      // Scheduled key is trip-based and prefixed, so it can never collide with a
      // live vehicle's garage-number key.
      expect(v.key, 'sched:T-77-1');
    });
  });

  group('source flows through the animator', () {
    test('a scheduled sample yields a scheduled track that still moves', () {
      var now = DateTime.utc(2026, 7, 14, 9);
      final animator = VehicleTrackAnimator(clock: () => now);
      animator.syncSamples([
        VehicleSample(
          key: 'sched:T1',
          position: const ll.LatLng(44.80, 20.50),
          line: '2',
          type: VehicleType.tram,
          source: VehicleSource.scheduled,
          trajectory: const [
            TrajectoryPoint(44.80, 20.50, 0),
            TrajectoryPoint(44.80, 20.60, 100),
          ],
          asOf: now,
        ),
      ], 0, now: now);

      final track = animator.trackFor('sched:T1')!;
      expect(track.source, VehicleSource.scheduled);
      // Movement is identical to a live object — the plan bridges forward from
      // the fix (within the fresh window).
      now = now.add(const Duration(seconds: 10));
      animator.advanceTimed(now);
      expect(animator.positionOf('sched:T1', 0).longitude, greaterThan(20.50));
    });
  });
}
