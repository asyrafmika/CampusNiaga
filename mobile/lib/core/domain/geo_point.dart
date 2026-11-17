/// A spot on the map, in degrees (WGS 84), as `pickup_lat` / `pickup_lng`
/// store it.
class GeoPoint {
  const GeoPoint(this.latitude, this.longitude);

  final double latitude;
  final double longitude;

  /// The pin from a row's `pickup_lat` and `pickup_lng`, or `null` when the
  /// row has none (the database stores both or neither).
  static GeoPoint? fromWire(Object? latitude, Object? longitude) {
    if (latitude is! num || longitude is! num) return null;
    return GeoPoint(latitude.toDouble(), longitude.toDouble());
  }

  @override
  bool operator ==(Object other) =>
      other is GeoPoint &&
      other.latitude == latitude &&
      other.longitude == longitude;

  @override
  int get hashCode => Object.hash(latitude, longitude);

  @override
  String toString() => 'GeoPoint($latitude, $longitude)';
}

/// The rules for a pickup pin. They mirror `public.pickup_pin_problem`,
/// which checks again.
abstract final class PickupPinRules {
  // Malaysia's bounding box; every USM campus is inside it.
  static const double minLatitude = 0.8;
  static const double maxLatitude = 7.5;
  static const double minLongitude = 99.5;
  static const double maxLongitude = 119.5;

  static bool isValid(GeoPoint point) =>
      point.latitude >= minLatitude &&
      point.latitude <= maxLatitude &&
      point.longitude >= minLongitude &&
      point.longitude <= maxLongitude;

  /// Six decimals (about 10 cm) is more than a pickup spot needs; rounding
  /// keeps what is stored tidy.
  static GeoPoint rounded(GeoPoint point) =>
      GeoPoint(_round(point.latitude), _round(point.longitude));

  static double _round(double degrees) =>
      (degrees * 1000000).roundToDouble() / 1000000;
}

/// USM's campuses, where the map picker starts and can jump to.
enum UsmCampus {
  main('Main campus', GeoPoint(5.3559, 100.3025)),
  engineering('Engineering campus', GeoPoint(5.1453, 100.4930)),
  health('Health campus', GeoPoint(6.0997, 102.2830));

  const UsmCampus(this.label, this.centre);

  final String label;
  final GeoPoint centre;
}
