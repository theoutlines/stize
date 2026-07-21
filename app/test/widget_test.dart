import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stize/core/map_support.dart';
import 'package:stize/presentation/app.dart';

void main() {
  // MapLibre has no platform implementation under `flutter test`; render the
  // map widgets as placeholders so the app can boot in the test environment.
  setUp(() => kMapRenderingEnabled = false);
  tearDown(() => kMapRenderingEnabled = true);

  testWidgets('app boots to the home map with drawer nav (no bottom tab bar)', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: StiglaApp()));
    await tester.pump();

    // Navigation moved from a bottom tab bar to a left drawer opened via a
    // hamburger in the search bar.
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byIcon(Icons.menu), findsWidgets);
  });
}
