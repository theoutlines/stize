import 'package:latlong2/latlong.dart' as ll;

import '../domain/models/route_shape.dart';

/// A stop the tapped vehicle is about to reach, with a rough ETA.
class UpcomingStop {
  const UpcomingStop({
    required this.stop,
    required this.etaMinutes,
    required this.isBoardStop,
  });

  final RouteShapeStop stop;

  /// Estimated minutes until the vehicle reaches this stop, or null when we
  /// have nothing to anchor an estimate to. Only the board stop's value is a
  /// real prediction from the feed; the rest are extrapolated from it, so the
  /// UI must present them as approximate.
  final int? etaMinutes;

  /// True for the stop the arrivals board is about — "your stop".
  final bool isBoardStop;
}

/// The trace + downstream-stop plan for a single tapped vehicle, derived purely
/// from our own data (the GTFS route [RouteShape] plus the vehicle's live
/// position and the feed's `stops_remaining`/ETA to the board stop).
class VehicleRoutePlan {
  const VehicleRoutePlan({
    required this.traveled,
    required this.upcoming,
    required this.stops,
  });

  /// Polyline already behind the vehicle (drawn dim). `[[lat, lon], ...]`.
  final List<List<double>> traveled;

  /// Polyline still ahead of the vehicle (drawn bright). `[[lat, lon], ...]`.
  final List<List<double>> upcoming;

  /// Ordered stops from the vehicle's next stop to the end of the route.
  final List<UpcomingStop> stops;

  RouteShapeStop? get nextStop => stops.isEmpty ? null : stops.first.stop;
}

const _dist = ll.Distance();

/// Splits a route into the part behind the vehicle and the part ahead, and
/// lists the stops the vehicle still has to serve with approximate ETAs.
///
/// ETA anchoring: the feed tells us how many stops remain until the board stop
/// ([stopsRemaining]) and the ETA to it ([etaToBoardMinutes]). We turn that
/// into an average per-stop time and extrapolate along the route. The board
/// stop's own estimate therefore lands exactly on the real value; every other
/// number is a linear extrapolation and must be shown as approximate.
VehicleRoutePlan planVehicleRoute({
  required RouteShape shape,
  required ll.LatLng vehicle,
  required ll.LatLng boardStop,
  int? stopsRemaining,
  int? etaToBoardMinutes,
}) {
  final poly = shape.polyline;
  final splitIdx = poly.isEmpty ? 0 : _nearestPolylineIndex(poly, vehicle);
  final traveled = poly.isEmpty ? <List<double>>[] : poly.sublist(0, splitIdx + 1);
  final upcoming = poly.isEmpty ? <List<double>>[] : poly.sublist(splitIdx);

  final stops = shape.stops;
  if (stops.isEmpty) {
    return VehicleRoutePlan(
      traveled: traveled,
      upcoming: upcoming,
      stops: const [],
    );
  }

  final boardIdx = _nearestStopIndex(stops, boardStop);

  // The vehicle's next stop, from its LIVE position on the route: the first stop
  // whose along-track distance is at/after the vehicle's. This is what makes the
  // list SLIDE — as the vehicle passes a stop, that stop falls behind on the
  // track and drops off, and the next one moves to the top (owner R4 #1: the
  // list was static because it anchored on a FIXED `stopsRemaining` captured at
  // follow entry). `stopsRemaining` now only scales the ETA, never the position.
  //
  // Along-track (projected onto each segment) rather than nearest-vertex, so a
  // vehicle sitting BETWEEN two stops correctly counts the one behind it as
  // passed. A tiny epsilon lets a stop the vehicle is essentially at still count
  // as "next" rather than flickering off a metre early.
  final vehicleAlong = _alongTrackMeters(poly, vehicle);
  int nextIdx = stops.length;
  for (var i = 0; i < stops.length; i++) {
    final stopAlong =
        _alongTrackMeters(poly, ll.LatLng(stops[i].lat, stops[i].lon));
    if (stopAlong >= vehicleAlong - 15) {
      nextIdx = i;
      break;
    }
  }
  if (nextIdx >= stops.length) nextIdx = stops.length - 1; // all behind → last

  // Average per-stop minutes for the ETA extrapolation (approximate). Anchored
  // to the feed's stops_remaining/ETA-to-board when available.
  final avgPerStop = (stopsRemaining != null &&
          stopsRemaining > 0 &&
          etaToBoardMinutes != null)
      ? etaToBoardMinutes / stopsRemaining
      : null;

  final upcomingStops = <UpcomingStop>[];
  for (var j = nextIdx; j < stops.length; j++) {
    int? eta;
    if (avgPerStop != null) {
      // Minutes to stop j, counted from the LIVE next stop (j - nextIdx), so the
      // ETAs advance with the vehicle instead of staying pinned to entry.
      final stopsAhead = j - nextIdx + 1;
      eta = (avgPerStop * stopsAhead).round();
      if (eta < 0) eta = 0;
    }
    upcomingStops.add(
      UpcomingStop(stop: stops[j], etaMinutes: eta, isBoardStop: j == boardIdx),
    );
  }

  return VehicleRoutePlan(
    traveled: traveled,
    upcoming: upcoming,
    stops: upcomingStops,
  );
}

/// The along-track distance (metres from the route start) of the nearest point
/// on [poly] to [p]. Projects [p] onto each segment (planar approximation —
/// exact enough at city scale) and returns the cumulative length to the nearest
/// projection. Used to order stops by progress, so a vehicle between two stops
/// counts the one behind it as passed.
double _alongTrackMeters(List<List<double>> poly, ll.LatLng p) {
  if (poly.length < 2) return 0;
  var bestDist = double.infinity;
  var bestAlong = 0.0;
  var cum = 0.0;
  for (var i = 0; i < poly.length - 1; i++) {
    final a = ll.LatLng(poly[i][0], poly[i][1]);
    final b = ll.LatLng(poly[i + 1][0], poly[i + 1][1]);
    final segLen = _dist.as(ll.LengthUnit.Meter, a, b);
    // Parametric projection t of p onto segment a→b, clamped to the segment.
    final dLat = b.latitude - a.latitude;
    final dLon = b.longitude - a.longitude;
    final len2 = dLat * dLat + dLon * dLon;
    final t = len2 == 0
        ? 0.0
        : (((p.latitude - a.latitude) * dLat + (p.longitude - a.longitude) * dLon) /
                len2)
            .clamp(0.0, 1.0);
    final proj = ll.LatLng(a.latitude + dLat * t, a.longitude + dLon * t);
    final d = _dist.as(ll.LengthUnit.Meter, p, proj);
    if (d < bestDist) {
      bestDist = d;
      bestAlong = cum + segLen * t;
    }
    cum += segLen;
  }
  return bestAlong;
}

int _nearestPolylineIndex(List<List<double>> poly, ll.LatLng p) {
  var best = 0;
  var bestD = double.infinity;
  for (var i = 0; i < poly.length; i++) {
    final d = _dist.as(
      ll.LengthUnit.Meter,
      p,
      ll.LatLng(poly[i][0], poly[i][1]),
    );
    if (d < bestD) {
      bestD = d;
      best = i;
    }
  }
  return best;
}

int _nearestStopIndex(List<RouteShapeStop> stops, ll.LatLng p) {
  var best = 0;
  var bestD = double.infinity;
  for (var i = 0; i < stops.length; i++) {
    final d = _dist.as(
      ll.LengthUnit.Meter,
      p,
      ll.LatLng(stops[i].lat, stops[i].lon),
    );
    if (d < bestD) {
      bestD = d;
      best = i;
    }
  }
  return best;
}
