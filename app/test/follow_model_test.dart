import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:stize/core/vehicle_route.dart';
import 'package:stize/domain/models/route_shape.dart';
import 'package:stize/l10n/app_localizations.dart';
import 'package:stize/presentation/widgets/follow_model.dart';

const _names = ['Vukov spomenik', 'Batutova', 'Lion', 'Zeleni venac'];

UpcomingStop _up(int seq, int? eta, {bool board = false, bool here = false}) =>
    UpcomingStop(
      stop: RouteShapeStop(
        stopId: '$seq',
        name: _names[seq],
        lat: 0,
        lon: 0,
        seq: seq,
      ),
      etaMinutes: eta,
      isBoardStop: board,
      vehicleHere: here,
    );

void main() {
  late AppLocalizations l10n;
  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  test('nothing ahead: empty route, no time, no caption', () {
    final m = buildFollowModel(
      upcoming: const [],
      lineStopNames: _names,
      stuckMinutes: null,
      l10n: l10n,
    );
    expect(m.route, isEmpty);
    expect(m.eta, isNull);
    expect(m.caption, isNull);
  });

  test('between stops: the stop behind, then the stops ahead to yours', () {
    final m = buildFollowModel(
      upcoming: [_up(1, 2), _up(2, 4, board: true), _up(3, 6)],
      lineStopNames: _names,
      stuckMinutes: null,
      l10n: l10n,
    );
    expect(m.between, isTrue);
    expect(m.route.map((r) => r.name), [
      'Vukov spomenik',
      'Batutova',
      'Lion',
      'Zeleni venac',
    ]);
    expect(m.route.first.passed, isTrue);
    expect(m.route.where((r) => r.yours).single.name, 'Lion');
    expect(m.eta, 4);
    expect(m.caption, l10n.followStopsTo(2, 'Lion'));
  });

  test('standing at your stop says so', () {
    final m = buildFollowModel(
      upcoming: [_up(2, 0, board: true, here: true)],
      lineStopNames: _names,
      stuckMinutes: 3,
      l10n: l10n,
    );
    expect(m.between, isFalse);
    expect(m.route.last.vehicleHere, isTrue);
    expect(m.caption, l10n.followAtStop('Lion'));
    expect(m.stuckMinutes, 3);
  });

  test('no stop of yours on the way: the next stop leads', () {
    final m = buildFollowModel(
      upcoming: [_up(0, 1), _up(1, 3)],
      lineStopNames: _names,
      stuckMinutes: null,
      l10n: l10n,
    );
    expect(m.eta, 1);
    expect(m.caption, l10n.followNextStop('Vukov spomenik'));
  });
}
