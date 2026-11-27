import 'package:flutter_test/flutter_test.dart';
import 'package:stize/presentation/screens/home_map/sheet_levels.dart';
import 'package:stize/presentation/widgets/guide/belgrade_guide.dart';

void main() {
  test('empty is Nearby', () {
    final s = SheetLevelStack();
    expect(s.top, isNull);
    expect(s.below, isNull);
    expect(s.pop(), isNull);
  });

  test('the same level on top is not stacked twice', () {
    final s = SheetLevelStack()
      ..open(const StopLevel('20001', 'Lion'))
      ..open(const StopLevel('20001', 'Lion'))
      ..open(const MyStopsLevel())
      ..open(const MyStopsLevel())
      ..open(const GuideLevel(GuidePage.home))
      ..open(const GuideLevel(GuidePage.home))
      ..open(const FeedbackLevel())
      ..open(const FeedbackLevel());
    expect(s.length, 4);
  });

  test('a different stop, page or form is a new level', () {
    final s = SheetLevelStack()
      ..open(const StopLevel('20001', 'Lion'))
      ..open(const StopLevel('20002', 'Batutova'))
      ..open(const GuideLevel(GuidePage.home))
      ..open(const GuideLevel(GuidePage.places))
      ..open(const FeedbackLevel())
      ..open(const FeedbackLevel(form: true));
    expect(s.length, 6);
    expect((s.top! as FeedbackLevel).form, isTrue);
    expect(s.below, isA<FeedbackLevel>());
  });

  test('back returns to the level below; the stop on top is known', () {
    final s = SheetLevelStack()
      ..open(const StopLevel('20001', 'Lion'))
      ..open(const SettingsLevel());
    expect(s.topStop, isNull);
    expect(s.pop(), isA<SettingsLevel>());
    expect(s.topStop?.id, '20001');
    expect(s.topStop?.name, 'Lion');
  });

  test('pin after pin keeps only the last eight', () {
    final s = SheetLevelStack();
    for (var i = 0; i < 12; i++) {
      s.open(StopLevel('$i', null));
    }
    expect(s.length, SheetLevelStack.maxDepth);
    expect(s.topStop?.id, '11');
    s.clear();
    expect(s.isEmpty, isTrue);
  });
}
