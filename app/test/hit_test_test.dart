import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:stize/core/hit_test.dart';

void main() {
  group('pickNearest — tap opens the pin under the finger, not the first', () {
    test('picks the candidate nearest the tap, ignoring list order', () {
      // "far" is first in the list (query/z order) but "near" is closer to the tap.
      final near = ('near', const Offset(102, 100));
      final far = ('far', const Offset(140, 100));
      expect(pickNearest(const Offset(100, 100), [far, near]), 'near');
    });

    test('returns null when there are no candidates', () {
      expect(pickNearest<String>(const Offset(0, 0), const []), isNull);
    });

    test('keeps the first on an exact tie', () {
      final a = ('a', const Offset(110, 100));
      final b = ('b', const Offset(90, 100)); // same distance (10px) the other side
      expect(pickNearest(const Offset(100, 100), [a, b]), 'a');
    });
  });
}
