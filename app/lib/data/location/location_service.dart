import 'package:geolocator/geolocator.dart';

enum LocationUnavailableReason {
  serviceDisabled,
  permissionDenied,
  permissionDeniedForever,
}

class LocationUnavailable implements Exception {
  const LocationUnavailable(this.reason);
  final LocationUnavailableReason reason;
}

/// Wraps geolocator's permission dance. Requesting permission only pops the
/// OS dialog when the status is genuinely undecided — once the user has
/// answered (either way), later calls are silent, which is what gives us
/// "one system prompt on first launch, then automatic" for free.
class LocationService {
  /// Whether location access has already been granted, without prompting.
  Future<bool> isPermissionGranted() async {
    try {
      final permission = await Geolocator.checkPermission();
      return permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse;
    } catch (_) {
      return false;
    }
  }

  /// A cached fix the OS already has — returns immediately (no GPS wait), so we
  /// can recenter the map instantly on launch when access is granted. Null on
  /// web (unsupported) or when there is no cached fix.
  Future<Position?> lastKnownIfGranted() async {
    if (!await isPermissionGranted()) return null;
    try {
      return await Geolocator.getLastKnownPosition();
    } catch (_) {
      return null;
    }
  }

  Future<Position> getCurrentPosition() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw const LocationUnavailable(
        LocationUnavailableReason.serviceDisabled,
      );
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw const LocationUnavailable(
        LocationUnavailableReason.permissionDenied,
      );
    }
    if (permission == LocationPermission.deniedForever) {
      throw const LocationUnavailable(
        LocationUnavailableReason.permissionDeniedForever,
      );
    }

    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.medium,
        timeLimit: Duration(seconds: 12),
      ),
    );
  }
}
