import 'dart:math';

double haversineDistanceMeters(double lat1, double lon1, double lat2, double lon2) {
  const earthRadiusMeters = 6371000.0;
  double toRad(double deg) => deg * pi / 180;

  final dLat = toRad(lat2 - lat1);
  final dLon = toRad(lon2 - lon1);
  final a =
      sin(dLat / 2) * sin(dLat / 2) + cos(toRad(lat1)) * cos(toRad(lat2)) * sin(dLon / 2) * sin(dLon / 2);
  return 2 * earthRadiusMeters * asin(sqrt(a));
}
