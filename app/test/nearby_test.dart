import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stize/domain/models/arrival.dart' show ServiceStatus;
import 'package:latlong2/latlong.dart' as ll;

import 'package:stize/data/api/api_exceptions.dart';
import 'package:stize/domain/models/nearby_arrival.dart';
import 'package:stize/domain/repositories/nearby_arrivals_repository.dart';
import 'package:stize/l10n/app_localizations.dart';
import 'package:stize/presentation/providers/providers.dart';
import 'package:stize/presentation/widgets/nearby_list.dart';
import 'package:stize/presentation/widgets/nearby_sheet.dart';

NearbyGroup _group({
  required String line,
  required String destination,
  required String stopName,
  required int distance,
  required List<int> etas,
}) {
  return NearbyGroup.fromJson({
    'line': line,
    'vehicle_type': 'bus',
    'destination': destination,
    'route_id': '$line-0',
    'stop_id': 's-$line',
    'stop_name': stopName,
    'distance_meters': distance,
    'arrivals': [
      for (final e in etas) {'eta_minutes': e, 'garage_no': null, 'stops_remaining': null},
    ],
  });
}

class _FakeNearbyRepo implements NearbyArrivalsRepository {
  _FakeNearbyRepo(this.result);
  final Object result; // List<NearbyGroup> or an Exception to throw

  @override
  Future<NearbyResult> nearby({
    required double lat,
    required double lon,
    double radiusMeters = 500,
  }) async {
    if (result is Exception) throw result as Exception;
    return NearbyResult(
      groups: result as List<NearbyGroup>,
      serviceStatus: ServiceStatus.ok,
    );
  }
}

/// Records the coordinates every `/arrivals/nearby` request is made with, so a
/// test can assert what actually drives the request.
class _RecordingNearbyRepo implements NearbyArrivalsRepository {
  final List<({double lat, double lon})> calls = [];

  @override
  Future<NearbyResult> nearby({
    required double lat,
    required double lon,
    double radiusMeters = 500,
  }) async {
    calls.add((lat: lat, lon: lon));
    return const NearbyResult(groups: [], serviceStatus: ServiceStatus.ok);
  }
}

Widget _wrap(Widget child, {NearbyArrivalsRepository? repo}) {
  return ProviderScope(
    overrides: [
      if (repo != null) nearbyArrivalsRepositoryProvider.overrideWithValue(repo),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  group('NearbyList', () {
    testWidgets('renders a line+direction card with ETA, stop and distance', (tester) async {
      await tester.pumpWidget(
        _wrap(
          NearbyList(
            groups: [
              _group(
                line: '79',
                destination: 'Zeleni venac',
                stopName: 'Batutova',
                distance: 120,
                etas: [3, 9],
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('79'), findsOneWidget);
      expect(find.text('→ Zeleni venac'), findsOneWidget);
      expect(find.textContaining('Batutova'), findsOneWidget);
      expect(find.textContaining('120 m'), findsOneWidget);
      expect(find.text('3 min'), findsOneWidget); // soonest, emphasised
      expect(find.text('9 min'), findsOneWidget); // second departure
    });

    testWidgets('brightness == clickability: a live group has a chevron, a '
        'schedule-only group is dimmed and has none', (tester) async {
      NearbyGroup mk(String line, {required bool scheduled}) => NearbyGroup.fromJson({
            'line': line,
            'vehicle_type': 'bus',
            'destination': 'Dorćol',
            'route_id': '$line-0',
            'stop_id': 's-$line',
            'stop_name': 'Trg',
            'distance_meters': 100,
            'arrivals': [
              {
                'eta_minutes': 4,
                'garage_no': scheduled ? null : 'BG123',
                'stops_remaining': 3,
                if (scheduled) 'source': 'scheduled',
              },
            ],
          });

      await tester.pumpWidget(_wrap(NearbyList(groups: [
        mk('79', scheduled: false), // live → chevron, full brightness
        mk('26', scheduled: true), // schedule-only → dimmed, no chevron
      ])));
      await tester.pumpAndSettle();

      // Exactly one row (the live one) carries the drill-in chevron.
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);

      // The schedule-only row's line badge is dimmed; the live one is not.
      Opacity badgeOpacity(String line) => tester.widget<Opacity>(
            find
                .ancestor(
                  of: find.text(line),
                  matching: find.byType(Opacity),
                )
                .first,
          );
      expect(badgeOpacity('79').opacity, 1.0);
      expect(badgeOpacity('26').opacity, lessThan(1.0));
    });
  });

  group('NearbySheet', () {
    testWidgets('invites enabling location when there is no fix', (tester) async {
      await tester.pumpWidget(
        _wrap(
          NearbySheet(
            userLocation: null,
            locationDenied: false,
            active: true,
            onEnableLocation: () {},
          ),
          repo: _FakeNearbyRepo(const <NearbyGroup>[]),
        ),
      );
      await tester.pump();

      expect(find.text('See what\'s nearby'), findsOneWidget);
      expect(find.text('Use my location'), findsOneWidget);

      await tester.pumpWidget(const SizedBox()); // dispose → cancel the 30s timer
    });

    testWidgets('lists groups fetched from the user location', (tester) async {
      await tester.pumpWidget(
        _wrap(
          NearbySheet(
            userLocation: ll.LatLng(44.795374, 20.499713),
            locationDenied: false,
            active: true,
            onEnableLocation: () {},
          ),
          repo: _FakeNearbyRepo([
            _group(
              line: '26',
              destination: 'Dorćol',
              stopName: 'Trg Republike',
              distance: 80,
              etas: [2],
            ),
          ]),
        ),
      );
      await tester.pump(); // run the initState fetch
      await tester.pump(const Duration(milliseconds: 20));

      expect(find.text('26'), findsOneWidget);
      expect(find.text('→ Dorćol'), findsOneWidget);
      expect(find.text('2 min'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('shows the offline state on a network failure', (tester) async {
      await tester.pumpWidget(
        _wrap(
          NearbySheet(
            userLocation: ll.LatLng(44.795374, 20.499713),
            locationDenied: false,
            active: true,
            onEnableLocation: () {},
          ),
          repo: _FakeNearbyRepo(const NetworkException('offline')),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));

      expect(find.text('Looks like the connection dropped'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('shows a human empty state when nothing is nearby', (tester) async {
      await tester.pumpWidget(
        _wrap(
          NearbySheet(
            userLocation: ll.LatLng(44.795374, 20.499713),
            locationDenied: false,
            active: true,
            onEnableLocation: () {},
          ),
          repo: _FakeNearbyRepo(const <NearbyGroup>[]),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));

      expect(find.text('No stops nearby'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });
  });

  group('Nearby request is anchored to the user, not the map', () {
    // The request coordinates come only from the user's location; the map
    // viewport is not even an input to NearbySheet. A parent rebuild that leaves
    // [userLocation] unchanged (which is exactly what a map pan/zoom does) must
    // not issue a new request.
    testWidgets('a parent rebuild with the same location issues no new request', (tester) async {
      final repo = _RecordingNearbyRepo();
      final loc = ll.LatLng(44.8000, 20.4600);

      Widget sheet(ll.LatLng at) => _wrap(
            NearbySheet(
              userLocation: at,
              locationDenied: false,
              active: true,
              onEnableLocation: () {},
            ),
            repo: repo,
          );

      await tester.pumpWidget(sheet(loc));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      expect(repo.calls.length, 1);
      expect(repo.calls.first.lat, closeTo(44.8000, 1e-9));
      expect(repo.calls.first.lon, closeTo(20.4600, 1e-9));

      // Simulate the map being panned/zoomed: the widget rebuilds but the user's
      // location is unchanged. A fresh LatLng with identical coords stands in for
      // "nothing about the user moved".
      await tester.pumpWidget(sheet(ll.LatLng(44.8000, 20.4600)));
      await tester.pump(const Duration(milliseconds: 20));
      expect(repo.calls.length, 1, reason: 'map movement must not refetch');

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a sub-threshold user move does not refetch', (tester) async {
      final repo = _RecordingNearbyRepo();
      Widget sheet(ll.LatLng at) => _wrap(
            NearbySheet(
              userLocation: at,
              locationDenied: false,
              active: true,
              onEnableLocation: () {},
            ),
            repo: repo,
          );

      await tester.pumpWidget(sheet(ll.LatLng(44.8000, 20.4600)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      expect(repo.calls.length, 1);

      // ~33 m north (< 75 m threshold) — GPS jitter, not a real move.
      await tester.pumpWidget(sheet(ll.LatLng(44.80030, 20.4600)));
      await tester.pump(const Duration(milliseconds: 20));
      expect(repo.calls.length, 1);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a real user move past the threshold refetches at the new spot', (tester) async {
      final repo = _RecordingNearbyRepo();
      Widget sheet(ll.LatLng at) => _wrap(
            NearbySheet(
              userLocation: at,
              locationDenied: false,
              active: true,
              onEnableLocation: () {},
            ),
            repo: repo,
          );

      await tester.pumpWidget(sheet(ll.LatLng(44.8000, 20.4600)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      expect(repo.calls.length, 1);

      // ~222 m north (> 75 m threshold).
      await tester.pumpWidget(sheet(ll.LatLng(44.8020, 20.4600)));
      await tester.pump(const Duration(milliseconds: 20));
      expect(repo.calls.length, 2);
      expect(repo.calls.last.lat, closeTo(44.8020, 1e-9));

      await tester.pumpWidget(const SizedBox());
    });
  });

  group('shouldRefetchNearby', () {
    test('always fetches the first time (no previous fix)', () {
      expect(
        shouldRefetchNearby(last: null, current: ll.LatLng(44.8, 20.46)),
        isTrue,
      );
    });

    test('does not refetch for a move under the threshold', () {
      expect(
        shouldRefetchNearby(
          last: ll.LatLng(44.8000, 20.4600),
          current: ll.LatLng(44.80030, 20.4600), // ~33 m
        ),
        isFalse,
      );
    });

    test('refetches once the user has moved past the threshold', () {
      expect(
        shouldRefetchNearby(
          last: ll.LatLng(44.8000, 20.4600),
          current: ll.LatLng(44.8020, 20.4600), // ~222 m
        ),
        isTrue,
      );
    });
  });
}
