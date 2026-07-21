import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stigla/core/search.dart';
import 'package:stigla/domain/models/stop.dart';
import 'package:stigla/l10n/app_localizations.dart';
import 'package:stigla/presentation/providers/providers.dart';
import 'package:stigla/presentation/widgets/nearby_view.dart';

class _FakeGlobalSearch implements GlobalSearch {
  @override
  Future<GlobalSearchResults> run(String query) async => const GlobalSearchResults(
        stops: [Stop(stopId: '1', name: 'Zeleni venac', lat: 44.8, lon: 20.45, lines: ['24', '27'])],
        lines: [],
      );
}

Widget _wrap(Widget child) => ProviderScope(
      overrides: [globalSearchProvider.overrideWithValue(_FakeGlobalSearch())],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: child),
      ),
    );

void main() {
  testWidgets(
      'search works without a location fix: typing shows global results, '
      'not the enable-location empty state', (tester) async {
    await tester.pumpWidget(_wrap(
      NearbyView(
        userLocation: null, // no fix
        locationDenied: false,
        active: false, // no polling timer
        onEnableLocation: () {},
      ),
    ));
    await tester.pump();

    // Before typing: the enable-location invite is shown.
    expect(find.text('Turn on location to list the lines you can catch around you.'),
        findsOneWidget);

    // Type a query → global stop results replace the empty state.
    await tester.enterText(find.byType(TextField), 'Zeleni');
    await tester.pump(); // apply _query
    await tester.pump(const Duration(milliseconds: 350)); // debounce
    await tester.pump(); // apply results

    expect(find.text('Zeleni venac'), findsOneWidget);
    expect(find.textContaining('Turn on location'), findsNothing);
  });
}
