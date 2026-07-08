import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stigla/data/api/api_exceptions.dart';
import 'package:stigla/domain/models/arrival.dart';
import 'package:stigla/domain/models/favorite_stop.dart';
import 'package:stigla/domain/models/route_alert.dart';
import 'package:stigla/domain/models/stop.dart';
import 'package:stigla/domain/repositories/arrivals_repository.dart';
import 'package:stigla/domain/repositories/favorites_repository.dart';
import 'package:stigla/l10n/app_localizations.dart';
import 'package:stigla/presentation/providers/providers.dart';
import 'package:stigla/presentation/screens/stop_screen.dart';

const _batutovaStop = Stop(stopId: '20091', name: 'Batutova', lat: 44.795374, lon: 20.499713, lines: ['79']);

// Real captured shape from the live backend for stop 20091 (Batutova, line 79).
final _sampleBoard = ArrivalsBoard.fromJson({
  'stop_id': '20091',
  'stop_name': 'Batutova',
  'updated_at': DateTime.now().toUtc().toIso8601String(),
  'arrivals': [
    {
      'line': '79',
      'vehicle_type': 'bus',
      'eta_minutes': 11,
      'stops_remaining': 6,
      'route_id': '00079',
      'gps': {'lat': 44.7870116, 'lon': 20.5365183},
      'garage_no': 'P26603',
    },
  ],
  'service_status': 'ok',
});

class _FakeArrivalsRepository implements ArrivalsRepository {
  _FakeArrivalsRepository(this.result);
  final Object result; // ArrivalsBoard or an Exception to throw

  @override
  Future<ArrivalsBoard> getArrivals(String stopId) async {
    if (result is Exception) throw result as Exception;
    return result as ArrivalsBoard;
  }
}

class _FakeFavoritesRepository implements FavoritesRepository {
  final List<FavoriteStop> _stops = [];

  @override
  Future<void> add(FavoriteStop stop) async => _stops.add(stop);

  @override
  Future<List<FavoriteStop>> getFavorites() async => List.unmodifiable(_stops);

  @override
  Future<bool> isFavorite(String stopId) async => _stops.any((s) => s.stopId == stopId);

  @override
  Future<void> remove(String stopId) async => _stops.removeWhere((s) => s.stopId == stopId);
}

Widget _wrap(
  Widget child, {
  required ArrivalsRepository arrivals,
  FavoritesRepository? favorites,
  List<RouteAlert> alerts = const [],
  Stop? stopLocation = _batutovaStop,
}) {
  return ProviderScope(
    overrides: [
      arrivalsRepositoryProvider.overrideWithValue(arrivals),
      if (favorites != null) favoritesRepositoryProvider.overrideWithValue(favorites),
      alertsProvider.overrideWith((ref) async => alerts),
      stopLocationProvider('20091').overrideWith((ref) async => stopLocation),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    ),
  );
}

void main() {
  testWidgets('renders a live arrival matching the real backend contract', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const StopScreen(stopId: '20091', initialStopName: 'Batutova'),
        arrivals: _FakeArrivalsRepository(_sampleBoard),
        favorites: _FakeFavoritesRepository(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Batutova'), findsOneWidget);
    expect(find.text('79'), findsOneWidget);
    expect(find.text('11 min'), findsOneWidget);
    expect(find.text('6 stops away'), findsOneWidget);
  });

  testWidgets('shows the human empty state when there are no arrivals', (tester) async {
    final emptyBoard = ArrivalsBoard.fromJson({
      'stop_id': '20091',
      'stop_name': 'Batutova',
      'updated_at': DateTime.now().toUtc().toIso8601String(),
      'arrivals': <Object>[],
      'service_status': 'ok',
    });

    await tester.pumpWidget(
      _wrap(
        const StopScreen(stopId: '20091', initialStopName: 'Batutova'),
        arrivals: _FakeArrivalsRepository(emptyBoard),
        favorites: _FakeFavoritesRepository(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text("It's quiet here right now"), findsOneWidget);
  });

  testWidgets('shows the kill-switch state without a scary error', (tester) async {
    final killedBoard = ArrivalsBoard.fromJson({
      'stop_id': '20091',
      'stop_name': '',
      'updated_at': DateTime.now().toUtc().toIso8601String(),
      'arrivals': <Object>[],
      'service_status': 'unavailable',
    });

    await tester.pumpWidget(
      _wrap(
        const StopScreen(stopId: '20091', initialStopName: 'Batutova'),
        arrivals: _FakeArrivalsRepository(killedBoard),
        favorites: _FakeFavoritesRepository(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text("We're taking a short break"), findsOneWidget);
  });

  testWidgets('shows the offline state on a network failure', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const StopScreen(stopId: '20091', initialStopName: 'Batutova'),
        arrivals: _FakeArrivalsRepository(const NetworkException('offline')),
        favorites: _FakeFavoritesRepository(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Looks like the connection dropped'), findsOneWidget);
  });

  testWidgets('shows a route alert banner when it matches a line serving this stop', (tester) async {
    final alert = RouteAlert(
      id: 'test-alert',
      url: 'https://www.bgprevoz.rs/vesti/test-alert',
      title: 'Test',
      publishedAt: DateTime(2026, 1, 1),
      lines: const ['79'],
      stops: const [],
      validFrom: null,
      validUntil: null,
      confidence: 'line',
      summary: 'Linija 79 menja trasu.',
    );

    await tester.pumpWidget(
      _wrap(
        const StopScreen(stopId: '20091', initialStopName: 'Batutova'),
        arrivals: _FakeArrivalsRepository(_sampleBoard),
        favorites: _FakeFavoritesRepository(),
        alerts: [alert],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Linija 79 menja trasu.'), findsOneWidget);
    expect(find.text('Route change'), findsOneWidget);
  });

  testWidgets('does not show an alert for an unrelated line', (tester) async {
    final alert = RouteAlert(
      id: 'test-alert',
      url: 'https://www.bgprevoz.rs/vesti/test-alert',
      title: 'Test',
      publishedAt: DateTime(2026, 1, 1),
      lines: const ['35'],
      stops: const [],
      validFrom: null,
      validUntil: null,
      confidence: 'line',
      summary: 'Linija 35 menja trasu.',
    );

    await tester.pumpWidget(
      _wrap(
        const StopScreen(stopId: '20091', initialStopName: 'Batutova'),
        arrivals: _FakeArrivalsRepository(_sampleBoard),
        favorites: _FakeFavoritesRepository(),
        alerts: [alert],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Linija 35 menja trasu.'), findsNothing);
  });

  testWidgets('toggling favorite updates the star icon', (tester) async {
    final favorites = _FakeFavoritesRepository();
    await tester.pumpWidget(
      _wrap(
        const StopScreen(stopId: '20091', initialStopName: 'Batutova'),
        arrivals: _FakeArrivalsRepository(_sampleBoard),
        favorites: favorites,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.star_outline), findsOneWidget);

    await tester.tap(find.byIcon(Icons.star_outline));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.star), findsOneWidget);
    expect(await favorites.isFavorite('20091'), isTrue);
  });
}
