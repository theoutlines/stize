import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stize/core/design/stize_theme.dart';
import 'package:stize/l10n/app_localizations.dart';
import 'package:stize/presentation/widgets/arrival_time.dart';

Widget _host(Widget child) => MaterialApp(
  theme: StizeTheme.dark(),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: const Locale('en'),
  home: Scaffold(body: Center(child: child)),
);

void main() {
  late AppLocalizations l10n;
  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  testWidgets('minutes with their unit', (t) async {
    await t.pumpWidget(
      _host(const ArrivalTime(etaMinutes: 7, color: Colors.white)),
    );
    expect(find.text('7'), findsOneWidget);
    expect(find.text(l10n.arrivalEtaMinutesUnit), findsOneWidget);
    expect(find.byType(Opacity), findsNothing);
  });

  testWidgets('a due vehicle says now, with no unit', (t) async {
    await t.pumpWidget(
      _host(const ArrivalTime(etaMinutes: 0, color: Colors.white)),
    );
    expect(find.text(l10n.arrivalEtaNow.toLowerCase()), findsOneWidget);
    expect(find.text(l10n.arrivalEtaMinutesUnit), findsNothing);
  });

  testWidgets('a far vehicle shows a clock time, not minutes', (t) async {
    await t.pumpWidget(
      _host(const ArrivalTime(etaMinutes: 75, color: Colors.white)),
    );
    expect(find.text('75'), findsNothing);
    expect(find.textContaining(':'), findsOneWidget);
  });

  testWidgets('a time we no longer trust: ≈ and dimmed', (t) async {
    await t.pumpWidget(
      _host(
        const ArrivalTime(
          etaMinutes: 4,
          color: Colors.white,
          approximate: true,
        ),
      ),
    );
    expect(find.text('≈'), findsOneWidget);
    final o = t.widget<Opacity>(find.byType(Opacity).first);
    expect(o.opacity, ArrivalTime.approximateOpacity);
  });

  testWidgets('unknown reads as a dash', (t) async {
    await t.pumpWidget(
      _host(const ArrivalTime(etaMinutes: null, color: Colors.white)),
    );
    expect(find.text('—'), findsOneWidget);
  });
}
