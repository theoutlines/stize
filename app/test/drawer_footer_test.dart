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

// The exact EN donate-banner headline (l10n `drawerDonateBannerTitle`).
const _donateTitle = 'Support Stiže ♥';
// The unofficial disclaimer (l10n `aboutDisclaimer`), moved into the footer.
const _disclaimer =
    'Unofficial app. Not affiliated with JKP Upravljanje javnim prevozom Beograd.';

void main() {
  testWidgets('renders the version line, disclaimer and footer entries',
      (tester) async {
    await tester.pumpWidget(_host(feedbackOn: true));
    await tester.pumpAndSettle();
    expect(find.text('Stiže 1.0.0 (1)'), findsOneWidget);
    // The disclaimer now closes the footer (moved out of the About block).
    expect(find.text(_disclaimer), findsOneWidget);
    // The former About block heading is gone from the drawer.
    expect(find.text('About Stiže'), findsNothing);
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
    // The CTA lives only in the banner headline; there is no plain list item.
    expect(find.text(_donateTitle), findsOneWidget);
    expect(find.text('Support Stiže'), findsNothing);
  });

  testWidgets('support banner is hidden when donate_url is empty',
      (tester) async {
    await tester.pumpWidget(_host(feedbackOn: true, donateUrl: null));
    await tester.pumpAndSettle();
    expect(find.text(_donateTitle), findsNothing);
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

    expect(find.text(_donateTitle), findsOneWidget);

    await tester.tap(find.text(_donateTitle));
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
