// ignore_for_file: public_member_api_docs

/// A point annotation that can be drawn on the embedded navigation map from
/// Dart, independent of the route. Use it to show the passenger pickup point,
/// nearby drivers, points of interest, etc.
///
/// By default a marker is rendered natively as a colored circle with an
/// optional text label, so no image asset is required. Provide [imageBase64]
/// (the base64 of a PNG) to draw a custom image icon instead of the circle.
class MapMarker {
  MapMarker({
    required this.id,
    required this.latitude,
    required this.longitude,
    this.label,
    this.color = '#FF3B30',
    this.radius = 8,
    this.imageBase64,
    this.imageWidth,
    this.imageHeight,
  });

  /// Base64-encoded PNG to use as the marker icon. When set, the icon image is
  /// drawn instead of the default circle (the [label], if any, still shows).
  final String? imageBase64;

  /// Optional rendered width of the icon image in logical pixels.
  final double? imageWidth;

  /// Optional rendered height of the icon image in logical pixels.
  final double? imageHeight;

  /// Stable identifier used to update or remove the marker later. Adding a
  /// marker with an existing [id] replaces the previous one.
  final String id;

  /// Latitude of the marker in degrees.
  final double latitude;

  /// Longitude of the marker in degrees.
  final double longitude;

  /// Optional text drawn next to the marker.
  final String? label;

  /// Fill color as a hex string, e.g. `#FF3B30` or `#FFFF3B30` (with alpha).
  final String color;

  /// Circle radius in logical pixels.
  final double radius;

  Map<String, dynamic> toMap() => <String, dynamic>{
        'id': id,
        'latitude': latitude,
        'longitude': longitude,
        'label': label,
        'color': color,
        'radius': radius,
        'imageBase64': imageBase64,
        'imageWidth': imageWidth,
        'imageHeight': imageHeight,
      };
}
