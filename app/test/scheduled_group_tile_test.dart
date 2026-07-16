import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stigla/core/arrival_grouping.dart';
import 'package:stigla/domain/models/vehicle_type.dart';
import 'package:stigla/l10n/app_localizations.dart';
import 'package:stigla/presentation/widgets/scheduled_group_tile.dart';

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
}
