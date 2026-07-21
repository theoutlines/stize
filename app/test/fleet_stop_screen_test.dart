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
import 'package:stize/presentation/screens/stop_screen.dart';
import 'package:stize/presentation/widgets/stop_sheet.dart';

// A tiny, deterministic catalog: two tram classes with very different comfort,
// so we exercise badges, the model card and the comfort sort without depending
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
   "comfort_score":5,"years_built":[2024,2026],"human_note_ru":"Novi tramvaj.",
   "confidence":{"ranges":"verified"}}
 ],
 "models_catalog": {},
 "vehicles": {}
}
''';

const _stop = Stop(stopId: '20091', name: 'Batutova', lat: 44.79, lon: 20.49, lines: ['12']);

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
  Future<bool> isFavorite(String stopId) async => _s.any((s) => s.stopId == stopId);
  @override
  Future<void> remove(String stopId) async => _s.removeWhere((s) => s.stopId == stopId);
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
      home: const StopScreen(stopId: '20091', initialStopName: 'Batutova'),
    ),
  );
}

void main() {
  setUp(() => kMapRenderingEnabled = false);
  tearDown(() => kMapRenderingEnabled = true);

  testWidgets('B5: a null catalog silently disables Fleet-ID, transit still works',
      (tester) async {
    await tester.pumpWidget(_wrap(catalog: null));
    await tester.pumpAndSettle();

    // Arrivals render normally.
    expect(find.text('12'), findsWidgets);
    expect(find.text('3 min'), findsOneWidget);
    // No fleet badges, no comfort sort, no crash.
    expect(find.byIcon(Icons.ac_unit), findsNothing);
    expect(find.text('By comfort'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('B2/B4: badges show, junk number is hidden, comfort sort appears',
      (tester) async {
    final catalog = FleetCatalog.tryParse(_catalogJson)!;
    await tester.pumpWidget(_wrap(catalog: catalog));
    await tester.pumpAndSettle();

    // Bozankaya has AC + low floor → those badges appear.
    expect(find.byIcon(Icons.ac_unit), findsOneWidget);
    expect(find.byIcon(Icons.accessible), findsOneWidget);

    // Two distinct classes → the comfort sort is offered.
    expect(find.text('By comfort'), findsOneWidget);
    expect(find.text('By time'), findsOneWidget);

    // The junk placeholder P5 is never shown anywhere.
    expect(find.textContaining('P5'), findsNothing);
    expect(find.textContaining('#P5'), findsNothing);
  });

  testWidgets('B4: sorting by comfort puts the Bozankaya above the Kata',
      (tester) async {
    final catalog = FleetCatalog.tryParse(_catalogJson)!;
    await tester.pumpWidget(_wrap(catalog: catalog));
    await tester.pumpAndSettle();

    // Default (time) order: Kata (3 min) is above Bozankaya (9 min).
    final kataY0 = tester.getTopLeft(find.text('3 min')).dy;
    final bozaY0 = tester.getTopLeft(find.text('9 min')).dy;
    expect(kataY0, lessThan(bozaY0));

    await tester.tap(find.text('By comfort'));
    await tester.pumpAndSettle();

    // Now the comfy Bozankaya (9 min) sits above the old Kata (3 min).
    final kataY1 = tester.getTopLeft(find.text('3 min')).dy;
    final bozaY1 = tester.getTopLeft(find.text('9 min')).dy;
    expect(bozaY1, lessThan(kataY1));
  });

  testWidgets('B3: card shows model on top, nickname below (ru locale)',
      (tester) async {
    final catalog = FleetCatalog.tryParse(_catalogJson)!;
    await tester.pumpWidget(_wrap(catalog: catalog, locale: const Locale('ru')));
    await tester.pumpAndSettle();

    // Tap the AC badge (only the Bozankaya has one).
    await tester.tap(find.byIcon(Icons.ac_unit));
    await tester.pumpAndSettle();

    expect(find.text('Bozankaya'), findsOneWidget); // model name, headline
    expect(find.text('Турчин'), findsOneWidget); // nickname beneath
    expect(find.text('Novi tramvaj.'), findsOneWidget); // human_note_ru
    expect(find.text('Производитель: Bozankaya, Турция'), findsOneWidget);

    // Model sits above the nickname.
    final modelY = tester.getTopLeft(find.text('Bozankaya')).dy;
    final nickY = tester.getTopLeft(find.text('Турчин')).dy;
    expect(modelY, lessThan(nickY));
  });

  testWidgets('B3: English card shows model on top, ASCII nickname below',
      (tester) async {
    final catalog = FleetCatalog.tryParse(_catalogJson)!;
    await tester.pumpWidget(_wrap(catalog: catalog, locale: const Locale('en')));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.ac_unit));
    await tester.pumpAndSettle();

    expect(find.text('Bozankaya'), findsOneWidget); // model headline
    expect(find.text('Turcin'), findsOneWidget); // ASCII nickname, for fun
    expect(find.text('Турчин'), findsNothing); // not the Cyrillic form
  });

  // Regression: the *in-app* tap path opens the map's bottom sheet
  // (stop_sheet.dart), not the full StopScreen. Fleet-ID must show there too.
  testWidgets('map stop sheet also shows Fleet-ID badges', (tester) async {
    final catalog = FleetCatalog.tryParse(_catalogJson)!;
    await tester.pumpWidget(
      ProviderScope(
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
                  onPressed: () => showStopSheet(context, stopId: '20091', stopName: 'Batutova'),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Sheet is open with Fleet-ID surfaced.
    expect(find.byIcon(Icons.ac_unit), findsOneWidget);
    expect(find.text('By comfort'), findsOneWidget);
    expect(find.textContaining('P5'), findsNothing); // junk hidden
  });
}
