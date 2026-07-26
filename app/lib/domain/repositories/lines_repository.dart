import '../models/line_info.dart';
import '../models/route_shape.dart';

abstract class LinesRepository {
  Future<List<LineInfo>> search(String query);

  /// Every line in the bundle (both directions), with its authoritative vehicle
  /// type. Used to build the line→type index (marker types, tram-rail set).
  /// Falls back to the on-device cache when the network is down.
  Future<List<LineInfo>> getAll();
  Future<RouteShape> getShapeByLineNumber(String line);

  /// Fetches a specific direction's shape by its route/shape key (from
  /// [LineInfo.routeId]). By-number lookups only ever return the canonical
  /// direction, so opening a chosen direction must go through this (F8).
  Future<RouteShape> getShapeByRouteId(String routeId);
}
