import 'package:geolocator/geolocator.dart';
import 'package:geolocator_web/geolocator_web.dart' show WebSettings;

/// Web: accept a cached position up to a few minutes old (`maximumAge`). The
/// browser's default is 0 = always fetch a fresh fix, which can block for many
/// seconds; with a maximumAge it returns the last fix (e.g. the one taken when
/// the user granted access) immediately.
LocationSettings buildLocationSettings() => WebSettings(
  accuracy: LocationAccuracy.medium,
  maximumAge: const Duration(minutes: 5),
  timeLimit: const Duration(seconds: 12),
);

/// The live "my position" stream on web: high accuracy, distance-filtered to
/// ~8 m so `watchPosition` reports genuine movement. `maximumAge` is zero — a
/// live stream wants fresh fixes, not a cached one — and there is no
/// `timeLimit`, so a slow-to-move user doesn't abort the stream.
LocationSettings buildStreamLocationSettings() => WebSettings(
  accuracy: LocationAccuracy.high,
  distanceFilter: 8,
  maximumAge: Duration.zero,
);
