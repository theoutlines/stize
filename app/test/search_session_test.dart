import 'package:flutter_test/flutter_test.dart';
import 'package:stize/domain/models/stop.dart';
import 'package:stize/presentation/screens/home_map/search_session.dart';

const _lion = Stop(stopId: '1', name: 'Lion', lat: 0, lon: 0, lines: []);
const _vuk = Stop(stopId: '2', name: 'Vukov', lat: 0, lon: 0, lines: []);

void main() {
  test('a slow answer to an older query is dropped', () {
    final s = SearchSession()..typed(); // "79"
    final old = s.ticket;
    s.typed(); // "790"
    final current = s.ticket;
    expect(s.apply(current, stops: [_vuk], lines: [], places: []), isTrue);
    expect(s.apply(old, stops: [_lion], lines: [], places: []), isFalse);
    expect(s.stops.single.name, 'Vukov');
  });

  test('search_used once per session; clearing starts a new one', () {
    final s = SearchSession()..typed();
    expect(s.firstUse(), isTrue);
    s.typed();
    expect(s.firstUse(), isFalse);
    s.clear();
    s.typed();
    expect(s.firstUse(), isTrue);
  });

  test(
    'clearing leaves search mode, empties results, drops what is in flight',
    () {
      final s = SearchSession()..typed();
      final t = s.ticket;
      s.clear();
      expect(s.active, isFalse);
      expect(s.hasResults, isFalse);
      expect(s.apply(t, stops: [_lion], lines: [], places: []), isFalse);
    },
  );
}
