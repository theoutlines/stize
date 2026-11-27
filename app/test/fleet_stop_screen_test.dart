import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stize/core/fleet_matcher.dart';
import 'package:stize/core/map_support.dart';
import 'package:stize/domain/models/arrival.dart';
import 'package:stize/domain/models/favorite_stop.dart';
import 'package:stize/domain/models/stop.dart';
import 'package:stize/domain/repositories/arrivals_repository.dart';
import 'package:stize/domain/repositories/favorites_repository.dart';
import 'package:stize/l10n/app_localizations.dart';
import 'package:stize/presentation/providers/providers.dart';
import 'helpers/stop_board_page.dart';
import 'package:stize/presentation/widgets/follow_view.dart';
import 'package:stize/domain/models/vehicle_type.dart';

// A tiny, deterministic catalog: two tram classes with very different comfort,
// so we exercise the board's fleet handling without depending
// on the full production asset.
const _catalogJson = '''
{
 "classes": [
  {"id":"kt4","type":"tram","ranges":[[80201,80399]],"model":"Tatra KT4YU",
   "nickname_sr":"Ката","ac":false,"low_floor":false,"usb":false,
   "articulated":true,"length_m":18.1,"capacity":135,"powertrain":"tram",
   "comfort_score":1,"years_built":[1980,1990],"human_note_ru":"Stara Kata.",
   "confidence":{"ranges":"verified","ac":"verified"}},
  {"id":"bozankaya","type":"tram","ranges":[[81531,81560]],"model":"Bozankaya",
   "manufacturer":"Bozankaya","country":"TR",
   "nickname_sr":"Турчин","nickname_latin":"Turčin","nickname_en":"Turcin",
   "ac":true,"low_floor":true,"usb":true,
   "articulated":true,"length_m":30.5,"capacity":218,"powertrain":"tram",
   "comfort_score":5,"years_built":[2024,2026],"human_note_ru":"Новый трамвай.","human_note_sr":"Novi tramvaj.",
   "confidence":{"ranges":"verified"}}
 ],
 "models_catalog": {},
 "vehicles": {}
}
''';

const _stop = Stop(
  stopId: '20091',
  name: 'Batutova',
  lat: 44.79,
  lon: 20.49,
  lines: ['12'],
);

// Line 12: the real-life case — a comfy Bozankaya vs. an old Kata. Kata arrives
// sooner (default time order), Bozankaya is far more comfortable.
ArrivalsBoard _board() => ArrivalsBoard.fromJson({
  'stop_id': '20091',
  'stop_name': 'Batutova',
  'updated_at': DateTime.now().toUtc().toIso8601String(),
  'arrivals': [
    {
      'line': '12',
      'vehicle_type': 'tram',
      'eta_minutes': 3,
      'stops_remaining': 2,
      'route_id': '00012',
      'gps': null,
      'garage_no': 'P80210', // Kata, comfort 1
    },
    {
      'line': '12',
      'vehicle_type': 'tram',
      'eta_minutes': 9,
      'stops_remaining': 5,
      'route_id': '00012',
      'gps': null,
      'garage_no': 'P81540', // Bozankaya, comfort 5
    },
    {
      'line': '12',
      'vehicle_type': 'tram',
      'eta_minutes': 1,
      'stops_remaining': 1,
      'route_id': '00012',
      'gps': null,
      'garage_no': 'P5', // junk placeholder — number must never be shown
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
  Future<bool> isFavorite(String stopId) async =>
      _s.any((s) => s.stopId == stopId);
  @override
  Future<void> remove(String stopId) async =>
      _s.removeWhere((s) => s.stopId == stopId);
}

Widget _wrap({required FleetCatalog? catalog, Locale? locale}) {
  return ProviderScope(
    overrides: [
      arrivalsRepositoryProvider.overrideWithValue(_FakeArrivals(_board())),
      favoritesRepositoryProvider.overrideWithValue(_FakeFavorites()),
      alertsProvider.overrideWith((ref) async => const []),
      stopLocationProvider('20091').overrideWith((ref) async => _stop),
      fleetCatalogProvider.overrideWith((ref) async => catalog),
    ],
    child: MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const StopBoardPage(stopId: '20091', initialStopName: 'Batutova'),
    ),
  );
}

void main() {
  setUp(() => kMapRenderingEnabled = false);
  tearDown(() => kMapRenderingEnabled = true);

  testWidgets(
    'B5: a null catalog silently disables Fleet-ID, transit still works',
    (tester) async {
      await tester.pumpWidget(_wrap(catalog: null));
      await tester.pumpAndSettle();

      // Arrivals render normally.
      expect(find.text('12'), findsWidgets);
      expect(find.text('3'), findsOneWidget);
      // No fleet badges, no comfort sort, no crash.
      expect(find.text('By comfort'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('board cards carry no fleet badges, no junk number, no sort', (
    tester,
  ) async {
    final catalog = FleetCatalog.tryParse(_catalogJson)!;
    await tester.pumpWidget(_wrap(catalog: catalog));
    await tester.pumpAndSettle();

    // Model, age and amenities moved to the follow screen (owner,
    // 2026-11-25): a board card only says how to catch the vehicle.
    expect(find.text('By comfort'), findsNothing);
    expect(find.text('By time'), findsNothing);
    expect(find.textContaining('P5'), findsNothing);
  });

  testWidgets('the board is always in time order', (tester) async {
    final catalog = FleetCatalog.tryParse(_catalogJson)!;
    await tester.pumpWidget(_wrap(catalog: catalog));
    await tester.pumpAndSettle();

    // Kata (3 min) stays above the more comfortable Bozankaya (9 min).
    final kataY = tester.getTopLeft(find.text('3')).dy;
    final bozaY = tester.getTopLeft(find.text('9')).dy;
    expect(kataY, lessThan(bozaY));
  });

  Widget vehicleCard(FleetCatalog catalog, Locale locale) => ProviderScope(
    overrides: [fleetCatalogProvider.overrideWith((ref) async => catalog)],
    child: MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(
          child: FleetVehicleCard(
            fleet: catalog.resolve('81540'),
            type: VehicleType.tram,
            garageNo: '81540',
          ),
        ),
      ),
    ),
  );

  testWidgets('follow card: model with the Latin nickname (sr locale)', (
    tester,
  ) async {
    final catalog = FleetCatalog.tryParse(_catalogJson)!;
    await tester.pumpWidget(vehicleCard(catalog, const Locale('sr')));
    await tester.pumpAndSettle();

    expect(find.text('Bozankaya'), findsOneWidget); // model name, headline
    expect(find.text('“Turčin” · #81540'), findsOneWidget); // Latin nickname
    expect(find.textContaining('Турчин'), findsNothing); // never Cyrillic
    expect(find.text('Novi tramvaj.'), findsOneWidget); // human_note_sr
    expect(find.text('Новый трамвай.'), findsNothing); // never the ru source

    final modelY = tester.getTopLeft(find.text('Bozankaya')).dy;
    final nickY = tester.getTopLeft(find.textContaining('Turčin')).dy;
    expect(modelY, lessThan(nickY));
  });

  testWidgets('follow card: model with the ASCII nickname (en locale)', (
    tester,
  ) async {
    final catalog = FleetCatalog.tryParse(_catalogJson)!;
    await tester.pumpWidget(vehicleCard(catalog, const Locale('en')));
    await tester.pumpAndSettle();

    expect(find.text('Bozankaya'), findsOneWidget);
    expect(find.text('“Turcin” · #81540'), findsOneWidget);
    expect(find.textContaining('Турчин'), findsNothing);
    expect(find.text('Articulated'), findsOneWidget);
    expect(find.text('~218 people'), findsOneWidget);
  });
}
