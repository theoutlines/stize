import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stize/core/map_support.dart';
import 'package:stize/domain/models/arrival.dart';
import 'package:stize/domain/models/favorite_stop.dart';
import 'package:stize/domain/models/stop.dart';
import 'package:stize/domain/repositories/arrivals_repository.dart';
import 'package:stize/domain/repositories/favorites_repository.dart';
import 'package:stize/l10n/app_localizations.dart';
import 'package:stize/presentation/providers/providers.dart';
import 'package:stize/presentation/widgets/arrival_tile.dart';
import 'package:stize/presentation/widgets/stop_sheet.dart';

// A board with one genuinely live vehicle (real GPS + trajectory + direction)
// and one placeholder row (junk garage, GPS pinned to the stop). The live row
// carries everything the map needs to build a marker from the arrival ALONE —
// no viewport fan-out — which is the whole point of the §C fix.
ArrivalsBoard _board() => ArrivalsBoard.fromJson({
      'stop_id': '20091',
      'stop_name': 'Batutova',
      'updated_at': DateTime.now().toUtc().toIso8601String(),
      'arrivals': [
        {
          'line': '79',
          'vehicle_type': 'bus',
          'eta_minutes': 3,
          'stops_remaining': 2,
          'route_id': '00079',
          'direction_route_id': '00079-B',
          'gps': {'lat': 44.802, 'lon': 20.478},
          'garage_no': 'P70260',
          'heading': 137.0,
          'trajectory': [
            {'lat': 44.802, 'lon': 20.478, 'eta_seconds': 0},
            {'lat': 44.804, 'lon': 20.480, 'eta_seconds': 40},
          ],
        },
        {
          'line': '79',
          'vehicle_type': 'bus',
          'eta_minutes': 7,
          'stops_remaining': 5,
          'route_id': '00079',
          // Placeholder: GPS is just the stop's coordinate, garage is junk.
          'gps': {'lat': 44.790, 'lon': 20.490},
          'garage_no': 'P5',
        },
      ],
      'service_status': 'ok',
    });

const _stop = Stop(stopId: '20091', name: 'Batutova', lat: 44.79, lon: 20.49, lines: ['79']);

class _FakeArrivals implements ArrivalsRepository {
  _FakeArrivals(this.board);
  final ArrivalsBoard board;
  @override
  Future<ArrivalsBoard> getArrivals(String stopId) async => board;
}

class _FakeFavorites implements FavoritesRepository {
  final _s = <FavoriteStop>[];
  @override
  Future<void> add(FavoriteStop stop) async => _s.add(stop);
  @override
  Future<List<FavoriteStop>> getFavorites() async => List.unmodifiable(_s);
  @override
  Future<bool> isFavorite(String stopId) async => _s.any((s) => s.stopId == stopId);
  @override
  Future<void> remove(String stopId) async => _s.removeWhere((s) => s.stopId == stopId);
}

Widget _host(void Function(Arrival, DateTime) onFocus) {
  return ProviderScope(
    overrides: [
      arrivalsRepositoryProvider.overrideWithValue(_FakeArrivals(_board())),
      favoritesRepositoryProvider.overrideWithValue(_FakeFavorites()),
      alertsProvider.overrideWith((ref) async => const []),
      stopLocationProvider('20091').overrideWith((ref) async => _stop),
      fleetCatalogProvider.overrideWith((ref) async => null),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => showStopSheet(
                context,
                stopId: '20091',
                stopName: 'Batutova',
                onFocusVehicle: onFocus,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  // The stop sheet renders no map itself, but be safe with the shared flag.
  setUp(() => kMapRenderingEnabled = false);
  tearDown(() => kMapRenderingEnabled = true);

  testWidgets(
      'tapping a live arrival row hands the map the full arrival (guaranteed '
      'marker data, no fan-out); placeholder rows are not tappable', (tester) async {
    Arrival? captured;
    DateTime? capturedAsOf;
    await tester.pumpWidget(_host((a, asOf) {
      captured = a;
      capturedAsOf = asOf;
    }));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final tiles = tester.widgetList<ArrivalTile>(find.byType(ArrivalTile)).toList();
    final live = tiles.firstWhere((t) => t.arrival.garageNo == 'P70260');
    final placeholder = tiles.firstWhere((t) => t.arrival.garageNo == 'P5');

    // The placeholder (list-only) offers no "show on map" action.
    expect(placeholder.onTap, isNull);
    // The live vehicle does.
    expect(live.onTap, isNotNull);

    live.onTap!.call();
    await tester.pumpAndSettle();

    // The map received the arrival's own data — enough to build a moving marker
    // WITHOUT any /vehicles/nearby fan-out.
    expect(captured, isNotNull);
    expect(captured!.garageNo, 'P70260');
    expect(captured!.gps, isNotNull);
    expect(captured!.directionRouteId, '00079-B');
    expect(captured!.heading, 137.0);
    expect(captured!.trajectory, isNotNull);
    expect(captured!.trajectory!.length, 2);
    // The as-of time anchors the timed-trajectory plan.
    expect(capturedAsOf, isNotNull);
  });
}
