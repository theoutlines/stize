import 'package:flutter_test/flutter_test.dart';

import 'package:stize/core/fps_overlay.dart';

void main() {
  test('FPS overlay is disabled by default (prod build, no URL param)', () {
    // In the test/prod build the compile-time flag is off, the environment is
    // "production", and there's no `?fps=1` — so the overlay is never built and
    // registers no timings callback or timer (idle = zero frames is untouched).
    expect(fpsOverlayEnabled(), isFalse);
    expect(kShowFpsOverlay, isFalse);
  });
}
