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

  // The vehicle's next stop. With stops_remaining we can anchor precisely
  // (stopsRemaining == 1 means the board stop is next); without it, fall back
  // to the stop nearest the vehicle's current position.
  int nextIdx;
  if (stopsRemaining != null && stopsRemaining >= 0) {
    nextIdx = boardIdx - stopsRemaining + 1;
  } else {
    nextIdx = _nearestStopIndex(stops, vehicle);
  }
  nextIdx = nextIdx.clamp(0, stops.length - 1);

  final avgPerStop = (stopsRemaining != null &&
          stopsRemaining > 0 &&
          etaToBoardMinutes != null)
      ? etaToBoardMinutes / stopsRemaining
      : null;

  final upcomingStops = <UpcomingStop>[];
  for (var j = nextIdx; j < stops.length; j++) {
    int? eta;
    if (avgPerStop != null) {
      // Stops ahead of the vehicle: j relative to the vehicle's position
      // (boardIdx - stopsRemaining).
      final stopsAhead = j - (boardIdx - stopsRemaining!);
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
