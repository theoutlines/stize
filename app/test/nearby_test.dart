import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart' as ll;

import 'package:stigla/data/api/api_exceptions.dart';
import 'package:stigla/domain/models/nearby_arrival.dart';
import 'package:stigla/domain/repositories/nearby_arrivals_repository.dart';
import 'package:stigla/l10n/app_localizations.dart';
import 'package:stigla/presentation/providers/providers.dart';
import 'package:stigla/presentation/widgets/nearby_list.dart';
import 'package:stigla/presentation/widgets/nearby_sheet.dart';

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
    'direction_id': '0',
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
  Future<List<NearbyGroup>> nearby({
    required double lat,
    required double lon,
    double radiusMeters = 500,
  }) async {
    if (result is Exception) throw result as Exception;
    return result as List<NearbyGroup>;
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
}
