import 'package:flutter_test/flutter_test.dart';
import 'package:stize/presentation/screens/home_map/search_session.dart';

void main() {
  test('search_used once per session; clearing starts a new one', () {
    final s = SearchSession()..typed();
    expect(s.firstUse(), isTrue);
    s.typed();
    expect(s.firstUse(), isFalse);
    s.clear();
    s.typed();
    expect(s.firstUse(), isTrue);
  });

  test('clearing leaves search mode', () {
    final s = SearchSession()..typed();
    expect(s.active, isTrue);
    s.clear();
    expect(s.active, isFalse);
  });
}
