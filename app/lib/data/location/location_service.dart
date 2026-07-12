import 'dart:async';

import 'package:geolocator/geolocator.dart';

import 'location_settings.dart';

/// Why a location fix couldn't be obtained. Kept distinct so the UI can tell
/// the user the *truth* (F3a): a fix that merely timed out or is momentarily
/// unavailable must not be reported as "location is off / access denied".
enum LocationUnavailableReason {
  /// OS-level location services are switched off.
  serviceDisabled,

  /// The app/site was refused permission (this session).
  permissionDenied,

  /// Permission was refused permanently (must be re-enabled in settings).
  permissionDeniedForever,

  /// The fix took too long — common on iOS Safari even with access granted.
  timeout,

  /// The device couldn't determine a position right now (no signal, etc.).
  positionUnavailable,
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

  /// A continuous high-accuracy position stream that emits roughly every few
  /// metres travelled (distance-filtered, *not* on a timer), so the "my
  /// position" marker tracks the user smoothly and independently of any API
  /// polling. Assumes access is already granted — callers gate on
  /// [isPermissionGranted] or the recenter button's explicit request.
  ///
  /// Platform errors are normalised to [LocationUnavailable] so callers never
  /// have to reach for geolocator's exception types; a permission-revoked event
  /// surfaces as [LocationUnavailableReason.permissionDenied].
  Stream<Position> positionStream() {
    return Geolocator.getPositionStream(
      locationSettings: buildStreamLocationSettings(),
    ).handleError((Object error) {
      if (error is PermissionDeniedException) {
        throw const LocationUnavailable(
          LocationUnavailableReason.permissionDenied,
        );
      }
      if (error is LocationServiceDisabledException) {
        throw const LocationUnavailable(
          LocationUnavailableReason.serviceDisabled,
        );
      }
      throw const LocationUnavailable(
        LocationUnavailableReason.positionUnavailable,
      );
    });
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

    // Access is granted at this point, so any failure here is a *fetch*
    // problem, not a permission one — classify it honestly (F3a). On iOS Safari
    // the fix routinely times out even with permission, which previously fell
    // through to the generic "location is off" banner.
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: buildLocationSettings(),
      );
    } on LocationUnavailable {
      rethrow;
    } on TimeoutException {
      throw const LocationUnavailable(LocationUnavailableReason.timeout);
    } on LocationServiceDisabledException {
      throw const LocationUnavailable(
        LocationUnavailableReason.serviceDisabled,
      );
    } on PermissionDeniedException {
      throw const LocationUnavailable(
        LocationUnavailableReason.permissionDenied,
      );
    } catch (_) {
      // PositionUpdateException and anything else the platform throws: the
      // position simply isn't available right now.
      throw const LocationUnavailable(
        LocationUnavailableReason.positionUnavailable,
      );
    }
  }
}
