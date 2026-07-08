import '../models/arrival.dart';

abstract class ArrivalsRepository {
  Future<ArrivalsBoard> getArrivals(String stopId);
}
