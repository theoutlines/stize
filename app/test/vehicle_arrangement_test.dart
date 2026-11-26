import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:stize/core/moving_object_layer.dart';
import 'package:stize/core/vehicle_arrangement.dart';

const _lat = 44.8125;
const _stop = ll.LatLng(_lat, 20.4612);

MovingObject _veh(String key, {bool moving = false, ll.LatLng at = _stop}) =>
    MovingObject(
      key: key,
      position: at,
      kind: MovingObjectKind.bus,
      label: '79',
      moving: moving,
    );

List<MovingObject> _settle(VehicleArranger a, List<MovingObject> objs) {
  var out = a.arrange(objs, 17, driverRunning: true, refLatitude: _lat);
  for (var i = 0; i < 60 && a.fanAnimating; i++) {
    out = a.arrange(objs, 17, driverRunning: true, refLatitude: _lat);
  }
  return out;
}

void main() {
  test('far zoom: plain true positions, no easing left running', () {
    final a = VehicleArranger();
    final objs = [_veh('a'), _veh('b')];
    a.arrange(objs, 17, driverRunning: true, refLatitude: _lat);
    expect(a.fanAnimating, isTrue);
    final out = a.arrange(objs, 12, driverRunning: true, refLatitude: _lat);
    expect(out, same(objs));
    expect(a.fanAnimating, isFalse);
  });

  test('parked vehicles on one spot fan out and the fan settles', () {
    final a = VehicleArranger();
    final out = _settle(a, [_veh('a'), _veh('b')]);
    expect(a.fanAnimating, isFalse);
    final d = const ll.Distance().as(
      ll.LengthUnit.Meter,
      out[0].position,
      out[1].position,
    );
    expect(d, greaterThan(1));
    expect(out.every((o) => o.opacity == 1.0), isTrue);
  });

  test('the fan eases in over frames instead of jumping', () {
    final a = VehicleArranger();
    final objs = [_veh('a'), _veh('b')];
    final first = a.arrange(objs, 17, driverRunning: true, refLatitude: _lat);
    final settled = _settle(a, objs);
    final firstGap = const ll.Distance().as(
      ll.LengthUnit.Meter,
      first[0].position,
      first[1].position,
    );
    final settledGap = const ll.Distance().as(
      ll.LengthUnit.Meter,
      settled[0].position,
      settled[1].position,
    );
    expect(firstGap, lessThan(settledGap));
  });

  test('moving vehicles that cross keep their positions and dim', () {
    final a = VehicleArranger();
    final objs = [_veh('a', moving: true), _veh('b', moving: true)];
    final out = a.arrange(objs, 17, driverRunning: false, refLatitude: _lat);
    expect(out.map((o) => o.position), everyElement(_stop));
    expect(out.map((o) => o.opacity), everyElement(closeTo(0.7, 1e-9)));
  });

  test('a lone vehicle is untouched', () {
    final a = VehicleArranger();
    final out = a.arrange(
      [_veh('a')],
      17,
      driverRunning: false,
      refLatitude: _lat,
    );
    expect(out.single.position, _stop);
    expect(out.single.opacity, 1.0);
    expect(a.fanAnimating, isFalse);
  });
}
