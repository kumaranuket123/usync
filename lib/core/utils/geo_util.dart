import 'dart:math';

abstract final class GeoUtil {
  static const _earthRadiusMetres = 6371000.0;

  /// Great-circle distance between two coordinates, in metres.
  static double distanceMetres(double lat1, double lon1, double lat2, double lon2) {
    double rad(double deg) => deg * pi / 180;
    final dLat = rad(lat2 - lat1);
    final dLon = rad(lon2 - lon1);
    final a = pow(sin(dLat / 2), 2) + cos(rad(lat1)) * cos(rad(lat2)) * pow(sin(dLon / 2), 2);
    return 2 * _earthRadiusMetres * asin(sqrt(a));
  }

  /// "850 m", "4.2 km" under 10 km, then whole kilometres ("420 km").
  static String formatDistance(double metres) {
    if (metres < 1000) return '${metres.round()} m';
    final km = metres / 1000;
    return km < 10 ? '${km.toStringAsFixed(1)} km' : '${km.round()} km';
  }
}
