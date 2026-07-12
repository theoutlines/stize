import '../models/line_info.dart';
import '../models/route_shape.dart';

abstract class LinesRepository {
  Future<List<LineInfo>> search(String query);
  Future<RouteShape> getShapeByLineNumber(String line);

  /// Fetches a specific direction's shape by its route/shape key (from
  /// [LineInfo.routeId]). By-number lookups only ever return the canonical
  /// direction, so opening a chosen direction must go through this (F8).
  Future<RouteShape> getShapeByRouteId(String routeId);
}
