import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:stize/l10n/app_localizations.dart';
import 'package:stize/presentation/providers/providers.dart';
import 'package:stize/presentation/widgets/app_menu.dart';

Widget _host({bool feedbackOn = true, String? donateUrl}) {
  return ProviderScope(
    overrides: [
      feedbackFormEnabledProvider.overrideWithValue(feedbackOn),
      donateUrlProvider.overrideWithValue(donateUrl),
      coverageEnabledProvider.overrideWithValue(false),
      analyticsEnabledProvider.overrideWithValue(false),
      appVersionProvider.overrideWith((ref) => Future.value('Stiže 1.0.0 (1)')),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => showAppMenu(
                context,
                topInset: 0,
                currentIndex: 0,
                onSelectSection: (_) {},
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _open(WidgetTester tester, Widget host) async {
  await tester.pumpWidget(host);
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('menu lists destinations without a redundant Map item', (
    tester,
  ) async {
    await _open(tester, _host());
    expect(find.text('My Stops'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Share feedback'), findsOneWidget);
    // About is one full-size row; licences and privacy moved inside it.
    expect(find.text('About Stiže'), findsOneWidget);
    expect(find.text('Licenses'), findsNothing);
    // Every row is at least 44 px tall (thumb target).
    for (final label in [
      'My Stops',
      'Settings',
      'Share feedback',
      'About Stiže',
    ]) {
      final box = tester.getSize(
        find
            .ancestor(of: find.text(label), matching: find.byType(InkWell))
            .first,
      );
      expect(box.height, greaterThanOrEqualTo(44), reason: label);
    }
    // The map is always underneath; no "Map" destination.
    expect(find.text('Map'), findsNothing);
  });

  testWidgets('support row is hidden without a donate URL', (tester) async {
    await _open(tester, _host(donateUrl: null));
    expect(find.text('Support Stiže'), findsNothing);
  });

  testWidgets('support row opens the donate URL', (tester) async {
    final launched = <Uri>[];
    TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/url_launcher'),
          (call) async {
            if (call.method == 'launch' || call.method == 'launchUrl') {
              launched.add(Uri.parse((call.arguments as Map)['url'] as String));
            }
            return true;
          },
        );
    addTearDown(
      () => TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/url_launcher'),
            null,
          ),
    );
    await _open(tester, _host(donateUrl: 'https://example.org/donate'));
    await tester.tap(find.text('Support Stiže'));
    await tester.pumpAndSettle();
    expect(launched, [Uri.parse('https://example.org/donate')]);
  });

  testWidgets('close button dismisses the menu', (tester) async {
    await _open(tester, _host());
    await tester.tap(find.byTooltip('Close menu'));
    await tester.pumpAndSettle();
    expect(find.text('My Stops'), findsNothing);
  });

  // Settings and Feedback open as levels of the map's one sheet (owner,
  // 2026-11-23): the menu only closes itself and asks the map to open them.
  testWidgets('Share feedback asks the map for the feedback level', (
    tester,
  ) async {
    await _open(tester, _host());
    final container = ProviderScope.containerOf(
      tester.element(find.text('Share feedback')),
    );
    await tester.tap(find.text('Share feedback'));
    await tester.pumpAndSettle();
    expect(container.read(feedbackRequestProvider), 1);
    expect(find.text('Share feedback'), findsNothing);
  });

  testWidgets('Settings asks the map for the settings level', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await _open(tester, _host());
    final container = ProviderScope.containerOf(
      tester.element(find.text('Settings')),
    );
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(container.read(settingsRequestProvider), 1);
  });
}
