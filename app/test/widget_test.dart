import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stigla/presentation/app.dart';

void main() {
  testWidgets('app boots to the My Stops tab without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: StiglaApp()));
    await tester.pump();

    expect(find.byType(NavigationBar), findsOneWidget);
  });
}
