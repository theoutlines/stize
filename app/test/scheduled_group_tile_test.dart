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

final _clock = RegExp(r'^\d{2}:\d{2}$');
final _twoClocks = RegExp(r'^\d{2}:\d{2} · \d{2}:\d{2}$');

Finder _textMatching(RegExp re) =>
    find.byWidgetPredicate((w) => w is Text && re.hasMatch(w.data ?? ''));

void main() {
  testWidgets('renders line, Scheduled label, nearest time + next two as clocks', (tester) async {
    await tester.pumpWidget(_wrap(const ScheduledGroupCell(
      line: '79',
      vehicleType: VehicleType.bus,
      etaMinutes: [18, 26, 30],
    )));

    expect(find.text('79'), findsOneWidget);
    expect(find.text('Scheduled'), findsOneWidget);
    // A planned time reads as a clock: nearest large, the two follow-ups on
    // one quiet line under it.
    expect(_textMatching(_clock), findsOneWidget);
    expect(_textMatching(_twoClocks), findsOneWidget);
  });

  testWidgets('a single surviving time shows no follow-up line', (tester) async {
    await tester.pumpWidget(_wrap(const ScheduledGroupCell(
      line: '83',
      vehicleType: VehicleType.bus,
      etaMinutes: [12],
    )));

    expect(_textMatching(_clock), findsOneWidget);
    expect(find.textContaining('·'), findsNothing);
  });

  testWidgets('a far ETA never renders as an unreadable "146 min"', (tester) async {
    await tester.pumpWidget(_wrap(const ScheduledGroupCell(
      line: '29N',
      vehicleType: VehicleType.bus,
      etaMinutes: [26, 146],
    )));

    expect(find.textContaining('146'), findsNothing);
    expect(_textMatching(_clock), findsNWidgets(2)); // nearest + the follow-up
  });
}
