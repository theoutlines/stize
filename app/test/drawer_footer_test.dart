import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stigla/l10n/app_localizations.dart';
import 'package:stigla/presentation/providers/providers.dart';
import 'package:stigla/presentation/widgets/app_drawer.dart';

Widget _host({required bool feedbackOn, String? donateUrl}) {
  return ProviderScope(
    overrides: [
      feedbackFormEnabledProvider.overrideWithValue(feedbackOn),
      donateUrlProvider.overrideWithValue(donateUrl),
      appVersionProvider.overrideWith((ref) => Future.value('Stigla 1.0.0 (1)')),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: AppDrawer(currentIndex: 0, onSelect: (_) {}),
    ),
  );
}

void main() {
  testWidgets('renders the dimmed version line at the bottom', (tester) async {
    await tester.pumpWidget(_host(feedbackOn: true));
    await tester.pumpAndSettle();
    expect(find.text('Stigla 1.0.0 (1)'), findsOneWidget);
    // The footer entries are present.
    expect(find.text('Open source licenses'), findsOneWidget);
    expect(find.text('Privacy policy'), findsOneWidget);
  });

  testWidgets('donate item is hidden when donate_url is empty', (tester) async {
    await tester.pumpWidget(_host(feedbackOn: true, donateUrl: null));
    await tester.pumpAndSettle();
    expect(find.text('Support Stigla'), findsNothing);
  });

  testWidgets('donate item appears when donate_url is set', (tester) async {
    await tester.pumpWidget(
        _host(feedbackOn: true, donateUrl: 'https://example.org/donate'));
    await tester.pumpAndSettle();
    expect(find.text('Support Stigla'), findsOneWidget);
  });

  testWidgets('feedback form action is hidden when feedback_form is off',
      (tester) async {
    await tester.pumpWidget(_host(feedbackOn: false));
    await tester.pumpAndSettle();

    // Open the feedback actions sheet from the banner.
    await tester.tap(find.text('Built solo by Ivan in Belgrade — found a bug? Tell me.'));
    await tester.pumpAndSettle();

    // GitHub Issues is always offered; the in-app form action is not (killswitch).
    expect(find.text('GitHub Issues'), findsOneWidget);
    expect(find.text('Write to me'), findsNothing);
  });

  testWidgets('feedback form action shows when feedback_form is on',
      (tester) async {
    await tester.pumpWidget(_host(feedbackOn: true));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Built solo by Ivan in Belgrade — found a bug? Tell me.'));
    await tester.pumpAndSettle();

    expect(find.text('Write to me'), findsOneWidget);
    expect(find.text('GitHub Issues'), findsOneWidget);
  });
}
