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

  group('contextBoardNeedsRefetch — SWR second tap keeps the board fresh', () {
    test('a within-TTL board is left alone', () {
      // A board younger than the SWR TTL is as fresh as SWR will hand out; a
      // second tap would just re-read the same entry.
      expect(contextBoardNeedsRefetch(0), isFalse);
      expect(contextBoardNeedsRefetch(20), isFalse);
      expect(contextBoardNeedsRefetch(30), isFalse);
    });

    test('a stale (>TTL) board triggers a second tap to grab the fresh copy', () {
      // A single SWR fetch returned an entry older than its TTL (and kicked off a
      // background revalidation); pull the revalidated copy a beat later.
      expect(contextBoardNeedsRefetch(35), isTrue);
      expect(contextBoardNeedsRefetch(58), isTrue);
      expect(contextBoardNeedsRefetch(187), isTrue);
    });

    test('the threshold sits above the 30s SWR TTL and below the 45s gate', () {
      // Otherwise a "fresh enough" board would be re-tapped forever (hammering),
      // or a board would be allowed to cross the playback staleness gate (freeze).
      expect(kContextRefetchThresholdSeconds, greaterThan(30));
      expect(kContextRefetchThresholdSeconds, lessThan(45));
    });
  });
}
