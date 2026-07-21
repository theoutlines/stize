import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart' as ll;

import 'package:stize/core/context_slot.dart';
import 'package:stize/domain/models/arrival.dart';
import 'package:stize/domain/models/favorite_stop.dart';
import 'package:stize/domain/models/stop.dart';
import 'package:stize/domain/repositories/arrivals_repository.dart';
import 'package:stize/domain/repositories/favorites_repository.dart';
import 'package:stize/domain/repositories/nearby_arrivals_repository.dart';
import 'package:stize/domain/models/nearby_arrival.dart';
import 'package:stize/l10n/app_localizations.dart';
import 'package:stize/presentation/providers/providers.dart';
import 'package:stize/presentation/widgets/nearby_sheet.dart';
import 'package:stize/presentation/widgets/stop_sheet.dart';

// Every mobile bottom sheet must cap at `large` (owner R2 #4 / R3 #3): dragged
// to the top it stops at kSheetLarge, leaving a strip of map — never fullscreen.
// These tests prove the cap deterministically for each sheet path.

class _EmptyNearby implements NearbyArrivalsRepository {
  @override
  Future<NearbyResult> nearby({
    required double lat,
    required double lon,
    double radiusMeters = 500,
  }) async =>
      const NearbyResult(groups: [], serviceStatus: ServiceStatus.ok);
}

class _FakeArrivals implements ArrivalsRepository {
  @override
  Future<ArrivalsBoard> getArrivals(String stopId) async =>
      ArrivalsBoard.fromJson({
        'stop_id': stopId,
        'stop_name': 'Batutova',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
        'arrivals': const [],
        'service_status': 'ok',
      });
}

class _FakeFavorites implements FavoritesRepository {
  final _s = <FavoriteStop>[];
  @override
  Future<void> add(FavoriteStop stop) async => _s.add(stop);
  @override
  Future<List<FavoriteStop>> getFavorites() async => List.unmodifiable(_s);
  @override
  Future<bool> isFavorite(String id) async => _s.any((s) => s.stopId == id);
  @override
  Future<void> remove(String id) async => _s.removeWhere((s) => s.stopId == id);
}

Widget _app(Widget home, {List<Override> overrides = const []}) => ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: home),
      ),
    );

DraggableScrollableSheet _theSheet(WidgetTester tester) =>
    tester.widget<DraggableScrollableSheet>(
        find.byType(DraggableScrollableSheet));

void main() {
  testWidgets('detent constants: large is not fullscreen', (_) async {
    expect(kSheetLarge, lessThan(1.0));
    expect(kSheetDetents.last, kSheetLarge);
  });

  testWidgets('Nearby sheet caps at large (maxChildSize + snap)', (tester) async {
    await tester.pumpWidget(_app(
      NearbySheet(
        userLocation: ll.LatLng(44.8, 20.5),
        locationDenied: false,
        active: true,
        onEnableLocation: () {},
      ),
      overrides: [
        nearbyArrivalsRepositoryProvider.overrideWithValue(_EmptyNearby()),
      ],
    ));
    await tester.pump();
    final sheet = _theSheet(tester);
    expect(sheet.maxChildSize, kSheetLarge);
    expect(sheet.snapSizes, contains(kSheetLarge));
    expect(sheet.snapSizes!.every((s) => s <= kSheetLarge), isTrue);
    await tester.pumpWidget(const SizedBox()); // cancel the 30s timer
  });

  testWidgets('Stop sheet caps at large', (tester) async {
    const stop = Stop(
        stopId: '20091', name: 'Batutova', lat: 44.79, lon: 20.49, lines: ['79']);
    late BuildContext ctx;
    await tester.pumpWidget(_app(
      Builder(builder: (c) {
        ctx = c;
        return const SizedBox();
      }),
      overrides: [
        arrivalsRepositoryProvider.overrideWithValue(_FakeArrivals()),
        favoritesRepositoryProvider.overrideWithValue(_FakeFavorites()),
        alertsProvider.overrideWith((ref) async => const []),
        stopLocationProvider('20091').overrideWith((ref) async => stop),
        fleetCatalogProvider.overrideWith((ref) async => null),
      ],
    ));
    showStopSheet(ctx, stopId: '20091', stopName: 'Batutova');
    await tester.pump();
    await tester.pump();
    final sheet = _theSheet(tester);
    expect(sheet.maxChildSize, kSheetLarge);
    expect(sheet.snapSizes, contains(kSheetLarge));
  });
}
