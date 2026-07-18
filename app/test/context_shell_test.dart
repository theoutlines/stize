import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stigla/core/context_slot.dart';
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
    testWidgets('shows the persistent search + back-chip and hosts the view',
        (tester) async {
      var backTapped = false;
      await tester.pumpWidget(_wrap(
        ContextPanel(
          width: 384,
          header: ContextSlotHeader(
            view: ContextView.stop,
            backLabel: 'Nearby',
            onBack: () => backTapped = true,
          ),
          searchField: const TextField(
            key: Key('panel-search'),
            decoration: InputDecoration(hintText: 'search'),
          ),
          child: const Center(child: Text('STOP-CONTENT')),
        ),
      ));

      expect(find.byKey(const Key('panel-search')), findsOneWidget);
      expect(find.text('STOP-CONTENT'), findsOneWidget);
      // Back-chip present and wired.
      expect(find.text('Nearby'), findsOneWidget);
      await tester.tap(find.text('Nearby'));
      expect(backTapped, isTrue);

      // The panel is exactly the resolved rubber-band width.
      final box = tester.getSize(find.byType(ContextPanel));
      expect(box.width, 384);
    });

    testWidgets('nearby view draws no back-chip and no title row',
        (tester) async {
      await tester.pumpWidget(_wrap(
        ContextPanel(
          width: 360,
          header: const ContextSlotHeader(view: ContextView.nearby),
          searchField: const SizedBox(key: Key('s')),
          child: const Center(child: Text('NEARBY')),
        ),
      ));
      expect(find.text('NEARBY'), findsOneWidget);
      expect(find.byType(ContextBackChip), findsNothing);
      expect(find.byType(ContextTitleRow), findsNothing);
    });
  });

  group('ContextSheet (mobile shell)', () {
    testWidgets('hosts the view in a draggable sheet starting at peek',
        (tester) async {
      final controller = DraggableScrollableController();
      final sizes = <double>[];
      await tester.pumpWidget(_wrap(
        ContextSheet(
          controller: controller,
          header: const ContextSlotHeader(view: ContextView.nearby),
          onSizeChanged: sizes.add,
          child: ListView(children: const [Text('SHEET-CONTENT')]),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('SHEET-CONTENT'), findsOneWidget);
      // The content lives inside a draggable sheet (the detent heights it snaps
      // to are asserted by the pure-model test).
      final sheet = tester.widget<DraggableScrollableSheet>(
          find.byType(DraggableScrollableSheet));
      expect(sheet.initialChildSize, kDetentPeek);
      expect(sheet.snapSizes, const [kDetentPeek, kDetentHalf, kDetentLarge]);
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
