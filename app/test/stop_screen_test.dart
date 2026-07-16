import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stigla/core/map_support.dart';
import 'package:stigla/data/api/api_exceptions.dart';
import 'package:stigla/domain/models/app_config.dart';
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
  bool livePositionOnly = false,
}) {
  return ProviderScope(
    overrides: [
      arrivalsRepositoryProvider.overrideWithValue(arrivals),
      if (favorites != null) favoritesRepositoryProvider.overrideWithValue(favorites),
      alertsProvider.overrideWith((ref) async => alerts),
      stopLocationProvider('20091').overrideWith((ref) async => stopLocation),
      appConfigProvider.overrideWith(
        (ref) async => AppConfig(
          version: 'test',
          flags: {'live_position_only': livePositionOnly},
        ),
      ),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    ),
  );
}

void main() {
  // MapLibre (the live-vehicles mini-map) has no platform impl under
  // `flutter test`; render it as a placeholder so StopScreen can be pumped.
  setUp(() => kMapRenderingEnabled = false);
  tearDown(() => kMapRenderingEnabled = true);

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

  testWidgets('live_position_only: an all-placeholder stop shows the explained '
      'hint instead of a map, but still lists the line', (tester) async {
    // One arrival, a schedule placeholder: junk garage P1 with GPS pinned to the
    // stop's own coordinate — exactly the upstream shape that used to draw a
    // motionless marker on the stop.
    final placeholderBoard = ArrivalsBoard.fromJson({
      'stop_id': '20091',
      'stop_name': 'Batutova',
      'updated_at': DateTime.now().toUtc().toIso8601String(),
      'arrivals': [
        {
          'line': '79',
          'vehicle_type': 'bus',
          'eta_minutes': 4,
          'stops_remaining': 1,
          'route_id': '00079',
          'gps': {'lat': 44.795374, 'lon': 20.499713}, // == stop coordinate
          'garage_no': 'P1', // junk placeholder pool
        },
      ],
      'service_status': 'ok',
    });

    await tester.pumpWidget(
      _wrap(
        const StopScreen(stopId: '20091', initialStopName: 'Batutova'),
        arrivals: _FakeArrivalsRepository(placeholderBoard),
        favorites: _FakeFavoritesRepository(),
        livePositionOnly: true,
      ),
    );
    await tester.pumpAndSettle();

    // The line stays in the arrivals list (its ETA is valid) ...
    expect(find.text('79'), findsOneWidget);
    // ... but the map slot is replaced by the explained empty state.
    expect(
      find.text('No live-tracked vehicles to map right now — see the arrivals below.'),
      findsOneWidget,
    );
  });

  testWidgets('renders a scheduled (timetable) arrival marked as such', (tester) async {
    final board = ArrivalsBoard.fromJson({
      'stop_id': '20091',
      'stop_name': 'Batutova',
      'updated_at': DateTime.now().toUtc().toIso8601String(),
      'arrivals': [
        {
          'line': '79',
          'vehicle_type': 'bus',
          'eta_minutes': 12,
          'stops_remaining': null,
          'route_id': '00079',
          'gps': null,
          'garage_no': null,
          'source': 'scheduled',
        },
      ],
      'service_status': 'ok',
    });

    await tester.pumpWidget(
      _wrap(
        const StopScreen(stopId: '20091', initialStopName: 'Batutova'),
        arrivals: _FakeArrivalsRepository(board),
        favorites: _FakeFavoritesRepository(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('79'), findsOneWidget);
    expect(find.text('12 min'), findsOneWidget);
    expect(find.text('Scheduled'), findsOneWidget); // planned marker
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

  testWidgets('a stop with many lines scrolls the filter chips instead of '
      'clipping them, and filtering still works', (tester) async {
    // Suburban node (e.g. Baćevac) carrying 22 lines. Before the fix the chips
    // were a Wrap that ballooned into a tall block; now they must be a single
    // horizontally-scrolling row that neither overflows nor drops chips.
    const manyLines = [
      '401', '402', '403', '404', '405', '407', '408', '410', '411', '412',
      '413', '525', '526', '527', '551', '552', '553', '554', '555', '860',
      '862', '863',
    ];
    const bacevac = Stop(
      stopId: '20091',
      name: 'Baćevac',
      lat: 44.70,
      lon: 20.35,
      lines: manyLines,
    );
    // Two lines actually arriving, so we can prove tapping a chip filters.
    final board = ArrivalsBoard.fromJson({
      'stop_id': '20091',
      'stop_name': 'Baćevac',
      'updated_at': DateTime.now().toUtc().toIso8601String(),
      'arrivals': [
        {'line': '401', 'vehicle_type': 'bus', 'eta_minutes': 6, 'stops_remaining': 3, 'route_id': '00401', 'gps': {'lat': 44.65, 'lon': 20.28}},
        {'line': '405', 'vehicle_type': 'bus', 'eta_minutes': 9, 'stops_remaining': 7, 'route_id': '00405', 'gps': {'lat': 44.66, 'lon': 20.29}},
      ],
      'service_status': 'ok',
    });

    await tester.pumpWidget(
      _wrap(
        const StopScreen(stopId: '20091', initialStopName: 'Baćevac'),
        arrivals: _FakeArrivalsRepository(board),
        favorites: _FakeFavoritesRepository(),
        stopLocation: bacevac,
      ),
    );
    await tester.pumpAndSettle();

    // No RenderFlex overflow from cramming 22 chips onto one line.
    expect(tester.takeException(), isNull);

    // The row is a horizontal scroller (SingleChildScrollView → an
    // Axis.horizontal Scrollable), not a Wrap.
    final horizontal = tester
        .widgetList<Scrollable>(find.byType(Scrollable))
        .where((s) =>
            s.axisDirection == AxisDirection.right ||
            s.axisDirection == AxisDirection.left);
    expect(horizontal, isNotEmpty);

    // Every chip is built — including the last one, off-screen to the right —
    // so nothing is clipped away. (A SingleChildScrollView builds all children.)
    expect(find.widgetWithText(ChoiceChip, 'All lines'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, '401'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, '863'), findsOneWidget);

    // Both arrivals show before filtering.
    expect(find.text('3 stops away'), findsOneWidget); // line 401
    expect(find.text('7 stops away'), findsOneWidget); // line 405

    // Tapping the 401 chip filters the list down to just line 401.
    await tester.tap(find.widgetWithText(ChoiceChip, '401'));
    await tester.pumpAndSettle();

    expect(find.text('3 stops away'), findsOneWidget); // 401 stays
    expect(find.text('7 stops away'), findsNothing);   // 405 filtered out
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
