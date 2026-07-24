import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stize/l10n/app_localizations.dart';
import 'package:stize/presentation/providers/providers.dart';
import 'package:stize/presentation/widgets/app_drawer.dart';

Widget _host({required bool feedbackOn, String? donateUrl}) {
  return ProviderScope(
    overrides: [
      feedbackFormEnabledProvider.overrideWithValue(feedbackOn),
      donateUrlProvider.overrideWithValue(donateUrl),
      appVersionProvider.overrideWith((ref) => Future.value('Stiže 1.0.0 (1)')),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: AppDrawer(currentIndex: 0, onSelect: (_) {}),
    ),
  );
}

// The exact EN donate-banner line (l10n `drawerDonateBannerLine`).
const _donateLine =
    'Made solo in Belgrade — free and ad-free. If Stiže helps your ride, you can support it.';

void main() {
  testWidgets('renders the dimmed version line and footer entries', (tester) async {
    await tester.pumpWidget(_host(feedbackOn: true));
    await tester.pumpAndSettle();
    expect(find.text('Stiže 1.0.0 (1)'), findsOneWidget);
    // The footer list entries are present, "Share feedback" among them.
    expect(find.text('Share feedback'), findsOneWidget);
    expect(find.text('Open source licenses'), findsOneWidget);
    expect(find.text('Privacy policy'), findsOneWidget);
  });

  testWidgets('there is no standalone "Donate" list item anymore',
      (tester) async {
    await tester.pumpWidget(
        _host(feedbackOn: true, donateUrl: 'https://example.org/donate'));
    await tester.pumpAndSettle();
    // The old list item label is gone; the CTA now lives in the banner.
    expect(find.text('Support Stiže'), findsNothing);
  });

  testWidgets('support banner is hidden when donate_url is empty',
      (tester) async {
    await tester.pumpWidget(_host(feedbackOn: true, donateUrl: null));
    await tester.pumpAndSettle();
    expect(find.text(_donateLine), findsNothing);
    // With no banner, "Share feedback" is the first footer entry.
    expect(find.text('Share feedback'), findsOneWidget);
  });

  testWidgets('support banner appears and opens the URL when donate_url is set',
      (tester) async {
    // Intercept url_launcher so tapping the banner is verifiable without a real
    // browser launch under the test host.
    final launched = <Uri>[];
    TestWidgetsFlutterBinding.ensureInitialized()
        .defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/url_launcher'),
      (call) async {
        if (call.method == 'launch' || call.method == 'launchUrl') {
          final url = (call.arguments as Map)['url'] as String;
          launched.add(Uri.parse(url));
        }
        if (call.method == 'canLaunch' || call.method == 'canLaunchUrl') {
          return true;
        }
        return true;
      },
    );
    addTearDown(() => TestWidgetsFlutterBinding.ensureInitialized()
        .defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/url_launcher'), null));

    await tester.pumpWidget(
        _host(feedbackOn: true, donateUrl: 'https://example.org/donate'));
    await tester.pumpAndSettle();

    expect(find.text(_donateLine), findsOneWidget);

    await tester.tap(find.text(_donateLine));
    await tester.pumpAndSettle();
    expect(launched, [Uri.parse('https://example.org/donate')]);
  });

  testWidgets('feedback form action is hidden when feedback_form is off',
      (tester) async {
    await tester.pumpWidget(_host(feedbackOn: false));
    await tester.pumpAndSettle();

    // Open the feedback actions sheet from the "Share feedback" entry.
    await tester.tap(find.text('Share feedback'));
    await tester.pumpAndSettle();

    // GitHub Issues is always offered; the in-app form action is not (killswitch).
    expect(find.text('GitHub Issues'), findsOneWidget);
    expect(find.text('Write to me'), findsNothing);
  });

  testWidgets('feedback form action shows when feedback_form is on',
      (tester) async {
    await tester.pumpWidget(_host(feedbackOn: true));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Share feedback'));
    await tester.pumpAndSettle();

    expect(find.text('Write to me'), findsOneWidget);
    expect(find.text('GitHub Issues'), findsOneWidget);
  });
}
