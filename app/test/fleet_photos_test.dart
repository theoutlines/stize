import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stize/core/fleet_photos.dart';

void main() {
  final photos =
      FleetPhoto.parseAll(File('assets/data/fleet_photos.json').readAsStringSync());
  final catalog = jsonDecode(File('assets/data/fleet_models.json').readAsStringSync())
      as Map<String, dynamic>;
  final ids = <String>{
    for (final c in catalog['classes'] as List) (c as Map)['id'] as String,
    ...(catalog['models_catalog'] as Map).keys.cast<String>(),
  };

  test('bundled photos parse and every key is a known class or model id', () {
    expect(photos, isNotEmpty);
    for (final key in photos.keys) {
      expect(ids, contains(key), reason: 'unknown fleet id $key');
    }
  });

  test('every photo carries the credit the licence requires', () {
    for (final p in photos.values) {
      expect(p.author.trim(), isNotEmpty);
      expect(p.license, matches(RegExp(r'^(CC BY|CC BY-SA|CC0|Public domain)')));
      expect(p.page, startsWith('https://commons.wikimedia.org/wiki/File:'));
      expect(p.url, contains('/500px-'));
    }
  });

  test('malformed or foreign-host entries are dropped, never thrown', () {
    expect(FleetPhoto.parseAll('not json'), isEmpty);
    expect(
        FleetPhoto.parseAll(
            '{"photos":{"x":{"url":"https://evil.example/a.jpg","page":"p","author":"a","license":"CC0"}}}'),
        isEmpty);
  });

  test('model names shown in the UI carry no Cyrillic (the app is EN/SR-Latin)', () {
    final cyrillic = RegExp(r'[\u0400-\u04FF]');
    for (final e in (catalog['models_catalog'] as Map).entries) {
      final name = (e.value as Map)['name'] as String?;
      if (name == null) continue;
      expect(cyrillic.hasMatch(name), isFalse, reason: '${e.key}: $name');
    }
    for (final c in catalog['classes'] as List) {
      final name = (c as Map)['model'] as String?;
      if (name == null) continue;
      expect(cyrillic.hasMatch(name), isFalse, reason: '${c['id']}: $name');
    }
  });
}
