import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stigla/core/context_slot.dart';
import 'package:stigla/core/fleet_matcher.dart';
import 'package:stigla/core/map_support.dart';
import 'package:stigla/domain/models/arrival.dart';
import 'package:stigla/domain/models/favorite_stop.dart';
import 'package:stigla/domain/models/stop.dart';
import 'package:stigla/domain/repositories/arrivals_repository.dart';
import 'package:stigla/domain/repositories/favorites_repository.dart';
import 'package:stigla/l10n/app_localizations.dart';
import 'package:stigla/presentation/providers/providers.dart';
import 'package:stigla/presentation/widgets/fleet_model_card.dart';
import 'package:stigla/presentation/widgets/stop_board.dart';
import 'package:stigla/presentation/widgets/stop_sheet.dart';

// One AC/low-floor tram so a Fleet-ID badge is tappable → opens the fleet card.
const _catalogJson = '''
{
 "classes": [
  {"id":"bozankaya","type":"tram","ranges":[[81531,81560]],"model":"Bozankaya",
   "manufacturer":"Bozankaya","country":"TR","nickname_sr":"Турчин",
   "ac":true,"low_floor":true,"usb":true,"articulated":true,"length_m":30.5,
   "capacity":218,"powertrain":"tram","comfort_score":5,"years_built":[2024,2026],
   "human_note_ru":"Novi tramvaj.","confidence":{"ranges":"verified"}}
 ],
 "models_catalog": {},
 "vehicles": {}
}
''';

const _stop = Stop(stopId: '20091', name: 'Batutova', lat: 44.79, lon: 20.49, lines: ['12']);

ArrivalsBoard _board() => ArrivalsBoard.fromJson({
      'stop_id': '20091',
      'stop_name': 'Batutova',
      'updated_at': DateTime.now().toUtc().toIso8601String(),
      'arrivals': [
        {
          'line': '12',
          'vehicle_type': 'tram',
          'eta_minutes': 9,
          'stops_remaining': 5,
          'route_id': '00012',
          'gps': null,
          'garage_no': 'P81540', // Bozankaya, has AC → tappable badge
        },
      ],
      'service_status': 'ok',
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

Widget _host({ValueChanged<double>? onHeightChanged}) {
  final catalog = FleetCatalog.tryParse(_catalogJson)!;
  return ProviderScope(
    overrides: [
      arrivalsRepositoryProvider.overrideWithValue(_FakeArrivals(_board())),
      favoritesRepositoryProvider.overrideWithValue(_FakeFavorites()),
      alertsProvider.overrideWith((ref) async => const []),
      stopLocationProvider('20091').overrideWith((ref) async => _stop),
      fleetCatalogProvider.overrideWith((ref) async => catalog),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => showStopSheet(context,
                  stopId: '20091',
                  stopName: 'Batutova',
                  onHeightChanged: onHeightChanged),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  setUp(() => kMapRenderingEnabled = false);
  tearDown(() => kMapRenderingEnabled = true);

  testWidgets(
      'stop sheet feeds its live height to the map geometry owner '
      '(non-zero bottom inset while open — R2 #3 regression)', (tester) async {
    double? reported;
    await tester.pumpWidget(_host(onHeightChanged: (h) => reported = h));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // A small drag on the sheet dispatches a DraggableScrollableNotification,
    // which the sheet forwards as its live pixel height (the app relies on this
    // exact wiring to shift the map).
    await tester.drag(find.byType(StopBoard), const Offset(0, 40));
    await tester.pumpAndSettle();

    // The sheet reported a positive height → the map can shift up to keep the
    // stop above the sheet (mapInsetsFor gets a bottom inset, not zero).
    expect(reported, isNotNull);
    expect(reported!, greaterThan(0));

    // Sanity: that height feeds a positive bottom map inset.
    final insets = mapInsetsFor(
        panelActive: false, panelWidth: 0, mobileSheetPx: reported!);
    expect(insets.bottom, greaterThan(0));
  });

  testWidgets(
      'fleet card opens as an in-sheet subview and back returns to the board; '
      'detents unchanged through the swap', (tester) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // The board is up (its comfort/time sort is a board-only control) and no
    // fleet subview yet.
    expect(find.byType(StopBoard), findsOneWidget);
    expect(find.byType(FleetModelView), findsNothing);

    // Detent contract before the swap.
    double maxDetent() => tester
        .widget<DraggableScrollableSheet>(find.byType(DraggableScrollableSheet))
        .maxChildSize;
    expect(maxDetent(), kSheetLarge);

    // Tap the Fleet-ID (AC) badge → the sheet swaps to the fleet card subview,
    // in the SAME sheet (no second modal barrier).
    await tester.tap(find.byIcon(Icons.ac_unit));
    await tester.pumpAndSettle();

    expect(find.byType(FleetModelView), findsOneWidget);
    // Model name shows in the back header AND as the card headline (same pairing
    // as the desktop panel: nav-row title + card headline).
    expect(find.text('Bozankaya'), findsWidgets);
    expect(find.byIcon(Icons.arrow_back), findsOneWidget); // back header
    expect(find.byType(StopBoard), findsNothing); // board swapped out
    // The sheet is the same one — detents are unchanged through the swap.
    expect(maxDetent(), kSheetLarge);

    // Back returns to the exact previous view (the arrivals board).
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();

    expect(find.byType(FleetModelView), findsNothing);
    expect(find.byType(StopBoard), findsOneWidget);
    expect(maxDetent(), kSheetLarge);
  });
}
