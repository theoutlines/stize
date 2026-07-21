import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart' as ll;

import 'package:stize/core/map_support.dart';
import 'package:stize/domain/models/app_config.dart';
import 'package:stize/domain/models/arrival.dart';
import 'package:stize/domain/models/favorite_stop.dart';
import 'package:stize/domain/models/jam.dart';
import 'package:stize/domain/models/stop.dart';
import 'package:stize/domain/repositories/arrivals_repository.dart';
import 'package:stize/domain/repositories/favorites_repository.dart';
import 'package:stize/l10n/app_localizations.dart';
import 'package:stize/presentation/providers/providers.dart';
import 'package:stize/presentation/screens/stop_screen.dart';

const _stop = Stop(stopId: '20100', name: 'dr Velizara Kosanovića', lat: 44.80, lon: 20.46, lines: ['6']);

final _board = ArrivalsBoard.fromJson({
  'stop_id': '20100',
  'stop_name': 'dr Velizara Kosanovića',
  'updated_at': DateTime.now().toUtc().toIso8601String(),
  'arrivals': [
    {'line': '6', 'vehicle_type': 'tram', 'eta_minutes': 5, 'stops_remaining': 3, 'route_id': '00006', 'gps': {'lat': 44.79, 'lon': 20.49}, 'garage_no': 'P80300'},
  ],
  'service_status': 'ok',
});

class _FakeArrivals implements ArrivalsRepository {
  @override
  Future<ArrivalsBoard> getArrivals(String stopId) async => _board;
}

class _FakeFavs implements FavoritesRepository {
  @override
  Future<void> add(FavoriteStop stop) async {}
  @override
  Future<List<FavoriteStop>> getFavorites() async => const [];
  @override
  Future<bool> isFavorite(String stopId) async => false;
  @override
  Future<void> remove(String stopId) async {}
}

JamsBoard _simBoard() => JamsBoard(
      feedHealthy: true,
      jams: [
        Jam(
          line: '6',
          directionRouteId: '00006',
          vehicles: const [],
          frozenSecs: 360,
          hasSubstitute: false,
          segmentRear: const ll.LatLng(44.7986, 20.4917),
          segmentFront: const ll.LatLng(44.7930, 20.5049),
          affectedStopIds: const {'20100', '20102', '20104', '20106'},
          simulated: true,
        ),
      ],
      substitutions: const [],
    );

void main() {
  setUp(() => kMapRenderingEnabled = false);
  tearDown(() => kMapRenderingEnabled = true);

  testWidgets('delay banner shows on a downstream stop when the jam flag is on', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          arrivalsRepositoryProvider.overrideWithValue(_FakeArrivals()),
          favoritesRepositoryProvider.overrideWithValue(_FakeFavs()),
          alertsProvider.overrideWith((ref) async => const []),
          stopLocationProvider('20100').overrideWith((ref) async => _stop),
          appConfigProvider.overrideWith(
            (ref) async => const AppConfig(version: 't', flags: {'jam_detection_show': true}),
          ),
          jamsProvider.overrideWith((ref) async => _simBoard()),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const StopScreen(stopId: '20100', initialStopName: 'dr Velizara Kosanovića'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('possible delay'), findsOneWidget,
        reason: 'downstream delay banner should render');
  });
}
