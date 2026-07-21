import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stize/core/fleet_matcher.dart';

/// B1 — the fleet matcher, tested against the *real* reference asset (loaded
/// straight from disk, no Flutter harness) plus a few synthetic broken inputs
/// for the degradation seam (B5).
void main() {
  final catalog = FleetCatalog.tryParse(
    File('assets/data/fleet_models.json').readAsStringSync(),
  )!;

  group('junk pool (P1..P999)', () {
    test('low placeholder ids are UNKNOWN_JUNK', () {
      for (final g in ['P1', 'P7', 'P500', 'P999']) {
        expect(catalog.resolve(g).kind, FleetMatchKind.unknownJunk, reason: g);
      }
    });

    test('999 is junk but 1000 is not (boundary)', () {
      expect(catalog.resolve('P999').kind, FleetMatchKind.unknownJunk);
      // 1000 clears the junk gate; it matches no range here, so it's UNKNOWN.
      expect(catalog.resolve('P1000').kind, FleetMatchKind.unknown);
    });
  });

  group('per-vehicle map beats range', () {
    test('70259 resolves to its exact catalog model, not the Strela class', () {
      final v = catalog.resolve('P70259');
      expect(v.kind, FleetMatchKind.modelHit);
      expect(v.id, 'conecto3_h');
      expect(v.modelName, 'Mercedes Conecto III hybrid');
      // Operator + type are borrowed from the enclosing Strela class.
      expect(v.operatorName, 'Strela Beograd');
      expect(v.vehicleClassType, 'bus');
      // Exact catalog hit is verified, never approximate.
      expect(v.approximate, isFalse);
    });
  });

  group('nested ranges — narrowest wins', () {
    test('23055 hits the electric-bus class nested inside the Banbus block', () {
      // akia_banbus [23050-23059] ⊂ banbus [23000-23499]; the narrow one wins.
      final v = catalog.resolve('P23055');
      expect(v.kind, FleetMatchKind.classHit);
      expect(v.id, 'akia_banbus');
      expect(v.powertrain, Powertrain.electricBattery);
    });

    test('a plain Banbus number falls to the wide operator class', () {
      // 23200 is inside banbus but outside the nested electric range.
      final v = catalog.resolve('P23200');
      expect(v.kind, FleetMatchKind.classHit);
      expect(v.id, 'banbus');
      // Private-operator mixed class → approximate ("~") attributes.
      expect(v.approximate, isTrue);
    });
  });

  group('Lasta suburban blocks stay honestly UNKNOWN', () {
    // NB: the Strela block 70000-71999 in the data covers the 71000-71499
    // "Lasta" numbers noted in spec §6, so those are class-hits, not holes.
    // The genuinely uncovered blocks are 58xxx and 76xxx/78xxx/79xxx.
    test('58xxx / 76xxx / 79xxx are not guessed', () {
      for (final g in ['P58001', 'P58580', 'P76050', 'P79010']) {
        expect(catalog.resolve(g).kind, FleetMatchKind.unknown, reason: g);
      }
    });
  });

  group('range boundaries are inclusive', () {
    test('first and last number of the KT4 range are class-hits', () {
      expect(catalog.resolve('P80201').id, 'kt4'); // first
      expect(catalog.resolve('P80399').id, 'kt4'); // last
    });

    test('one below the range is not the class', () {
      expect(catalog.resolve('P80200').id, isNot('kt4'));
    });
  });

  group('robustness — total, never throws, never guesses', () {
    test('empty / malformed garage numbers resolve to UNKNOWN', () {
      for (final g in <String?>[null, '', '   ', 'P', 'PABC', 'P12A', 'xyz']) {
        expect(catalog.resolve(g).kind, FleetMatchKind.unknown, reason: '$g');
      }
    });

    test('a number outside every range is UNKNOWN, not a nearest guess', () {
      expect(catalog.resolve('P50000').kind, FleetMatchKind.unknown);
    });

    test('the "P" prefix is optional', () {
      final withP = catalog.resolve('P80209');
      final withoutP = catalog.resolve('80209');
      expect(withoutP.kind, FleetMatchKind.classHit);
      expect(withoutP.id, withP.id);
      expect(withoutP.id, 'kt4');
    });
  });

  group('resolve is memoised', () {
    test('the same number returns the identical cached instance', () {
      expect(identical(catalog.resolve('P70259'), catalog.resolve('P70259')),
          isTrue);
    });
  });

  group('resolved attributes surface the spec §3 fields', () {
    test('a tram class carries nickname, age anchor and comfort', () {
      final v = catalog.resolve('P80210'); // KT4 "Ката"
      expect(v.nicknameSr, 'Ката');
      expect(v.ac, isFalse);
      expect(v.lowFloor, isFalse);
      expect(v.comfortScore, 1);
      expect(v.midYear, 1985); // (1980+1990)/2
    });

    test('concrete-model classes carry manufacturer and country', () {
      final v = catalog.resolve('P81510'); // CAF Urbos 3
      expect(v.manufacturer, 'CAF');
      expect(v.country, 'ES');
    });

    test('assumed confidence fields are flagged', () {
      // Solaris 18 (93000-93200) marks `ac` as assumed in the reference data.
      final v = catalog.resolve('P93100');
      expect(v.id, 'solaris18');
      expect(v.isAssumed('ac'), isTrue);
      expect(v.isAssumed('low_floor'), isFalse);
    });
  });

  group('localized content (notes + nicknames) picks by language, falls back to ru', () {
    test('nickname: ru Cyrillic, sr Serbian-Latin, en ASCII', () {
      final v = catalog.resolve('P80210'); // KT4 — "Ката"/"Kata"
      expect(v.nicknameSr, 'Ката');
      expect(v.nicknameFor('ru'), 'Ката');
      expect(v.nicknameFor('sr'), 'Kata');
      expect(v.nicknameFor('en'), 'Kata');

      // A nickname with diacritics diverges: sr keeps them, en strips them.
      final b = catalog.resolve('P81540'); // Bozankaya — "Турчин"
      expect(b.nicknameFor('ru'), 'Турчин');
      expect(b.nicknameFor('sr'), 'Turčin');
      expect(b.nicknameFor('en'), 'Turcin');
    });

    test('note is translated per locale', () {
      final v = catalog.resolve('P80210'); // KT4
      expect(v.humanNoteFor('ru'), startsWith('Легендарная'));
      expect(v.humanNoteFor('en'), startsWith('The legendary'));
      expect(v.humanNoteFor('sr'), startsWith('Legendarna'));
    });

    test('unknown language falls back to ru note and the ASCII nickname', () {
      final v = catalog.resolve('P80210');
      expect(v.humanNoteFor('de'), startsWith('Легендарная'));
      expect(v.nicknameFor('de'), 'Kata');
    });

    test('operator class note is translated too', () {
      final v = catalog.resolve('P23200'); // banbus
      expect(v.humanNoteFor('en'), contains('Private operator'));
      expect(v.humanNoteFor('sr'), contains('Privatni prevoznik'));
    });
  });

  group('B5 — degradation seam: tryParse returns null on bad data', () {
    test('invalid JSON', () {
      expect(FleetCatalog.tryParse('{not json'), isNull);
      expect(FleetCatalog.tryParse(''), isNull);
    });

    test('valid JSON but wrong shape', () {
      expect(FleetCatalog.tryParse('[]'), isNull);
      expect(FleetCatalog.tryParse('"a string"'), isNull);
      expect(FleetCatalog.tryParse('{"classes": {}}'), isNull); // classes not a list
      expect(
        FleetCatalog.tryParse('{"classes": [], "models_catalog": [], "vehicles": {}}'),
        isNull, // models_catalog not a map
      );
    });

    test('a minimally valid shape parses', () {
      final c = FleetCatalog.tryParse(
        '{"classes": [], "models_catalog": {}, "vehicles": {}}',
      );
      expect(c, isNotNull);
      expect(c!.resolve('P80209').kind, FleetMatchKind.unknown);
      expect(c.resolve('P1').kind, FleetMatchKind.unknownJunk);
    });
  });
}
