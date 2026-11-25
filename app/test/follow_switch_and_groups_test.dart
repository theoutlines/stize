import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stize/core/design/stize_icons.dart';
import 'package:stize/core/design/stize_theme.dart';
import 'package:stize/domain/models/vehicle_type.dart';
import 'package:stize/l10n/app_localizations.dart';
import 'package:stize/presentation/widgets/follow_view.dart';
import 'package:stize/presentation/widgets/stize_filter_chips.dart';

Widget _wrap(Widget child) => MaterialApp(
  theme: StizeTheme.dark(),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: const Locale('en'),
  home: Scaffold(body: child),
);

void main() {
  testWidgets('line chips group by type: tram, trolleybus, bus', (t) async {
    await t.pumpWidget(
      _wrap(
        StizeLineFilterRow(
          allLabel: 'All lines',
          lines: const ['26', '7L', '40', '2'],
          typeByLine: const {
            '26': VehicleType.bus,
            '7L': VehicleType.tram,
            '40': VehicleType.trolleybus,
            '2': VehicleType.tram,
          },
          selected: const {},
          onSelect: (_) {},
        ),
      ),
    );
    double x(String s) => t.getTopLeft(find.text(s)).dx;
    expect(x('7L'), lessThan(x('40')));
    expect(x('2'), lessThan(x('40')));
    expect(x('40'), lessThan(x('26')));
    expect(find.byIcon(StizeIcons.tram), findsOneWidget);
    expect(find.byIcon(StizeIcons.trolleybus), findsOneWidget);
    expect(find.byIcon(StizeIcons.bus), findsOneWidget);
  });

  testWidgets('one type: a plain row, no group icons', (t) async {
    await t.pumpWidget(
      _wrap(
        StizeLineFilterRow(
          allLabel: 'All lines',
          lines: const ['2', '7L'],
          typeByLine: const {'2': VehicleType.tram, '7L': VehicleType.tram},
          selected: const {},
          onSelect: (_) {},
        ),
      ),
    );
    expect(find.byIcon(StizeIcons.tram), findsNothing);
  });

  testWidgets('follow head switches between vehicles of the direction', (
    t,
  ) async {
    int? tapped;
    await t.pumpWidget(
      _wrap(
        FollowHeader(
          line: '7L',
          type: VehicleType.tram,
          destination: 'Pogon Sava',
          etaMinutes: 1,
          vehicles: [
            FollowVehicleOption(
              etaMinutes: 1,
              selected: true,
              onTap: () => tapped = 1,
            ),
            FollowVehicleOption(
              etaMinutes: 3,
              selected: false,
              onTap: () => tapped = 3,
            ),
            FollowVehicleOption(
              etaMinutes: 7,
              selected: false,
              onTap: () => tapped = 7,
            ),
          ],
        ),
      ),
    );
    expect(find.text('3 min'), findsOneWidget);
    await t.tap(find.text('3 min'));
    expect(tapped, 3);
    await t.tap(find.text('1 min'));
    expect(tapped, 3); // the picked one is not a button
  });
}
