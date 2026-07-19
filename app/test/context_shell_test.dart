import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stigla/l10n/app_localizations.dart';
import 'package:stigla/presentation/widgets/context_shell.dart';

Widget _wrap(Widget child, {Locale? locale}) => MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: Stack(children: [child])),
    );

void main() {
  group('ContextPanel (desktop shell)', () {
    testWidgets('hosts the search row, an optional nav row, and the view',
        (tester) async {
      var backTapped = false;
      await tester.pumpWidget(_wrap(
        Align(
          alignment: Alignment.centerLeft,
          child: ContextPanel(
            width: 384,
            searchField: const TextField(
              key: Key('panel-search'),
              decoration: InputDecoration(hintText: 'search'),
            ),
            navRow: ContextNavRow(
              onBack: () => backTapped = true,
              title: 'Batutova',
            ),
            child: const Center(child: Text('STOP-CONTENT')),
          ),
        ),
      ));

      expect(find.byKey(const Key('panel-search')), findsOneWidget);
      expect(find.text('STOP-CONTENT'), findsOneWidget);
      expect(find.text('Batutova'), findsOneWidget);
      // The single nav row has ONE back control and NO close (owner R1 #4).
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
      expect(find.byIcon(Icons.close), findsNothing);
      await tester.tap(find.byIcon(Icons.arrow_back));
      expect(backTapped, isTrue);

      // The panel is exactly the resolved rubber-band width.
      expect(tester.getSize(find.byType(ContextPanel)).width, 384);
    });

    testWidgets('nearby view has no nav row (root)', (tester) async {
      await tester.pumpWidget(_wrap(
        Align(
          alignment: Alignment.centerLeft,
          child: ContextPanel(
            width: 360,
            searchField: const SizedBox(key: Key('s')),
            child: const Center(child: Text('NEARBY')),
          ),
        ),
      ));
      expect(find.text('NEARBY'), findsOneWidget);
      expect(find.byType(ContextNavRow), findsNothing);
      expect(find.byIcon(Icons.arrow_back), findsNothing);
    });
  });

  group('BackToVehiclePill (follow-lost, decision #8)', () {
    testWidgets('EN / RU / SR-latin triple', (tester) async {
      for (final entry in {
        'en': 'Back to vehicle',
        'ru': 'Вернуться к транспорту',
        'sr': 'Nazad na vozilo',
      }.entries) {
        await tester.pumpWidget(_wrap(
          BackToVehiclePill(line: '79', onTap: () {}, arrowTurns: 0.25),
          locale: Locale(entry.key),
        ));
        await tester.pump();
        expect(find.text(entry.value), findsOneWidget,
            reason: 'locale ${entry.key}');
      }
    });

    testWidgets('tapping resumes follow', (tester) async {
      var tapped = false;
      await tester.pumpWidget(_wrap(
        BackToVehiclePill(line: '5', onTap: () => tapped = true),
      ));
      await tester.tap(find.text('Back to vehicle'));
      expect(tapped, isTrue);
    });
  });
}
