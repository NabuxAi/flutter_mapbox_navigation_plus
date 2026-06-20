// ignore_for_file: public_member_api_docs

/// The device's current location as reported by the embedded map.
class UserLocation {
  UserLocation({
    required this.latitude,
    required this.longitude,
    this.bearing,
    this.speed,
    this.speedLimit,
  });

  UserLocation.fromMap(Map<dynamic, dynamic> map)
      : latitude = (map['latitude'] as num?)?.toDouble() ?? 0.0,
        longitude = (map['longitude'] as num?)?.toDouble() ?? 0.0,
        bearing = (map['bearing'] as num?)?.toDouble(),
        speed = (map['speed'] as num?)?.toDouble(),
        speedLimit = (map['speedLimit'] as num?)?.toDouble();

  /// Latitude in degrees.
  final double latitude;

  /// Longitude in degrees.
  final double longitude;

  /// Heading/course in degrees (0 = north), or null if unknown.
  final double? bearing;

  /// Speed in meters per second, or null if unknown.
  final double? speed;

  /// Posted speed limit in km/h, or null if unknown.
  final double? speedLimit;
}
