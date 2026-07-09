import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stigla/core/map_support.dart';
import 'package:stigla/presentation/app.dart';

void main() {
  // MapLibre has no platform implementation under `flutter test`; render the
  // map widgets as placeholders so the app can boot in the test environment.
  setUp(() => kMapRenderingEnabled = false);
  tearDown(() => kMapRenderingEnabled = true);

  testWidgets('app boots to the home map without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: StiglaApp()));
    await tester.pump();

    expect(find.byType(NavigationBar), findsOneWidget);
  });
}
