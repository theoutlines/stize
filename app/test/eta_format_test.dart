import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stigla/core/eta_format.dart';
import 'package:stigla/l10n/app_localizations.dart';

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));

  group('etaLabel — minutes stay minutes until they stop being readable', () {
    test('a due/past arrival is "Now"', () {
      expect(etaLabel(l10n, 'en', 0), 'Now');
      expect(etaLabel(l10n, 'en', -1), 'Now');
    });

    test('a near arrival is "N min"', () {
      expect(etaLabel(l10n, 'en', 5), '5 min');
      expect(etaLabel(l10n, 'en', 89), '89 min'); // just under the threshold
    });

    test('at/beyond ${kFarEtaMinutes} min it becomes a 24h clock arrival time', () {
      final now = DateTime(2026, 7, 17, 1, 15); // 01:15
      expect(etaLabel(l10n, 'en', 90, now: now), '02:45'); // +90m
      expect(etaLabel(l10n, 'en', 158, now: now), '03:53'); // +158m
    });

    test('the threshold is exactly 90 (89 → min, 90 → time)', () {
      final now = DateTime(2026, 7, 17, 12, 0);
      expect(etaLabel(l10n, 'en', 89, now: now), '89 min');
      expect(etaLabel(l10n, 'en', 90, now: now), '13:30');
    });
  });
}
