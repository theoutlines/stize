import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

import 'package:stigla/data/location/location_service.dart';
import 'package:stigla/domain/models/favorite_stop.dart';
import 'package:stigla/domain/models/geocode_result.dart';
import 'package:stigla/domain/models/line_info.dart';
import 'package:stigla/domain/models/route_shape.dart';
import 'package:stigla/domain/models/stop.dart';
import 'package:stigla/domain/models/vehicle_type.dart';
import 'package:stigla/domain/repositories/favorites_repository.dart';
import 'package:stigla/domain/repositories/geocode_repository.dart';
import 'package:stigla/domain/repositories/lines_repository.dart';
import 'package:stigla/domain/repositories/stops_repository.dart';
import 'package:stigla/l10n/app_localizations.dart';
import 'package:stigla/presentation/providers/providers.dart';
import 'package:stigla/presentation/screens/home_map_screen.dart';

const _batutova91 = Stop(stopId: '20091', name: 'Batutova', lat: 44.795374, lon: 20.499713, lines: ['79']);
const _line79 = LineInfo(
  line: '79',
  vehicleType: VehicleType.bus,
  routeId: '00079',
  origin: 'Dorćol',
  destination: 'Mirijevo 4',
);

class _FakeStopsRepository implements StopsRepository {
  _FakeStopsRepository({this.searchResult = const [], this.nearbyResult = const []});
  final List<Stop> searchResult;
  final List<Stop> nearbyResult;

  @override
  Future<List<Stop>> search(String query) async => searchResult;

  @override
  Future<List<Stop>> nearby({required double lat, required double lon, double radiusMeters = 500}) async =>
      nearbyResult;
}

class _FakeLinesRepository implements LinesRepository {
  @override
  Future<List<LineInfo>> search(String query) async => [_line79];

  @override
  Future<RouteShape> getShapeByLineNumber(String line) => throw UnimplementedError();
}

class _FakeGeocodeRepository implements GeocodeRepository {
  @override
  Future<List<GeocodeResult>> search(String query) async => const [
        GeocodeResult(displayName: 'Batutova, Beograd', lat: 44.79, lon: 20.50),
      ];
}

class _FakeFavoritesRepository implements FavoritesRepository {
  @override
  Future<void> add(FavoriteStop stop) async {}

  @override
  Future<List<FavoriteStop>> getFavorites() async => const [];

  @override
  Future<bool> isFavorite(String stopId) async => false;

  @override
  Future<void> remove(String stopId) async {}
}

class _DeniedLocationService implements LocationService {
  @override
  Future<Position> getCurrentPosition() async {
    throw const LocationUnavailable(LocationUnavailableReason.permissionDenied);
  }
}

Widget _wrap({List<Stop> searchResult = const []}) {
  return ProviderScope(
    overrides: [
      stopsRepositoryProvider.overrideWithValue(_FakeStopsRepository(searchResult: searchResult)),
      linesRepositoryProvider.overrideWithValue(_FakeLinesRepository()),
      geocodeRepositoryProvider.overrideWithValue(_FakeGeocodeRepository()),
      favoritesRepositoryProvider.overrideWithValue(_FakeFavoritesRepository()),
      locationServiceProvider.overrideWithValue(_DeniedLocationService()),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const HomeMapScreen(),
    ),
  );
}

void main() {
  testWidgets('boots showing the map and search bar, no crash without location', (tester) async {
    await tester.pumpWidget(_wrap());
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
    expect(find.byIcon(Icons.my_location), findsOneWidget);
  });

  testWidgets('typing a query shows matching stops, lines, and places', (tester) async {
    await tester.pumpWidget(_wrap(searchResult: const [_batutova91]));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Batutova');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(ListTile, 'Batutova'), findsOneWidget);
    expect(find.text('Dorćol → Mirijevo 4'), findsOneWidget);
    expect(find.text('Batutova, Beograd'), findsOneWidget);
  });

  testWidgets('clearing search hides the results overlay', (tester) async {
    await tester.pumpWidget(_wrap(searchResult: const [_batutova91]));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Batutova');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ListTile, 'Batutova'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(ListTile, 'Batutova'), findsNothing);
    expect(find.byIcon(Icons.my_location), findsOneWidget);
  });
}
