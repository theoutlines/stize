import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart' as ll;

import 'package:stigla/core/user_location_tracker.dart';

void main() {
  group('lerpLatLng', () {
    final from = ll.LatLng(44.80, 20.40);
    final to = ll.LatLng(44.82, 20.44);

    test('t=0 is the start, t=1 is the end', () {
      expect(lerpLatLng(from, to, 0).latitude, 44.80);
      expect(lerpLatLng(from, to, 0).longitude, 20.40);
      expect(lerpLatLng(from, to, 1).latitude, 44.82);
      expect(lerpLatLng(from, to, 1).longitude, 20.44);
    });

    test('t=0.5 is the midpoint', () {
      final mid = lerpLatLng(from, to, 0.5);
      expect(mid.latitude, closeTo(44.81, 1e-9));
      expect(mid.longitude, closeTo(20.42, 1e-9));
    });

    test('clamps t outside [0, 1] so it never overshoots', () {
      expect(lerpLatLng(from, to, -1).latitude, 44.80);
      expect(lerpLatLng(from, to, 2).latitude, 44.82);
    });
  });

  group('shouldResubscribe', () {
    final subscribedAt = DateTime(2026, 1, 1, 12, 0, 0);
    const threshold = Duration(seconds: 15);

    test('never resubscribes while the screen is inactive', () {
      expect(
        shouldResubscribe(
          active: false,
          lastFixAt: null,
          subscribedAt: subscribedAt,
          now: subscribedAt.add(const Duration(minutes: 5)),
          staleThreshold: threshold,
        ),
        isFalse,
      );
    });

    test('a fresh subscription with no fix yet is left alone', () {
      expect(
        shouldResubscribe(
          active: true,
          lastFixAt: null,
          subscribedAt: subscribedAt,
          now: subscribedAt.add(const Duration(seconds: 5)),
          staleThreshold: threshold,
        ),
        isFalse,
      );
    });

    test('an active subscription past the threshold with no fix is recreated', () {
      expect(
        shouldResubscribe(
          active: true,
          lastFixAt: null,
          subscribedAt: subscribedAt,
          now: subscribedAt.add(const Duration(seconds: 20)),
          staleThreshold: threshold,
        ),
        isTrue,
      );
    });

    test('a recent fix keeps the subscription even if it is old', () {
      final lastFix = subscribedAt.add(const Duration(minutes: 4));
      expect(
        shouldResubscribe(
          active: true,
          lastFixAt: lastFix,
          subscribedAt: subscribedAt,
          now: lastFix.add(const Duration(seconds: 5)),
          staleThreshold: threshold,
        ),
        isFalse,
      );
    });

    test('a stalled stream (last fix older than threshold) is recreated', () {
      final lastFix = subscribedAt.add(const Duration(minutes: 4));
      expect(
        shouldResubscribe(
          active: true,
          lastFixAt: lastFix,
          subscribedAt: subscribedAt,
          now: lastFix.add(const Duration(seconds: 16)),
          staleThreshold: threshold,
        ),
        isTrue,
      );
    });
  });
}
