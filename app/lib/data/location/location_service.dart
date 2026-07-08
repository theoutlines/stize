import 'package:geolocator/geolocator.dart';

enum LocationUnavailableReason { serviceDisabled, permissionDenied, permissionDeniedForever }

class LocationUnavailable implements Exception {
  const LocationUnavailable(this.reason);
  final LocationUnavailableReason reason;
}

/// Wraps geolocator's permission dance. Requesting permission only pops the
/// OS dialog when the status is genuinely undecided — once the user has
/// answered (either way), later calls are silent, which is what gives us
/// "one system prompt on first launch, then automatic" for free.
class LocationService {
  Future<Position> getCurrentPosition() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw const LocationUnavailable(LocationUnavailableReason.serviceDisabled);
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw const LocationUnavailable(LocationUnavailableReason.permissionDenied);
    }
    if (permission == LocationPermission.deniedForever) {
      throw const LocationUnavailable(LocationUnavailableReason.permissionDeniedForever);
    }

    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
    );
  }
}
