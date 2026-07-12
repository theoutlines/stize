import 'package:flutter_test/flutter_test.dart';

import 'package:stigla/core/coverage_heatmap.dart';

void main() {
  group('coverageMainHeatmapActive (threshold + hysteresis)', () {
    test('mounts when zoomed out below the fade-end threshold', () {
      expect(
        coverageMainHeatmapActive(zoom: 12.0, wasActive: false),
        isTrue,
      );
    });

    test('does not mount when zoomed in above the threshold', () {
      expect(
        coverageMainHeatmapActive(zoom: 15.0, wasActive: false),
        isFalse,
      );
    });

    test('hysteresis: once active it stays active across the sticky band', () {
      // Just above fade-end but within the hysteresis band: an already-mounted
      // layer stays mounted, an unmounted one stays unmounted.
      final zoom = kCoverageMainFadeEnd + kCoverageMainHysteresis / 2;
      expect(coverageMainHeatmapActive(zoom: zoom, wasActive: true), isTrue);
      expect(coverageMainHeatmapActive(zoom: zoom, wasActive: false), isFalse);
    });

    test('unmounts once past the top of the hysteresis band', () {
      final zoom = kCoverageMainFadeEnd + kCoverageMainHysteresis + 0.1;
      expect(coverageMainHeatmapActive(zoom: zoom, wasActive: true), isFalse);
    });

    test('re-mounts below fade-end even coming from inactive', () {
      final zoom = kCoverageMainFadeEnd - 0.1;
      expect(coverageMainHeatmapActive(zoom: zoom, wasActive: false), isTrue);
    });
  });

  group('crossfade opacities', () {
    test('heatmap is at its modest peak far out, gone once zoomed in', () {
      expect(
        coverageMainHeatmapOpacity(kCoverageMainFadeStart - 1),
        kCoverageMainMaxOpacity,
      );
      expect(coverageMainHeatmapOpacity(kCoverageMainFadeEnd + 1), 0.0);
    });

    test('stops are hidden far out, full once zoomed in', () {
      expect(coverageMainStopsOpacity(kCoverageMainFadeStart - 1), 0.0);
      expect(coverageMainStopsOpacity(kCoverageMainFadeEnd + 1), 1.0);
    });

    test('the two crossfade: opacities are complementary in the band', () {
      const mid = (kCoverageMainFadeStart + kCoverageMainFadeEnd) / 2;
      final heat = coverageMainHeatmapOpacity(mid);
      final stops = coverageMainStopsOpacity(mid);
      // Heatmap fades kCoverageMainMaxOpacity→0 while stops fade 0→1 over the
      // same band, so at the midpoint each sits halfway along its own ramp.
      expect(heat, closeTo(kCoverageMainMaxOpacity / 2, 1e-9));
      expect(stops, closeTo(0.5, 1e-9));
    });

    test('the GL opacity expression mirrors the Dart opacity fn', () {
      // Both derive from the same fade constants; assert the interpolation
      // stops line up so they can never diverge silently.
      final expr = coverageMainOpacityExpression();
      // ['interpolate', ['linear'], ['zoom'], start, max, end, 0.0]
      expect(expr[3], kCoverageMainFadeStart);
      expect(expr[4], kCoverageMainMaxOpacity);
      expect(expr[5], kCoverageMainFadeEnd);
      expect(expr[6], 0.0);
      expect(
        coverageMainHeatmapOpacity(kCoverageMainFadeStart),
        expr[4],
      );
      expect(coverageMainHeatmapOpacity(kCoverageMainFadeEnd), expr[6]);
    });
  });
}
