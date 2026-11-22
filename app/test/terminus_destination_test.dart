import 'package:flutter_test/flutter_test.dart';
import 'package:stize/core/arrival_grouping.dart';

void main() {
  test('a line ending at this stop shows the terminus label', () {
    expect(displayDestination('Slavija', 'Slavija', 'Konačna'), 'Konačna');
    expect(displayDestination('Trg Nikole Pašića', 'trg nikole pasica', 'K'), 'K');
  });
  test('other destinations and empties pass through', () {
    expect(displayDestination('Vukov spomenik', 'Slavija', 'K'), 'Vukov spomenik');
    expect(displayDestination(null, 'Slavija', 'K'), isNull);
    expect(displayDestination('Slavija', '', 'K'), 'Slavija');
  });
}
