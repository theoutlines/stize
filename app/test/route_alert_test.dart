import 'package:flutter_test/flutter_test.dart';

import 'package:stize/domain/models/route_alert.dart';

RouteAlert _alert({
  DateTime? validFrom,
  DateTime? validUntil,
  List<String> lines = const ['79'],
  List<String> stops = const [],
  String confidence = 'line',
}) {
  return RouteAlert(
    id: 'test',
    url: 'https://example.com',
    title: 'Test',
    publishedAt: DateTime(2026, 1, 1),
    lines: lines,
    stops: stops,
    validFrom: validFrom,
    validUntil: validUntil,
    confidence: confidence,
    summary: 'A test alert',
  );
}

void main() {
  group('activity window', () {
    test('with no dates at all, is active and never expires', () {
      final alert = _alert();
      expect(alert.isActiveNow, isTrue);
      expect(alert.isUpcoming, isFalse);
      expect(alert.isExpired, isFalse);
    });

    test('a future validFrom makes it upcoming, not active', () {
      final alert = _alert(validFrom: DateTime.now().add(const Duration(days: 5)));
      expect(alert.isUpcoming, isTrue);
      expect(alert.isActiveNow, isFalse);
      expect(alert.isExpired, isFalse);
    });

    test('a past validUntil makes it expired', () {
      final alert = _alert(validUntil: DateTime.now().subtract(const Duration(days: 1)));
      expect(alert.isExpired, isTrue);
      expect(alert.isActiveNow, isFalse);
    });

    test('validFrom in the past and validUntil in the future is active now', () {
      final alert = _alert(
        validFrom: DateTime.now().subtract(const Duration(days: 1)),
        validUntil: DateTime.now().add(const Duration(days: 1)),
      );
      expect(alert.isActiveNow, isTrue);
      expect(alert.isUpcoming, isFalse);
      expect(alert.isExpired, isFalse);
    });
  });

  group('matching', () {
    test('matchesLine is case-insensitive', () {
      final alert = _alert(lines: ['7L']);
      expect(alert.matchesLine('7l'), isTrue);
      expect(alert.matchesLine('79'), isFalse);
    });

    test('matchesStopName only applies when confidence is "stop"', () {
      final lineOnly = _alert(stops: ['Batutova'], confidence: 'line');
      expect(lineOnly.matchesStopName('Batutova'), isFalse);

      final stopLevel = _alert(stops: ['Batutova'], confidence: 'stop');
      expect(stopLevel.matchesStopName('Batutova'), isTrue);
      expect(stopLevel.matchesStopName('Terazije'), isFalse);
    });
  });

  test('fromJson round-trips the backend contract shape', () {
    final alert = RouteAlert.fromJson({
      'id': 'izmena-trase-linije-94',
      'url': 'https://www.bgprevoz.rs/vesti/izmena-trase-linije-94',
      'title': 'Измена трасе линије 94',
      'publishedAt': '2026-04-09',
      'lines': ['94'],
      'stops': ['13. октобра'],
      'validFrom': '2026-04-11',
      'validUntil': null,
      'confidence': 'stop',
      'summary': 'Линија 94 мења трасу.',
    });

    expect(alert.lines, ['94']);
    expect(alert.validUntil, isNull);
    expect(alert.validFrom, DateTime.parse('2026-04-11'));
  });
}
