import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stize/core/design/stize_icons.dart';
import 'package:stize/core/design/stize_theme.dart';
import 'package:stize/presentation/widgets/flat_cards.dart';
import 'package:stize/presentation/widgets/notice_strip.dart';

Widget _host(Widget child, {bool flat = true}) => MaterialApp(
  theme: StizeTheme.dark(),
  home: Scaffold(
    body: FlatCards(
      flat: flat,
      child: Column(children: [child]),
    ),
  ),
);

void main() {
  testWidgets('flat on mobile: full width, a hairline, no radius', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const NoticeStrip(
          icon: StizeIcons.hourglass,
          title: 'Possible delay on line 7L',
          surface: Colors.brown,
        ),
      ),
    );
    final m = tester.widget<Material>(
      find
          .ancestor(
            of: find.text('Possible delay on line 7L'),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(m.shape, isA<Border>());
    expect(
      tester.getSize(find.byType(NoticeStrip)).width,
      tester.getSize(find.byType(Scaffold)).width,
    );
  });

  testWidgets('rounded in the desktop island', (tester) async {
    await tester.pumpWidget(
      _host(
        const NoticeStrip(
          icon: StizeIcons.info,
          title: 'Notice',
          surface: Colors.grey,
        ),
        flat: false,
      ),
    );
    final m = tester.widget<Material>(
      find
          .ancestor(of: find.text('Notice'), matching: find.byType(Material))
          .first,
    );
    expect(m.shape, isA<RoundedRectangleBorder>());
  });

  testWidgets('details show only when open, with a chevron', (tester) async {
    var open = false;
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) => _host(
          NoticeStrip(
            icon: StizeIcons.hourglass,
            title: 'Delay',
            surface: Colors.brown,
            open: open,
            details: const Text('Batutova · Lion'),
            onTap: () => setState(() => open = !open),
          ),
        ),
      ),
    );
    expect(find.text('Batutova · Lion'), findsNothing);
    expect(find.byIcon(StizeIcons.chevronDown), findsOneWidget);
    await tester.tap(find.text('Delay'));
    await tester.pump();
    expect(find.text('Batutova · Lion'), findsOneWidget);
    expect(find.byIcon(StizeIcons.chevronUp), findsOneWidget);
  });
}
