import 'dart:ui';

/// From [candidates], each a value paired with its screen position, the value
/// whose position is nearest to [tap]. Null when there are no candidates.
///
/// Pure so the "nearest to the finger, not first in query order" tap rule is
/// unit-testable. `featuresInRect` returns every feature under a fat tap rect in
/// z/query order; in a dense stop cluster the first isn't necessarily the one the
/// user aimed at, so we pick by distance instead.
T? pickNearest<T>(Offset tap, Iterable<(T value, Offset at)> candidates) {
  T? best;
  var bestDistanceSq = double.infinity;
  for (final (value, at) in candidates) {
    final dx = at.dx - tap.dx;
    final dy = at.dy - tap.dy;
    final d2 = dx * dx + dy * dy;
    if (d2 < bestDistanceSq) {
      bestDistanceSq = d2;
      best = value;
    }
  }
  return best;
}
