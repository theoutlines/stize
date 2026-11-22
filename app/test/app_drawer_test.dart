import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stize/l10n/app_localizations.dart';
import 'package:stize/presentation/widgets/app_drawer.dart';

Widget _wrap() => ProviderScope(
  child: MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: AppDrawer(currentIndex: 0, onSelect: (_) {}),
  ),
);

void main() {
  testWidgets('Ideas is gone from the drawer (section removed 2026-11-22)', (tester) async {
    await tester.pumpWidget(_wrap());
    await tester.pumpAndSettle();

    expect(find.text('Ideas'), findsNothing);
    // The rest of the navigation is untouched.
    expect(find.text('Map'), findsOneWidget);
    expect(find.text('My Stops'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });
}
