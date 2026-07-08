import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

import 'package:stigla/data/location/location_service.dart';
import 'package:stigla/domain/models/geocode_result.dart';
import 'package:stigla/domain/models/line_info.dart';
import 'package:stigla/domain/models/route_shape.dart';
import 'package:stigla/domain/models/stop.dart';
import 'package:stigla/domain/models/vehicle_type.dart';
import 'package:stigla/domain/repositories/geocode_repository.dart';
import 'package:stigla/domain/repositories/lines_repository.dart';
import 'package:stigla/domain/repositories/stops_repository.dart';
import 'package:stigla/l10n/app_localizations.dart';
import 'package:stigla/presentation/providers/providers.dart';
import 'package:stigla/presentation/screens/search_screen.dart';

const _batutova91 = Stop(stopId: '20091', name: 'Batutova', lat: 44.795374, lon: 20.499713, lines: ['79']);
const _batutova97 = Stop(stopId: '20097', name: 'Batutova', lat: 44.795946, lon: 20.498157, lines: ['5', '7L']);
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
  _FakeLinesRepository([this.result = const []]);
  final List<LineInfo> result;

  @override
  Future<List<LineInfo>> search(String query) async => result;

  @override
  Future<RouteShape> getShapeByLineNumber(String line) {
    throw UnimplementedError();
  }
}

class _FakeGeocodeRepository implements GeocodeRepository {
  _FakeGeocodeRepository([this.result = const []]);
  final List<GeocodeResult> result;

  @override
  Future<List<GeocodeResult>> search(String query) async => result;
}

class _DeniedLocationService implements LocationService {
  @override
  Future<Position> getCurrentPosition() async {
    throw const LocationUnavailable(LocationUnavailableReason.permissionDenied);
  }
}

Widget _wrap(
  Widget child, {
  required StopsRepository stops,
  LinesRepository? lines,
  GeocodeRepository? geocode,
  LocationService? location,
}) {
  return ProviderScope(
    overrides: [
      stopsRepositoryProvider.overrideWithValue(stops),
      linesRepositoryProvider.overrideWithValue(lines ?? _FakeLinesRepository()),
      geocodeRepositoryProvider.overrideWithValue(geocode ?? _FakeGeocodeRepository()),
      locationServiceProvider.overrideWithValue(location ?? _DeniedLocationService()),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    ),
  );
}

void main() {
  testWidgets('shows the soft empty state when location is denied and no query typed', (tester) async {
    await tester.pumpWidget(_wrap(const SearchScreen(), stops: _FakeStopsRepository()));
    await tester.pumpAndSettle();

    expect(find.text('Turn on location, or search for a stop, street, or line above.'), findsOneWidget);
  });

  testWidgets('typing a query shows matching stops, lines, and places', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const SearchScreen(),
        stops: _FakeStopsRepository(searchResult: const [_batutova91, _batutova97]),
        lines: _FakeLinesRepository(const [_line79]),
        geocode: _FakeGeocodeRepository(
          const [GeocodeResult(displayName: 'Batutova, Beograd', lat: 44.79, lon: 20.50)],
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Batutova');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(ListTile, 'Batutova'), findsNWidgets(2));
    expect(find.text('Dorćol → Mirijevo 4'), findsOneWidget);
    expect(find.text('Batutova, Beograd'), findsOneWidget);
  });

  testWidgets('shows nearby stops automatically when location succeeds', (tester) async {
    final fakeLocation = _FakeLocationService();
    await tester.pumpWidget(
      _wrap(
        const SearchScreen(),
        stops: _FakeStopsRepository(nearbyResult: const [_batutova91]),
        location: fakeLocation,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Nearby stops'), findsOneWidget);
    expect(find.text('Batutova'), findsOneWidget);
  });
}

class _FakeLocationService implements LocationService {
  @override
  Future<Position> getCurrentPosition() async {
    return Position(
      latitude: 44.795374,
      longitude: 20.499713,
      timestamp: DateTime.now(),
      accuracy: 5,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );
  }
}
