import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stize/core/design/stize_theme.dart';
import 'package:stize/core/search.dart';
import 'package:stize/domain/models/stop.dart';
import 'package:stize/presentation/widgets/stop_result_tile.dart';

Stop _s(String id, String name) =>
    Stop(stopId: id, name: name, lat: 0, lon: 0, lines: const ['46', '55']);

void main() {
  final stops = [
    _s('20025', 'Trg republike'),
    _s('20830', 'Škola Vojislav Ilić'),
    _s('20250', 'Zvezdara'),
    _s('20844', 'Blok 25'),
    _s('20083', 'Lion'),
    _s('20831', 'Lion'),
  ];

  test('sign number is stop_id minus 20000, other schemes have none', () {
    expect(stopCodeOf('20830'), '830');
    expect(stopCodeOf('21106'), '1106');
    expect(stopCodeOf('830'), isNull);
    expect(stopCodeOf('10830'), isNull);
  });

  test('a number finds its stop first, leading zeros ignored', () {
    expect(searchStopsLocal(stops, '830').first.stopId, '20830');
    expect(searchStopsLocal(stops, '0830').first.stopId, '20830');
  });

  test('typing narrows by prefix, exact first, then name matches', () {
    expect(searchStopsLocal(stops, '83').map((s) => s.stopId).toList(), [
      '20083',
      '20830',
      '20831',
    ]);
    expect(searchStopsLocal(stops, '25').map((s) => s.stopId).toList(), [
      '20025',
      '20250',
      '20844', // "Blok 25" by name
    ]);
  });

  test('a name query is unchanged', () {
    expect(searchStopsLocal(stops, 'lion').map((s) => s.stopId).toList(), [
      '20083',
      '20831',
    ]);
  });

  testWidgets('the stop row shows the sign number', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: StizeTheme.dark(),
        home: Scaffold(body: StopResultTile(stop: stops[1])),
      ),
    );
    expect(find.text('Škola Vojislav Ilić'), findsOneWidget);
    expect(find.text('830'), findsOneWidget);
    expect(find.text('46 · 55'), findsOneWidget);
  });
}
