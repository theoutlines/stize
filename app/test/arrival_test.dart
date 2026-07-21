import 'package:flutter_test/flutter_test.dart';
import 'package:stize/domain/models/arrival.dart';

Map<String, dynamic> _board(List<Map<String, dynamic>> arrivals) => {
  'stop_id': 'S1',
  'stop_name': 'Tašmajdan',
  'updated_at': '2026-07-11T10:00:00Z',
  'service_status': 'ok',
  'arrivals': arrivals,
};

Map<String, dynamic> _arrival(String line) => {
  'line': line,
  'vehicle_type': 'bus',
  'eta_minutes': 0,
  'stops_remaining': 1,
  'route_id': line.isEmpty ? '' : '000$line',
  'gps': null,
  'garage_no': 'G-$line',
};

void main() {
  test('drops phantom arrivals with a blank line number (F6)', () {
    final board = ArrivalsBoard.fromJson(
      _board([_arrival('24'), _arrival(''), _arrival('  ')]),
    );
    expect(board.arrivals.map((a) => a.line), ['24']);
  });

  test('keeps every real arrival', () {
    final board = ArrivalsBoard.fromJson(
      _board([_arrival('24'), _arrival('79')]),
    );
    expect(board.arrivals.length, 2);
  });

  test('parses direction_route_id (used to stitch a followed vehicle to the '
      'right direction shape / highlight)', () {
    final a = Arrival.fromJson({
      ..._arrival('79'),
      'route_id': '00079',
      'direction_route_id': '00079-B',
    });
    expect(a.routeId, '00079');
    expect(a.directionRouteId, '00079-B');
  });

  test('direction_route_id is null when absent (older payload)', () {
    final a = Arrival.fromJson(_arrival('79'));
    expect(a.directionRouteId, isNull);
  });
}
