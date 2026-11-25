import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stize/core/map_style.dart';

void main() {
  for (final b in Brightness.values) {
    test('Stiže Standard ${b.name} is valid JSON with the POI tiers', () {
      final style =
          jsonDecode(MapStyle.forBrightness(b)) as Map<String, dynamic>;
      expect(style['version'], 8);
      expect(
        style['sprite'],
        contains('/map/poi-${b == Brightness.dark ? 'dark' : 'light'}'),
      );
      final ids = [for (final l in style['layers'] as List) (l as Map)['id']];
      expect(
        ids,
        containsAllInOrder([
          'bg',
          'building-3d',
          'poi-tier-0',
          'poi-tier-1',
          'poi-tier-2',
          'place-city',
        ]),
      );
      final out = Platform.environment['STYLE_DUMP'];
      if (out != null) {
        File('$out/style-${b.name}.json').writeAsStringSync(jsonEncode(style));
      }
    });
  }
}
