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
import 'package:stize/presentation/screens/stop_screen.dart';

const _stop = Stop(stopId: '20091', name: 'Batutova', lat: 44.79, lon: 20.49, lines: ['12']);

// The bug: during a live-data outage the board comes back service_status
// "unavailable" but WITH scheduled rows (they need only our own GTFS bundle).
// The shutter must render the timetable with a banner, not the "short break"
// wall — the wall is only for a board with genuinely nothing on it.
ArrivalsBoard _boardWithSchedule() => ArrivalsBoard.fromJson({
      'stop_id': '20091',
      'stop_name': 'Batutova',
      'updated_at': DateTime.now().toUtc().toIso8601String(),
      'arrivals': [
        {
          'line': '12',
          'vehicle_type': 'tram',
          'eta_minutes': 6,
          'stops_remaining': null,
          'route_id': '00012',
          'gps': null,
          'garage_no': null,
          'source': 'scheduled',
        },
      ],
      'service_status': 'unavailable',
    });

ArrivalsBoard _boardEmpty() => ArrivalsBoard.fromJson({
      'stop_id': '20091',
      'stop_name': 'Batutova',
      'updated_at': DateTime.now().toUtc().toIso8601String(),
      'arrivals': <Map<String, dynamic>>[],
      'service_status': 'unavailable',
    });

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

Widget _wrap(ArrivalsBoard board) => ProviderScope(
      overrides: [
        arrivalsRepositoryProvider.overrideWithValue(_FakeArrivals(board)),
        favoritesRepositoryProvider.overrideWithValue(_FakeFavorites()),
        alertsProvider.overrideWith((ref) async => const []),
        stopLocationProvider('20091').overrideWith((ref) async => _stop),
        fleetCatalogProvider.overrideWith((ref) async => null),
      ],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: StopScreen(stopId: '20091', initialStopName: 'Batutova'),
      ),
    );

void main() {
  setUp(() => kMapRenderingEnabled = false);
  tearDown(() => kMapRenderingEnabled = true);

  testWidgets('outage + scheduled rows: renders the timetable with a banner, not the wall',
      (tester) async {
    await tester.pumpWidget(_wrap(_boardWithSchedule()));
    await tester.pumpAndSettle();

    // The schedule row is shown...
    expect(find.text('12'), findsWidgets);
    // ...with the "live unavailable — timetable" banner above it...
    expect(find.text('Live data temporarily unavailable — timetable'), findsOneWidget);
    // ...and NOT the "short break" wall.
    expect(find.text("We're taking a short break"), findsNothing);
  });

  testWidgets('outage with genuinely nothing: still shows the wall', (tester) async {
    await tester.pumpWidget(_wrap(_boardEmpty()));
    await tester.pumpAndSettle();

    expect(find.text("We're taking a short break"), findsOneWidget);
    expect(find.text('Live data temporarily unavailable — timetable'), findsNothing);
  });
}
