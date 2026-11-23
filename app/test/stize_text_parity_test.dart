import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stize/core/design/stize_text.dart';
import 'package:stize/core/design/stize_theme.dart';

/// StizeText.of(context).X renders exactly like the Material text-theme slot
/// it replaced, so moving screens off `textTheme.*` changes no pixels.
void main() {
  for (final brightness in Brightness.values) {
    testWidgets('StizeText matches the text theme ($brightness)', (t) async {
      final theme = brightness == Brightness.dark
          ? StizeTheme.dark()
          : StizeTheme.light();
      late Map<String, (TextStyle?, TextStyle)> pairs;
      await t.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Builder(
            builder: (context) {
              final tt = Theme.of(context).textTheme;
              final s = StizeText.of(context);
              pairs = {
                'displayLarge': (tt.displayLarge, s.etaHero),
                'displayMedium': (tt.displayMedium, s.bigNumber),
                'displaySmall': (tt.displaySmall, s.heroTitle),
                'headlineMedium': (tt.headlineMedium, s.h1),
                'headlineSmall': (tt.headlineSmall, s.date),
                'titleLarge': (tt.titleLarge, s.section),
                'titleMedium': (tt.titleMedium, s.label),
                'titleSmall': (tt.titleSmall, s.control),
                'bodyLarge': (tt.bodyLarge, s.body),
                'bodyMedium': (tt.bodyMedium, s.body),
                'bodySmall': (tt.bodySmall, s.caption),
                'labelLarge': (tt.labelLarge, s.label),
                'labelMedium': (tt.labelMedium, s.control),
                'labelSmall': (tt.labelSmall, s.note),
              };
              return Material(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      for (final e in pairs.entries) ...[
                        Text('x', key: Key('a${e.key}'), style: e.value.$1),
                        Text('x', key: Key('b${e.key}'), style: e.value.$2),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      );
      for (final k in pairs.keys) {
        TextStyle eff(String key) =>
            (t
                        .renderObject<RenderParagraph>(
                          find.descendant(
                            of: find.byKey(Key(key)),
                            matching: find.byType(RichText),
                          ),
                        )
                        .text
                    as TextSpan)
                .style!;
        final a = eff('a$k'), b = eff('b$k');
        for (final (name, x, y) in [
          ('family', a.fontFamily, b.fontFamily),
          ('size', a.fontSize, b.fontSize),
          ('height', a.height, b.height),
          ('weight', a.fontWeight, b.fontWeight),
          ('spacing', a.letterSpacing, b.letterSpacing),
          ('color', a.color, b.color),
          ('leading', a.leadingDistribution, b.leadingDistribution),
          ('baseline', a.textBaseline, b.textBaseline),
          ('features', a.fontFeatures, b.fontFeatures),
          ('decoration', a.decoration, b.decoration),
        ]) {
          expect(y, x, reason: '$k $name');
        }
      }
    });
  }
}
