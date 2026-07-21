import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stize/core/map_support.dart';
import 'package:stize/l10n/app_localizations.dart';
import 'package:stize/presentation/screens/coverage_screen.dart';

Widget _wrap(Widget child) => ProviderScope(
  child: MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: child,
  ),
);

void main() {
  // MapLibre has no platform impl under `flutter test`; render the placeholder
  // so the coverage screen can be pumped (see kMapRenderingEnabled).
  setUp(() => kMapRenderingEnabled = false);
  tearDown(() => kMapRenderingEnabled = true);

  testWidgets('renders the filter chips and the weight legend', (tester) async {
    await tester.pumpWidget(_wrap(const CoverageScreen()));
    await tester.pumpAndSettle();

    // Title + the "All" reset chip.
    expect(find.text('Coverage'), findsWidgets);
    expect(find.text('All'), findsOneWidget);
    // One chip per vehicle type.
    expect(find.text('Tram'), findsOneWidget);
    expect(find.text('Trolleybus'), findsOneWidget);
    expect(find.text('Bus'), findsOneWidget);
    // The density legend.
    expect(find.text('Transit density'), findsOneWidget);
    expect(find.text('rarer'), findsOneWidget);
    expect(find.text('busier'), findsOneWidget);
  });

  testWidgets('starts with "All" selected and toggles a type chip', (tester) async {
    await tester.pumpWidget(_wrap(const CoverageScreen()));
    await tester.pumpAndSettle();

    FilterChip chip(String label) =>
        tester.widget<FilterChip>(find.widgetWithText(FilterChip, label));

    // Empty selection ⇒ "All" is selected, the types are not.
    expect(chip('All').selected, isTrue);
    expect(chip('Tram').selected, isFalse);

    // Selecting a type turns "All" off and that chip on. (Map layer refresh is
    // a no-op here — no style controller under flutter test.)
    await tester.tap(find.widgetWithText(FilterChip, 'Tram'));
    await tester.pumpAndSettle();

    expect(chip('Tram').selected, isTrue);
    expect(chip('All').selected, isFalse);

    // Tapping "All" clears the selection again.
    await tester.tap(find.widgetWithText(FilterChip, 'All'));
    await tester.pumpAndSettle();

    expect(chip('All').selected, isTrue);
    expect(chip('Tram').selected, isFalse);
  });
}
