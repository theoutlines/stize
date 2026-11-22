import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stize/core/design/stize_theme.dart';
import 'package:stize/core/map_support.dart';
import 'package:stize/domain/models/vehicle_type.dart';

/// Parses the colour formats the token JSON uses (#RRGGBB, #RRGGBBAA, rgb(a)).
Color _parse(String v) {
  v = v.trim();
  final hex = RegExp(r'^#([0-9a-fA-F]{6})([0-9a-fA-F]{2})?$').firstMatch(v);
  if (hex != null) {
    final a = hex.group(2) ?? 'FF';
    return Color(int.parse('$a${hex.group(1)}', radix: 16));
  }
  final rgba = RegExp(
    r'^rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*(?:,\s*([\d.]+)\s*)?\)$',
  ).firstMatch(v);
  if (rgba != null) {
    final a = rgba.group(4) == null ? 1.0 : double.parse(rgba.group(4)!);
    return Color.fromARGB(
      (a * 255).round(),
      int.parse(rgba.group(1)!),
      int.parse(rgba.group(2)!),
      int.parse(rgba.group(3)!),
    );
  }
  throw FormatException('unsupported colour', v);
}

void main() {
  // `flutter test` runs from app/, the token JSON lives at the repo root.
  final json = jsonDecode(
    File('../design/tokens/stize.tokens.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final color = json['color'] as Map<String, dynamic>;
  final themes = [
    for (final t in color['themes'] as List) (t as Map)['id'] as String,
  ];
  final tokens = (color['tokens'] as List).cast<Map<String, dynamic>>();

  test('generated colours match design/tokens/stize.tokens.json', () {
    // A failure here means the JSON changed without rerunning
    // `node design/tokens/gen-tokens.mjs`.
    final generated = {'dark': StizeColors.dark, 'light': StizeColors.light};
    expect(themes.toSet(), generated.keys.toSet());
    for (final t in tokens) {
      final name = t['name'] as String;
      final raw = t['value'];
      for (final theme in themes) {
        final v = raw is String
            ? raw
            : ((raw as Map)[theme] ?? raw[themes.first]) as String;
        expect(
          generated[theme]!.toMap()[name],
          _parse(v),
          reason: '$name ($theme)',
        );
      }
    }
    expect(StizeColors.dark.toMap().length, tokens.length);
  });

  test('token names are unique', () {
    final names = tokens.map((t) => t['name']).toList();
    expect(names.toSet().length, names.length);
  });

  test('map vehicle colours are the design-system transit colours', () {
    expect(vehicleColor(VehicleType.bus), StizeColors.dark.transitBus);
    expect(vehicleColor(VehicleType.tram), StizeColors.dark.transitTram);
    expect(
      vehicleColor(VehicleType.trolleybus),
      StizeColors.dark.transitTrolleybus,
    );
    // Transit colours don't change with the theme.
    expect(StizeColors.light.transitBus, StizeColors.dark.transitBus);
    expect(StizeColors.light.transitTram, StizeColors.dark.transitTram);
    expect(
      StizeColors.light.transitTrolleybus,
      StizeColors.dark.transitTrolleybus,
    );
  });

  test('both themes build and carry the colour extension', () {
    for (final (theme, colors) in [
      (StizeTheme.dark(), StizeColors.dark),
      (StizeTheme.light(), StizeColors.light),
    ]) {
      expect(theme.extension<StizeColors>(), colors);
      expect(theme.scaffoldBackgroundColor, colors.bg);
      // The accent never becomes Material's primary (focus, defaults).
      expect(theme.colorScheme.primary, colors.ink);
    }
  });

  test('type scale stays on the system: sizes and weights', () {
    const allowedSizes = {10.0, 12.0, 16.0, 20.0, 24.0, 28.0, 32.0, 40.0, 44.0, 104.0};
    for (final s in [
      StizeType.landingHero, StizeType.etaHero, StizeType.bigNumber,
      StizeType.heroTitle, StizeType.h1, StizeType.date, StizeType.section,
      StizeType.body, StizeType.label, StizeType.subtitle,
      StizeType.lineNumber, StizeType.control, StizeType.caption,
      StizeType.note, StizeType.mono,
    ]) {
      expect(allowedSizes, contains(s.fontSize));
      expect(
        [FontWeight.w400, FontWeight.w500, FontWeight.w600],
        contains(s.fontWeight),
      );
    }
    // 600 is reserved for line numbers.
    expect(StizeType.lineNumber.fontWeight, FontWeight.w600);
    expect(StizeType.label.fontWeight, FontWeight.w500);
  });
}
