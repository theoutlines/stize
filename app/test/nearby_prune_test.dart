import 'package:flutter_test/flutter_test.dart';
import 'package:stize/core/nearby_focus.dart';
import 'package:stize/presentation/widgets/nearby_list.dart';
import 'package:stize/domain/models/nearby_arrival.dart';
import 'package:stize/domain/models/vehicle_type.dart';

NearbyGroup _g(
  String line,
  String stop,
  List<NearbyEta> a, {
  String route = 'r',
}) => NearbyGroup(
  line: line,
  vehicleType: VehicleType.bus,
  destination: 'X',
  routeId: '$line$route',
  stopId: stop,
  stopName: stop,
  distanceMeters: 40,
  arrivals: a,
);

NearbyEta _live(int eta) => NearbyEta(
  etaMinutes: eta,
  garageNo: 'g$eta',
  stopsRemaining: 2,
  isScheduled: false,
);
NearbyEta _sch(int eta) => NearbyEta(
  etaMinutes: eta,
  garageNo: null,
  stopsRemaining: null,
  isScheduled: true,
);

void main() {
  test('scheduled sooner than the soonest live at that stop is dropped', () {
    final out = pruneImpossibleScheduled([
      _g('14', 'batutova', [_live(14)]),
      _g('5', 'batutova', [_sch(0), _sch(20)]),
    ]);
    final five = out.firstWhere((g) => g.line == '5');
    expect(five.arrivals.map((a) => a.etaMinutes).toList(), [20]);
  });

  test('a group with only impossible departures disappears', () {
    final out = pruneImpossibleScheduled([
      _g('14', 'batutova', [_live(14)]),
      _g('5', 'batutova', [_sch(0), _sch(9)]),
    ]);
    expect(out.where((g) => g.line == '5'), isEmpty);
  });

  test('a stop with no live data keeps its timetable', () {
    final out = pruneImpossibleScheduled([
      _g('5', 'other', [_sch(0), _sch(9)]),
    ]);
    expect(out.single.arrivals, hasLength(2));
  });

  test('scheduled at or before its own live vehicle is the same bus', () {
    final out = pruneImpossibleScheduled([
      _g('26', 's', [_live(5), _sch(4), _sch(5), _sch(30)]),
    ]);
    expect(out.single.arrivals.map((a) => a.etaMinutes).toList(), [5, 30]);
  });

  test('carousel: one card per line, directions kept in order', () {
    final lines = carouselByLine([
      _g('6', 'a', [_live(2)], route: 'x'),
      _g('79', 'b', [_live(3)]),
      _g('6', 'c', [_live(4)], route: 'y'),
    ]);
    expect(lines.map((l) => l.first.line).toList(), ['6', '79']);
    expect(lines.first.map((g) => g.routeId).toList(), ['6x', '6y']);
  });
}
