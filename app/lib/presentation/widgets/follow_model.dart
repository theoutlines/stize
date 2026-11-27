import '../../core/vehicle_route.dart';
import '../../l10n/app_localizations.dart';
import 'follow_view.dart';

/// What the follow header and its route list show.
typedef FollowModel = ({
  List<FollowRouteStop> route,
  bool between,
  int? stuckMinutes,
  int? eta,
  String? caption,
});

/// Builds the follow view's content from the followed vehicle's upcoming stops
/// ([upcoming], as planned from the route shape and its live position) and
/// the names of the line's stops in order ([lineStopNames]): the stop behind
/// the vehicle, up to eight stops ahead with their times, your stop, the head
/// time and its caption ("2 stops to Batutova", "At Batutova", "Next: …").
///
/// [stuckMinutes] is how long the vehicle has stood still, when it is stuck.
FollowModel buildFollowModel({
  required List<UpcomingStop> upcoming,
  required List<String>? lineStopNames,
  required int? stuckMinutes,
  required AppLocalizations l10n,
}) {
  final route = <FollowRouteStop>[];
  var between = false;
  if (upcoming.isNotEmpty && lineStopNames != null) {
    final seq = upcoming.first.stop.seq;
    final atStop = upcoming.first.vehicleHere;
    final hasPassed = seq > 0 && seq - 1 < lineStopNames.length;
    if (hasPassed) {
      route.add(FollowRouteStop(name: lineStopNames[seq - 1], passed: true));
    }
    between = hasPassed && !atStop;
    final shown = upcoming.take(8).toList();
    for (var i = 0; i < shown.length; i++) {
      final u = shown[i];
      route.add(
        FollowRouteStop(
          name: u.stop.name,
          etaMinutes: u.etaMinutes,
          yours: u.isBoardStop,
          vehicleHere: i == 0 && !between,
        ),
      );
    }
  }

  int? eta;
  String? caption;
  final boardIdx = upcoming.indexWhere((u) => u.isBoardStop);
  if (boardIdx >= 0) {
    final u = upcoming[boardIdx];
    eta = u.etaMinutes;
    caption = boardIdx == 0 && u.vehicleHere
        ? l10n.followAtStop(u.stop.name)
        : l10n.followStopsTo(boardIdx + 1, u.stop.name);
  } else if (upcoming.isNotEmpty) {
    eta = upcoming.first.etaMinutes;
    caption = l10n.followNextStop(upcoming.first.stop.name);
  }
  return (
    route: route,
    between: between,
    stuckMinutes: stuckMinutes,
    eta: eta,
    caption: caption,
  );
}
