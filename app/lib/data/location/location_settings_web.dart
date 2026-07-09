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
