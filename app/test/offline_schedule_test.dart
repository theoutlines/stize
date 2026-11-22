import 'package:flutter_test/flutter_test.dart';
import 'package:stize/core/offline_schedule.dart';

void main() {
  group('belgradeNow', () {
    test('winter is UTC+1', () {
      final n = belgradeNow(DateTime.utc(2026, 1, 15, 10, 30));
      expect(n.dateISO, '2026-01-15');
      expect(n.minutes, 11 * 60 + 30);
    });
    test('summer is UTC+2 and rolls the date at local midnight', () {
      final n = belgradeNow(DateTime.utc(2026, 7, 14, 22, 15));
      expect(n.dateISO, '2026-07-15');
      expect(n.yesterdayISO, '2026-07-14');
      expect(n.minutes, 15);
    });
    test('DST switches on the last Sunday of March and October at 01:00 UTC', () {
      expect(belgradeOffset(DateTime.utc(2026, 3, 29, 0, 59)).inHours, 1);
      expect(belgradeOffset(DateTime.utc(2026, 3, 29, 1, 0)).inHours, 2);
      expect(belgradeOffset(DateTime.utc(2026, 10, 25, 0, 59)).inHours, 2);
      expect(belgradeOffset(DateTime.utc(2026, 10, 25, 1, 0)).inHours, 1);
    });
  });

  final meta = <String, dynamic>{
    'services': {
      'RD': {'monday': 1, 'tuesday': 1, 'wednesday': 1, 'thursday': 1, 'friday': 1, 'saturday': 0, 'sunday': 0},
      'S': {'monday': 0, 'tuesday': 0, 'wednesday': 0, 'thursday': 0, 'friday': 0, 'saturday': 1, 'sunday': 0},
      'N': {'monday': 0, 'tuesday': 0, 'wednesday': 0, 'thursday': 0, 'friday': 0, 'saturday': 0, 'sunday': 1},
    },
    'exceptions': {
      '2026-05-01': {'add': ['N'], 'remove': ['RD']},
    },
  };

  test('activeServices uses the weekday and applies exceptions', () {
    expect(activeServices('2026-11-23', meta), {'RD'}); // Monday
    expect(activeServices('2026-11-22', meta), {'N'}); // Sunday
    expect(activeServices('2026-05-01', meta), {'N'}); // holiday Friday
  });

  test('upcomingScheduled picks the next trips and yesterday overnight tail', () {
    final schedule = <String, dynamic>{
      'stop_id': '1',
      'deps': [
        {
          'line': '5', 'route_id': 'r5', 'dir': '1',
          'svc': {'RD': [600, 610, 620, 900], 'N': [1450]},
        },
      ],
    };
    final mon = upcomingScheduled(schedule, meta, const BelgradeNow('2026-11-23', '2026-11-22', 605));
    // Monday 10:05: 610 and 620 are next; 900 is ~5h out, past the 3h ceiling.
    expect(mon.map((d) => d.etaMinutes).toList(), [5, 15]);
    // Monday 00:05: yesterday (Sunday, N) overnight trip at 1450 = 00:10 today.
    final night = upcomingScheduled(schedule, meta, const BelgradeNow('2026-11-23', '2026-11-22', 5));
    expect(night.first.etaMinutes, 5);
    expect(night.first.line, '5');
  });

  test('plannedHeadways: median gap around now, sparse lines left out', () {
    final schedule = <String, dynamic>{
      'deps': [
        {'line': '26', 'route_id': 'r26', 'dir': '1', 'svc': {'RD': [590, 598, 606, 614, 622, 630]}},
        {'line': '9', 'route_id': 'r9', 'dir': '1', 'svc': {'RD': [540, 615, 690]}}, // every 75 min
        {'line': '7', 'route_id': 'r7', 'dir': '1', 'svc': {'RD': [600, 612]}}, // too few
      ],
    };
    final h = plannedHeadways(schedule, meta, const BelgradeNow('2026-11-23', '2026-11-22', 600));
    expect(h, {'r26': 8});
  });
}
