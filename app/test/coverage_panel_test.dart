import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stize/l10n/app_localizations.dart';
import 'package:stize/presentation/providers/providers.dart';
import 'package:stize/presentation/widgets/coverage_panel.dart';
import 'package:stize/presentation/widgets/stize_filter_chips.dart';

void main() {
  late ProviderContainer container;

  Widget host() => UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(body: CoveragePanel()),
    ),
  );

  setUp(() => container = ProviderContainer());
  tearDown(() => container.dispose());

  testWidgets('All plus one chip per type, and the density key', (
    tester,
  ) async {
    await tester.pumpWidget(host());
    expect(find.text('All'), findsOneWidget);
    expect(find.widgetWithText(StizeTypeChip, 'Tram'), findsOneWidget);
    expect(find.widgetWithText(StizeTypeChip, 'Trolleybus'), findsOneWidget);
    expect(find.widgetWithText(StizeTypeChip, 'Bus'), findsOneWidget);
    expect(find.text('rarer'), findsOneWidget);
    expect(find.text('busier'), findsOneWidget);
  });

  testWidgets('a type tap narrows the map, All brings every type back', (
    tester,
  ) async {
    await tester.pumpWidget(host());
    StizeTypeChip chip(String label) =>
        tester.widget(find.widgetWithText(StizeTypeChip, label));

    expect(container.read(coverageTypesProvider), isEmpty);
    await tester.tap(find.text('Tram'));
    await tester.pump();
    expect(container.read(coverageTypesProvider), {'tram'});
    expect(chip('Tram').selected, isTrue);

    await tester.tap(find.text('Bus'));
    await tester.pump();
    expect(container.read(coverageTypesProvider), {'tram', 'bus'});

    await tester.tap(find.text('All'));
    await tester.pump();
    expect(container.read(coverageTypesProvider), isEmpty);
    expect(chip('Tram').selected, isFalse);
  });
}
