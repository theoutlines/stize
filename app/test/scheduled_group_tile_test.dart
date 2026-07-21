import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stize/core/arrival_grouping.dart';
import 'package:stize/domain/models/vehicle_type.dart';
import 'package:stize/l10n/app_localizations.dart';
import 'package:stize/presentation/widgets/scheduled_group_tile.dart';

Widget _wrap(ScheduledGroupCell cell) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: ScheduledGroupTile(cell: cell)),
    );

void main() {
  testWidgets('renders line, Scheduled label, nearest + next two times', (tester) async {
    await tester.pumpWidget(_wrap(const ScheduledGroupCell(
      line: '79',
      vehicleType: VehicleType.bus,
      etaMinutes: [18, 26, 30],
    )));

    expect(find.text('79'), findsOneWidget);
    expect(find.text('Scheduled'), findsOneWidget);
    // Nearest, large.
    expect(find.text('18 min'), findsOneWidget);
    // The two follow-ups on one muted line.
    expect(find.text('26 min · 30 min'), findsOneWidget);
    // Not clickable → no drill-in chevron.
    expect(find.byIcon(Icons.chevron_right), findsNothing);
  });

  testWidgets('a single surviving time shows no follow-up line', (tester) async {
    await tester.pumpWidget(_wrap(const ScheduledGroupCell(
      line: '83',
      vehicleType: VehicleType.bus,
      etaMinutes: [12],
    )));

    expect(find.text('12 min'), findsOneWidget);
    expect(find.textContaining('·'), findsNothing);
  });

  testWidgets('a far ETA (>= 60 min) renders as a clock time, not "N min" — '
      'including the cell\'s secondary times', (tester) async {
    await tester.pumpWidget(_wrap(const ScheduledGroupCell(
      line: '29N',
      vehicleType: VehicleType.bus,
      etaMinutes: [26, 146], // 26 stays minutes; 146 becomes a clock time
    )));

    expect(find.text('26 min'), findsOneWidget); // near time unchanged
    expect(find.textContaining('146 min'), findsNothing); // not an unreadable count
    // The follow-up line reads "HH:mm" (24h clock arrival time).
    expect(
      find.byWidgetPredicate((w) =>
          w is Text && (w.data ?? '').contains(RegExp(r'\d{2}:\d{2}'))),
      findsOneWidget,
    );
  });
}
