import '../models/route_alert.dart';

abstract class AlertsRepository {
  Future<List<RouteAlert>> list();
}
