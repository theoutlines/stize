import 'package:geolocator/geolocator.dart';

/// Native platforms: a medium-accuracy fix with a hang guard. (The instant
/// path on mobile is [LocationService.lastKnownIfGranted], which web lacks.)
LocationSettings buildLocationSettings() => const LocationSettings(
  accuracy: LocationAccuracy.medium,
  timeLimit: Duration(seconds: 12),
);

/// The live "my position" stream: high accuracy, emitting only after the user
/// has moved ~8 m (distance-filtered, not timer-driven) so the marker tracks
/// smoothly without a firehose of near-identical fixes. No [timeLimit] — a
/// stream should keep waiting for the next fix, not give up.
LocationSettings buildStreamLocationSettings() => const LocationSettings(
  accuracy: LocationAccuracy.high,
  distanceFilter: 8,
);
