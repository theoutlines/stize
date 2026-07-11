import 'package:flutter_test/flutter_test.dart';
import 'package:stigla/domain/models/arrival.dart';

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
}
