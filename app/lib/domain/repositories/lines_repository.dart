import '../models/line_info.dart';
import '../models/route_shape.dart';

abstract class LinesRepository {
  Future<List<LineInfo>> search(String query);
  Future<RouteShape> getShapeByLineNumber(String line);
}
