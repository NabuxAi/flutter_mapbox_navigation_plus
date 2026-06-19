// ignore_for_file: public_member_api_docs

/// A geographic coordinate used by the map drawing shapes.
class LatLng {
  const LatLng(this.latitude, this.longitude);

  final double latitude;
  final double longitude;

  List<double> toList() => <double>[latitude, longitude];
}

/// A polyline (connected line) drawn on the embedded map from Dart, e.g. a
/// historical trip path, a planned detour, or a geo-fence boundary.
class MapPolyline {
  MapPolyline({
    required this.id,
    required this.points,
    this.color = '#1A73E8',
    this.width = 5,
  });

  /// Stable identifier; re-adding with the same id replaces the polyline.
  final String id;

  /// Ordered list of coordinates that make up the line.
  final List<LatLng> points;

  /// Line color as a hex string (`#RRGGBB` or `#AARRGGBB`).
  final String color;

  /// Line width in logical pixels.
  final double width;

  Map<String, dynamic> toMap() => <String, dynamic>{
        'id': id,
        'points': points.map((p) => p.toList()).toList(),
        'color': color,
        'width': width,
      };
}

/// A filled circle of a real-world radius (in meters) — handy for delivery
/// zones, service areas, and geo-fences. Rendered natively as a polygon so the
/// radius stays correct in meters at any zoom level.
class MapCircle {
  MapCircle({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.radiusMeters,
    this.fillColor = '#331A73E8',
    this.strokeColor = '#1A73E8',
    this.strokeWidth = 2,
  });

  /// Stable identifier; re-adding with the same id replaces the circle.
  final String id;

  final double latitude;
  final double longitude;

  /// Radius of the circle in meters.
  final double radiusMeters;

  /// Fill color as a hex string (include alpha for transparency, e.g.
  /// `#331A73E8`).
  final String fillColor;

  /// Outline color as a hex string.
  final String strokeColor;

  /// Outline width in logical pixels.
  final double strokeWidth;

  Map<String, dynamic> toMap() => <String, dynamic>{
        'id': id,
        'latitude': latitude,
        'longitude': longitude,
        'radiusMeters': radiusMeters,
        'fillColor': fillColor,
        'strokeColor': strokeColor,
        'strokeWidth': strokeWidth,
      };
}
