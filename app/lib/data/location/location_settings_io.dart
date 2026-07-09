import 'package:geolocator/geolocator.dart';

/// Native platforms: a medium-accuracy fix with a hang guard. (The instant
/// path on mobile is [LocationService.lastKnownIfGranted], which web lacks.)
LocationSettings buildLocationSettings() => const LocationSettings(
  accuracy: LocationAccuracy.medium,
  timeLimit: Duration(seconds: 12),
);
