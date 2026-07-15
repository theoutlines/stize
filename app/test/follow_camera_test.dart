import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre/maplibre.dart' show CameraChangeReason;
import 'package:stigla/core/follow_camera.dart';
import 'package:stigla/core/moving_object_layer.dart';

void main() {
  group('shouldBreakFollow — follow must not cancel itself', () {
    test('a genuine user gesture while following breaks it', () {
      expect(
        shouldBreakFollow(
          following: true,
          selfMove: false,
          reason: CameraChangeReason.apiGesture,
        ),
        isTrue,
      );
    });

    test('our OWN move never breaks follow, even if labelled a gesture', () {
      // This is the self-cancelling-follow bug: the follow tick pans the camera,
      // that pan reports as apiGesture, and a naive detector would kill follow on
      // the very first tick. The selfMove guard must veto it.
      expect(
        shouldBreakFollow(
          following: true,
          selfMove: true,
          reason: CameraChangeReason.apiGesture,
        ),
        isFalse,
      );
    });

    test('programmatic (developer / api) moves never break follow', () {
      for (final r in const [
        CameraChangeReason.developerAnimation,
        CameraChangeReason.apiAnimation,
      ]) {
        expect(
          shouldBreakFollow(following: true, selfMove: false, reason: r),
          isFalse,
          reason: '$r should not break follow',
        );
      }
    });

    test('nothing happens when not following', () {
      expect(
        shouldBreakFollow(
          following: false,
          selfMove: false,
          reason: CameraChangeReason.apiGesture,
        ),
        isFalse,
      );
    });
  });

  group('focusInsertBelowLayerId — route renders under the vehicles', () {
    test('focus is inserted below the lowest vehicle layer', () {
      final below = focusInsertBelowLayerId(vehicleLayersAdded: true);
      expect(below, movingObjectsBadgeLayerId);
      // The badge is the bottom of the vehicle stack, so below-badge is below
      // ALL vehicle symbols — the coin the user follows never gets covered.
      expect(movingObjectsLayersBottomToTop.first, movingObjectsBadgeLayerId);
      expect(movingObjectsLayersBottomToTop, contains(movingObjectsArrowLayerId));
      expect(movingObjectsLayersBottomToTop, contains(movingObjectsLabelLayerId));
    });

    test('no anchor when the vehicle layers are not up yet', () {
      expect(focusInsertBelowLayerId(vehicleLayersAdded: false), isNull);
    });
  });
}
