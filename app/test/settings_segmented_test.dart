import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:stize/l10n/app_localizations.dart';
import 'package:stize/presentation/screens/settings_screen.dart';

void main() {
  testWidgets('settings fit one screen: language and theme as segments', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SettingsScreen(),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Language'), findsOneWidget);
    expect(find.text('Theme'), findsOneWidget);
    expect(find.text('Auto'), findsNWidgets(2));
    expect(find.text('Srpski'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
    expect(find.text('Dark'), findsOneWidget);
    // No nested pages, no radio lists.
    expect(find.byType(RadioListTile<ThemeMode>), findsNothing);
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    // The selected segment is the filled one.
    Color fill(String label) => tester
        .widget<Material>(find.ancestor(of: find.text(label), matching: find.byType(Material)).first)
        .color!;
    expect(fill('Dark'), isNot(Colors.transparent));
    expect(fill('Light'), Colors.transparent);
  });
}
