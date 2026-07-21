import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stize/core/live_position.dart';
import 'package:stize/domain/models/arrival.dart';

// Real /arrivals responses captured from staging for Batutova (the owner said
// "works") and Zvezdara (reported as "all here / dead rows"). This locks the
// model: both parse the same way, and each has genuinely live, clickable rows
// with real stops-remaining — i.e. the "all here / not clickable" symptom is NOT
// a parse regression (it was the stale board pinned alive during a follow; see
// the freeze/stale fix). This code is off-flag, so a real regression here would
// ship to prod — hence the guard.
ArrivalsBoard _load(String name) {
  final file = File('test/fixtures/$name.json');
  final board = ArrivalsBoard.fromJson(
    jsonDecode(file.readAsStringSync()) as Map<String, dynamic>,
  );
  return board;
}

void _expectHealthyLiveRows(ArrivalsBoard board, String label) {
  final live = board.arrivals.where(arrivalHasLivePosition).toList();
  expect(live, isNotEmpty, reason: '$label should have live rows');
  // A live row is a real tracked vehicle: it has a GPS fix...
  for (final a in live) {
    expect(a.gps, isNotNull, reason: '$label live row must carry gps');
    expect(isPlaceholderGarage(a.garageNo), isFalse,
        reason: '$label live row must not be a placeholder');
  }
  // ...and not every row collapses to "here" (stops_remaining == 0): at least
  // one live row is genuinely several stops away, exactly what the tile renders
  // as "N stops away" rather than "here".
  expect(
    live.any((a) => (a.stopsRemaining ?? 0) > 0),
    isTrue,
    reason: '$label must have a live row that is >0 stops away (not all "here")',
  );
}

void main() {
  test('Batutova parses healthy, clickable live rows', () {
    _expectHealthyLiveRows(_load('arrivals_batutova'), 'Batutova');
  });

  test('Zvezdara parses healthy, clickable live rows (not "all here")', () {
    final board = _load('arrivals_zvezdara');
    _expectHealthyLiveRows(board, 'Zvezdara');
    // direction_route_id parses for lettered/short variants too (40L, 62), which
    // the map uses to stitch a followed vehicle to the right direction.
    final has40L = board.arrivals.any((a) => a.line == '40L');
    if (has40L) {
      final v = board.arrivals.firstWhere((a) => a.line == '40L');
      expect(v.directionRouteId, isNotNull);
    }
  });
}
