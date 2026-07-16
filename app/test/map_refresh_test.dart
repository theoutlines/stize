import 'package:flutter_test/flutter_test.dart';
import 'package:stigla/core/map_refresh.dart';

void main() {
  group('mapRefreshAction — a live context never stops polling', () {
    test('off-demand refreshes the viewport aquarium', () {
      expect(
        mapRefreshAction(onDemand: false, stopContextId: null),
        MapRefresh.aquarium,
      );
      // Even with a context id lingering, off-demand is aquarium.
      expect(
        mapRefreshAction(onDemand: false, stopContextId: '20091'),
        MapRefresh.aquarium,
      );
    });

    test('on-demand with a stop/vehicle context re-polls that stop', () {
      expect(
        mapRefreshAction(onDemand: true, stopContextId: '20091'),
        MapRefresh.pollStop,
      );
    });

    test('on-demand with no context does nothing (state A)', () {
      expect(
        mapRefreshAction(onDemand: true, stopContextId: null),
        MapRefresh.none,
      );
    });

    // Regression guard for the freeze: the poll depends only on there being a
    // context, NOT on follow state — following a vehicle (after the stop sheet
    // closed) must keep the context id set, so the data keeps refreshing and
    // nothing freezes. `following` isn't even an input here by design.
    test('the decision has no follow input — follow cannot freeze the data', () {
      expect(
        mapRefreshAction(onDemand: true, stopContextId: '20256'),
        MapRefresh.pollStop,
      );
    });
  });
}
