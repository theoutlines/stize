import '../models/line_info.dart';

abstract class LinesRepository {
  Future<List<LineInfo>> search(String query);
}
