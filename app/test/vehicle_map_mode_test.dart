import 'package:flutter_test/flutter_test.dart';
import 'package:stigla/core/vehicle_map_mode.dart';
import 'package:stigla/core/vehicle_track_animator.dart';
import 'package:stigla/domain/models/vehicle_type.dart';
import 'package:latlong2/latlong.dart' as ll;

void main() {
  group('resolveVehicleMapMode — the setting × flag matrix', () {
    test('flag OFF is a killswitch: always the aquarium, whatever is stored', () {
      for (final choice in [null, VehicleMapMode.onDemand, VehicleMapMode.aquarium]) {
        expect(
          resolveVehicleMapMode(flagOn: false, choice: choice),
          VehicleMapMode.aquarium,
          reason: 'stored choice $choice must not survive the killswitch',
        );
      }
    });

    test('flag ON, nothing chosen → on-demand is the default', () {
      expect(
        resolveVehicleMapMode(flagOn: true, choice: null),
        VehicleMapMode.onDemand,
      );
    });

    test('flag ON, user picked the aquarium → aquarium', () {
      expect(
        resolveVehicleMapMode(flagOn: true, choice: VehicleMapMode.aquarium),
        VehicleMapMode.aquarium,
      );
    });

    test('flag ON, user picked on-demand explicitly → on-demand', () {
      expect(
        resolveVehicleMapMode(flagOn: true, choice: VehicleMapMode.onDemand),
        VehicleMapMode.onDemand,
      );
    });
  });

  group('VehicleTrackAnimator.retainOnly — switching into on-demand', () {
    VehicleSample sample(String key) => VehicleSample(
      key: key,
      position: ll.LatLng(44.81, 20.46),
      line: '79',
      type: VehicleType.bus,
    );

    test('drops the background set at once but keeps the followed vehicle', () {
      final animator = VehicleTrackAnimator();
      animator.syncSamples([sample('a'), sample('b'), sample('c')], 1);

      animator.retainOnly({'b'});

      expect(animator.tracks.keys, ['b']);
    });

    test('an empty keep-set clears everything (no context)', () {
      final animator = VehicleTrackAnimator();
      animator.syncSamples([sample('a'), sample('b')], 1);

      animator.retainOnly({});

      expect(animator.tracks, isEmpty);
    });
  });
}
