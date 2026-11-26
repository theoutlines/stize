import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stize/core/design/stize_theme.dart';
import 'package:stize/core/vehicle_diagnostics.dart';
import 'package:stize/domain/models/vehicle_type.dart';
import 'package:stize/l10n/app_localizations.dart';
import 'package:stize/presentation/widgets/map/diagnostics_overlay.dart';
import 'package:stize/presentation/widgets/map/follow_bar.dart';
import 'package:stize/presentation/widgets/map/map_controls.dart';
import 'package:stize/presentation/widgets/sheet_chrome.dart';

Widget _host(Widget child) => MaterialApp(
  theme: StizeTheme.dark(),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: const Locale('en'),
  home: Scaffold(body: Stack(children: [child])),
);

void main() {
  group('JamModeButton', () {
    testWidgets('a jam elsewhere: button present, no count badge', (t) async {
      await t.pumpWidget(
        _host(JamModeButton(on: false, relevantCount: 0, onToggle: () {})),
      );
      expect(find.byType(IconButton), findsOneWidget);
      expect(find.text('0'), findsNothing);
    });

    testWidgets('a relevant jam shows its count and toggles', (t) async {
      var toggled = 0;
      await t.pumpWidget(
        _host(
          JamModeButton(on: false, relevantCount: 2, onToggle: () => toggled++),
        ),
      );
      expect(find.text('2'), findsOneWidget);
      await t.tap(find.byType(IconButton));
      expect(toggled, 1);
    });
  });

  group('FollowBar', () {
    testWidgets('before the route shape loads it still reads and closes', (
      t,
    ) async {
      var closed = false;
      await t.pumpWidget(
        _host(
          FollowBar(
            line: '79',
            type: VehicleType.bus,
            subtitle: null,
            scheduled: false,
            onClose: () => closed = true,
          ),
        ),
      );
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(find.text('79'), findsOneWidget);
      expect(find.text(l10n.followingVehicle), findsOneWidget);
      expect(find.text(l10n.vehicleScheduled), findsNothing);
      await t.tap(find.byType(SheetCloseButton));
      expect(closed, isTrue);
    });

    testWidgets('a scheduled object says so under the terminals', (t) async {
      await t.pumpWidget(
        _host(
          FollowBar(
            line: '2',
            type: VehicleType.tram,
            subtitle: 'Vukov spomenik → Vukov spomenik',
            scheduled: true,
            onClose: () {},
          ),
        ),
      );
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(find.text('Vukov spomenik → Vukov spomenik'), findsOneWidget);
      expect(find.text(l10n.vehicleScheduled), findsOneWidget);
    });
  });

  testWidgets('MapZoomControl calls back for + and −', (t) async {
    var zoom = 0;
    await t.pumpWidget(
      _host(MapZoomControl(onZoomIn: () => zoom++, onZoomOut: () => zoom--)),
    );
    await t.tap(find.byType(IconButton).first);
    await t.tap(find.byType(IconButton).first);
    await t.tap(find.byType(IconButton).last);
    expect(zoom, 1);
  });

  testWidgets('DiagnosticsOverlay draws every line and ignores taps', (
    t,
  ) async {
    await t.pumpWidget(
      _host(const DiagnosticsOverlay(lines: ['A', 'B'], bottomMargin: 8)),
    );
    expect(find.text('A'), findsOneWidget);
    expect(find.text('B'), findsOneWidget);
    expect(
      find.ancestor(of: find.text('A'), matching: find.byType(IgnorePointer)),
      findsWidgets,
    );
  });

  group('vehicle diagnostics lines', () {
    test('nothing followed reads as dashes', () {
      final now = DateTime(2026, 11, 27, 12);
      expect(
        catchUpDiagLine(null, now),
        'VEH catchUp gap - plan - vel - age -',
      );
      expect(dwellDiagLine(null), 'VEH dwell -');
      expect(stopCauseDiagLine(null, now), 'VEH stopWhy -');
    });

    test('fix age and board age summarise their samples', () {
      expect(fixAgeDiagLine((total: 0, over45: 0, over90: 0)), 'VEH fixAge -');
      expect(
        fixAgeDiagLine((total: 10, over45: 3, over90: 1)),
        'VEH fixAge >45s 3/10 >90s 1/10 (real fix age, not as_of)',
      );
      expect(boardAgeDiagLine(const []), 'VEH boardAge@poll -');
      expect(
        boardAgeDiagLine(const [4, 20, 9]),
        'VEH boardAge@poll 4,20,9 max 20s freeze-bound 1/3',
      );
    });
  });
}
